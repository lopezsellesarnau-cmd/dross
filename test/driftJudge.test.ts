import { test } from 'node:test'
import assert from 'node:assert/strict'
import { applyJudge, extractJsonObject, parseJudgeReport } from '../src/llm/driftJudge.js'
import type { DriftSurface } from '../src/checks/contractDrift.js'
import type { Finding } from '../src/report.js'

const surface: DriftSurface = {
  server: [
    { method: 'GET', path: '/api/scan', file: 'api/server.ts', line: 10 },
    { method: 'POST', path: '/api/notify', file: 'api/server.ts', line: 40 },
  ],
  client: [{ method: 'GET', path: '/api/scan', file: 'app/client.ts', line: 7 }],
}

function candidate(over: Partial<Finding> = {}): Finding {
  return {
    check: 'contract-drift',
    severity: 'warning',
    file: 'api/server.ts',
    line: 40,
    message: 'Server route POST "/api/notify" has no matching client call — dead endpoint or a client outside this tree.',
    ...over,
  }
}

test('extractJsonObject respects nested braces inside strings', () => {
  const raw = 'preamble {"items":[{"path":"/x","reason":"has } brace"}],"suppress":[]} trailing'
  const json = extractJsonObject(raw)
  assert.ok(json)
  const parsed = JSON.parse(json!)
  assert.equal(parsed.items[0].reason, 'has } brace')
})

test('parseJudgeReport reads fenced JSON', () => {
  const text = 'Sure.\n```json\n{"suppress":[],"items":[{"path":"/api/notify","side":"server","reason":"dead","severity":"warning"}]}\n```'
  const report = parseJudgeReport(text)
  assert.ok(report)
  assert.equal(report!.items.length, 1)
  assert.equal(report!.items[0].path, '/api/notify')
})

test('applyJudge drops invented paths and attaches file:line from the surface', () => {
  const { extra } = applyJudge(
    {
      suppress: [],
      items: [
        { path: '/api/invented', side: 'client', reason: 'nope', severity: 'finding' },
        { path: '/api/notify', side: 'server', reason: 'unused', severity: 'warning', method: 'POST' },
      ],
    },
    surface,
    [],
  )
  assert.equal(extra.length, 1)
  assert.equal(extra[0].file, 'api/server.ts')
  assert.equal(extra[0].line, 40)
  assert.match(extra[0].message, /\/api\/notify/)
  assert.equal(extra[0].check, 'contract-drift-llm')
})

test('applyJudge suppresses matching low-confidence candidates', () => {
  const cand = candidate()
  const { extra, drop } = applyJudge(
    { suppress: [{ file: 'api/server.ts', line: 40, reason: 'intentional webhook' }], items: [] },
    surface,
    [cand],
  )
  assert.equal(extra.length, 0)
  assert.equal(drop.length, 1)
  assert.equal(drop[0], cand)
})

test('applyJudge ignores suppress that does not match a candidate', () => {
  const { drop } = applyJudge(
    { suppress: [{ file: 'nope.ts', line: 1 }], items: [] },
    surface,
    [candidate()],
  )
  assert.equal(drop.length, 0)
})
