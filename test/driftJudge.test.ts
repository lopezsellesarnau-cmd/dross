import { test } from 'node:test'
import assert from 'node:assert/strict'
import { applyJudge, extractJsonObject, judgeContractDrift, parseJudgeReport } from '../src/llm/driftJudge.js'
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

/** Run `fn` with a fake Anthropic key and a stubbed global fetch. */
async function withFetch<T>(impl: typeof fetch, fn: () => Promise<T>): Promise<T> {
  const realFetch = globalThis.fetch
  const realKey = process.env.ANTHROPIC_API_KEY
  globalThis.fetch = impl
  process.env.ANTHROPIC_API_KEY = 'test-key'
  try {
    return await fn()
  } finally {
    globalThis.fetch = realFetch
    if (realKey === undefined) delete process.env.ANTHROPIC_API_KEY
    else process.env.ANTHROPIC_API_KEY = realKey
  }
}

test('judgeContractDrift reports an API error as failed, with the reason', async () => {
  const out = await withFetch(
    async () => new Response(JSON.stringify({ error: { message: 'model not found' } }), { status: 404 }),
    () => judgeContractDrift(surface, [candidate()]),
  )
  assert.equal(out.status, 'failed')
  assert.match(out.error ?? '', /404 — model not found/)
  assert.deepEqual(out.drop, [])
})

test('judgeContractDrift reports a network error as failed, never as ran', async () => {
  const out = await withFetch(
    async () => {
      throw new TypeError('fetch failed')
    },
    () => judgeContractDrift(surface, [candidate()]),
  )
  assert.equal(out.status, 'failed')
  assert.match(out.error ?? '', /network error/)
})

test('judgeContractDrift is ok only when the model answers', async () => {
  const c = candidate()
  const body = {
    content: [{ type: 'tool_use', name: 'report_drift', input: { suppress: [{ file: c.file, line: c.line }], items: [] } }],
  }
  const out = await withFetch(
    async () => new Response(JSON.stringify(body), { status: 200 }),
    () => judgeContractDrift(surface, [c]),
  )
  assert.equal(out.status, 'ok')
  assert.deepEqual(out.drop, [c])
})

test('judgeContractDrift skips (does not fail) with no key', async () => {
  const realKey = process.env.ANTHROPIC_API_KEY
  delete process.env.ANTHROPIC_API_KEY
  try {
    assert.equal((await judgeContractDrift(surface, [])).status, 'skipped')
  } finally {
    if (realKey !== undefined) process.env.ANTHROPIC_API_KEY = realKey
  }
})
