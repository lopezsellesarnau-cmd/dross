import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { checkInjection } from '../src/checks/injection.js'

function scan(text: string, relPath = 'server.ts') {
  return checkInjection([{ absPath: '/x/' + relPath, relPath, text }])
}

function lines(text: string, relPath?: string): number[] {
  return scan(text, relPath).map((f) => f.line!).sort((a, b) => a - b)
}

describe('injection: flagged', () => {
  it('shell command built from req.body (Express)', () => {
    const out = scan(`
app.post('/run', (req, res) => {
  exec('convert ' + req.body.file)
})`)
    assert.equal(out.length, 1)
    assert.equal(out[0].line, 3)
    assert.match(out[0].message, /req\.body\.file.*command injection/)
  })

  it('eval of request input', () => {
    assert.deepEqual(lines(`app.post('/calc', (req, res) => { res.send(String(eval(req.body.expr))) })`), [1])
  })

  it('new Function with request input', () => {
    assert.deepEqual(lines(`app.post('/f', (req, res) => { const f = new Function(req.body.code) })`), [1])
  })

  it('SQL template literal with a destructured query param', () => {
    const out = scan(`
router.get('/user', async (req, res) => {
  const { id } = req.query
  const rows = await db.query(\`SELECT * FROM users WHERE id = '\${id}'\`)
})`)
    assert.equal(out.length, 1)
    assert.equal(out[0].line, 4)
    assert.match(out[0].message, /SQL injection/)
  })

  it('SQL string concatenation, handler param not named req', () => {
    assert.deepEqual(
      lines(`
app.get('/u', (r, s) => {
  pool.query("SELECT * FROM users WHERE name = '" + r.query.name + "'")
})`),
      [3],
    )
  })

  it('Prisma $queryRawUnsafe', () => {
    assert.deepEqual(
      lines(`app.get('/u', async (req, res) => { await prisma.$queryRawUnsafe('SELECT * FROM t WHERE a = ' + req.params.a) })`),
      [1],
    )
  })

  it('path traversal via res.sendFile and fs.readFile(path.join(...))', () => {
    assert.deepEqual(
      lines(`
app.get('/file', (req, res) => res.sendFile(__dirname + '/' + req.query.name))
app.get('/doc', async (req, res) => {
  const p = path.join(DOCS, req.params.doc)
  const text = await fs.readFile(p, 'utf8')
})`),
      [2, 5],
    )
  })

  it('Next.js route handler: request.json() and searchParams', () => {
    assert.deepEqual(
      lines(
        `
export async function POST(request: Request) {
  const body = await request.json()
  execSync(\`git checkout \${body.branch}\`)
}
export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const q = searchParams.get('q')
  await sql.unsafe('SELECT * FROM t WHERE q = ' + q)
}`,
        'app/api/x/route.ts',
      ),
      [4, 9],
    )
  })

  it('Next.js dynamic params argument', () => {
    assert.deepEqual(
      lines(
        `export async function GET(req: Request, { params }: { params: { name: string } }) {
  return new Response(await readFile('/data/' + params.name))
}`,
        'app/api/f/[name]/route.ts',
      ),
      [2],
    )
  })

  it('Hono c.req.query() and Lambda event.body', () => {
    assert.deepEqual(
      lines(`
app.get('/h', (c) => { exec('ls ' + c.req.query('dir')) })
export const handler = async (event) => { eval(event.body) }`),
      [2, 3],
    )
  })

  it('spawn with shell: true', () => {
    assert.deepEqual(lines(`app.post('/s', (req, res) => { spawn('tar', ['-x', req.body.f], { shell: true }) })`), [1])
  })

  it('sqlite db.exec with request input', () => {
    assert.deepEqual(lines(`app.post('/x', (req, res) => { db.exec('DELETE FROM t WHERE id=' + req.body.id) })`), [1])
  })
})

describe('injection: not flagged', () => {
  it('parameterized queries and tagged templates', () => {
    assert.deepEqual(
      lines(`
app.get('/u', async (req, res) => {
  await db.query('SELECT * FROM users WHERE id = $1', [req.query.id])
  await knex.raw('select * from t where a = ?', [req.body.a])
  await prisma.$queryRaw\`SELECT * FROM t WHERE id = \${req.params.id}\`
  await sql\`SELECT * FROM t WHERE id = \${req.params.id}\`
})`),
      [],
    )
  })

  it('sanitized input: Number / parseInt / basename', () => {
    assert.deepEqual(
      lines(`
app.get('/u', async (req, res) => {
  const id = Number(req.query.id)
  await db.query('SELECT * FROM t WHERE id = ' + id)
  await db.query(\`SELECT * FROM t LIMIT \${parseInt(req.query.n, 10)}\`)
  res.sendFile(path.join(DIR, path.basename(req.query.name)))
})`),
      [],
    )
  })

  it('execFile with an argument array and no shell', () => {
    assert.deepEqual(lines(`app.post('/s', (req, res) => { execFile('convert', [req.body.file, 'out.png']) })`), [])
  })

  it('path guarded by a startsWith check', () => {
    assert.deepEqual(
      lines(`
app.get('/f', (req, res) => {
  const p = path.resolve(ROOT, req.query.p)
  if (!p.startsWith(ROOT)) return res.status(400).end()
  res.sendFile(p)
})`),
      [],
    )
  })

  it('constants, env vars, RegExp.exec and code outside a request', () => {
    assert.deepEqual(
      lines(`
const table = 'users'
db.query(\`SELECT * FROM \${table}\`)
exec('git rev-parse HEAD')
exec(process.env.BUILD_CMD)
const m = /x(\\d+)/.exec(input)
app.get('/a', (req, res) => { const ok = /^\\d+$/.exec(req.query.id) })
function helper(id) { return db.query('SELECT * FROM t WHERE id = ' + id) }`),
      [],
    )
  })

  it('same variable name in a different function is not tainted', () => {
    assert.deepEqual(
      lines(`
app.get('/a', (req, res) => { const id = req.query.id; res.json({ id }) })
function other() { const id = 'fixed'; return db.query('SELECT ' + id) }`),
      [],
    )
  })

  it('ignores test files', () => {
    assert.deepEqual(lines(`app.post('/x', (req) => eval(req.body.x))`, 'server.test.ts'), [])
  })
})
