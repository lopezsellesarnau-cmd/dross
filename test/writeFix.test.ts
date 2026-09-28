import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fixRemoveExport } from '../src/fix/removeExport.js'
import { fixDeleteDead } from '../src/fix/deleteDead.js'
import { fixAddEnvExample } from '../src/fix/addEnvExample.js'

/** A fix must never report success for a write that didn't reach the disk. */
describe('fixes on a file that cannot be written', () => {
  function readOnlyRepo(files: Record<string, string>): string {
    const dir = mkdtempSync(join(tmpdir(), 'dross-rofix-'))
    for (const [name, text] of Object.entries(files)) {
      writeFileSync(join(dir, name), text)
      chmodSync(join(dir, name), 0o444)
    }
    return dir
  }
  function cleanup(dir: string, names: string[]) {
    for (const n of names) chmodSync(join(dir, n), 0o644)
    rmSync(dir, { recursive: true, force: true })
  }

  it('remove-export reports the failure and leaves the file as it was', () => {
    const src = 'export function unused() {\n  return 1\n}\n'
    const dir = readOnlyRepo({ 'a.ts': src })
    try {
      const r = fixRemoveExport(dir, 'a.ts', 1)
      assert.equal(r.ok, false)
      assert.match(r.message, /Could not write a\.ts/)
      assert.equal(readFileSync(join(dir, 'a.ts'), 'utf8'), src)
    } finally {
      cleanup(dir, ['a.ts'])
    }
  })

  it('delete-dead reports the failure and leaves the file as it was', () => {
    const src = 'export const keep = 1\nexport function dead() {\n  return 2\n}\n'
    const dir = readOnlyRepo({ 'b.ts': src })
    try {
      const r = fixDeleteDead(dir, 'b.ts', 2)
      assert.equal(r.ok, false)
      assert.match(r.message, /Could not write b\.ts/)
      assert.equal(readFileSync(join(dir, 'b.ts'), 'utf8'), src)
    } finally {
      cleanup(dir, ['b.ts'])
    }
  })

  it('add-env-example reports the failure when .env.example is read-only', () => {
    const dir = readOnlyRepo({ 'c.ts': 'const k = process.env.API_TOKEN\n', '.env.example': 'OTHER=\n' })
    try {
      const r = fixAddEnvExample(dir, 'c.ts', 1)
      assert.equal(r.ok, false)
      assert.match(r.message, /Could not write \.env\.example/)
      assert.equal(readFileSync(join(dir, '.env.example'), 'utf8'), 'OTHER=\n')
    } finally {
      cleanup(dir, ['c.ts', '.env.example'])
    }
  })
})
