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
}
