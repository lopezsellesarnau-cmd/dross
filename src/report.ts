export type Severity = 'info' | 'warning' | 'finding'

export type FixHint = 'remove-export' | 'delete-dead' | 'add-env-example' | 'open-editor'

export type Confidence = 'high' | 'medium' | 'low'

export type Finding = {
  check: string
  severity: Severity
  file: string
  line?: number
  message: string
  /** How the Mac app / CLI can act on this finding. */
  fixHint?: FixHint
  /** How sure the engine is this is a real ship-break, not noise. */
  confidence?: Confidence
}

export type Report = {
  repoRoot: string
  filesScanned: number
  findings: Finding[]
  generatedAt: number
  /** True if the scan hit MAX_FILES and stopped early — the report is a
   *  partial view, not a complete one, and must say so rather than look
   *  identical to a clean small repo. */
  truncated: boolean
  /** True when the optional LLM drift pass ran (needs ANTHROPIC_API_KEY). */
  llmUsed?: boolean
  /** True when an Anthropic key was present but the LLM pass was withheld
   *  because there's no valid Pro license — the paid upgrade prompt. */
  llmGated?: boolean
}

