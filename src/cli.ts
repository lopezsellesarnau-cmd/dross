#!/usr/bin/env node
import { resolve } from 'node:path'
import { collectSourceFiles } from './scan.js'
import { checkDeadExports } from './checks/deadExports.js'
import type { Report } from './report.js'

function printReport(report: Report) {
  console.log(`\nSHIPCHECK · ${report.repoRoot}`)
  console.log(`${report.filesScanned} files scanned · ${report.findings.length} findings\n`)

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
  const repoArg = process.argv[2] ?? '.'
  const repoRoot = resolve(repoArg)

  const files = collectSourceFiles(repoRoot)
  const findings = [...checkDeadExports(files)]

  const report: Report = {
    repoRoot,
    filesScanned: files.length,
    findings,
    generatedAt: Date.now(),
  }

  printReport(report)
  if (report.findings.length > 0) process.exitCode = 1
}

main()
