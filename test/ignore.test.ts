import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { parseDrossIgnore } from '../src/ignore.js'
import { runScan } from '../src/runScan.js'

describe('.drossignore patterns', () => {
  const rules = parseDrossIgnore(`
# test fixtures
eval/corpus/
vendor/
*.min.js
/scripts/
docs/**/*.ts
!keep-me/
`)

  it('an anchored folder skips everything under it, only at that path', () => {
    assert.equal(rules.ignores('eval/corpus/injection/server.js'), true)
    assert.equal(rules.ignores('eval/corpus', true), true)
    assert.equal(rules.ignores('src/eval/corpus/x.ts'), false)
    assert.equal(rules.ignores('eval/run.ts'), false)
  })

  it('an unanchored folder name matches at any depth, but not a file of that name', () => {
    assert.equal(rules.ignores('vendor/lib.js'), true)
    assert.equal(rules.ignores('packages/a/vendor/lib.js'), true)
    assert.equal(rules.ignores('src/vendor'), false) // a file named vendor
  })

  it('file globs, root-only folders and ** globs', () => {
    assert.equal(rules.ignores('public/app.min.js'), true)
    assert.equal(rules.ignores('public/app.js'), false)
    assert.equal(rules.ignores('scripts/seed.ts'), true)
    assert.equal(rules.ignores('api/scripts/seed.ts'), false)
    assert.equal(rules.ignores('docs/a/b/example.ts'), true)
    assert.equal(rules.ignores('docs/example.ts'), true)
  })

  it('reports its patterns and skips negations instead of guessing', () => {
    assert.deepEqual(rules.patterns, ['eval/corpus/', 'vendor/', '*.min.js', '/scripts/', 'docs/**/*.ts'])
    assert.equal(rules.ignores('keep-me/x.ts'), false)
  })
})

describe('.drossignore in a scan', () => {
  it('drops findings under ignored paths and says how much was skipped', async () => {
    const root = mkdtempSync(join(tmpdir(), 'dross-ignore-'))
    try {
      mkdirSync(join(root, 'fixtures-app'))
      mkdirSync(join(root, 'src'))
      const vuln = `app.post('/run', (req, res) => { exec('ls ' + req.body.dir) })\n`
      writeFileSync(join(root, 'fixtures-app', 'server.js'), vuln)
      writeFileSync(join(root, 'src', 'server.js'), vuln)

      const before = await runScan([root])
      assert.equal(before.findings.filter((f) => f.check === 'injection').length, 2)

      writeFileSync(join(root, '.drossignore'), 'fixtures-app/\n')
      const after = await runScan([root])
      const injections = after.findings.filter((f) => f.check === 'injection')
      assert.deepEqual(injections.map((f) => f.file), ['src/server.js'])
      assert.equal(after.ignored, 1)
      assert.deepEqual(after.ignorePatterns, ['fixtures-app/'])
    } finally {
      rmSync(root, { recursive: true, force: true })
    }
  })
})
