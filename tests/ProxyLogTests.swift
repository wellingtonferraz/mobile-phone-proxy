import Foundation

@main struct ProxyLogTests {
    static func main() throws {
        var checks = 0
        func check(_ ok: Bool, _ name: String) {
            guard ok else { fatalError("FAIL: \(name)") }
            checks += 1
        }
        let sensitive = [
            "Request https://alice:secret-pass@example.com/private?token=abc#fragment",
            "Proxy-Authorization: Basic dXNlcjpwYXNz\r\nOperation failed",
            "Authorization: Bearer token-value\nfailed",
            "Cookie: session=secret-cookie\nfailed",
            "password=secret-pass token=secret-token api_key=secret-api-key",
            "Callback shortcuts://run?name=test&input=secret-input",
            #"{"token":"secret-json"}"#,
            "access_token=secret-access refresh_token=secret-refresh",
            #"password="review phrase secret-quoted""#,
            "alice:secret-userinfo@example.com:443",
            #"{"Authorization":"Bearer secret-json-header"}"#,
            #"{'api_key': 'review phrase secret-single'}"#
        ]
        for (i, raw) in sensitive.enumerated() {
            let s = ProxyLogEntry(raw, level: .error, category: .connection).message
            check(!s.contains("secret-") && !s.contains("token-value") && !s.contains("dXNlcjpwYXNz"), "credential redaction \(i)")
            check(!s.contains("\n") && !s.contains("\r"), "single-line message \(i)")
        }
        let ordinary = "Conectado a example.com:443 pela rede móvel."
        check(ProxyLogEntry.sanitize(ordinary) == ordinary, "retain useful host/route")
        check(ProxyLogEntry.diagnosticHost("alice:secret-userinfo@example.com") == "[destino omitido]", "do not log arbitrary host content")
        check(ProxyLogEntry.diagnosticHost("example.com") == "example.com", "retain normal host")
        check(ProxyLogEntry.diagnosticHost("2001:db8::1") == "2001:db8::1", "retain IPv6 host")
        check(ProxyLogEntry.sanitize("IP 1.2.3.4 → 5.6.7.8") == "IP 1.2.3.4 → 5.6.7.8", "retain IP changes")
        check(ProxyLogEntry.sanitize(String(repeating: "á", count: 700)).count == 500, "bound unicode message")
        let a = ProxyLogEntry("same", level: .info, category: .server)
        let b = ProxyLogEntry("same", level: .info, category: .server)
        check(a.id != b.id, "duplicate log lines retain distinct row identity")
        var buffer = ProxyLogBuffer()
        for i in 0..<325 { buffer.append(ProxyLogEntry("event \(i)", level: .info, category: .server)) }
        check(buffer.entries.count == 300, "memory bound")
        check(buffer.entries.first?.message == "event 25", "evict oldest")
        check(buffer.entries.last?.message == "event 324", "retain latest")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let json = try JSONSerialization.jsonObject(with: encoder.encode(a)) as! [String: Any]
        check(json["level"] as? String == "INFO" && json["category"] as? String == "Servidor", "structured levels and categories")
        check(json["timestamp"] is String && json["id"] is String, "export stable identity and timestamp")
        buffer.clear(); check(buffer.entries.isEmpty, "clear history")
        print("PASS: \(checks) log checks")
    }
}
