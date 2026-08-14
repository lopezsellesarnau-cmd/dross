import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { scoreConfidence } from '../src/confidence.js'
import type { Finding } from '../src/report.js'

function f(over: Partial<Finding>): Finding {
  return {
    check: 'dead-exports',
    severity: 'finding',
    file: 'x.ts',
    message: 'x',
    ...over,
  }
}

describe('confidence', () => {
  it('rates fully unused exports high, local-only exports medium', () => {
    assert.equal(scoreConfidence(f({ check: 'dead-exports', severity: 'finding' })), 'high')
    assert.equal(scoreConfidence(f({ check: 'dead-exports', severity: 'warning' })), 'medium')
  })

  it('rates dead-endpoint contract-drift low and client-missing-route high', () => {
    assert.equal(
      scoreConfidence(
        f({
          check: 'contract-drift',
          message: 'Server route GET "/x" has no matching client call — dead endpoint or a client outside this tree.',
        }),
      ),
      'low',
    )
    assert.equal(
      scoreConfidence(
        f({
          check: 'contract-drift',
          message: 'Client calls "/api/scan" but no matching server route was found.',
        }),
      ),
      'high',
    )
  })

  it('rates LLM drift low', () => {
    assert.equal(scoreConfidence(f({ check: 'contract-drift-llm' })), 'low')
  })
})
