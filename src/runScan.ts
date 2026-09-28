import { basename } from 'node:path'
import { collectSourceFilesMulti } from './scan.js'
import { checkDeadExports } from './checks/deadExports.js'
import { checkContractDrift, summarizeDriftSurfaces } from './checks/contractDrift.js'
import { checkTodoDensity } from './checks/todoDensity.js'
import { checkHardcodedDemo } from './checks/hardcodedDemo.js'
import { checkEnvDrift } from './checks/envDrift.js'
import { checkRepoSecrets } from './checks/secrets.js'
import { checkInjection } from './checks/injection.js'
import { checkAuthDrift } from './checks/authDrift.js'
import { checkDangerousConfig } from './checks/dangerousConfig.js'
import { judgeContractDrift } from './llm/driftJudge.js'
import { resolveLlmProvider } from './llm/providers.js'
import { scoreConfidence } from './confidence.js'
import { licenseStatus } from './license.js'
import type { Report } from './report.js'

/**
 * The single scan code path — shared by the CLI, the Mac app (via the CLI),
 * and the eval harness so all three measure the exact same engine. Keep this
 * the only place that composes the checks.
 */
export async function runScan(roots: string[]): Promise<Report> {
  const { files, truncated } = collectSourceFilesMulti(roots)

  const findings = [
    ...checkDeadExports(files),
    ...checkContractDrift(files),
    ...checkTodoDensity(files),
    ...checkHardcodedDemo(files),
    ...checkInjection(files),
    ...checkAuthDrift(files),
    ...checkDangerousConfig(files),
  ]

  // Env files live per package — check each root against its own files.
  for (const root of roots) {
    const owned = files.filter((f) => (f.root ?? roots[0]) === root)
    findings.push(...checkEnvDrift(root, owned))
  }

  // Secrets look past the JS/TS walk: every file git would ship (any
  // language, config, dotfiles) plus local .env files feeding the bundle.
  // Companion roots use the same basename prefix as collectSourceFilesMulti.
  roots.forEach((root, i) => {
    const owned = files.filter((f) => (f.root ?? roots[0]) === root)
    findings.push(...checkRepoSecrets(root, i === 0 ? '' : basename(root), owned))
  })

  for (const f of findings) {
    f.confidence = scoreConfidence(f)
  }

  // The LLM drift pass is the paid tier. It runs only when the user both
  // brings a key for a supported provider AND holds a valid Pro license. Deterministic
  // checks above always run, free — the free/paid line per the product plan.
  // LLM is a suppressor: it may drop low-confidence drift noise and add
  // extras only for paths already on the extracted surface.
  let llmUsed = false
  let llmGated = false
  let llmError: string | undefined
  const llm = resolveLlmProvider()
  const llmProvider = llm ? `${llm.label ?? llm.id} · ${llm.model}` : undefined
  if (llm) {
    if (licenseStatus().valid) {
      const surface = summarizeDriftSurfaces(files)
      const candidates = findings.filter(
        (f) => f.check === 'contract-drift' && f.confidence === 'low',
      )
      const judged = await judgeContractDrift(surface, candidates)
      if (judged.drop.length) {
        const dropSet = new Set(judged.drop)
        for (let i = findings.length - 1; i >= 0; i--) {
          if (dropSet.has(findings[i])) findings.splice(i, 1)
        }
      }
      for (const extra of judged.extra) {
        extra.confidence = scoreConfidence(extra)
        findings.push(extra)
      }
      // Only claim the pass ran when the model actually answered.
      llmUsed = judged.status === 'ok'
      if (judged.status === 'failed') llmError = judged.error
    } else {
      // Key present but unlicensed — tell the caller so it can prompt to upgrade.
      llmGated = true
    }
  }

  const primary = roots[0]

  return {
    repoRoot: primary,
    filesScanned: files.length,
    findings,
    generatedAt: Date.now(),
    truncated,
    llmUsed,
    llmGated,
    llmError,
    llmProvider: llmUsed || llmError ? llmProvider : undefined,
  }
}
