import Foundation

enum Severity: String, Codable {
    case info, warning, finding
}

enum FixHint: String, Codable {
    case removeExport = "remove-export"
    case deleteDead = "delete-dead"
    case addEnvExample = "add-env-example"
    case openEditor = "open-editor"
}

enum Confidence: String, Codable {
    case high, medium, low
}

struct Finding: Codable, Identifiable, Hashable {
    var id: String { fingerprint ?? "\(check)-\(file)-\(line ?? 0)-\(message)" }
    let check: String
    let severity: Severity
    let file: String
    let line: Int?
    let message: String
    let fixHint: FixHint?
    let confidence: Confidence
    let fingerprint: String?
    let timesSeen: Int
    let isNew: Bool
    let isRecurring: Bool
    let muted: Bool
    let note: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        check = try c.decode(String.self, forKey: .check)
        severity = try c.decode(Severity.self, forKey: .severity)
        file = try c.decode(String.self, forKey: .file)
        line = try c.decodeIfPresent(Int.self, forKey: .line)
        message = try c.decode(String.self, forKey: .message)
        fixHint = try c.decodeIfPresent(FixHint.self, forKey: .fixHint)
        confidence = try c.decodeIfPresent(Confidence.self, forKey: .confidence) ?? .medium
        fingerprint = try c.decodeIfPresent(String.self, forKey: .fingerprint)
        timesSeen = try c.decodeIfPresent(Int.self, forKey: .timesSeen) ?? 1
        isNew = try c.decodeIfPresent(Bool.self, forKey: .isNew) ?? false
        isRecurring = try c.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

struct ScanReport: Codable {
    let repoRoot: String
    let filesScanned: Int
    let findings: [Finding]
    let generatedAt: Double
    let truncated: Bool
    let llmUsed: Bool?
    /// Anthropic key was present but the LLM drift pass was withheld for lack
    /// of a Pro license — drives the in-app upgrade prompt.
    let llmGated: Bool?

    var openFindings: [Finding] { findings.filter { !$0.muted } }
    var mutedCount: Int { findings.filter(\.muted).count }
    var openCount: Int { openFindings.count }

    init(repoRoot: String, filesScanned: Int, findings: [Finding], generatedAt: Double, truncated: Bool, llmUsed: Bool? = nil, llmGated: Bool? = nil) {
        self.repoRoot = repoRoot
        self.filesScanned = filesScanned
        self.findings = findings
        self.generatedAt = generatedAt
        self.truncated = truncated
        self.llmUsed = llmUsed
        self.llmGated = llmGated
    }
}
