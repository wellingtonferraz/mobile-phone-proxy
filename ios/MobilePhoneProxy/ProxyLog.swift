import Foundation

enum ProxyLogLevel: String, Codable, CaseIterable {
    case info = "INFO", warning = "AVISO", error = "ERRO", debug = "DETALHE"
}

enum ProxyLogCategory: String, Codable {
    case server = "Servidor", connection = "Conexão", network = "Rede"
    case rotation = "Rotação", background = "Keep alive", security = "Acesso"
}

struct ProxyLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: ProxyLogLevel
    let category: ProxyLogCategory
    let message: String

    init(_ message: String, level: ProxyLogLevel, category: ProxyLogCategory, at: Date = Date()) {
        id = UUID()
        timestamp = at
        self.level = level
        self.category = category
        self.message = Self.sanitize(message)
    }

    var formatted: String {
        "\(timestamp.formatted(date: .omitted, time: .standard)) [\(level.rawValue)] [\(category.rawValue)] \(message)"
    }

    // Defense in depth for errors: external callback payloads are omitted at
    // source, and these rules redact common credential forms from diagnostics.
    static func sanitize(_ message: String) -> String {
        var text = message
        for (pattern, replacement) in [
            (#"(?i)(?:https?|socks5?|shortcuts)://[^\s<>]+"#, "[URL omitida]"),
            (#"(?im)["']?\b(?:proxy-authorization|authorization|cookie|set-cookie)["']?\s*:[^\r\n]*"#, "[cabeçalho omitido]"),
            (#"(?i)["']?\b(?:password|passwd|pwd|(?:access[_-]?|refresh[_-]?|id[_-]?)?token|(?:client[_-]?)?secret|api[_-]?key)["']?\s*[:=]\s*(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s&,;}\]]+)"#, "[segredo omitido]"),
            (#"[^\s:@/<>]+:[^\s@<>]+@[^\s<>]+"#, "[credenciais omitidas]")
        ] {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        text = text.components(separatedBy: .controlCharacters).joined(separator: " ")
        return String(text.prefix(500))
    }

    static func diagnosticHost(_ host: String) -> String {
        guard !host.isEmpty, host.count <= 253,
              host.range(of: #"\A[A-Za-z0-9_.:%\[\]-]+\z"#, options: .regularExpression) != nil
        else { return "[destino omitido]" }
        return host
    }
}

struct ProxyLogBuffer {
    private(set) var entries: [ProxyLogEntry] = []
    static let limit = 300

    mutating func append(_ entry: ProxyLogEntry) {
        entries.append(entry)
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }

    mutating func clear() { entries.removeAll() }
}
