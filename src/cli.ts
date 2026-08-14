#!/usr/bin/env node
import { resolve } from 'node:path'
import { companionRoots } from './companions.js'
import { runScan } from './runScan.js'
import { fixRemoveExport } from './fix/removeExport.js'
import { fixDeleteDead } from './fix/deleteDead.js'
import {
  applyMemory,
  blockingCount,
  loadMemory,
  matchFinding,
  saveMemory,
  fingerprint,
  type AnnotatedFinding,
} from './memory.js'
import type { FixHint, Report } from './report.js'

function printHelp() {
  console.log(`
dross — scan a repo before you ship

Usage:
  dross scan [path…] [--also <path>] [--json]
      Scan one or more roots. Pass client + API dirs together so contract-drift
      can compare both sides (TRACE-class). Exit 1 if findings.
  dross [path] [--json]
      Same as scan (shortcut for a single root).
  dross fix <repo> <file> <line> [remove-export|delete-dead] [--json]
  dross mute <repo> <file> <line> [--reason "..."]
      Remember this finding as accepted — muted findings do not fail CI.
  dross unmute <repo> <file> <line>
      Forget a mute. Next scan treats the finding as open again.
  dross --help

CI examples:
  npx dross scan . --json
  npx dross scan ./trace-app --also ./trace-backend --json
`)
}

function printReport(report: Report, annotated: AnnotatedFinding[]) {
  const muted = annotated.filter((f) => f.muted).length
  const open = annotated.length - muted
  console.log(`\nDROSS · ${report.repoRoot}`)
  console.log(`${report.filesScanned} files scanned · ${open} findings`)
  if (report.llmUsed) console.log(`LLM drift pass: on`)
  if (report.truncated) {
    console.log(`⚠ Stopped early at the file cap — this repo (or directory) is larger than a single scan covers. Point Dross at a narrower path.`)
  }
  console.log('')

  const visible = annotated.filter((f) => !f.muted)
  if (visible.length === 0) {
    console.log('Clear to ship — no findings.\n')
    if (muted > 0) console.log(`${muted} muted\n`)
    return
  }

  for (const f of visible) {
    const loc = f.line ? `${f.file}:${f.line}` : f.file
    const tag = f.isRecurring ? '  ↻ regression — seen before, was fixed, back again' : ''
    const conf = f.confidence && f.confidence !== 'medium' ? ` ${f.confidence}` : ''
    console.log(`  [${f.check}] ${loc}${conf}${tag}`)
    console.log(`    ${f.message}`)
    if (f.note) console.log(`    note: ${f.note}`)
    console.log('')
  }
  if (muted > 0) console.log(`${muted} muted\n`)
}

function parseAlso(argv: string[]): { rest: string[]; also: string[] } {
  const also: string[] = []
  const rest: string[] = []
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--also' || argv[i] === '--with') {
      const next = argv[i + 1]
      if (next && !next.startsWith('-')) {
        also.push(next)
        i++
      }
      continue
    }
    rest.push(argv[i])
  }
  return { rest, also }
}

function parseReason(argv: string[]): { rest: string[]; reason: string | undefined } {
  const rest: string[] = []
  let reason: string | undefined
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--reason') {
      const next = argv[i + 1]
      if (next && !next.startsWith('-')) {
        reason = next
        i++
      }
      continue
    }
    rest.push(argv[i])
  }
  return { rest, reason }
}

async function scanRoots(pathArgs: string[], also: string[]): Promise<{ unique: string[]; report: Awaited<ReturnType<typeof runScan>> }> {
  const explicit = [...pathArgs, ...also].map((p) => resolve(p))
  const roots =
    explicit.length === 1 && also.length === 0 ? companionRoots(explicit[0]) : explicit
  const unique = [...new Set(roots)]
  const report = await runScan(unique)
  return { unique, report }
}

async function main() {
  const argv = process.argv.slice(2)
  if (argv.includes('--help') || argv.includes('-h')) {
    printHelp()
    return
  }

  const { rest: withoutReason, reason } = parseReason(argv)
  const asJson = withoutReason.includes('--json')
  const { rest, also } = parseAlso(withoutReason)
  const flags = new Set(['--json', '--help', '-h', '--also', '--with', '--reason'])

  // dross fix | dross --fix
  const fixIdx = rest[0] === 'fix' ? 0 : rest.indexOf('--fix')
  if (fixIdx >= 0) {
    const base = fixIdx === 0 && rest[0] === 'fix' ? 1 : fixIdx + 1
    const repoArg = rest[base]
    const relPath = rest[base + 1]
    const line = Number(rest[base + 2])
    const kind = (rest[base + 3] && !rest[base + 3].startsWith('-')
      ? rest[base + 3]
      : 'remove-export') as FixHint
    if (!repoArg || !relPath || !Number.isFinite(line)) {
      console.error('Usage: dross fix <repoRoot> <relPath> <line> [remove-export|delete-dead]')
      process.exitCode = 2
      return
    }
    const root = resolve(repoArg)
    const result =
      kind === 'delete-dead'
        ? fixDeleteDead(root, relPath, line)
        : fixRemoveExport(root, relPath, line)
    if (asJson) console.log(JSON.stringify(result))
    else console.log(result.ok ? `✓ ${result.message}` : `✗ ${result.message}`)
    process.exitCode = result.ok ? 0 : 1
    return
  }

  // dross mute | dross unmute
  if (rest[0] === 'mute' || rest[0] === 'unmute') {
    const verb = rest[0]
    const repoArg = rest[1]
    const relPath = rest[2]
    const line = Number(rest[3])
    if (!repoArg || !relPath || !Number.isFinite(line)) {
      console.error(`Usage: dross ${verb} <repoRoot> <relPath> <line>${verb === 'mute' ? ' [--reason "..."]' : ''}`)
      process.exitCode = 2
      return
    }
    const root = resolve(repoArg)
    const { report } = await scanRoots([root], [])
    const hit = matchFinding(report.findings, relPath, line)
    if (!hit) {
      console.error(`No finding at ${relPath}:${line}`)
      process.exitCode = 1
      return
    }
    const fp = fingerprint(hit)
    const mem = loadMemory(root)
    const now = Date.now()
    const { nextMemory } = applyMemory(report.findings, mem, now)
    if (verb === 'mute') {
      const prev = nextMemory.decisions[fp]
      nextMemory.decisions[fp] = {
        ...prev,
        status: 'muted',
        reason: reason ?? prev.reason,
        lastSeen: now,
      }
      saveMemory(root, nextMemory)
      const msg = `muted ${fp}${reason ? ` (${reason})` : ''}`
      if (asJson) console.log(JSON.stringify({ ok: true, fingerprint: fp, message: msg }))
      else console.log(`✓ ${msg}`)
    } else {
      delete nextMemory.decisions[fp]
      saveMemory(root, nextMemory)
      const msg = `unmuted ${fp}`
      if (asJson) console.log(JSON.stringify({ ok: true, fingerprint: fp, message: msg }))
      else console.log(`✓ ${msg}`)
    }
    return
  }

  // dross scan [path…] [--also path] | dross [path]
  const positionals = rest.filter((a) => !flags.has(a) && !a.startsWith('-'))
  let pathArgs: string[] = []
  if (positionals[0] === 'scan') {
    pathArgs = positionals.slice(1)
  } else {
    pathArgs = positionals
  }
  if (pathArgs.length === 0) pathArgs = ['.']

  const { unique, report } = await scanRoots(pathArgs, also)
  const mem = loadMemory(unique[0])
  const { annotated, nextMemory } = applyMemory(report.findings, mem, Date.now())
  saveMemory(unique[0], nextMemory)

  if (asJson) {
    console.log(JSON.stringify({ ...report, findings: annotated }))
  } else {
    printReport(report, annotated)
  }
  if (blockingCount(annotated) > 0) process.exitCode = 1
}

main().catch((err) => {
  console.error(err)
  process.exitCode = 1
})
