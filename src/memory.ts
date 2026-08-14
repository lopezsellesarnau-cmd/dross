import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import type { Finding } from './report.js'

export type DecisionStatus = 'muted' | 'acknowledged'

export type Decision = {
  status: DecisionStatus
  reason?: string
  firstSeen: number
  lastSeen: number
  timesSeen: number
  resolvedAt?: number
}

export type MemoryStore = {
  version: 1
  decisions: Record<string, Decision>
}

export type AnnotatedFinding = Finding & {
  fingerprint: string
  timesSeen: number
  isNew: boolean
  isRecurring: boolean
  muted: boolean
  note?: string
}

const QUOTED = /"([^"]+)"/
const API_PATH = /\/[A-Za-z][\w./:-]*/

export function fingerprint(f: Finding): string {
  const quoted = f.message.match(QUOTED)
  const path = f.message.match(API_PATH)
  const stableKey = quoted?.[1] ?? path?.[0] ?? f.message.slice(0, 120)
  return `${f.check}::${f.file}::${stableKey}`
}

export function emptyMemory(): MemoryStore {
  return { version: 1, decisions: {} }
}

export function memoryPath(repoRoot: string): string {
  return join(repoRoot, '.dross', 'memory.json')
}

export function loadMemory(repoRoot: string): MemoryStore {
  const path = memoryPath(repoRoot)
  if (!existsSync(path)) return emptyMemory()
  try {
    const raw = JSON.parse(readFileSync(path, 'utf8')) as Partial<MemoryStore>
    if (raw?.version !== 1 || !raw.decisions || typeof raw.decisions !== 'object') {
      return emptyMemory()
    }
    return { version: 1, decisions: { ...raw.decisions } }
  } catch {
    return emptyMemory()
  }
}

export function saveMemory(repoRoot: string, mem: MemoryStore): void {
  const path = memoryPath(repoRoot)
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, JSON.stringify(mem, null, 2) + '\n', 'utf8')
}

function cloneStore(mem: MemoryStore): MemoryStore {
  return {
    version: 1,
    decisions: Object.fromEntries(Object.entries(mem.decisions).map(([k, v]) => [k, { ...v }])),
  }
}

export function applyMemory(
  findings: Finding[],
  mem: MemoryStore,
  now: number,
): { annotated: AnnotatedFinding[]; nextMemory: MemoryStore } {
  const nextMemory = cloneStore(mem)
  const present = new Set<string>()
  const annotated: AnnotatedFinding[] = []

  for (const f of findings) {
    const fp = fingerprint(f)
    present.add(fp)
    const prev = nextMemory.decisions[fp]

    if (!prev) {
      nextMemory.decisions[fp] = {
        status: 'acknowledged',
        firstSeen: now,
        lastSeen: now,
        timesSeen: 1,
      }
      annotated.push({
        ...f,
        fingerprint: fp,
        timesSeen: 1,
        isNew: true,
        isRecurring: false,
        muted: false,
      })
      continue
    }

    const isRecurring = prev.resolvedAt != null
    const timesSeen = prev.timesSeen + 1
    const muted = prev.status === 'muted'
    const updated: Decision = {
      ...prev,
      lastSeen: now,
      timesSeen,
    }
    if (isRecurring) delete updated.resolvedAt
    nextMemory.decisions[fp] = updated

    annotated.push({
      ...f,
      fingerprint: fp,
      timesSeen,
      isNew: false,
      isRecurring,
      muted,
      note: prev.reason,
      confidence: isRecurring ? 'high' : (f.confidence ?? 'medium'),
    })
  }

  for (const [fp, dec] of Object.entries(nextMemory.decisions)) {
    if (present.has(fp)) continue
    if (dec.resolvedAt == null) {
      nextMemory.decisions[fp] = { ...dec, resolvedAt: now }
    }
  }

  return { annotated, nextMemory }
}

/** Findings that should fail CI — muted ones are the user's explicit pass. */
export function blockingCount(annotated: AnnotatedFinding[]): number {
  return annotated.filter((f) => !f.muted).length
}

export function matchFinding(findings: Finding[], file: string, line: number): Finding | undefined {
  return findings.find((f) => f.file === file && f.line === line)
}
