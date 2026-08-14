import ts from 'typescript'
import type { SourceFile } from '../scan.js'
import type { Finding } from '../report.js'
import { stripComments } from '../stripComments.js'

/**
 * Contract drift v2 — path + HTTP method agreement, Next App/Pages routes,
 * and a cheap auth-header check (server requires token, client fetch omits it).
 * Still deterministic; LLM pass remains optional elsewhere.
 */

type RouteHit = {
  path: string
  method: string // GET|POST|…|ALL
  file: string
  line: number
  side: 'server' | 'client'
  /** True when this call site sets Authorization / getIdToken / Bearer */
  hasAuth?: boolean
}

function normalizePath(raw: string): string | null {
  let p = raw.trim()
  if (!p.startsWith('/')) return null
  p = p.split('?')[0].split('#')[0]
  p = p.replace(/\$\{[^}]+\}/g, ':param')
  p = p.replace(/:[A-Za-z_][\w]*/g, ':param')
  p = p.replace(/\[([^\]]+)\]/g, ':param')
  p = p.replace(/\/{2,}/g, '/')
  if (p.length > 1 && p.endsWith('/')) p = p.slice(0, -1)
  return p
}

/** Objects whose `.get('/x')` etc. mean an HTTP route mount, not a Map/cache. */
const SERVER_OBJECTS = /^(?:app|router|server|fastify|api|route)$/i
/** HTTP-client instances: `axios.get('/x')`, `api.post('/x')`. */
const CLIENT_OBJECTS = /^(?:axios|ky|ofetch|api|http|client)$/i
const HTTP_METHODS = new Set(['get', 'post', 'put', 'patch', 'delete', 'options', 'head', 'all'])

function scriptKindFor(relPath: string): ts.ScriptKind {
  const p = relPath.toLowerCase()
  if (p.endsWith('.tsx')) return ts.ScriptKind.TSX
  if (p.endsWith('.jsx')) return ts.ScriptKind.JSX
  if (p.endsWith('.js') || p.endsWith('.mjs') || p.endsWith('.cjs')) return ts.ScriptKind.JS
  return ts.ScriptKind.TS
}

/** Parse once per file. TS's parser never throws — it recovers from syntax
 *  errors — so a malformed file yields a partial tree rather than a crash. */
function parse(file: SourceFile): ts.SourceFile {
  return ts.createSourceFile(
    file.relPath,
    file.text,
    ts.ScriptTarget.Latest,
    /* setParentNodes */ true,
    scriptKindFor(file.relPath),
  )
}

function lineOf(sf: ts.SourceFile, node: ts.Node): number {
  return sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1
}

/** Static string value of a call argument: a plain string or a backtick with
 *  no interpolation. Anything with `${…}` is handled as a template elsewhere. */
function staticStringArg(node: ts.Node | undefined): string | null {
  if (!node) return null
  if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) return node.text
  return null
}

/** Reconstruct a template URL as raw text (`${API_BASE}/scan`) plus the leading
 *  interpolated identifier, if the template starts with `${VAR}`. */
function templateInfo(node: ts.Node): { raw: string; baseVar: string | null } | null {
  if (ts.isNoSubstitutionTemplateLiteral(node)) return { raw: node.text, baseVar: null }
  if (!ts.isTemplateExpression(node)) return null
  let raw = node.head.text
  let baseVar: string | null = null
  if (node.head.text === '' && node.templateSpans.length) {
    const first = node.templateSpans[0].expression
    if (ts.isIdentifier(first)) baseVar = first.text
  }
  for (const span of node.templateSpans) {
    raw += '${' + span.expression.getText(node.getSourceFile()) + '}' + span.literal.text
  }
  return { raw, baseVar }
}

/** `{ method: 'POST' }` in a fetch/axios options object → "POST". */
function methodFromOptions(node: ts.Node | undefined): string | null {
  if (!node || !ts.isObjectLiteralExpression(node)) return null
  for (const prop of node.properties) {
    if (
      ts.isPropertyAssignment(prop) &&
      ts.isIdentifier(prop.name) &&
      prop.name.text === 'method'
    ) {
      const v = staticStringArg(prop.initializer)
      if (v) return v.toUpperCase()
    }
  }
  return null
}

function identifierName(node: ts.Expression): string | null {
  return ts.isIdentifier(node) ? node.text : null
}

/** Depth-first walk over every node in a parsed file. */
function walk(node: ts.Node, visit: (n: ts.Node) => void): void {
  visit(node)
  node.forEachChild((child) => walk(child, visit))
}

/** Next App Router file → /api/... */
function nextAppRoute(relPath: string): string | null {
  const m = relPath.replace(/\\/g, '/').match(/(?:^|\/)app\/(api\/.+)\/route\.[jt]sx?$/)
  if (!m) return null
  return normalizePath('/' + m[1])
}

/** Next Pages Router: pages/api/foo/bar.ts → /api/foo/bar */
function nextPagesRoute(relPath: string): string | null {
  const m = relPath.replace(/\\/g, '/').match(/(?:^|\/)pages\/api\/(.+)\.[jt]sx?$/)
  if (!m) return null
  let rest = m[1].replace(/\/index$/, '')
  rest = rest.replace(/\[([^\]]+)\]/g, ':param')
  return normalizePath('/api/' + rest)
}

const NEXT_METHOD = /export\s+(?:async\s+)?function\s+(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)\b/g

function nextMethodsInFile(code: string): string[] {
  const methods: string[] = []
  NEXT_METHOD.lastIndex = 0
  let m: RegExpExecArray | null
  while ((m = NEXT_METHOD.exec(code))) methods.push(m[1].toUpperCase())
  return methods.length ? methods : ['ALL']
}

const AUTH_HINT =
  /Authorization|Bearer\s|getIdToken|getAccessToken|authHeaders|auth\.currentUser|FirebaseAuth|headers\s*:\s*\{[^}]*(?:authorization|Authorization)/i

/**
 * TRACE-class client calls: `fetch(\`${API_BASE}/scan\`, …)`.
 * Strip a leading `${BASE}` / absolute host and keep the static path suffix.
 * Purely dynamic URLs (`${XON_ENDPOINT}/${encode…}`) return null.
 */
function pathFromTemplateLiteral(raw: string): string | null {
  if (/https?:\/\//.test(raw) && !/localhost|127\.0\.0\.1/.test(raw)) return null

  // `${API_BASE}/scan` or `${API_BASE}/removal-requests/send`
  const afterBase = raw.match(/\$\{[^}]+\}(\/[A-Za-z][\w/-]*(?:\/[A-Za-z][\w/-]*)*)/)
  if (afterBase) {
    const staticPath = afterBase[1].replace(/\$\{[^}]+\}/g, ':param')
    return pathFromRaw(staticPath)
  }

  // `` `/api/${id}/x` `` — no host placeholder
  if (raw.trimStart().startsWith('/')) {
    return pathFromRaw(raw.replace(/\$\{[^}]+\}/g, ':param'))
  }

  return null
}

function serverRequiresAuth(files: SourceFile[]): boolean {
  return files.some((f) => {
    if (!/(route|middleware|auth|server|api)/i.test(f.relPath)) return false
    const code = stripComments(f.text)
    return /verifyIdToken|getAuth\(|requireAuth|authenticate|Authorization|Bearer/.test(code)
  })
}

function extractServerRoutes(files: SourceFile[]): RouteHit[] {
  const hits: RouteHit[] = []
  for (const file of files) {
    const code = stripComments(file.text)
    const nextApp = nextAppRoute(file.relPath)
    if (nextApp) {
      for (const method of nextMethodsInFile(code)) {
        hits.push({ path: nextApp, method, file: file.relPath, line: 1, side: 'server' })
      }
    }
    const nextPages = nextPagesRoute(file.relPath)
    if (nextPages) {
      hits.push({ path: nextPages, method: 'ALL', file: file.relPath, line: 1, side: 'server' })
    }

    // `app.get('/x', …)` / `router.post('/x', …)` — a real call expression, not
    // the same text sitting inside a string literal or comment.
    const sf = parse(file)
    walk(sf, (node) => {
      if (!ts.isCallExpression(node)) return
      const callee = node.expression
      if (!ts.isPropertyAccessExpression(callee)) return
      const method = callee.name.text.toLowerCase()
      if (!HTTP_METHODS.has(method)) return
      const obj = identifierName(callee.expression)
      if (!obj || !SERVER_OBJECTS.test(obj)) return
      const literal = staticStringArg(node.arguments[0])
      if (!literal) return
      const path = normalizePath(literal)
      if (!path) return
      hits.push({
        path,
        method: method === 'all' ? 'ALL' : method.toUpperCase(),
        file: file.relPath,
        line: lineOf(sf, node),
        side: 'server',
      })
    })
  }
  return hits
}

function pathFromRaw(raw: string): string | null {
  const pathPart = raw.includes('://') ? raw.replace(/^https?:\/\/[^/]+/, '') : raw
  if (raw.includes('://') && !/localhost|127\.0\.0\.1/.test(raw)) return null
  const path = normalizePath(
    pathPart.startsWith('/')
      ? pathPart
      : pathPart.includes('/')
        ? '/' + pathPart.split('/').slice(-2).join('/')
        : '',
  )
  if (!path || path === '/') return null
  if (/[…·]/.test(path) || /\.(png|jpg|svg|css|json|ico|woff2?)$/i.test(path)) return null
  // Framework / static noise — not API contracts.
  if (/^\/(_next|static|assets|public|favicon|__)\b/i.test(path)) return null
  return path
}

function isTestOrStoryFile(relPath: string): boolean {
  const p = relPath.replace(/\\/g, '/')
  return (
    /\.(test|spec|stories)\.[jt]sx?$/i.test(p) ||
    /\/(__tests__|__mocks__|fixtures|mocks)\//i.test(p)
  )
}

/**
 * Local dev tooling — demo scripts, seeders, migrations, CLI helpers — that
 * `fetch`es the backend's own routes over localhost. These are NOT the product
 * frontend, so they must not define the "client contract": a demo that touches
 * 4 endpoints would otherwise make every other route look like a dead endpoint.
 */
function isNonClientScript(relPath: string): boolean {
  const p = relPath.replace(/\\/g, '/')
  return (
    /(?:^|\/)(demo|seed|seeds?|migrate|migration|script|scripts|bench|benchmark|examples?|e2e|smoke|fixtures?)(?:\/|[.-])/i.test(
      p,
    ) ||
    /(?:^|\/)(bin|tools|scripts|migrations|seeds)\//i.test(p) ||
    /\.(seed|demo|script|migration)\.[jt]sx?$/i.test(p)
  )
}

/** Server-only routes that often have no in-repo client (webhooks, health). */
function isServerOnlyExpected(path: string): boolean {
  return /\/(health|ready|livez|readyz|webhook|hooks|cron|internal|admin\/ping)(\/|$)/i.test(path)
}

/**
 * Base-URL constants that point at a HARDCODED third-party host (Microsoft
 * Graph, Stripe, an OAuth provider…) rather than this app's own backend.
 * Own-backend bases are env-driven (`process.env.X || '…'`); third-party
 * bases are plain literals. Calls through these are outbound integrations,
 * not the app↔API contract — counting them floods a backend-only scan with
 * "client calls /servicePrincipals but no matching server route".
 */
function thirdPartyBaseVars(code: string): Set<string> {
  const names = new Set<string>()
  const RE = /(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*([^\n]+)/g
  let m: RegExpExecArray | null
  while ((m = RE.exec(code))) {
    const name = m[1]
    const rhs = m[2]
    const envBased = /process\.env|import\.meta\.env|Deno\.env/.test(rhs)
    const externalLiteral = /['"`]https?:\/\/(?!localhost|127\.0\.0\.1)/.test(rhs)
    if (externalLiteral && !envBased) names.add(name)
  }
  return names
}

/** Client verbs we treat as HTTP contract calls (not `.head`/`.options`/`.all`). */
const CLIENT_HTTP_METHODS = new Set(['get', 'post', 'put', 'patch', 'delete'])

function extractClientCalls(files: SourceFile[]): RouteHit[] {
  const hits: RouteHit[] = []
  for (const file of files) {
    if (/\/route\.[jt]sx?$/.test(file.relPath)) continue
    if (/(?:^|\/)pages\/api\//.test(file.relPath.replace(/\\/g, '/'))) continue
    if (isNonClientScript(file.relPath)) continue

    const thirdParty = thirdPartyBaseVars(stripComments(file.text))
    const sf = parse(file)

    const record = (node: ts.CallExpression, path: string | null, method: string) => {
      if (!path) return
      const start = node.getStart(sf)
      // Widen slightly above the call — `const h = await authHeaders()` often
      // sits just before the fetch — to judge whether a token is attached.
      const window = file.text.slice(Math.max(0, start - 180), node.getEnd() + 40)
      hits.push({
        path,
        method,
        file: file.relPath,
        line: lineOf(sf, node),
        side: 'client',
        hasAuth: AUTH_HINT.test(window),
      })
    }

    const fromArg = (
      node: ts.CallExpression,
      arg: ts.Node | undefined,
      method: string,
    ): void => {
      const lit = staticStringArg(arg)
      if (lit != null) {
        record(node, pathFromRaw(lit), method)
        return
      }
      if (!arg) return
      const tpl = templateInfo(arg)
      if (!tpl) return
      if (tpl.baseVar && thirdParty.has(tpl.baseVar)) return
      record(node, pathFromTemplateLiteral(tpl.raw), method)
    }

    walk(sf, (node) => {
      if (!ts.isCallExpression(node)) return
      const callee = node.expression

      // fetch('/x' | `${BASE}/x`, { method })
      if (ts.isIdentifier(callee) && callee.text === 'fetch') {
        fromArg(node, node.arguments[0], methodFromOptions(node.arguments[1]) ?? 'GET')
        return
      }

      // axios.get('/x') / api.post(`${BASE}/x`) — a real HTTP-client instance.
      if (ts.isPropertyAccessExpression(callee)) {
        const method = callee.name.text.toLowerCase()
        if (!CLIENT_HTTP_METHODS.has(method)) return
        const obj = identifierName(callee.expression)
        if (!obj || !CLIENT_OBJECTS.test(obj)) return
        fromArg(node, node.arguments[0], method.toUpperCase())
      }
    })
  }
  return hits
}

function pathsMatch(a: string, b: string): boolean {
  if (a === b) return true
  const as = a.split('/')
  const bs = b.split('/')
  if (as.length !== bs.length) return false
  for (let i = 0; i < as.length; i++) {
    if (as[i] === ':param' || bs[i] === ':param') continue
    if (as[i] !== bs[i]) return false
  }
  return true
}

function methodsCompatible(server: string, client: string): boolean {
  if (server === 'ALL' || client === 'ALL') return true
  return server === client
}

export function checkContractDrift(files: SourceFile[]): Finding[] {
  const sourceFiles = files.filter((f) => !isTestOrStoryFile(f.relPath))
  const servers = extractServerRoutes(sourceFiles)
  const clients = extractClientCalls(sourceFiles)
  if (servers.length === 0 || clients.length === 0) return []

  const findings: Finding[] = []
  const seen = new Set<string>()
  const authRequired = serverRequiresAuth(sourceFiles)

  for (const call of clients) {
    const pathHits = servers.filter((s) => pathsMatch(s.path, call.path))
    if (pathHits.length === 0) {
      const key = `client:${call.path}:${call.file}`
      if (seen.has(key)) continue
      seen.add(key)
      findings.push({
        check: 'contract-drift',
        severity: 'finding',
        file: call.file,
        line: call.line,
        message: `Client calls "${call.path}" but no matching server route was found — frontend expects an API the backend may no longer serve.`,
        fixHint: 'open-editor',
      })
      continue
    }

    const methodOk = pathHits.some((s) => methodsCompatible(s.method, call.method))
    if (!methodOk) {
      const key = `method:${call.method}:${call.path}:${call.file}`
      if (!seen.has(key)) {
        seen.add(key)
        const served = [...new Set(pathHits.map((s) => s.method))].join(', ')
        findings.push({
          check: 'contract-drift',
          severity: 'finding',
          file: call.file,
          line: call.line,
          message: `Client calls ${call.method} "${call.path}" but server only exposes [${served}] — method mismatch (silent 405 / wrong handler).`,
          fixHint: 'open-editor',
        })
      }
    }

    // Auth drift: only /api* and only when the call site clearly has no token helper
    // in a wider window (spread authHeaders() often sits just above fetch).
    if (authRequired && call.path.startsWith('/api') && call.hasAuth === false) {
      const key = `auth:${call.path}:${call.file}:${call.line}`
      if (!seen.has(key)) {
        seen.add(key)
        findings.push({
          check: 'contract-drift',
          severity: 'finding',
          file: call.file,
          line: call.line,
          message: `Client fetch to "${call.path}" has no Authorization / token helper nearby, but this repo’s server/auth layer looks like it requires auth — the TRACE-class silent production failure.`,
          fixHint: 'open-editor',
        })
      }
    }
  }

  // "Dead endpoint" (server route with no client) is only trustworthy when the
  // client tree is actually part of this scan. If NOT a single client call
  // lines up with ANY server route, the frontend for these routes lives in a
  // different repo (backend-only scan) — flagging every route as dead is noise.
  const clientTreePresent = clients.some((c) =>
    servers.some((s) => pathsMatch(s.path, c.path)),
  )

  for (const route of servers) {
    if (!clientTreePresent) break
    if (isServerOnlyExpected(route.path)) continue
    const matched = clients.some(
      (c) => pathsMatch(c.path, route.path) && methodsCompatible(route.method, c.method),
    )
    if (matched) continue
    const key = `server:${route.method}:${route.path}:${route.file}`
    if (seen.has(key)) continue
    // Avoid flooding: one warning per path
    const pathKey = `serverpath:${route.path}`
    if (seen.has(pathKey)) continue
    seen.add(pathKey)
    seen.add(key)
    findings.push({
      check: 'contract-drift',
      severity: 'warning',
      file: route.file,
      line: route.line,
      message: `Server route ${route.method} "${route.path}" has no matching client call — dead endpoint or a client outside this tree.`,
      fixHint: 'open-editor',
    })
  }

  return findings
}

export type DriftRoute = {
  method: string
  path: string
  file: string
  line: number
}

export type DriftSurface = {
  server: DriftRoute[]
  client: DriftRoute[]
}

function toDriftRoutes(hits: RouteHit[]): DriftRoute[] {
  const seen = new Set<string>()
  const out: DriftRoute[] = []
  for (const r of hits) {
    const key = `${r.method} ${r.path} ${r.file}:${r.line}`
    if (seen.has(key)) continue
    seen.add(key)
    out.push({ method: r.method, path: r.path, file: r.file, line: r.line })
  }
  return out
}

export function summarizeDriftSurfaces(files: SourceFile[]): DriftSurface {
  return {
    server: toDriftRoutes(extractServerRoutes(files)),
    client: toDriftRoutes(extractClientCalls(files)),
  }
}
