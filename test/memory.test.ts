import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import type { Finding } from '../src/report.js'
import {
  applyMemory,
  blockingCount,
  emptyMemory,
  fingerprint,
} from '../src/memory.js'

function finding(over: Partial<Finding> = {}): Finding {
  return {
    check: 'dead-exports',
    severity: 'finding',
    file: 'helpers.ts',
    line: 4,
    message: '"unusedHelper" is exported but not referenced anywhere in the repo, not even within its own file — likely dead code.',
    fixHint: 'delete-dead',
    ...over,
  }
}

describe('dross memory', () => {
  it('fingerprint is stable when only line changes', () => {
    const a = finding({ line: 4 })
    const b = finding({ line: 18 })
    assert.equal(fingerprint(a), fingerprint(b))
    assert.equal(fingerprint(a), 'dead-exports::helpers.ts::unusedHelper')
  })

  it('new → resolved → reappear = isRecurring', () => {
    const f = finding()
    const t1 = 1_000
    const first = applyMemory([f], emptyMemory(), t1)
    assert.equal(first.annotated[0].isNew, true)
    assert.equal(first.annotated[0].isRecurring, false)
    assert.equal(first.annotated[0].timesSeen, 1)

    const t2 = 2_000
    const gone = applyMemory([], first.nextMemory, t2)
    const stored = gone.nextMemory.decisions[fingerprint(f)]
    assert.ok(stored)
    assert.equal(stored.resolvedAt, t2)

    const t3 = 3_000
    const back = applyMemory([f], gone.nextMemory, t3)
    assert.equal(back.annotated[0].isNew, false)
    assert.equal(back.annotated[0].isRecurring, true)
    assert.equal(back.annotated[0].timesSeen, 2)
    assert.equal(back.nextMemory.decisions[fingerprint(f)].resolvedAt, undefined)
  })

  it('muted finding excluded from exit-code count', () => {
    const f = finding()
    const t1 = 1_000
    const first = applyMemory([f], emptyMemory(), t1)
    first.nextMemory.decisions[fingerprint(f)].status = 'muted'
    first.nextMemory.decisions[fingerprint(f)].reason = 'used by the native app'

    const t2 = 2_000
    const again = applyMemory([f], first.nextMemory, t2)
    assert.equal(again.annotated[0].muted, true)
    assert.equal(blockingCount(again.annotated), 0)
    assert.equal(blockingCount(first.annotated), 1)
  })

    it('stored reason resurfaces (note) on recurrence', () => {
    const f = finding()
    const t1 = 1_000
    const first = applyMemory([f], emptyMemory(), t1)
    const fp = fingerprint(f)
    first.nextMemory.decisions[fp].status = 'muted'
    first.nextMemory.decisions[fp].reason = 'intentional export for a plugin'

    const gone = applyMemory([], first.nextMemory, 2_000)
    const back = applyMemory([f], gone.nextMemory, 3_000)

    assert.equal(back.annotated[0].isRecurring, true)
    assert.equal(back.annotated[0].muted, true)
    assert.equal(back.annotated[0].note, 'intentional export for a plugin')
    assert.equal(back.annotated[0].confidence, 'high')
  })
})
