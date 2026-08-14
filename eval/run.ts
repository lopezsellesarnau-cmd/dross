#!/usr/bin/env node
import { readdirSync, readFileSync, existsSync, statSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { runScan } from '../src/runScan.js'
import type { Finding } from '../src/report.js'

/**
 * Golden-corpus eval harness — turns "trust me, the engine got better" into a
 * measured precision/recall number. Every fixture in ./corpus is a tiny repo
 * with a hand-labeled `expected.json` of the findings that are TRUE. The runner
 * scans each with the exact same code path as the CLI/app (`runScan`) and
 * scores it:
 *   - a predicted finding that matches no expected item  = FALSE POSITIVE
 *   - an expected item that no prediction matches          = MISS (false negative)
 * Precision is what protects user trust (don't cry wolf); recall is coverage.
 * When you fix a false positive in the engine, add the repro here as a fixture
 * so it can never silently come back.
 */

type ExpectedItem = { check: string; file?: string; line?: number; note?: string }
type FixtureSpec = {
  description?: string
  /** Scan roots relative to the fixture dir. Defaults to ["."]. */
  roots?: string[]
  expected: ExpectedItem[]
}

const HERE = dirname(fileURLToPath(import.meta.url))
const CORPUS = join(HERE, 'corpus')
const MIN_PRECISION = Number(process.env.EVAL_MIN_PRECISION ?? '1')
const MIN_RECALL = Number(process.env.EVAL_MIN_RECALL ?? '1')

function endsWithPath(actual: string, expected: string): boolean {
  const a = actual.replace(/\\/g, '/')
  const e = expected.replace(/\\/g, '/')
  return a === e || a.endsWith('/' + e)
}

function matches(actual: Finding, expected: ExpectedItem): boolean {
  if (actual.check !== expected.check) return false
  if (expected.file && !(actual.file && endsWithPath(actual.file, expected.file))) return false
  if (expected.line != null && actual.line !== expected.line) return false
  return true
}

function fmtFinding(f: Finding): string {
  const loc = f.line ? `${f.file}:${f.line}` : f.file
  return `[${f.check}] ${loc}`
}

function fmtExpected(e: ExpectedItem): string {
  const loc = e.file ? (e.line ? `${e.file}:${e.line}` : e.file) : '(any file)'
  return `[${e.check}] ${loc}`
}

type FixtureResult = {
  name: string
  tp: number
  fp: number
  fn: number
  falsePositives: Finding[]
  misses: ExpectedItem[]
}

async function runFixture(name: string, dir: string): Promise<FixtureResult> {
  const specPath = join(dir, 'expected.json')
  const spec: FixtureSpec = JSON.parse(readFileSync(specPath, 'utf8'))
  const roots = (spec.roots ?? ['.']).map((r) => resolve(dir, r))
  const report = await runScan(roots)
  const actual = report.findings

  const falsePositives = actual.filter((a) => !spec.expected.some((e) => matches(a, e)))
  const misses = spec.expected.filter((e) => !actual.some((a) => matches(a, e)))
  const tp = actual.length - falsePositives.length

  return { name, tp, fp: falsePositives.length, fn: misses.length, falsePositives, misses }
}

function listFixtures(): { name: string; dir: string }[] {
  if (!existsSync(CORPUS)) return []
  return readdirSync(CORPUS)
    .map((name) => ({ name, dir: join(CORPUS, name) }))
    .filter(({ dir }) => statSync(dir).isDirectory() && existsSync(join(dir, 'expected.json')))
    .sort((a, b) => a.name.localeCompare(b.name))
}

async function main() {
  const fixtures = listFixtures()
  if (fixtures.length === 0) {
    console.error(`No fixtures found in ${CORPUS}`)
    process.exitCode = 1
    return
  }

  const results: FixtureResult[] = []
  for (const { name, dir } of fixtures) {
    results.push(await runFixture(name, dir))
  }

  let totalTp = 0
  let totalFp = 0
  let totalFn = 0

  console.log('\nDROSS eval — golden corpus\n')
  for (const r of results) {
    totalTp += r.tp
    totalFp += r.fp
    totalFn += r.fn
    const ok = r.fp === 0 && r.fn === 0
    const badge = ok ? 'PASS' : 'FAIL'
    console.log(`  ${badge}  ${r.name}  (tp ${r.tp}, fp ${r.fp}, miss ${r.fn})`)
    for (const fp of r.falsePositives) console.log(`         · false positive: ${fmtFinding(fp)}`)
    for (const miss of r.misses) console.log(`         · missed:         ${fmtExpected(miss)}`)
  }

  const precision = totalTp + totalFp === 0 ? 1 : totalTp / (totalTp + totalFp)
  const recall = totalTp + totalFn === 0 ? 1 : totalTp / (totalTp + totalFn)
  const f1 = precision + recall === 0 ? 0 : (2 * precision * recall) / (precision + recall)

  console.log('\n  ─────────────────────────────')
  console.log(`  precision ${(precision * 100).toFixed(1)}%   recall ${(recall * 100).toFixed(1)}%   F1 ${(f1 * 100).toFixed(1)}%`)
  console.log(`  ${results.length} fixtures · tp ${totalTp} · fp ${totalFp} · miss ${totalFn}\n`)

  if (precision < MIN_PRECISION || recall < MIN_RECALL) {
    console.error(
      `✗ below threshold (need precision ≥ ${(MIN_PRECISION * 100).toFixed(0)}%, recall ≥ ${(MIN_RECALL * 100).toFixed(0)}%)`,
    )
    process.exitCode = 1
  } else {
    console.log('✓ corpus clean')
  }
}

main().catch((err) => {
  console.error(err)
  process.exitCode = 1
})
