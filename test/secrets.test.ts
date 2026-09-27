import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { checkSecrets, checkTrackedSecretFiles } from '../src/checks/secrets.js'
import type { SourceFile } from '../src/scan.js'

// Fake keys are assembled at runtime so no key-shaped literal lives in the
// repo (GitHub push protection, and Dross scanning itself).
const rand = (n: number) => 'aB3dE5gH7jK9mN1pQ2rS4tU6vW8xY0zC'.repeat(4).slice(0, n)
const KEYS: Record<string, string> = {
  anthropic: ['sk', 'ant', 'api03', rand(40)].join('-'),
  openai: 'sk-' + 'proj-' + rand(40),
  stripe: 'sk_' + 'live_' + rand(30),
  aws: 'AK' + 'IA' + 'Q3EGRNZ7XK2M5BTW',
  github: 'gh' + 'p_' + rand(36),
  slack: 'xo' + 'xb-' + '1234567890-' + rand(20),
  privateKey: '-----BEGIN RSA ' + 'PRIVATE KEY-----',
}

function src(text: string, relPath = 'server.ts'): SourceFile {
  return { absPath: '/x/' + relPath, relPath, text }
}

describe('hardcoded-secrets: source keys', () => {
  for (const [name, key] of Object.entries(KEYS)) {
    it(`flags a hardcoded ${name} key`, () => {
      const out = checkSecrets([src(`const a = 1\nconst k = '${key}'\n`)])
      assert.equal(out.length, 1)
      assert.equal(out[0].check, 'hardcoded-secrets')
      assert.equal(out[0].line, 2)
    })
  }

  it('never echoes the full secret in the message', () => {
    const [f] = checkSecrets([src(`const k = '${KEYS.stripe}'`)])
    assert.ok(!f.message.includes(KEYS.stripe))
  })

  it('still flags a key sitting in a comment', () => {
    const out = checkSecrets([src(`// old key: ${KEYS.anthropic}\nconst k = process.env.KEY`)])
    assert.equal(out.length, 1)
  })

  it('ignores env reads, docs placeholders and Stripe test keys', () => {
    const text = [
      `const k = process.env.ANTHROPIC_API_KEY`,
      `const aws = 'AK' + 'IA' + 'IOSFODNN7EXAMPLE'`, // concatenated: not one token anyway
      `const docs = '${'AK' + 'IA' + 'IOSFODNN7EXAMPLE'}'`,
      `const s = '${'sk_' + 'live_' + 'x'.repeat(30)}'`,
      `const t = '${'sk_' + 'test_' + rand(30)}'`,
      `const g = 'AIzaSyA${rand(32)}'`, // Firebase web key: public by design
    ].join('\n')
    assert.deepEqual(checkSecrets([src(text)]), [])
  })
})

describe('hardcoded-secrets: files tracked by git', () => {
  function repo(files: Record<string, string>, track: string[]): string {
    const dir = mkdtempSync(join(tmpdir(), 'dross-secrets-'))
    for (const [name, body] of Object.entries(files)) writeFileSync(join(dir, name), body)
    execFileSync('git', ['init', '-q'], { cwd: dir })
    execFileSync('git', ['add', ...track], { cwd: dir })
    return dir
  }

  it('flags a tracked .env with values and a tracked private key', () => {
    const dir = repo(
      {
        '.env': 'DATABASE_URL=postgres://u:p@host/db\n',
        'deploy.pem': KEYS.privateKey + '\nabc\n',
        'AuthKey_ABC123.p8': 'x',
      },
      ['.env', 'deploy.pem', 'AuthKey_ABC123.p8'],
    )
    try {
      const files = checkTrackedSecretFiles(dir).map((f) => f.file).sort()
      assert.deepEqual(files, ['.env', 'AuthKey_ABC123.p8', 'deploy.pem'])
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })

  it('ignores templates, empty env files, public certs and untracked secrets', () => {
    const dir = repo(
      {
        '.env.example': 'DATABASE_URL=postgres://localhost/db\n',
        '.env.production': 'API_KEY=\n# comment\n',
        'cert.pem': '-----BEGIN CERTIFICATE-----\nabc\n',
        '.env': 'SECRET=real\n',
      },
      ['.env.example', '.env.production', 'cert.pem'],
    )
    try {
      assert.deepEqual(checkTrackedSecretFiles(dir), [])
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })

  it('treats .env.development as a warning, not a blocker-grade finding', () => {
    const dir = repo({ '.env.development': 'VITE_API=http://localhost:3000\n' }, ['.env.development'])
    try {
      const [f] = checkTrackedSecretFiles(dir)
      assert.equal(f.severity, 'warning')
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })

  it('returns nothing outside a git repo', () => {
    const dir = mkdtempSync(join(tmpdir(), 'dross-nogit-'))
    try {
      assert.deepEqual(checkTrackedSecretFiles(dir), [])
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })
})
