import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { checkContractDrift } from '../src/checks/contractDrift.js'
import type { SourceFile } from '../src/scan.js'

function file(relPath: string, text: string): SourceFile {
  return { absPath: `/tmp/${relPath}`, relPath, text }
}

describe('contract-drift hardenings', () => {
  it('ignores test files and static/_next paths', () => {
    const files = [
      file('app/api/scan/route.ts', `export async function POST() {}`),
      file('lib/api.test.ts', `fetch('/api/missing')`),
      file('ui/x.tsx', `fetch('/_next/static/chunk.js')`),
    ]
    const findings = checkContractDrift(files)
    assert.equal(findings.filter((f) => f.file.includes('.test.')).length, 0)
    assert.equal(findings.filter((f) => f.message.includes('/_next')).length, 0)
  })

  it('skips expected server-only health routes as unused-client warnings', () => {
    const files = [
      file('app/api/health/route.ts', `export async function GET() {}`),
      file('app/api/scan/route.ts', `export async function POST() {}`),
      file('client.ts', `fetch('/api/scan', { method: 'POST', headers: { Authorization: 'Bearer x' } })`),
    ]
    const findings = checkContractDrift(files)
    assert.equal(findings.filter((f) => f.message.includes('/api/health')).length, 0)
  })

  it('detects method mismatch', () => {
    const files = [
      file('app/api/scan/route.ts', `export async function POST() {}`),
      file('client.ts', `fetch('/api/scan', { method: 'GET' })`),
    ]
    const findings = checkContractDrift(files)
    assert.ok(findings.some((f) => /method mismatch/i.test(f.message)))
  })

  it('treats authHeaders() near fetch as auth present', () => {
    const files = [
      file('middleware.ts', `export function requireAuth() { verifyIdToken() }`),
      file('app/api/scan/route.ts', `export async function POST() {}`),
      file(
        'client.ts',
        `
async function run() {
  const headers = await authHeaders()
  return fetch('/api/scan', { method: 'POST', headers })
}
`,
      ),
    ]
    const findings = checkContractDrift(files)
    assert.equal(findings.filter((f) => /Authorization/.test(f.message)).length, 0)
  })

  it('extracts path from `${API_BASE}/scan` (TRACE client pattern)', () => {
    const files = [
      file(
        'backend/src/index.ts',
        `
import express from 'express'
const app = express()
app.post('/scan', requireAuth, async (req, res) => { res.json({}) })
app.post('/removal-requests', requireAuth, (req, res) => { res.json({}) })
`,
      ),
      file(
        'app/api.ts',
        `
async function authHeaders() { return { Authorization: 'Bearer x' } }
export async function runScan() {
  return fetch(\`\${API_BASE}/scan\`, {
    method: 'POST',
    headers: { ...(await authHeaders()) },
  })
}
export async function getRemoval() {
  return fetch(\`\${API_BASE}/removal-requests\`, {
    method: 'POST',
    headers: { ...(await authHeaders()) },
  })
}
`,
      ),
    ]
    const findings = checkContractDrift(files)
    assert.equal(
      findings.filter((f) => /no matching client|no matching server/.test(f.message)).length,
      0,
      findings.map((f) => f.message).join('\n'),
    )
  })

  it('ignores third-party template URLs like `${XON_ENDPOINT}/…`', () => {
    const files = [
      file('src/index.ts', `import express from 'express'\nconst app = express()\napp.post('/scan', () => {})`),
      file(
        'src/breaches.ts',
        `const XON_ENDPOINT = 'https://api.xposedornot.com/v1/check-email'\nfetch(\`\${XON_ENDPOINT}/\${encodeURIComponent(email)}\`)`,
      ),
      file('client.ts', `fetch(\`\${API_BASE}/scan\`, { method: 'POST' })`),
    ]
    const findings = checkContractDrift(files)
    assert.equal(findings.filter((f) => f.message.includes('/:param')).length, 0)
  })
})
