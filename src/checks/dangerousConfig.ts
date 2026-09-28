import ts from 'typescript'
import type { SourceFile } from '../scan.js'
import type { Finding, Severity } from '../report.js'

/**
 * Dangerous config — settings that switch a security control off, written
 * literally in code. Deterministic and literal-only: a value decided at
 * runtime (`origin: corsOrigin`, `rejectUnauthorized: !allowInsecure`) is
 * the app making a choice we can't see, so it is never flagged.
 *
 *   - CORS: any origin (`'*'` / `true` / reflected request origin) together with credentials
 *   - JWT: `'none'` in `algorithms`, `ignoreExpiration: true`
 *   - JWT/session secrets hardcoded, or `process.env.X || 'fallback'`
 *   - TLS verification off: `NODE_TLS_REJECT_UNAUTHORIZED = '0'`, `rejectUnauthorized: false`
 */

type Hit = { node: ts.Node; severity: Severity; message: string }

function scriptKindFor(relPath: string): ts.ScriptKind {
  const p = relPath.toLowerCase()
  if (p.endsWith('.tsx')) return ts.ScriptKind.TSX
  if (p.endsWith('.jsx')) return ts.ScriptKind.JSX
  if (p.endsWith('.js') || p.endsWith('.mjs') || p.endsWith('.cjs')) return ts.ScriptKind.JS
  return ts.ScriptKind.TS
}

function propName(p: ts.ObjectLiteralElementLike): string | null {
  if (!ts.isPropertyAssignment(p) && !ts.isShorthandPropertyAssignment(p)) return null
  const n = p.name
  if (ts.isIdentifier(n) || ts.isStringLiteral(n)) return n.text
  return null
}

function prop(obj: ts.ObjectLiteralExpression, name: string): ts.Expression | undefined {
  for (const p of obj.properties) {
    if (propName(p) === name && ts.isPropertyAssignment(p)) return p.initializer
  }
  return undefined
}

function isTrue(e: ts.Expression | undefined): boolean {
  return !!e && e.kind === ts.SyntaxKind.TrueKeyword
}
function isFalse(e: ts.Expression | undefined): boolean {
  return !!e && e.kind === ts.SyntaxKind.FalseKeyword
}
function stringValue(e: ts.Expression | undefined): string | null {
  if (!e) return null
  if (ts.isStringLiteral(e) || ts.isNoSubstitutionTemplateLiteral(e)) return e.text
  return null
}

function calleeText(call: ts.CallExpression | ts.NewExpression, sf: ts.SourceFile): string {
  return call.expression.getText(sf)
}

/**
 * A secret expression that is hardcoded: a string literal, or an env read
 * with a literal fallback (`process.env.JWT_SECRET || 'dev-secret'`) —
 * which silently ships the fallback the day the env var is missing.
 */
function hardcodedSecret(e: ts.Expression | undefined): 'literal' | 'fallback' | null {
  if (!e) return null
  if (stringValue(e) != null) return 'literal'
  if (
    ts.isBinaryExpression(e) &&
    (e.operatorToken.kind === ts.SyntaxKind.BarBarToken || e.operatorToken.kind === ts.SyntaxKind.QuestionQuestionToken) &&
    stringValue(e.right) != null
  ) {
    return 'fallback'
  }
  return null
}

function secretMessage(kind: 'literal' | 'fallback', what: string): string {
  return kind === 'literal'
    ? `${what} secret is hardcoded in source — anyone who sees the code can forge logins. Read it from an env var and fail at startup if it's missing.`
    : `${what} secret falls back to a hardcoded value when the env var is missing — a deploy without it silently uses a known secret, so anyone can forge logins. Throw at startup instead of falling back.`
}

function isInsideIf(node: ts.Node): boolean {
  for (let cur = node.parent; cur; cur = cur.parent) {
    if (ts.isIfStatement(cur) || ts.isConditionalExpression(cur)) return true
    if (ts.isFunctionLike(cur)) return false
  }
  return false
}

function checkCall(call: ts.CallExpression | ts.NewExpression, sf: ts.SourceFile, fnText: string, jwtBare: boolean): Hit[] {
  const hits: Hit[] = []
  const callee = calleeText(call, sf)
  const args = call.arguments ?? ts.factory.createNodeArray<ts.Expression>()

  // cors({ origin: '*' | true, credentials: true })
  if (/(?:^|\.)cors$/.test(callee) || /^require\(\s*['"]cors['"]\s*\)$/.test(callee)) {
    const opts = args[0]
    if (opts && ts.isObjectLiteralExpression(opts)) {
      const origin = prop(opts, 'origin')
      if (isTrue(prop(opts, 'credentials')) && (isTrue(origin) || stringValue(origin) === '*')) {
        hits.push({
          node: call,
          severity: 'finding',
          message:
            'CORS allows any origin together with credentials — any website can make requests as your logged-in users. List your allowed origins explicitly.',
        })
      }
    }
  }

  // res.setHeader('Access-Control-Allow-Origin', req.headers.origin) — reflected, unchecked, with credentials.
  if (/\.(?:setHeader|header|set)$/.test(callee) && stringValue(args[0])?.toLowerCase() === 'access-control-allow-origin') {
    const value = args[1]?.getText(sf) ?? ''
    const reflected = /\b(?:req|request)\.(?:headers\.origin|get\(\s*['"]origin['"]\s*\)|header\(\s*['"]origin['"]\s*\))/i.test(value)
    const withCredentials = /access-control-allow-credentials['"]\s*,\s*['"]?true/i.test(fnText)
    if (reflected && withCredentials && !isInsideIf(call)) {
      hits.push({
        node: call,
        severity: 'finding',
        message:
          'CORS reflects any request Origin back with credentials allowed — any website can make requests as your logged-in users. Check the origin against an allowlist first.',
      })
    }
  }

  // jwt.sign / jwt.verify: hardcoded secret, alg none, ignoreExpiration
  const isJwtCall =
    /(?:^|\.)(?:jwt|jsonwebtoken)\.(?:sign|verify)$/.test(callee) || (jwtBare && /^(?:sign|verify)$/.test(callee))
  if (isJwtCall) {
    const kind = hardcodedSecret(args[1])
    if (kind) hits.push({ node: call, severity: 'finding', message: secretMessage(kind, 'JWT') })
    const opts = args[2]
    if (opts && ts.isObjectLiteralExpression(opts)) {
      const algs = prop(opts, 'algorithms')
      if (algs && ts.isArrayLiteralExpression(algs) && algs.elements.some((el) => stringValue(el)?.toLowerCase() === 'none')) {
        hits.push({
          node: call,
          severity: 'finding',
          message: "JWT accepts the 'none' algorithm — anyone can forge a token with no signature. Allow only the algorithm you sign with (e.g. HS256).",
        })
      }
      if (isTrue(prop(opts, 'ignoreExpiration'))) {
        hits.push({
          node: call,
          severity: 'warning',
          message: 'JWT expiry is ignored — a stolen token works forever. Remove ignoreExpiration.',
        })
      }
    }
  }

  // session({ secret: '…' }) / cookieSession({ secret | keys }) / new JwtStrategy({ secretOrKey: '…' })
  const opts0 = args[0]
  if (opts0 && ts.isObjectLiteralExpression(opts0)) {
    if (/(?:^|\.)(?:session|expressSession|cookieSession)$/.test(callee)) {
      const kind = hardcodedSecret(prop(opts0, 'secret'))
      if (kind) hits.push({ node: call, severity: 'finding', message: secretMessage(kind, 'Session') })
    }
    if (/(?:^|\.)(?:JwtStrategy|Strategy)$/.test(callee)) {
      const kind = hardcodedSecret(prop(opts0, 'secretOrKey'))
      if (kind) hits.push({ node: call, severity: 'finding', message: secretMessage(kind, 'JWT') })
    }
  }
  return hits
}

export function checkDangerousConfig(files: SourceFile[]): Finding[] {
  const findings: Finding[] = []
  for (const file of files) {
    const p = file.relPath.replace(/\\/g, '/')
    if (/\.(test|spec)\.[jt]sx?$/.test(p) || /(?:^|\/)(?:__tests__|__mocks__|fixtures?|mocks?|e2e)\//i.test(p)) continue
    const sf = ts.createSourceFile(file.relPath, file.text, ts.ScriptTarget.Latest, true, scriptKindFor(file.relPath))
    const hits: Hit[] = []
    // `import { sign, verify } from 'jsonwebtoken'` — bare calls are JWT too.
    const jwtBare = /from\s+['"]jsonwebtoken['"]|require\(\s*['"]jsonwebtoken['"]\s*\)/.test(file.text) &&
      /\{[^}]*\b(?:sign|verify)\b[^}]*\}\s*(?:=|from)/.test(file.text)

    const visit = (node: ts.Node, fnText: string): void => {
      const text = ts.isFunctionLike(node) ? node.getText(sf) : fnText

      if (ts.isCallExpression(node) || ts.isNewExpression(node)) hits.push(...checkCall(node, sf, text, jwtBare))

      // process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0'
      if (
        ts.isBinaryExpression(node) &&
        node.operatorToken.kind === ts.SyntaxKind.EqualsToken &&
        /NODE_TLS_REJECT_UNAUTHORIZED/.test(node.left.getText(sf)) &&
        /^['"`]?0['"`]?$/.test(node.right.getText(sf).trim())
      ) {
        hits.push({
          node,
          severity: 'finding',
          message:
            'NODE_TLS_REJECT_UNAUTHORIZED=0 turns off HTTPS certificate checks for every request this process makes — anyone on the network can intercept them. Remove it.',
        })
      }

      // { rejectUnauthorized: false } — one connection without certificate checks.
      // Inside an if/ternary it's an opt-in the app decides at runtime
      // (`skipTls ? { rejectUnauthorized: false } : {}`) — not a default.
      if (
        ts.isPropertyAssignment(node) &&
        propName(node) === 'rejectUnauthorized' &&
        isFalse(node.initializer) &&
        !isInsideIf(node)
      ) {
        hits.push({
          node,
          severity: 'warning',
          message:
            'rejectUnauthorized: false skips the HTTPS certificate check on this connection — traffic can be intercepted. Common for hosted Postgres; prefer passing the provider’s CA certificate instead.',
        })
      }

      ts.forEachChild(node, (c) => visit(c, text))
    }
    visit(sf, '')

    const seen = new Set<string>()
    for (const h of hits) {
      const line = sf.getLineAndCharacterOfPosition(h.node.getStart(sf)).line + 1
      const key = `${line}:${h.message}`
      if (seen.has(key)) continue
      seen.add(key)
      findings.push({
        check: 'dangerous-config',
        severity: h.severity,
        file: file.relPath,
        line,
        message: h.message,
        fixHint: 'open-editor',
      })
    }
  }
  return findings
}
