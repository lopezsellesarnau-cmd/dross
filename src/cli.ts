#!/usr/bin/env node
import { resolve } from 'node:path'
import { collectSourceFiles } from './scan.js'
import { checkDeadExports } from './checks/deadExports.js'
import type { Report } from './report.js'

function printReport(report: Report) {
  console.log(`\nSHIPCHECK · ${report.repoRoot}`)
  console.log(`${report.filesScanned} files scanned · ${report.findings.length} findings`)
  if (report.truncated) {
    console.log(`⚠ Stopped early at the file cap — this repo (or directory) is larger than a single scan covers. Point ShipCheck at a narrower path.`)
  }
  console.log('')

  if (report.findings.length === 0) {
    console.log('Clear to ship — no findings.\n')
    return
  }

  for (const f of report.findings) {
    console.log(`  [${f.check}] ${f.file}`)
    console.log(`    ${f.message}\n`)
  }
}

function main() {
  const args = process.argv.slice(2).filter((a) => a !== '--json')
  const asJson = process.argv.includes('--json')
  const repoArg = args[0] ?? '.'
  const repoRoot = resolve(repoArg)

  const { files, truncated } = collectSourceFiles(repoRoot)
  const findings = [...checkDeadExports(files)]

  const report: Report = {
    repoRoot,
    filesScanned: files.length,
    findings,
    generatedAt: Date.now(),
    truncated,
  }

  // The Mac app shells out to this CLI and parses stdout — `--json` is that
  // contract. Kept as an explicit flag rather than always-on so a human
  // running this directly still gets the readable version by default.
  if (asJson) {
    console.log(JSON.stringify(report))
  } else {
    printReport(report)
  }
  if (report.findings.length > 0) process.exitCode = 1
}

main()
