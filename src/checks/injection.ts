import ts from 'typescript'
import type { SourceFile } from '../scan.js'
import type { Finding } from '../report.js'

/**
 * Injection — request input reaching a dangerous sink in the same function:
 * a shell command, eval, a SQL string, or a filesystem path.
 *
 * Deterministic taint tracking on the TypeScript AST, deliberately local
 * (one function, no cross-file flow): precision over recall, same rule as
 * the rest of the engine. A value counts as tainted when it is read from a
 * request (Express/Next/Hono/Koa/Lambda shapes) or from a local variable
 * that was assigned one; it stops being tainted when it goes through a
 * known sanitizer (Number, parseInt, basename, escape…). Unknown function
 * calls end the taint too — we only claim flows we can see.
 */

type Category = 'command' | 'code' | 'sql' | 'path'

const MESSAGES: Record<Category, string> = {
  command:
    'flows into a shell command — command injection: anyone can run commands on your server. Pass arguments as an array to execFile/spawn (no shell) instead.',
  code: 'flows into eval / new Function — code injection: anyone can run JavaScript on your server. Never evaluate request data.',
  sql: 'is built into a SQL string — SQL injection: anyone can read or delete your database. Use a parameterized query ($1 / ?) or a tagged sql`` template.',
  path: 'is used as a file path — path traversal: ../ lets anyone read or write any file on the server. Use path.basename() or check the resolved path stays inside your folder.',
}

/** `req.<part>` / `request.<part>` / `c.req.<part>()` — the input surfaces. */
const REQUEST_WORDS = new Set(['req', 'request'])
const REQUEST_PARTS = new Set([
  'body', 'query', 'params', 'param', 'headers', 'header', 'cookies',
  'json', 'text', 'formData', 'parseBody', 'url', 'nextUrl', 'originalUrl', 'path',
])
/** AWS Lambda / Netlify handlers: `event.body`, `event.queryStringParameters`. */
const EVENT_PARTS = new Set(['body', 'queryStringParameters', 'pathParameters', 'headers'])

/** Calls whose result is safe to use regardless of input. */
const SANITIZERS = new Set([
  'Number', 'parseInt', 'parseFloat', 'Boolean', 'basename',
  'escape', 'escapeId', 'escapeIdentifier', 'escapeLiteral', 'quote', 'encodeURIComponent',
])
/** Methods that keep a string/object tainted (`input.trim()`, `form.get('x')`). */
const TAINT_PRESERVING_METHODS = new Set([
  'get', 'getAll', 'toString', 'trim', 'toLowerCase', 'toUpperCase',
  'slice', 'substring', 'split', 'join', 'concat',
])
/** `path.join(dir, input)` is still attacker-controlled. */
const PATH_BUILDERS = new Set(['join', 'resolve', 'normalize'])

const HTTP_METHODS = new Set(['get', 'post', 'put', 'patch', 'delete', 'all', 'use'])
const SERVER_OBJECTS = /^(?:app|router|server|fastify|api|route|routes)$/i
const NEXT_HANDLERS = /^(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)$/
const DB_OBJECTS = /db|sql|database|conn|connection|client|pool|knex|sequelize|prisma|pg|mysql|sqlite|tx|trx/i

const FS_METHODS = new Set([
  'readFile', 'readFileSync', 'createReadStream', 'writeFile', 'writeFileSync',
  'appendFile', 'appendFileSync', 'createWriteStream', 'unlink', 'unlinkSync',
  'rm', 'rmSync', 'readdir', 'readdirSync', 'copyFile', 'copyFileSync', 'rename', 'renameSync',
])
/** Unambiguous enough to count when imported bare (`import { readFile }`). */
const FS_BARE = new Set([
  'readFile', 'readFileSync', 'createReadStream', 'writeFile', 'writeFileSync',
  'appendFile', 'appendFileSync', 'createWriteStream', 'unlink', 'unlinkSync',
])

function scriptKindFor(relPath: string): ts.ScriptKind {
  const p = relPath.toLowerCase()
  if (p.endsWith('.tsx')) return ts.ScriptKind.TSX
  if (p.endsWith('.jsx')) return ts.ScriptKind.JSX
  if (p.endsWith('.js') || p.endsWith('.mjs') || p.endsWith('.cjs')) return ts.ScriptKind.JS
  return ts.ScriptKind.TS
}

function unwrap(e: ts.Expression): ts.Expression {
  let cur = e
  for (;;) {
    if (ts.isParenthesizedExpression(cur) || ts.isAwaitExpression(cur) || ts.isNonNullExpression(cur)) {
      cur = cur.expression
    } else if (ts.isAsExpression(cur) || ts.isTypeAssertionExpression(cur) || ts.isSatisfiesExpression(cur)) {
      cur = cur.expression
    } else {
      return cur
    }
  }
}

/** `a.b['c'].d()` → ['a','b','c','d']; null when the root isn't a plain name. */
function chainOf(e: ts.Expression): string[] | null {
  const cur = unwrap(e)
  if (ts.isIdentifier(cur)) return [cur.text]
  if (ts.isPropertyAccessExpression(cur)) {
    const base = chainOf(cur.expression)
    return base ? [...base, cur.name.text] : null
  }
  if (ts.isElementAccessExpression(cur)) {
    const base = chainOf(cur.expression)
    const arg = cur.argumentExpression
    const key = ts.isStringLiteralLike(arg) ? arg.text : '*'
    return base ? [...base, key] : null
  }
  if (ts.isCallExpression(cur)) return chainOf(cur.expression)
  return null
}

function calleeName(call: ts.CallExpression | ts.NewExpression): string | null {
  const c = unwrap(call.expression)
  if (ts.isIdentifier(c)) return c.text
  if (ts.isPropertyAccessExpression(c)) return c.name.text
  return null
}

function receiverName(call: ts.CallExpression): string | null {
  const c = unwrap(call.expression)
  if (!ts.isPropertyAccessExpression(c)) return null
  const chain = chainOf(c.expression)
  return chain ? chain[chain.length - 1] : null
}

type Scope = { tainted: Set<string>; requestNames: Set<string> }

function isRequestSource(e: ts.Expression, scope: Scope): boolean {
  const chain = chainOf(e)
  if (!chain || chain.length < 2) return false
  if (chain[0] === 'event' && EVENT_PARTS.has(chain[1])) return true
  for (let i = 0; i < chain.length - 1; i++) {
    const w = chain[i]
    const isReq = REQUEST_WORDS.has(w) || (i === 0 && scope.requestNames.has(w))
    if (isReq && REQUEST_PARTS.has(chain[i + 1])) return true
  }
  return false
}

/** Human label for the tainted input in messages, e.g. `req.query.id`. */
function describe(e: ts.Expression, sf: ts.SourceFile): string {
  const text = e.getText(sf).replace(/\s+/g, ' ')
  return text.length > 48 ? text.slice(0, 45) + '…' : text
}

function isTainted(e: ts.Expression | undefined, scope: Scope): boolean {
  if (!e) return false
  const cur = unwrap(e)
  if (isRequestSource(cur, scope)) return true

  if (ts.isIdentifier(cur)) return scope.tainted.has(cur.text)
  if (ts.isPropertyAccessExpression(cur) || ts.isElementAccessExpression(cur)) {
    return isTainted(cur.expression, scope)
  }
  if (ts.isTemplateExpression(cur)) return cur.templateSpans.some((s) => isTainted(s.expression, scope))
  if (ts.isBinaryExpression(cur)) {
    const op = cur.operatorToken.kind
    if (
      op === ts.SyntaxKind.PlusToken ||
      op === ts.SyntaxKind.BarBarToken ||
      op === ts.SyntaxKind.QuestionQuestionToken
    ) {
      return isTainted(cur.left, scope) || isTainted(cur.right, scope)
    }
    return false
  }
  if (ts.isConditionalExpression(cur)) return isTainted(cur.whenTrue, scope) || isTainted(cur.whenFalse, scope)
  if (ts.isArrayLiteralExpression(cur)) return cur.elements.some((el) => ts.isExpression(el) && isTainted(el, scope))
  if (ts.isNewExpression(cur)) {
    // new URL(req.url) → its searchParams are still request data.
    return calleeName(cur) === 'URL' && isTainted(cur.arguments?.[0], scope)
  }
  if (ts.isCallExpression(cur)) {
    const name = calleeName(cur)
    if (!name || SANITIZERS.has(name)) return false
    const callee = unwrap(cur.expression)
    if (ts.isIdentifier(callee) && name === 'String') return isTainted(cur.arguments[0], scope)
    if (ts.isPropertyAccessExpression(callee)) {
      const recv = chainOf(callee.expression)
      const isPathBuilder = PATH_BUILDERS.has(name) && recv?.[recv.length - 1] === 'path'
      if (isPathBuilder) return cur.arguments.some((a) => isTainted(a, scope))
      if (TAINT_PRESERVING_METHODS.has(name)) {
        return isTainted(callee.expression, scope) || (name === 'concat' && cur.arguments.some((a) => isTainted(a, scope)))
      }
    }
    return false // unknown call — don't claim a flow we can't see
  }
  return false
}

function bindingNames(name: ts.BindingName): string[] {
  if (ts.isIdentifier(name)) return [name.text]
  const out: string[] = []
  for (const el of name.elements) {
    if (ts.isOmittedExpression(el)) continue
    out.push(...bindingNames(el.name))
  }
  return out
}

function hasShellTrue(args: ts.NodeArray<ts.Expression>): boolean {
  return args.some(
    (a) =>
      ts.isObjectLiteralExpression(a) &&
      a.properties.some(
        (p) =>
          ts.isPropertyAssignment(p) &&
          p.name.getText() === 'shell' &&
          p.initializer.kind === ts.SyntaxKind.TrueKeyword,
      ),
  )
}

/** Which sink this call is, and which argument carries the risk. */
function sinkOf(call: ts.CallExpression, scope: Scope): { category: Category; arg: ts.Expression } | null {
  const name = calleeName(call)
  if (!name) return null
  const callee = unwrap(call.expression)
  const recv = receiverName(call)
  const a0 = call.arguments[0]
  if (!a0) return null

  // Shell
  if (name === 'exec' || name === 'execSync') {
    if (ts.isIdentifier(callee) || (recv && /^(?:child_process|cp|childProcess|proc)$/.test(recv))) {
      return { category: 'command', arg: a0 }
    }
    if (recv && DB_OBJECTS.test(recv)) return { category: 'sql', arg: a0 } // sqlite db.exec(sql)
    return null // RegExp.exec etc.
  }
  if (/^(?:spawn|spawnSync|execFile|execFileSync)$/.test(name) && hasShellTrue(call.arguments)) {
    const risky = call.arguments.find((a) => isTainted(a, scope))
    return risky ? { category: 'command', arg: risky } : null
  }

  // Code
  if (ts.isIdentifier(callee) && name === 'eval') return { category: 'code', arg: a0 }
  if (recv === 'vm' && /^run(?:In(?:New|This)?Context)$/.test(name)) return { category: 'code', arg: a0 }
  if (ts.isIdentifier(callee) && (name === 'setTimeout' || name === 'setInterval')) {
    return ts.isFunctionLike(unwrap(a0)) ? null : { category: 'code', arg: a0 }
  }

  // SQL — a string argument, never a tagged template (TaggedTemplateExpression
  // is a different node and isn't treated as tainted).
  if (/^(?:query|execute|raw|unsafe|\$queryRawUnsafe|\$executeRawUnsafe)$/.test(name) && ts.isPropertyAccessExpression(callee)) {
    return { category: 'sql', arg: a0 }
  }
  if (name === 'prepare' && recv && DB_OBJECTS.test(recv)) return { category: 'sql', arg: a0 }

  // Filesystem paths
  if (name === 'sendFile' || name === 'download') {
    if (recv && /^(?:res|response|reply)$/.test(recv)) return { category: 'path', arg: a0 }
    return null
  }
  if (FS_METHODS.has(name)) {
    if (ts.isIdentifier(callee) && FS_BARE.has(name)) return { category: 'path', arg: a0 }
    if (recv && /^(?:fs|fsp|promises|fsPromises|fse)$/.test(recv)) return { category: 'path', arg: a0 }
  }
  return null
}

/** A handler that validates the path (`resolved.startsWith(root)`, rejects `..`) is out of scope for a local check. */
function looksPathGuarded(fn: ts.Node | undefined, sf: ts.SourceFile): boolean {
  if (!fn) return false
  return /\.startsWith\(|['"`]\.\.['"`/]/.test(fn.getText(sf))
}

/** First param of `app.get('/x', (req, res) => …)` / Next `export function GET(request)`. */
function requestParamName(fn: ts.SignatureDeclaration): string | null {
  const first = fn.parameters[0]
  if (!first || !ts.isIdentifier(first.name)) return null
  const parent = fn.parent
  if (parent && ts.isCallExpression(parent) && parent.arguments.includes(fn as unknown as ts.Expression)) {
    const callee = unwrap(parent.expression)
    if (ts.isPropertyAccessExpression(callee) && HTTP_METHODS.has(callee.name.text.toLowerCase())) {
      const obj = chainOf(callee.expression)
      if (obj && SERVER_OBJECTS.test(obj[obj.length - 1])) return first.name.text
    }
  }
  if (ts.isFunctionDeclaration(fn) && fn.name && NEXT_HANDLERS.test(fn.name.text)) return first.name.text
  return null
}

export function checkInjection(files: SourceFile[]): Finding[] {
  const findings: Finding[] = []
  for (const file of files) {
    if (/\.(test|spec)\.[jt]sx?$/.test(file.relPath)) continue
    if (/(?:^|\/)(?:fixtures?|__mocks__|mocks?)\//i.test(file.relPath)) continue
    const sf = ts.createSourceFile(file.relPath, file.text, ts.ScriptTarget.Latest, true, scriptKindFor(file.relPath))
    const seen = new Set<string>()

    const visit = (node: ts.Node, scope: Scope, fn: ts.Node | undefined): void => {
      if (ts.isFunctionLike(node) && 'body' in node && node.body) {
        const inner: Scope = { tainted: new Set(scope.tainted), requestNames: new Set(scope.requestNames) }
        const reqName = requestParamName(node)
        if (reqName) inner.requestNames.add(reqName)
        // Next route handlers: `GET(req, { params })` — params are request input.
        if (ts.isFunctionDeclaration(node) && node.name && NEXT_HANDLERS.test(node.name.text) && node.parameters[1]) {
          for (const n of bindingNames(node.parameters[1].name)) inner.tainted.add(n)
        }
        ts.forEachChild(node, (child) => visit(child, inner, node))
        return
      }

      if (ts.isVariableDeclaration(node) && node.initializer && isTainted(node.initializer, scope)) {
        for (const n of bindingNames(node.name)) scope.tainted.add(n)
      }
      if (
        ts.isBinaryExpression(node) &&
        node.operatorToken.kind === ts.SyntaxKind.EqualsToken &&
        ts.isIdentifier(node.left) &&
        isTainted(node.right, scope)
      ) {
        scope.tainted.add(node.left.text)
      }

      const isNewFunction = ts.isNewExpression(node) && calleeName(node) === 'Function'
      if (ts.isCallExpression(node) || isNewFunction) {
        let hit: { category: Category; arg: ts.Expression } | null = null
        if (isNewFunction) {
          const risky = (node as ts.NewExpression).arguments?.find((a) => isTainted(a, scope))
          if (risky) hit = { category: 'code', arg: risky }
        } else {
          const sink = sinkOf(node as ts.CallExpression, scope)
          if (sink && isTainted(sink.arg, scope)) hit = sink
        }
        if (hit && !(hit.category === 'path' && looksPathGuarded(fn, sf))) {
          const line = sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1
          const key = `${line}:${hit.category}`
          if (!seen.has(key)) {
            seen.add(key)
            findings.push({
              check: 'injection',
              severity: 'finding',
              file: file.relPath,
              line,
              message: `Request input (${describe(hit.arg, sf)}) ${MESSAGES[hit.category]}`,
              fixHint: 'open-editor',
            })
          }
        }
      }
      ts.forEachChild(node, (child) => visit(child, scope, fn))
    }

    visit(sf, { tainted: new Set(), requestNames: new Set() }, undefined)
  }
  return findings
}
