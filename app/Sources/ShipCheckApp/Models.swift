import Foundation

enum Severity: String, Codable {
    case info, warning, finding
}

struct Finding: Codable, Identifiable {
    var id: String { "\(check)-\(file)-\(message)" }
    let check: String
    let severity: Severity
    let file: String
    let line: Int?
    let message: String
}

struct ScanReport: Codable {
    let repoRoot: String
    let filesScanned: Int
    let findings: [Finding]
    let generatedAt: Double
    let truncated: Bool
}
