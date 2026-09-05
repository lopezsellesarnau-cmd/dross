import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fixAddEnvExample } from '../src/fix/addEnvExample.js'
import { checkEnvDrift } from '../src/checks/envDrift.js'

test('add-env-example documents the var and clears env-drift', () => {
  const root = mkdtempSync(join(tmpdir(), 'dross-env-'))
  try {
    mkdirSync(join(root, 'src'))
    const file = join(root, 'src/firebaseAdmin.ts')
    writeFileSync(
      file,
      `export const firebaseAdminConfigured = Boolean(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)\n`,
    )
    writeFileSync(join(root, '.env'), 'OTHER=1\n')

    const before = checkEnvDrift(root, [
      { absPath: file, relPath: 'src/firebaseAdmin.ts', text: readFileSync(file, 'utf8') },
    ])
    assert.equal(before.some((f) => f.message.includes('FIREBASE_SERVICE_ACCOUNT_JSON')), true)

    const result = fixAddEnvExample(root, 'src/firebaseAdmin.ts', 1)
    assert.equal(result.ok, true)
    const example = readFileSync(join(root, '.env.example'), 'utf8')
    assert.match(example, /^FIREBASE_SERVICE_ACCOUNT_JSON=\n/)

    const after = checkEnvDrift(root, [
      { absPath: file, relPath: 'src/firebaseAdmin.ts', text: readFileSync(file, 'utf8') },
    ])
    assert.equal(after.some((f) => f.message.includes('FIREBASE_SERVICE_ACCOUNT_JSON')), false)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
})
