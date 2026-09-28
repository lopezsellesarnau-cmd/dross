import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { callProvider, resolveLlmProvider, wrongProviderHint } from '../src/llm/providers.js'

describe('resolveLlmProvider', () => {
  it('none without any key', () => {
    assert.equal(resolveLlmProvider({}), null)
  })

  it('picks the first provider with a key, with its default model', () => {
    assert.deepEqual(resolveLlmProvider({ DEEPSEEK_API_KEY: 'd', MISTRAL_API_KEY: 'm' }), {
      id: 'deepseek',
      key: 'd',
      model: 'deepseek-flash',
    })
  })

  it('honours DROSS_LLM_PROVIDER and DROSS_LLM_MODEL', () => {
    const env = { ANTHROPIC_API_KEY: 'a', OPENAI_API_KEY: 'o', DROSS_LLM_PROVIDER: 'OpenAI', DROSS_LLM_MODEL: 'gpt-6-sol' }
    assert.deepEqual(resolveLlmProvider(env), { id: 'openai', key: 'o', model: 'gpt-6-sol' })
  })

  it('an explicit provider without its key (or an unknown one) resolves to none', () => {
    assert.equal(resolveLlmProvider({ ANTHROPIC_API_KEY: 'a', DROSS_LLM_PROVIDER: 'mistral' }), null)
    assert.equal(resolveLlmProvider({ ANTHROPIC_API_KEY: 'a', DROSS_LLM_PROVIDER: 'nope' }), null)
  })
})

describe('OpenAI-compatible providers', () => {
  async function withFetch<T>(impl: typeof fetch, fn: () => Promise<T>): Promise<T> {
    const real = globalThis.fetch
    globalThis.fetch = impl
    try {
      return await fn()
    } finally {
      globalThis.fetch = real
    }
  }

  it('posts JSON mode to the provider base URL with a Bearer key and returns the content', async () => {
    let seen: { url: string; auth: string | null; body: Record<string, unknown> } | null = null
    const out = await withFetch(
      async (url, init) => {
        seen = {
          url: String(url),
          auth: new Headers(init?.headers).get('authorization'),
          body: JSON.parse(String(init?.body)),
        }
        return new Response(JSON.stringify({ choices: [{ message: { content: '{"suppress":[],"items":[]}' } }] }), { status: 200 })
      },
      () => callProvider({ id: 'mistral', key: 'mk', model: 'mistral-small-latest' }, 'prompt', { type: 'object' }),
    )
    assert.deepEqual(out, { ok: true, text: '{"suppress":[],"items":[]}' })
    assert.equal(seen!.url, 'https://api.mistral.ai/v1/chat/completions')
    assert.equal(seen!.auth, 'Bearer mk')
    assert.deepEqual(seen!.body.response_format, { type: 'json_object' })
    assert.equal(seen!.body.model, 'mistral-small-latest')
  })

  it('reports provider errors with their message', async () => {
    const out = await withFetch(
      async () => new Response(JSON.stringify({ error: { message: 'Incorrect API key provided' } }), { status: 401 }),
      () => callProvider({ id: 'openai', key: 'bad', model: 'gpt-6-luna' }, 'p', {}),
    )
    assert.deepEqual(out, { ok: false, error: 'OpenAI API returned 401 — Incorrect API key provided' })
  })

  it('reports a network failure', async () => {
    const out = await withFetch(
      async () => {
        throw new TypeError('fetch failed')
      },
      () => callProvider({ id: 'deepseek', key: 'k', model: 'deepseek-flash' }, 'p', {}),
    )
    assert.deepEqual(out, { ok: false, error: 'network error — could not reach the DeepSeek API' })
  })
})

describe('wrongProviderHint', () => {
  it('names the provider a mismatched key belongs to', () => {
    assert.match(wrongProviderHint({ id: 'anthropic', key: 'sk-proj-abc', model: 'm' }), /looks like an? OpenAI key/)
    assert.match(wrongProviderHint({ id: 'openai', key: 'sk-ant-api03-x', model: 'm' }), /Anthropic key/)
    assert.match(wrongProviderHint({ id: 'mistral', key: 'sk-' + 'a'.repeat(32), model: 'm' }), /DeepSeek key/)
  })

  it('stays quiet when the key matches or its format is unknown', () => {
    assert.equal(wrongProviderHint({ id: 'openai', key: 'sk-proj-abc', model: 'm' }), '')
    assert.equal(wrongProviderHint({ id: 'anthropic', key: 'someMistralKey123', model: 'm' }), '')
  })
})
