export type Severity = 'info' | 'warning' | 'finding'

export type Finding = {
  check: string
  severity: Severity
  file: string
  line?: number
  message: string
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
}
