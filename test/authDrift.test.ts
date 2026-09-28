import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { checkAuthDrift } from '../src/checks/authDrift.js'
import type { SourceFile } from '../src/scan.js'

function files(map: Record<string, string>): SourceFile[] {
  return Object.entries(map).map(([relPath, text]) => ({ absPath: '/repo/' + relPath, relPath, text }))
}

function flagged(map: Record<string, string>): string[] {
  return checkAuthDrift(files(map)).map((f) => `${f.file}:${f.line}`).sort()
}

describe('auth-drift: flagged', () => {
  it('a mutating route missing the auth every other route uses', () => {
    const out = checkAuthDrift(
      files({
        'server.js': `
app.get('/me', requireAuth, (req, res) => res.json(req.user))
app.post('/projects', requireAuth, (req, res) => {})
app.delete('/projects/:id', (req, res) => { db.remove(req.params.id) })`,
      }),
    )
    assert.equal(out.length, 1)
    assert.equal(out[0].line, 4)
    assert.match(out[0].message, /DELETE "\/projects\/:param" has no auth, but 2 other routes/)
    assert.match(out[0].message, /`requireAuth`/)
  })

  it('an open /admin route even when the app has no auth at all', () => {
    const out = checkAuthDrift(files({ 'server.js': `app.delete('/admin/users/:id', (req, res) => { db.deleteUser(req.params.id) })` }))
    assert.equal(out.length, 1)
    assert.match(out[0].message, /admin route with no auth/)
  })

  it('a Next.js route handler without the session check its siblings have', () => {
    assert.deepEqual(
      flagged({
        'app/api/notes/route.ts': `export async function POST(req: Request) { const s = await getServerSession(); if (!s) return new Response(null, { status: 401 }) }`,
        'app/api/notes/[id]/route.ts': `export async function DELETE(req: Request) { await db.note.delete({}) }`,
      }),
      ['app/api/notes/[id]/route.ts:1'],
    )
  })

  it('a named handler defined in the same file, and routes outside a prefix-scoped auth', () => {
    assert.deepEqual(
      flagged({
        'server.ts': `
app.use('/api', requireAuth)
app.post('/api/items', (req, res) => {})
app.post('/upload', handleUpload)
function handleUpload(req, res) { save(req.body) }`,
      }),
      ['server.ts:4'],
    )
  })

  it('naming the Authorization header in CORS is not auth', () => {
    assert.deepEqual(
      flagged({
        'server.js': `
app.use((req, res, next) => { res.setHeader('Access-Control-Allow-Headers', 'Content-Type,Authorization'); next() })
app.post('/a', requireAuth, (req, res) => {})
app.post('/b', (req, res) => {})`,
      }),
      ['server.js:4'],
    )
  })
})

describe('auth-drift: not flagged', () => {
  it('routes after a global app.use(auth)', () => {
    assert.deepEqual(
      flagged({
        'server.js': `
app.post('/login', (req, res) => {})
app.use(requireAuth)
app.post('/projects', (req, res) => {})
app.delete('/admin/users/:id', (req, res) => {})`,
      }),
      [],
    )
  })

  it('a router file mounted behind auth in another file', () => {
    assert.deepEqual(
      flagged({
        'server.ts': `
import adminRoutes from './routes/admin'
app.get('/me', requireAuth, (req, res) => {})
app.use('/admin', requireAdmin, adminRoutes)`,
        'routes/admin.ts': `
const router = express.Router()
router.delete('/users/:id', (req, res) => {})
export default router`,
      }),
      [],
    )
  })

  it('an imported handler that checks the token itself, or one we cannot read', () => {
    assert.deepEqual(
      flagged({
        'server.ts': `
import { mcpHandler } from './mcp'
import { remoteHandler } from 'some-package'
app.get('/me', requireAuth, (req, res) => {})
app.post('/mcp', mcpHandler)
app.post('/remote', remoteHandler)`,
        'mcp/index.ts': `export async function mcpHandler(req, res) { if (!verifyToken(req.headers.authorization)) { res.status(401).end(); return } }`,
      }),
      [],
    )
  })

  it('public-by-design paths and capability links', () => {
    assert.deepEqual(
      flagged({
        'server.js': `
app.get('/me', requireAuth, (req, res) => {})
app.post('/auth/login', (req, res) => {})
app.post('/webhooks/stripe', (req, res) => {})
app.post('/newsletter', (req, res) => {})
app.post('/invites/:token/accept', (req, res) => {})`,
      }),
      [],
    )
  })

  it('apps with no auth anywhere (non-admin), and read-only GETs', () => {
    assert.deepEqual(flagged({ 'server.js': `app.post('/todos', (req, res) => {})\napp.delete('/todos/:id', (req, res) => {})` }), [])
    assert.deepEqual(
      flagged({ 'server.js': `app.post('/a', requireAuth, (req, res) => {})\napp.get('/posts', (req, res) => {})` }),
      [],
    )
  })

  it('auth checked inside the handler', () => {
    assert.deepEqual(
      flagged({
        'server.js': `
app.get('/me', requireAuth, (req, res) => {})
app.post('/notes', async (req, res) => { if (!req.user) return res.status(401).end() })`,
      }),
      [],
    )
  })

  it('another package in a monorepo: one service having auth says nothing about another', () => {
    const root = mkdtempSync(join(tmpdir(), 'dross-authdrift-'))
    try {
      for (const pkg of ['api', 'worker']) {
        mkdirSync(join(root, pkg))
        writeFileSync(join(root, pkg, 'package.json'), '{}')
      }
      const src: SourceFile[] = [
        { absPath: join(root, 'api/server.js'), relPath: 'api/server.js', text: `app.post('/a', requireAuth, (req, res) => {})` },
        { absPath: join(root, 'worker/server.js'), relPath: 'worker/server.js', text: `app.post('/jobs', (req, res) => {})` },
      ]
      assert.deepEqual(checkAuthDrift(src), [])
    } finally {
      rmSync(root, { recursive: true, force: true })
    }
  })
})
