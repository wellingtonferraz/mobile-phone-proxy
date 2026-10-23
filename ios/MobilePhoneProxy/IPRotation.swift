import Foundation

/// Tracks a manual request. A completed shortcut is not proof of a new IP.
struct IPRotation {
    enum Phase: String { case idle, requested, checking, changed, unchanged, unconfirmed, failed }
    private(set) var phase: Phase = .idle
    private(set) var id: String?
    private(set) var startedAt: Date?
    private var callbackAt: Date?
    private var previousIP: String?
    private(set) var message = "Instale o atalho Rotate IP antes de usar o botão."
    var isBusy: Bool { phase == .requested || phase == .checking }

    mutating func begin(previousIP: String?, at now: Date = Date()) -> Bool {
        guard !isBusy else { return false }
        id = UUID().uuidString
        startedAt = now
        callbackAt = nil
        self.previousIP = previousIP
        phase = .requested
        message = "Abrindo Rotate IP no app Atalhos. A conexão será interrompida enquanto o modo avião estiver ligado."
        return true
    }

    var shortcutURL: URL? {
        guard let id else { return nil }
        var c = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")!
        c.queryItems = [URLQueryItem(name: "name", value: "Rotate IP")]
        for (key, outcome) in [("x-success", "done"), ("x-cancel", "cancel"), ("x-error", "error")] {
            c.queryItems!.append(URLQueryItem(name: key, value: "mobilephoneproxy://rotate-\(outcome)?attempt=\(id)"))
        }
        return c.url
    }

    @discardableResult mutating func receive(_ url: URL, at now: Date = Date()) -> Bool {
        guard phase == .requested, url.scheme == "mobilephoneproxy",
              let outcome = url.host, ["rotate-done", "rotate-cancel", "rotate-error"].contains(outcome),
              let attempt = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "attempt" })?.value,
              attempt == id else { return false }
        if outcome == "rotate-done" {
            phase = .checking
            callbackAt = now
            message = "Atalho concluído. Consultando o IP móvel para verificar o resultado…"
        } else {
            fail(outcome == "rotate-cancel" ? "Rotação cancelada no app Atalhos." : "O atalho não foi concluído. Confira se Rotate IP está instalado e veja o erro no app Atalhos.")
        }
        return true
    }

    mutating func observe(_ ip: String, lookupStartedAt: Date) {
        guard phase == .checking, let callbackAt, lookupStartedAt >= callbackAt else { return }
        guard let previousIP else {
            phase = .unconfirmed
            message = "IP móvel consultado: \(ip). Não havia um IP anterior recente para confirmar a troca."
            return
        }
        phase = ip == previousIP ? .unchanged : .changed
        message = ip == previousIP
            ? "A operadora devolveu o mesmo IP: \(ip). O atalho terminou, mas não houve mudança observada."
            : "Mudança de IP confirmada: \(previousIP) → \(ip)."
    }

    mutating func fail(_ reason: String) {
        phase = .failed
        message = reason
    }

    @discardableResult mutating func expire(at now: Date = Date()) -> Bool {
        if phase == .requested, let startedAt, now.timeIntervalSince(startedAt) >= 180 {
            fail("Sem retorno do atalho após 3 minutos. Confira o app Atalhos e se o modo avião ficou desligado antes de tentar novamente.")
            return true
        }
        if phase == .checking, let callbackAt, now.timeIntervalSince(callbackAt) >= 60 {
            phase = .unconfirmed
            message = "Atalho concluído, mas o IP móvel não pôde ser consultado. A troca não foi confirmada."
            return true
        }
        return false
    }
}
