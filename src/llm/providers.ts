import Anthropic from '@anthropic-ai/sdk'

/**
 * Bring-your-own-key LLM providers for the (optional) drift-judge pass.
 * Dross never proxies or resells tokens: the user's own key goes straight
 * from their machine to the provider they chose.
 *
 * Anthropic goes through the official SDK with structured outputs; OpenAI,
 * DeepSeek, Mistral and `custom` (any OpenAI-compatible server: OpenRouter,
 * Groq, a local Ollama/LM Studio…) share one chat-completions path with
 * JSON mode. Either way the caller re-validates the JSON — the model
 * output is never trusted as-is (see applyJudge).
 */

export type ProviderId = 'anthropic' | 'openai' | 'deepseek' | 'mistral' | 'custom'

type ProviderSpec = {
  label: string
  /** Env var holding the user's key (the Mac app forwards it from the Keychain). */
  keyEnv: string
  defaultModel: string
  /** OpenAI-compatible base URL; Anthropic uses its SDK instead. */
  baseUrl?: string
}

const PROVIDERS: Record<ProviderId, ProviderSpec> = {
  anthropic: { label: 'Anthropic', keyEnv: 'ANTHROPIC_API_KEY', defaultModel: 'claude-opus-5' },
  openai: { label: 'OpenAI', keyEnv: 'OPENAI_API_KEY', defaultModel: 'gpt-6-luna', baseUrl: 'https://api.openai.com/v1' },
  deepseek: { label: 'DeepSeek', keyEnv: 'DEEPSEEK_API_KEY', defaultModel: 'deepseek-flash', baseUrl: 'https://api.deepseek.com' },
  mistral: { label: 'Mistral', keyEnv: 'MISTRAL_API_KEY', defaultModel: 'mistral-small-latest', baseUrl: 'https://api.mistral.ai/v1' },
  // Base URL and model come from DROSS_LLM_BASE_URL / DROSS_LLM_MODEL; the key is optional (local servers).
  custom: { label: 'Custom', keyEnv: 'DROSS_LLM_API_KEY', defaultModel: '' },
}

const ORDER: ProviderId[] = ['anthropic', 'openai', 'deepseek', 'mistral']

export type ResolvedProvider = {
  id: ProviderId
  key: string
  model: string
  /** Custom provider only: its OpenAI-compatible base URL and a display label. */
  baseUrl?: string
  label?: string
  /** Custom provider configured but unusable (bad URL, no model) — reported as a failed pass. */
  configError?: string
}

/**
 * Which provider to use: `DROSS_LLM_PROVIDER` if set (and its key is
 * present), otherwise the first provider with a key. `DROSS_LLM_MODEL`
 * overrides that provider's default model. Null = no usable key.
 * `custom` is only ever chosen explicitly — it has no key to detect it by.
 */
export function resolveLlmProvider(env: NodeJS.ProcessEnv = process.env): ResolvedProvider | null {
  const pick = (id: ProviderId): ResolvedProvider | null => {
    const key = env[PROVIDERS[id].keyEnv]?.trim()
    if (!key) return null
    return { id, key, model: env.DROSS_LLM_MODEL?.trim() || PROVIDERS[id].defaultModel }
  }
  const wanted = env.DROSS_LLM_PROVIDER?.trim().toLowerCase()
  if (wanted === 'custom') return resolveCustom(env)
  if (wanted) return wanted in PROVIDERS ? pick(wanted as ProviderId) : null
  for (const id of ORDER) {
    const hit = pick(id)
    if (hit) return hit
  }
  return null
}

const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '[::1]', '::1'])

/**
 * Custom OpenAI-compatible server. The URL must be https — plain http only
 * to this machine, so code and key never cross a network unencrypted.
 * Accepts the base (`…/v1`) or a pasted full endpoint (`…/v1/chat/completions`).
 */
function resolveCustom(env: NodeJS.ProcessEnv): ResolvedProvider | null {
  const raw = env.DROSS_LLM_BASE_URL?.trim()
  const model = env.DROSS_LLM_MODEL?.trim() ?? ''
  if (!raw) return null
  const key = env.DROSS_LLM_API_KEY?.trim() ?? ''
  const base = raw.replace(/\/+$/, '').replace(/\/chat\/completions$/, '')
  let url: URL
  try {
    url = new URL(base)
  } catch {
    return { id: 'custom', key, model, configError: `custom provider URL "${raw}" is not a valid URL` }
  }
  const label = `Custom (${url.host})`
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && LOCAL_HOSTS.has(url.hostname))) {
    return { id: 'custom', key, model, label, configError: 'custom provider URL must use https:// (http:// is only allowed for localhost)' }
  }
  if (!model) return { id: 'custom', key, model, label, configError: 'custom provider needs a model name' }
  return { id: 'custom', key, model, baseUrl: base, label }
}

/**
 * When a key is rejected, say so if its format names another provider —
 * the usual cause is a key pasted into the wrong slot (an OpenAI key sent
 * to Anthropic). Only unambiguous prefixes; Mistral keys have none.
 */
export function wrongProviderHint(p: ResolvedProvider): string {
  if (p.id === 'custom') return '' // any gateway can accept any key format
  const owner: ProviderId | null = p.key.startsWith('sk-ant-')
    ? 'anthropic'
    : /^sk-(?:proj|svcacct|admin)-/.test(p.key)
      ? 'openai'
      : /^sk-[0-9a-f]{32}$/.test(p.key)
        ? 'deepseek'
        : null
  if (!owner || owner === p.id) return ''
  const label = PROVIDERS[owner].label
  const article = /^[AEIOU]/.test(label) ? 'an' : 'a'
  return `. This looks like ${article} ${label} key: choose ${label} as the provider`
}

/** Hard cap per call — the Mac app kills the whole engine at 90s. */
const LLM_TIMEOUT_MS = 60_000

export type JudgeCall = { ok: true; text: string } | { ok: false; error: string }

/** One JSON-producing call to the chosen provider. Never throws. */
export async function callProvider(p: ResolvedProvider, prompt: string, schema: Record<string, unknown>): Promise<JudgeCall> {
  if (p.configError) return { ok: false, error: p.configError }
  return p.id === 'anthropic' ? callAnthropic(p, prompt, schema) : callOpenAICompatible(p, prompt, schema)
}

async function callAnthropic(p: ResolvedProvider, prompt: string, schema: Record<string, unknown>): Promise<JudgeCall> {
  const client = new Anthropic({ apiKey: p.key, timeout: LLM_TIMEOUT_MS, maxRetries: 1 })
  try {
    const res = await client.beta.messages.create({
      model: p.model,
      max_tokens: 16000,
      // A focused classification pass: low effort keeps it fast and cheap.
      output_config: { effort: 'low', format: { type: 'json_schema', schema } },
      // If the model declines, the API retries on a recommended fallback model.
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      messages: [{ role: 'user', content: prompt }],
    })
    if (res.stop_reason === 'refusal') return { ok: false, error: 'the model declined this request' }
    if (res.stop_reason === 'max_tokens') return { ok: false, error: 'the response was cut off (max_tokens)' }
    const text = res.content.map((b) => (b.type === 'text' ? b.text : '')).join('')
    return text ? { ok: true, text } : { ok: false, error: 'empty response from the model' }
  } catch (err) {
    if (err instanceof Anthropic.APIConnectionTimeoutError) {
      return { ok: false, error: `timed out after ${LLM_TIMEOUT_MS / 1000}s` }
    }
    if (err instanceof Anthropic.AuthenticationError) {
      return { ok: false, error: `Anthropic API key is invalid${wrongProviderHint(p)}` }
    }
    if (err instanceof Anthropic.APIConnectionError) return { ok: false, error: 'network error — could not reach the Anthropic API' }
    if (err instanceof Anthropic.APIError) {
      // `err.error` is the parsed error body: { type: 'error', error: { message } }.
      const body = err.error as { error?: { message?: string } } | undefined
      const detail = (body?.error?.message ?? err.message).slice(0, 160)
      return { ok: false, error: `Anthropic API returned ${err.status ?? 'an error'} — ${detail}` }
    }
    return { ok: false, error: 'unexpected error calling the Anthropic API' }
  }
}

async function callOpenAICompatible(p: ResolvedProvider, prompt: string, schema: Record<string, unknown>): Promise<JudgeCall> {
  const spec = PROVIDERS[p.id]
  const label = p.label ?? spec.label
  const base = p.baseUrl ?? spec.baseUrl
  const messages = [
    {
      role: 'system',
      content: `Reply with one JSON object and nothing else. It must match this JSON Schema:\n${JSON.stringify(schema)}`,
    },
    { role: 'user', content: prompt },
  ]
  const post = (jsonMode: boolean) =>
    fetch(`${base}/chat/completions`, {
      method: 'POST',
      // Local servers take no key — send the header only when there is one.
      headers: { 'content-type': 'application/json', ...(p.key ? { authorization: `Bearer ${p.key}` } : {}) },
      body: JSON.stringify({
        model: p.model,
        // JSON mode is the structured-output feature these providers share;
        // the schema goes in the prompt and the caller validates the result.
        ...(jsonMode ? { response_format: { type: 'json_object' } } : {}),
        messages,
      }),
      signal: AbortSignal.timeout(LLM_TIMEOUT_MS),
    })

  let res: Response
  try {
    res = await post(true)
    // Some OpenAI-compatible servers reject response_format — retry once
    // without it; the JSON is validated by the caller either way.
    if (p.id === 'custom' && (res.status === 400 || res.status === 422)) res = await post(false)
  } catch (err) {
    const timedOut = err instanceof Error && err.name === 'TimeoutError'
    return { ok: false, error: timedOut ? `timed out after ${LLM_TIMEOUT_MS / 1000}s` : `network error — could not reach the ${label} API` }
  }
  let data: { error?: { message?: string } | string; message?: string; choices?: { message?: { content?: string | null } }[] }
  try {
    data = (await res.json()) as typeof data
  } catch {
    return { ok: false, error: `${label} API returned ${res.status} with an unreadable body` }
  }
  if (!res.ok) {
    // OpenAI/DeepSeek: { error: { message } }; Mistral: { message }; Ollama: { error: "…" }.
    const msg = typeof data.error === 'string' ? data.error : (data.error?.message ?? data.message)
    const detail = msg ? ` — ${msg.slice(0, 160)}` : ''
    const hint = res.status === 401 || res.status === 403 ? wrongProviderHint(p) : ''
    return { ok: false, error: `${label} API returned ${res.status}${detail}${hint}` }
  }
  const text = data.choices?.[0]?.message?.content ?? ''
  return text ? { ok: true, text } : { ok: false, error: `empty response from ${label}` }
}
