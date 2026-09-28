import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { checkDangerousConfig } from '../src/checks/dangerousConfig.js'

function scan(text: string, relPath = 'server.ts') {
  return checkDangerousConfig([{ absPath: '/x/' + relPath, relPath, text }])
}
function lines(text: string): number[] {
  return scan(text).map((f) => f.line!).sort((a, b) => a - b)
}

describe('dangerous-config: flagged', () => {
  it('CORS any origin with credentials (incl. require("cors")(…))', () => {
    assert.deepEqual(
      lines(`
app.use(cors({ origin: '*', credentials: true }))
app.use(require('cors')({ origin: true, credentials: true }))`),
      [2, 3],
    )
  })

  it('reflected Origin with credentials, no allowlist check', () => {
    const out = scan(`
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', req.headers.origin)
  res.setHeader('Access-Control-Allow-Credentials', 'true')
  next()
})`)
    assert.equal(out.length, 1)
    assert.equal(out[0].line, 3)
  })

  it("JWT: 'none' algorithm, hardcoded secret, env fallback, ignoreExpiration", () => {
    const out = scan(`
jwt.verify(token, SECRET, { algorithms: ['HS256', 'none'] })
const t = jwt.sign(payload, 'super-secret')
const u = jwt.verify(token, process.env.JWT_SECRET || 'dev-secret')
jwt.verify(token, SECRET, { ignoreExpiration: true })`)
    assert.deepEqual(out.map((f) => f.line), [2, 3, 4, 5])
    assert.match(out[2].message, /falls back to a hardcoded value/)
    assert.equal(out[3].severity, 'warning')
  })

  it("bare sign/verify imported from 'jsonwebtoken'", () => {
    assert.deepEqual(lines(`import { sign } from 'jsonwebtoken'\nexport const t = sign({ id }, 'abc123')`), [2])
  })

  it('session and passport-jwt secrets', () => {
    assert.deepEqual(
      lines(`
app.use(session({ secret: 'keyboard cat', resave: false }))
passport.use(new JwtStrategy({ secretOrKey: process.env.JWT ?? 'changeme' }, verify))`),
      [2, 3],
    )
  })

  it('TLS verification off globally and per connection', () => {
    const out = scan(`
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0'
const pool = new Pool({ ssl: { rejectUnauthorized: false } })`)
    assert.deepEqual(out.map((f) => [f.line, f.severity]), [[2, 'finding'], [3, 'warning']])
  })
})

describe('dangerous-config: not flagged', () => {
  it('CORS decided at runtime, listed origins, or no credentials', () => {
    assert.deepEqual(
      lines(`
app.use(cors({ origin: corsOrigin, credentials: true }))
app.use(cors({ origin: ['https://app.example.com'], credentials: true }))
app.use(cors({ origin: '*' }))
app.use(cors())`),
      [],
    )
  })

  it('reflected Origin behind an allowlist check (aithority shape)', () => {
    assert.deepEqual(
      lines(`
app.use((req, res, next) => {
  const origin = req.headers.origin
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', req.headers.origin)
    res.setHeader('Access-Control-Allow-Credentials', 'true')
  }
  next()
})`),
      [],
    )
  })

  it('secrets from env with a startup check, and safe algorithms', () => {
    assert.deepEqual(
      lines(`
const SECRET = process.env.JWT_SECRET
if (!SECRET) throw new Error('Missing JWT_SECRET')
jwt.sign(payload, SECRET, { expiresIn: '1h' })
jwt.verify(token, SECRET, { algorithms: ['HS256'] })
app.use(session({ secret: process.env.SESSION_SECRET }))`),
      [],
    )
  })

  it('TLS opt-out gated by config (NOMAD shape)', () => {
    assert.deepEqual(
      lines(`
const t = nodemailer.createTransport({ host, ...(skipTls ? { tls: { rejectUnauthorized: false } } : {}) })
const a = new https.Agent({ rejectUnauthorized: !creds.allowInsecureTls })`),
      [],
    )
  })

  it('ignores test files', () => {
    assert.deepEqual(scan(`jwt.sign(p, 'test-secret')`, 'auth.test.ts'), [])
  })
})
