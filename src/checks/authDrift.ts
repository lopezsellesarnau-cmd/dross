import ts from 'typescript'
import { existsSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import type { SourceFile } from '../scan.js'
import type { Finding } from '../report.js'

/**
 * Auth drift — the server disagreeing with itself. When an app has clearly
 * adopted auth (some routes require it) and a route that changes data
 * (POST/PUT/PATCH/DELETE) or lives under /admin doesn't, that route is
 * open to anyone. The TRACE-class bug, but between two routes of the same
 * backend instead of client vs API.
 *
 * Deliberately does NOT guess which routes "should" be protected in an app
 * with no auth at all — no evidence, no finding. Public-by-design paths
 * (login, webhooks, OAuth callbacks, health…) are never flagged.
 *
 * A route counts as protected when any of these is visible:
 *   - an auth-looking middleware argument (`requireAuth`, `passport.authenticate(…)`)
 *   - an earlier `x.use(auth)` on the same object, or `x.use('/prefix', auth)` covering it
 *   - its router file is mounted behind auth elsewhere (`app.use('/admin', requireAdmin, adminRoutes)`)
 *   - the handler checks auth itself (`req.user`, `getServerSession`, `verifyIdToken`…)
 */

const METHODS = new Set(['get', 'post', 'put', 'patch', 'delete', 'all'])
const MUTATING = new Set(['POST', 'PUT', 'PATCH', 'DELETE', 'ALL'])
const ROUTER_OBJECT = /(?:^app$|^server$|^fastify$|^api$|router$|routes?$|^r$)/i
const NEXT_HANDLER = /^(?:POST|PUT|PATCH|DELETE)$/

/** Middleware names/calls that mean "this request must be authenticated/authorized". */
const AUTH_MIDDLEWARE =
  /auth|protect|verif|require(?:User|Login|Admin|Role|Session|Token|Auth)|ensure|isLogged|loggedIn|isAdmin|guard|jwt|session|passport|clerk|permission|role|firebase|apiKey|bearer/i

/**
 * Auth *enforced* inside a handler or inline middleware: reading the
 * logged-in user, verifying a token, or rejecting with 401/403. Merely
 * naming the `Authorization` header doesn't count — a CORS middleware lists
 * it in Access-Control-Allow-Headers and would otherwise "protect" every route.
 */
const AUTH_IN_HANDLER =
  /\b(?:req|request|ctx|c)\.(?:user|userId|auth|session)\b|getServerSession|getSession\s*\(|\bauth\s*\(\s*\)|currentUser|verifyIdToken|verify\w*Token\s*\(|getAuth\s*\(|jwt\.verify|supabase\.auth|getUser\s*\(|clerk|status\(\s*40[13]\s*\)|sendStatus\(\s*40[13]\s*\)/i

/** Capability links — the secret in the URL *is* the credential (invites, magic links). */
const CAPABILITY_PARAM = /:(?:token|\w*Token|code|secret|signature|sig|hash|nonce)\b/i

/** Public by design — never flagged even when unauthenticated. */
const PUBLIC_PATH =
  /(?:^|\/)(?:login|logout|signin|signout|sign-in|sign-up|signup|register|auth|oauth|sso|callback|webhooks?|hooks|stripe|health|healthz|ping|status|public|password|reset|forgot|verify|magic-link|otp|token|refresh|session|contact|newsletter|subscribe|waitlist|unsubscribe)(?:\/|$|-)/i

function scriptKindFor(relPath: string): ts.ScriptKind {
  const p = relPath.toLowerCase()
  if (p.endsWith('.tsx')) return ts.ScriptKind.TSX
  if (p.endsWith('.jsx')) return ts.ScriptKind.JSX
  if (p.endsWith('.js') || p.endsWith('.mjs') || p.endsWith('.cjs')) return ts.ScriptKind.JS
  return ts.ScriptKind.TS
}

function lastName(e: ts.Expression): string | null {
  if (ts.isIdentifier(e)) return e.text
  if (ts.isPropertyAccessExpression(e)) return e.name.text
  if (ts.isCallExpression(e)) return lastName(e.expression)
  return null
}

function stringArg(e: ts.Expression | undefined): string | null {
  if (!e) return null
  if (ts.isStringLiteral(e) || ts.isNoSubstitutionTemplateLiteral(e)) return e.text
  return null
}

function normalizePath(raw: string): string {
  let p = raw.split('?')[0]
  p = p.replace(/:[A-Za-z_]\w*/g, ':param').replace(/\[([^\]]+)\]/g, ':param').replace(/\/{2,}/g, '/')
  if (p.length > 1 && p.endsWith('/')) p = p.slice(0, -1)
  return p
}

function joinPaths(prefix: string, path: string): string {
  if (!prefix || prefix === '/') return path
  return normalizePath(prefix.replace(/\/\*$/, '') + (path === '/' ? '' : path))
}

/** `/api/*` or `/api` covers `/api/users` — how `use(prefix, auth)` scopes. */
function prefixCovers(prefix: string, path: string): boolean {
  const p = prefix.replace(/\*+$/, '').replace(/\/$/, '')
  return p === '' || path === p || path.startsWith(p + '/')
}

function isFunctionExpr(e: ts.Expression): e is ts.ArrowFunction | ts.FunctionExpression {
  return ts.isArrowFunction(e) || ts.isFunctionExpression(e)
}

function looksLikeAuth(e: ts.Expression, sf: ts.SourceFile): boolean {
  // Inline middleware `(req, res, next) => { if (!req.user) … }` — judge its body.
  if (isFunctionExpr(e)) return AUTH_IN_HANDLER.test(e.getText(sf))
  return AUTH_MIDDLEWARE.test(e.getText(sf))
}

type Route = {
  method: string
  path: string
  /** Path as written, before `:id` → `:param` — keeps param names for CAPABILITY_PARAM. */
  rawPath: string
  file: string
  line: number
  protected: boolean
  authName?: string
  /** Whether we could read the handler's code at all. Unknown handlers are never flagged. */
  handlerVisible: boolean
  /** Handler referenced by name and imported from another file — resolved later. */
  handlerImport?: string
}

type FileFacts = {
  file: SourceFile
  routes: Route[]
  /** Local router names mounted behind auth in this file → their import specifier. */
  protectedMounts: string[]
  imports: Map<string, string>
}

const RESOLVE_EXT = ['', '.ts', '.tsx', '.js', '.mjs', '.cjs', '/index.ts', '/index.js']

function resolveImport(fromAbs: string, spec: string, known: Set<string>): string | null {
  if (!spec.startsWith('.')) return null
  const base = resolve(dirname(fromAbs), spec)
  const candidates = [base, base.replace(/\.(?:m|c)?js$/, '')]
  for (const c of candidates) {
    for (const ext of RESOLVE_EXT) {
      const p = c + ext
      if (known.has(p)) return p
    }
  }
  return null
}

function analyzeFile(file: SourceFile): FileFacts {
  const sf = ts.createSourceFile(file.relPath, file.text, ts.ScriptTarget.Latest, true, scriptKindFor(file.relPath))
  const facts: FileFacts = { file, routes: [], protectedMounts: [], imports: new Map() }
  /** Per router object: `use()` calls seen so far, in source order. */
  const uses = new Map<string, { prefix: string; auth: boolean; authName?: string }[]>()
  const localFns = new Map<string, string>()
  /** Routes whose handler is referenced by name — resolved after the walk (hoisting). */
  const byName: { route: Route; name: string }[] = []

  const visit = (node: ts.Node): void => {
    // import x from './routes/admin' / const x = require('./routes/admin')
    if (ts.isImportDeclaration(node) && ts.isStringLiteral(node.moduleSpecifier) && node.importClause) {
      const spec = node.moduleSpecifier.text
      if (node.importClause.name) facts.imports.set(node.importClause.name.text, spec)
      const bindings = node.importClause.namedBindings
      if (bindings && ts.isNamedImports(bindings)) for (const el of bindings.elements) facts.imports.set(el.name.text, spec)
      if (bindings && ts.isNamespaceImport(bindings)) facts.imports.set(bindings.name.text, spec)
    }
    // Local handlers: function x() {} / const x = (req, res) => {}
    if (ts.isFunctionDeclaration(node) && node.name && node.body) localFns.set(node.name.text, node.getText(sf))
    if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.initializer && isFunctionExpr(node.initializer)) {
      localFns.set(node.name.text, node.initializer.getText(sf))
    }
    if (
      ts.isVariableDeclaration(node) &&
      ts.isIdentifier(node.name) &&
      node.initializer &&
      ts.isCallExpression(node.initializer) &&
      ts.isIdentifier(node.initializer.expression) &&
      node.initializer.expression.text === 'require'
    ) {
      const spec = stringArg(node.initializer.arguments[0])
      if (spec) facts.imports.set(node.name.text, spec)
    }

    if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression)) {
      const verb = node.expression.name.text
      const objName = lastName(node.expression.expression)
      if (objName && ROUTER_OBJECT.test(objName)) {
        const args = [...node.arguments]
        const prefix = stringArg(args[0])
        const rest = prefix != null ? args.slice(1) : args

        if (verb === 'use') {
          // An imported router (`authRoutes`) is a mount, not auth middleware.
          const isImportedRouter = (a: ts.Expression) => ts.isIdentifier(a) && facts.imports.has(a.text)
          const authArg = rest.find((a) => !isImportedRouter(a) && looksLikeAuth(a, sf))
          const list = uses.get(objName) ?? []
          list.push({ prefix: prefix ?? '', auth: !!authArg, authName: authArg ? lastName(authArg) ?? undefined : undefined })
          uses.set(objName, list)
          // Router mounted behind auth — here, or by an earlier global use(auth).
          const coveredBefore = list.slice(0, -1).some((u) => u.auth && prefixCovers(u.prefix, prefix ?? '/'))
          if (authArg || coveredBefore) {
            for (const a of rest) if (isImportedRouter(a)) facts.protectedMounts.push((a as ts.Identifier).text)
          }
        } else if (METHODS.has(verb.toLowerCase()) && prefix != null && rest.length > 0) {
          const handler = rest[rest.length - 1]
          const middleware = rest.slice(0, -1)
          const path = normalizePath(prefix)
          const mw = middleware.find((m) => looksLikeAuth(m, sf))
          const priorUse = (uses.get(objName) ?? []).find((u) => u.auth && prefixCovers(u.prefix, path))
          const ref = handlerRef(handler)
          const route: Route = {
            method: verb.toLowerCase() === 'all' ? 'ALL' : verb.toUpperCase(),
            path,
            rawPath: prefix,
            file: file.relPath,
            line: sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1,
            protected: !!mw || !!priorUse,
            authName: (mw && lastName(mw)) || priorUse?.authName,
            handlerVisible: false,
          }
          if (ref.fn) {
            route.handlerVisible = true
            route.protected ||= AUTH_IN_HANDLER.test(ref.fn.getText(sf))
          } else if (ref.name) {
            byName.push({ route, name: ref.name })
          }
          facts.routes.push(route)
        }
      }
    }

    // Next.js App Router: app/api/**/route.ts → export async function POST(…)
    if (ts.isFunctionDeclaration(node) && node.name && NEXT_HANDLER.test(node.name.text)) {
      const route = file.relPath.replace(/\\/g, '/').match(/(?:^|\/)app\/(api\/.+)\/route\.[jt]sx?$/)
      if (route) {
        facts.routes.push({
          method: node.name.text,
          path: normalizePath('/' + route[1]),
          rawPath: '/' + route[1].replace(/\[(?:\.\.\.)?(\w+)\]/g, ':$1'),
          file: file.relPath,
          line: sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1,
          protected: AUTH_IN_HANDLER.test(node.getText(sf)),
          handlerVisible: true,
        })
      }
    }
    ts.forEachChild(node, visit)
  }
  visit(sf)
  for (const { route, name } of byName) {
    const local = localFns.get(name)
    if (local != null) {
      route.handlerVisible = true
      route.protected ||= AUTH_IN_HANDLER.test(local)
    } else if (facts.imports.has(name)) {
      route.handlerImport = facts.imports.get(name)
    }
  }
  return facts
}

/**
 * What a route's handler argument points at: an inline function, or the
 * name to look up (`createUser`, `userController.create` → `userController`).
 * Wrappers like `asyncHandler(fn)` are unwrapped to their last argument.
 */
function handlerRef(e: ts.Expression): { fn?: ts.Node; name?: string } {
  if (isFunctionExpr(e)) return { fn: e }
  if (ts.isCallExpression(e) && e.arguments.length) return handlerRef(e.arguments[e.arguments.length - 1])
  let cur: ts.Expression = e
  while (ts.isPropertyAccessExpression(cur)) cur = cur.expression
  return ts.isIdentifier(cur) ? { name: cur.text } : {}
}

/** Next.js `middleware.ts` that does auth protects the app routes it matches — treat as all. */
function nextMiddlewareProtects(files: SourceFile[]): boolean {
  return files.some(
    (f) => /(?:^|\/)(?:src\/)?middleware\.[jt]s$/.test(f.relPath.replace(/\\/g, '/')) && AUTH_MIDDLEWARE.test(f.text),
  )
}

function isSkippedFile(relPath: string): boolean {
  const p = relPath.replace(/\\/g, '/')
  return (
    /\.(test|spec)\.[jt]sx?$/.test(p) ||
    // Tests, tooling, and sample apps — not the app being shipped.
    /(?:^|\/)(?:__tests__|__mocks__|fixtures?|mocks?|scripts?|e2e|corpus|examples?|samples?)\//i.test(p)
  )
}

/**
 * "This app" = the nearest package.json. In a monorepo, one service's auth
 * says nothing about another's routes — evidence only counts within a package.
 */
function packageOf(absPath: string, cache: Map<string, string>): string {
  let dir = dirname(absPath)
  const seen: string[] = []
  for (;;) {
    const hit = cache.get(dir)
    if (hit) break
    seen.push(dir)
    if (existsSync(resolve(dir, 'package.json'))) {
      cache.set(dir, dir)
      break
    }
    const up = dirname(dir)
    if (up === dir) {
      cache.set(dir, '/')
      break
    }
    dir = up
  }
  const pkg = cache.get(dir)!
  for (const d of seen) cache.set(d, pkg)
  return pkg
}

export function checkAuthDrift(files: SourceFile[]): Finding[] {
  const scanned = files.filter((f) => !isSkippedFile(f.relPath))
  const facts = scanned.map(analyzeFile)
  const known = new Set(scanned.map((f) => f.absPath))

  // Router files mounted behind auth anywhere protect all their routes.
  const protectedFiles = new Set<string>()
  for (const f of facts) {
    for (const name of f.protectedMounts) {
      const spec = f.imports.get(name)
      const target = spec ? resolveImport(f.file.absPath, spec, known) : null
      if (target) protectedFiles.add(target)
    }
  }
  const nextMw = nextMiddlewareProtects(scanned)

  const textByPath = new Map(scanned.map((f) => [f.absPath, f.text]))
  const routes = facts.flatMap((f) =>
    f.routes.map((r) => {
      const out = {
        ...r,
        protected: r.protected || protectedFiles.has(f.file.absPath) || (nextMw && /\/route\.[jt]sx?$/.test(r.file)),
      }
      // Handler imported from a local file: judge it by that file's code.
      if (!out.handlerVisible && r.handlerImport) {
        const target = resolveImport(f.file.absPath, r.handlerImport, known)
        const text = target ? textByPath.get(target) : undefined
        if (text != null) {
          out.handlerVisible = true
          out.protected ||= AUTH_IN_HANDLER.test(text)
        }
      }
      return out
    }),
  )
  const pkgCache = new Map<string, string>()
  const absByRel = new Map(scanned.map((f) => [f.relPath, f.absPath]))
  const pkgOf = (r: { file: string }) => packageOf(absByRel.get(r.file) ?? r.file, pkgCache)
  const guardedByPkg = new Map<string, typeof routes>()
  for (const r of routes) {
    if (!r.protected) continue
    const k = pkgOf(r)
    guardedByPkg.set(k, [...(guardedByPkg.get(k) ?? []), r])
  }

  const findings: Finding[] = []
  for (const r of routes) {
    // Only what we can show: a handler we couldn't read might check auth itself.
    if (r.protected || !r.handlerVisible) continue
    const isAdmin = /(?:^|\/)admin(?:\/|$)/i.test(r.path)
    if (!isAdmin && !MUTATING.has(r.method)) continue
    if (PUBLIC_PATH.test(r.path) || CAPABILITY_PARAM.test(r.rawPath)) continue
    const guarded = guardedByPkg.get(pkgOf(r)) ?? []
    // No auth anywhere in this app = no evidence it expects it — except
    // /admin, which is never meant to be open.
    if (guarded.length === 0 && !isAdmin) continue
    const names = guarded.map((g) => g.authName).filter((n): n is string => !!n)
    const commonAuth = names.sort((a, b) => names.filter((n) => n === b).length - names.filter((n) => n === a).length)[0]
    const fix = `Add ${commonAuth ? `\`${commonAuth}\`` : 'your auth middleware'} or, if it's meant to be public, mute this finding.`
    findings.push({
      check: 'auth-drift',
      severity: 'finding',
      file: r.file,
      line: r.line,
      message:
        guarded.length > 0
          ? `${r.method} "${r.path}" has no auth, but ${guarded.length} other route${guarded.length === 1 ? '' : 's'} here require it — anyone can call it. ${fix}`
          : `${r.method} "${r.path}" is an admin route with no auth, and this app has no auth on any route — anyone can call it. Add authentication before shipping.`,
      fixHint: 'open-editor',
    })
  }
  return findings
}
