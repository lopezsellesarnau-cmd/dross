import type { Finding } from '../report.js'
import type { DriftRoute, DriftSurface } from '../checks/contractDrift.js'

/**
 * Optional LLM pass for contract drift. Runs only when ANTHROPIC_API_KEY is
 * set AND a Pro license is valid (gated in runScan).
 *
 * Role: *suppressor*, not generator. It reviews low-confidence deterministic
 * candidates (dead-endpoint warnings) and may add extras only for paths that
 * already appear on the extracted surface — never invented URLs.
 *
 * Output is forced through a tool schema so we don't slice `{`…`}` out of
 * free text. A balanced-JSON fallback still exists for older API responses.
 */

export type { DriftSurface }

const TOOL_NAME = 'report_drift'
const MAX_ITEMS = 12
const MAX_SUPPRESS = 20

type LlmDriftItem = {
  path: string
  side: 'client' | 'server'
  reason: string
  severity: 'finding' | 'warning'
  method?: string
}

export type LlmDriftReport = {
  suppress: { file: string; line: number; reason?: string }[]
  items: LlmDriftItem[]
}

export type JudgeResult = {
  extra: Finding[]
  drop: Finding[]
}

function formatRoutes(routes: DriftRoute[]): string {
  if (routes.length === 0) return '(none)'
  return routes
    .slice(0, 80)
    .map((r) => `- ${r.method} ${r.path}  (${r.file}:${r.line})`)
    .join('\n')
}

function knownPaths(surface: DriftSurface): Set<string> {
  return new Set([...surface.server, ...surface.client].map((r) => r.path))
}

function lookupRoute(surface: DriftSurface, side: 'client' | 'server', path: string, method?: string): DriftRoute | undefined {
  const pool = side === 'client' ? surface.client : surface.server
  const methodMatch = method
    ? pool.find((r) => r.path === path && r.method.toUpperCase() === method.toUpperCase())
    : undefined
  return methodMatch ?? pool.find((r) => r.path === path)
}

/** First top-level JSON object, respecting strings so nested `}` can't truncate. */
export function extractJsonObject(text: string): string | null {
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i)
  const src = fence ? fence[1] : text
  const start = src.indexOf('{')
  if (start < 0) return null
  let depth = 0
  let inString = false
  let escape = false
  for (let i = start; i < src.length; i++) {
    const ch = src[i]
    if (inString) {
      if (escape) escape = false
      else if (ch === '\\') escape = true
      else if (ch === '"') inString = false
      continue
    }
    if (ch === '"') inString = true
    else if (ch === '{') depth++
    else if (ch === '}') {
      depth--
      if (depth === 0) return src.slice(start, i + 1)
    }
  }
  return null
}

function asItems(raw: unknown): LlmDriftItem[] {
  if (!Array.isArray(raw)) return []
  const out: LlmDriftItem[] = []
  for (const row of raw) {
    if (!row || typeof row !== 'object') continue
    const i = row as Record<string, unknown>
    const path = typeof i.path === 'string' ? i.path.trim() : ''
    const reason = typeof i.reason === 'string' ? i.reason.trim() : ''
    const side = i.side === 'client' || i.side === 'server' ? i.side : null
    if (!path || !reason || !side) continue
    const severity = i.severity === 'warning' ? 'warning' : 'finding'
    const method = typeof i.method === 'string' ? i.method.trim().toUpperCase() : undefined
    out.push({ path, side, reason, severity, method })
    if (out.length >= MAX_ITEMS) break
  }
  return out
}

function asSuppress(raw: unknown): LlmDriftReport['suppress'] {
  if (!Array.isArray(raw)) return []
  const out: LlmDriftReport['suppress'] = []
  for (const row of raw) {
    if (!row || typeof row !== 'object') continue
    const i = row as Record<string, unknown>
    const file = typeof i.file === 'string' ? i.file : ''
    const line = typeof i.line === 'number' ? i.line : Number(i.line)
    if (!file || !Number.isFinite(line)) continue
    const reason = typeof i.reason === 'string' ? i.reason : undefined
    out.push({ file, line, reason })
    if (out.length >= MAX_SUPPRESS) break
  }
  return out
}

export function parseJudgeReport(text: string): LlmDriftReport | null {
  const json = extractJsonObject(text)
  if (!json) return null
  let parsed: unknown
  try {
    parsed = JSON.parse(json)
  } catch {
    return null
  }
  if (!parsed || typeof parsed !== 'object') return null
  const obj = parsed as Record<string, unknown>
  return {
    suppress: asSuppress(obj.suppress),
    items: asItems(obj.items),
  }
}

export function applyJudge(
  report: LlmDriftReport,
  surface: DriftSurface,
  candidates: Finding[],
): JudgeResult {
  const allowed = knownPaths(surface)
  const extra: Finding[] = []
  const seen = new Set<string>()

  for (const i of report.items) {
    if (!allowed.has(i.path)) continue // never invent paths
    const loc = lookupRoute(surface, i.side, i.path, i.method)
    const key = `${i.side}:${i.method ?? ''}:${i.path}`
    if (seen.has(key)) continue
    seen.add(key)
    extra.push({
      check: 'contract-drift-llm',
      severity: i.severity,
      file: loc?.file ?? `(${i.side})`,
      line: loc?.line,
      message: `${i.method ? i.method + ' ' : ''}${i.path}: ${i.reason}`,
      fixHint: 'open-editor',
    })
  }

  const drop: Finding[] = []
  for (const s of report.suppress) {
    const hit = candidates.find((c) => c.file === s.file && (c.line ?? 0) === s.line)
    if (hit) drop.push(hit)
  }

  return { extra, drop }
}

function toolInputSchema() {
  return {
    type: 'object',
    properties: {
      suppress: {
        type: 'array',
        description:
          'Low-confidence deterministic findings that are noise (backend-only routes, health, third-party). Only use file+line from the candidate list.',
        items: {
          type: 'object',
          properties: {
            file: { type: 'string' },
            line: { type: 'number' },
            reason: { type: 'string' },
          },
          required: ['file', 'line'],
        },
      },
      items: {
        type: 'array',
        description:
          'Real mismatches only. path MUST be copied from the server/client lists. Empty if the deterministic pass already covered it.',
        items: {
          type: 'object',
          properties: {
            path: { type: 'string' },
            method: { type: 'string' },
            side: { type: 'string', enum: ['client', 'server'] },
            reason: { type: 'string' },
            severity: { type: 'string', enum: ['finding', 'warning'] },
          },
          required: ['path', 'side', 'reason', 'severity'],
        },
      },
    },
    required: ['suppress', 'items'],
  }
}

function promptFor(surface: DriftSurface, candidates: Finding[]): string {
  const cand =
    candidates.length === 0
      ? '(none)'
      : candidates
          .slice(0, 30)
          .map((c) => `- ${c.file}:${c.line ?? 0}  ${c.message}`)
          .join('\n')

  return `You are checking a full-stack repo for API contract drift.

Server routes:
${formatRoutes(surface.server)}

Client HTTP calls:
${formatRoutes(surface.client)}

Low-confidence deterministic candidates (may be noise — suppress if so):
${cand}

Rules:
- Do not invent paths. Copy path strings exactly from the lists above.
- Prefer suppress over new items when the deterministic check already said it.
- Flag only real mismatches: renames, missing handlers, clients calling gone endpoints, method mismatch the lists show.
- Empty items and empty suppress are fine.`
}

function reportFromToolInput(input: unknown): LlmDriftReport | null {
  if (!input || typeof input !== 'object') return null
  const obj = input as Record<string, unknown>
  return {
    suppress: asSuppress(obj.suppress),
    items: asItems(obj.items),
  }
}

export async function judgeContractDrift(
  surface: DriftSurface,
  candidates: Finding[] = [],
): Promise<JudgeResult> {
  const empty: JudgeResult = { extra: [], drop: [] }
  const key = process.env.ANTHROPIC_API_KEY
  if (!key) return empty
  if (surface.server.length === 0 || surface.client.length === 0) return empty

  const body = {
    model: 'claude-sonnet-4-20250514',
    max_tokens: 1024,
    temperature: 0,
    tool_choice: { type: 'tool', name: TOOL_NAME },
    tools: [
      {
        name: TOOL_NAME,
        description: 'Report contract-drift suppressions and extra mismatches.',
        input_schema: toolInputSchema(),
      },
    ],
    messages: [{ role: 'user', content: promptFor(surface, candidates) }],
  }

  try {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(body),
    })
    if (!res.ok) return empty
    const data = (await res.json()) as {
      content?: { type: string; text?: string; name?: string; input?: unknown }[]
    }
    const blocks = data.content ?? []
    const tool = blocks.find((c) => c.type === 'tool_use' && c.name === TOOL_NAME)
    const fromTool = tool ? reportFromToolInput(tool.input) : null
    const fromText = parseJudgeReport(blocks.find((c) => c.type === 'text')?.text ?? '')
    const report = fromTool ?? fromText
    if (!report) return empty
    return applyJudge(report, surface, candidates)
  } catch {
    // Optional pass — a network/parse failure must not fail the scan.
    return empty
  }
}
