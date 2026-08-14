import type { Confidence, Finding } from './report.js'

/**
 * Deterministic confidence for a finding. High = show by default (likely a
 * real ship-break). Low = tuck behind "show low" (weaker signal: dead-endpoint
 * warnings, LLM guesses). Recurrence is applied later in memory, not here.
 */
export function scoreConfidence(f: Finding): Confidence {
  if (f.check === 'contract-drift-llm') return 'low'
  if (f.check === 'contract-drift' && /no matching client call/i.test(f.message)) return 'low'
  if (f.check === 'contract-drift') return 'high'
  if (f.check === 'env-drift' && f.severity === 'finding') return 'high'
  if (f.check === 'env-drift') return 'medium'
  if (f.check === 'dead-exports' && f.severity === 'finding') return 'high'
  if (f.check === 'dead-exports') return 'medium'
  if (f.check === 'hardcoded-demo') return 'high'
  if (f.check === 'todo-density') return 'medium'
  return 'medium'
}
