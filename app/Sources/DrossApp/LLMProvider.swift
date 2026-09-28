import Foundation

/// Bring-your-own-key providers for the LLM drift pass. Must match the
/// engine's `src/llm/providers.ts` (ids and env var names).
enum LLMProvider: String, CaseIterable, Identifiable {
    case anthropic, openai, deepseek, mistral
    /// Any OpenAI-compatible server: OpenRouter, Groq, a local Ollama/LM Studio…
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .deepseek: return "DeepSeek"
        case .mistral: return "Mistral"
        case .custom: return "Custom"
        }
    }

    /// Env var the engine reads this provider's key from.
    var envVar: String {
        switch self {
        case .anthropic: return "ANTHROPIC_API_KEY"
        case .openai: return "OPENAI_API_KEY"
        case .deepseek: return "DEEPSEEK_API_KEY"
        case .mistral: return "MISTRAL_API_KEY"
        case .custom: return "DROSS_LLM_API_KEY"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-…"
        case .openai: return "sk-proj-…"
        case .deepseek: return "sk-…"
        case .mistral: return "Mistral API key"
        case .custom: return "API key (not needed for local servers)"
        }
    }

    /// The provider a key belongs to, when its format says so unambiguously.
    /// Mistral keys carry no prefix, so they're never guessed.
    static func detect(fromKey raw: String) -> LLMProvider? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.hasPrefix("sk-ant-") { return .anthropic }
        if key.hasPrefix("sk-proj-") || key.hasPrefix("sk-svcacct-") || key.hasPrefix("sk-admin-") { return .openai }
        // DeepSeek: "sk-" + 32 lowercase hex characters.
        if key.range(of: #"^sk-[0-9a-f]{32}$"#, options: .regularExpression) != nil { return .deepseek }
        return nil
    }

    /// One-click base URLs for the custom provider (all OpenAI-compatible).
    static let customPresets: [(name: String, url: String)] = [
        ("OpenRouter", "https://openrouter.ai/api/v1"),
        ("Groq", "https://api.groq.com/openai/v1"),
        ("Ollama", "http://localhost:11434/v1"),
        ("LM Studio", "http://localhost:1234/v1"),
    ]

    /// Env vars the engine reacts to — stripped from anything a GUI launch
    /// inherits, so only what the user chose in Dross is ever forwarded.
    static var allEngineEnvVars: [String] {
        allCases.map(\.envVar) + ["DROSS_LLM_PROVIDER", "DROSS_LLM_MODEL", "DROSS_LLM_BASE_URL"]
    }
}
