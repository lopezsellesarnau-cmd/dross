import { collectSourceFilesMulti } from './scan.js'
import { checkDeadExports } from './checks/deadExports.js'
import { checkContractDrift, summarizeDriftSurfaces } from './checks/contractDrift.js'
import { checkTodoDensity } from './checks/todoDensity.js'
import { checkHardcodedDemo } from './checks/hardcodedDemo.js'
import { checkEnvDrift } from './checks/envDrift.js'
import { judgeContractDrift } from './llm/driftJudge.js'
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
  ]

  // Env files live per package — check each root against its own files.
  for (const root of roots) {
    const owned = files.filter((f) => (f.root ?? roots[0]) === root)
    findings.push(...checkEnvDrift(root, owned))
  }

  for (const f of findings) {
    f.confidence = scoreConfidence(f)
  }

  // The LLM drift pass is the paid tier. It runs only when the user both
  // brings an Anthropic key AND holds a valid Pro license. Deterministic
  // checks above always run, free — the free/paid line per the product plan.
  let llmUsed = false
  let llmGated = false
  if (process.env.ANTHROPIC_API_KEY) {
    if (licenseStatus().valid) {
      const surface = summarizeDriftSurfaces(files)
      const llmFindings = await judgeContractDrift(surface)
      if (llmFindings.length) {
        findings.push(...llmFindings)
        llmUsed = true
      } else if (surface.server.length && surface.client.length) {
        llmUsed = true
      }
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
  }
}
