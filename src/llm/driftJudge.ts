import type { Finding } from '../report.js'

/**
 * Optional LLM pass for contract drift. Only runs when ANTHROPIC_API_KEY
 * is set — free/offline scans stay fully deterministic. Uses a forced
 * JSON schema shape (same idea as Aithority preclassify): no free text.
 */

export type DriftSurface = { server: string[]; client: string[] }

type LlmDriftItem = {
  path: string
  side: 'client' | 'server'
  reason: string
  severity: 'finding' | 'warning'
}

export async function judgeContractDrift(surface: DriftSurface): Promise<Finding[]> {
  const key = process.env.ANTHROPIC_API_KEY
  if (!key) return []
  if (surface.server.length === 0 || surface.client.length === 0) return []

  const body = {
    model: 'claude-sonnet-4-20250514',
    max_tokens: 1024,
    temperature: 0,
    messages: [
      {
        role: 'user',
        content: `You are checking a full-stack repo for API contract drift.
Server routes declared:\n${surface.server.map((p) => `- ${p}`).join('\n')}
Client HTTP paths called:\n${surface.client.map((p) => `- ${p}`).join('\n')}

Return ONLY JSON matching:
{"items":[{"path":"/api/...","side":"client"|"server","reason":"short","severity":"finding"|"warning"}]}

Flag only real mismatches (renames, missing handlers, clients calling gone endpoints).
Do not invent paths. Empty items if nothing meaningful.`,
      },
    ],
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
    if (!res.ok) return []
    const data = (await res.json()) as { content?: { type: string; text?: string }[] }
    const text = data.content?.find((c) => c.type === 'text')?.text ?? ''
    const jsonStart = text.indexOf('{')
    const jsonEnd = text.lastIndexOf('}')
    if (jsonStart < 0 || jsonEnd < 0) return []
    const parsed = JSON.parse(text.slice(jsonStart, jsonEnd + 1)) as { items?: LlmDriftItem[] }
    if (!Array.isArray(parsed.items)) return []

    return parsed.items
      .filter((i) => i.path && i.reason && (i.side === 'client' || i.side === 'server'))
      .map((i) => ({
        check: 'contract-drift-llm',
        severity: i.severity === 'warning' ? 'warning' : 'finding',
        file: i.side === 'client' ? '(client)' : '(server)',
        message: `${i.path}: ${i.reason}`,
        fixHint: 'open-editor' as const,
      }))
  } catch {
    return []
  }
}
