import Foundation
import Network
import Combine
import UIKit

@MainActor
final class ProxyServer: ObservableObject {
    @Published var isRunning = false
    @Published var port: UInt16 = 8888
    @Published var localIP: String = "—"
    @Published var cellularIP: String = "—"
    @Published var tailscaleIP: String = "—"
    @Published var publicIP: String = "—"
    @Published var publicIPCheckedAt: Date?
    @Published var publicIPLastError: String?
    @Published var isCheckingPublicIP = false
    @Published var keepAliveEnabled: Bool {
        didSet {
            UserDefaults.standard.set(keepAliveEnabled, forKey: Self.keepAlivePreferenceKey)
        }
    }
    @Published var guidedAccess = UIAccessibility.isGuidedAccessEnabled
    @Published private(set) var rotation = IPRotation()
    var rotateStartedAt: Date? { rotation.isBusy ? rotation.startedAt : nil }

    @Published var isPaired = RotateAuth.isPaired
    @Published var pairingOpenUntil: Date?
    @Published var lastRotateCommand: String?
    @Published var relayState = "off"

    private let relay = RelayClient()
    /// Relay job being executed, reported back once the new public IP is known.
    private var relayJob: (id: String, oldIP: String, awaitingIP: Bool)?
    private var relayReportedIP = ""

    /// The live instance, for App Intents (they run in-process but outside SwiftUI).
    static weak var current: ProxyServer?
    private static let keepAlivePreferenceKey = "backgroundAudioKeepAliveEnabled"

    init() {
        // Enable on first launch; preserve an explicit choice, including OFF.
        keepAliveEnabled = UserDefaults.standard.object(forKey: Self.keepAlivePreferenceKey) as? Bool ?? true
        Self.current = self
    }

    /// User-created Shortcut; the carrier determines whether reconnection changes IP.
    static let rotateShortcutName = "Rotate IP"

    private let keepAlive = BackgroundAudioKeepAlive()
    @Published var activeConnections: Int = 0
    @Published var bytesUp: UInt64 = 0
    @Published var bytesDown: UInt64 = 0
    @Published private(set) var logBuffer = ProxyLogBuffer()
    var log: [String] { logBuffer.entries.map(\.formatted) }
    private var connectionIDs = Set<ObjectIdentifier>()
    private var lastPublicIPFailure: String?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "proxy.listener", qos: .userInitiated)
    private var ipRefreshTimer: Timer?
    private var publicIPTimer: Timer?
    private let lookupQueue = DispatchQueue(label: "proxy.publicip")

    func start() {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = false
            // Incoming access stays on USB/local Wi-Fi; outbound cellular is separate.
            params.prohibitedInterfaceTypes = [.cellular, .other]
            (params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4

            let listener = try NWListener(using: params, on: nwPort)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                guard LocalProxyAccess.allows(conn.endpoint, wifiSubnets: NetworkInterface.wifiIPv4Subnets()) else {
                    conn.cancel()
                    self.logLine("Conexão rejeitada: origem fora do USB ou da sub-rede Wi-Fi atual.", level: .warning, category: .security)
                    return
                }
                Task { @MainActor in
                    self.connectionIDs.insert(ObjectIdentifier(conn))
                    self.activeConnections = self.connectionIDs.count
                    HTTPProxyHandler.handle(client: conn, server: self, queue: self.queue)
                }
            }

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.refreshIPs()
                        self.updateKeepAlive()
                        self.append("Proxy HTTP iniciado na porta \(self.port). Entrada restrita a USB/Wi-Fi local.")
                        self.startRelay()
                        self.ipRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                            Task { @MainActor in self.refreshIPs() }
                        }
                        self.refreshPublicIP()
                        self.publicIPTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                            Task { @MainActor in self.refreshPublicIP() }
                        }
                    case .failed(let err):
                        self.append("Falha ao receber conexões: \(err)", level: .error)
                        self.stop()
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }

            listener.start(queue: queue)
        } catch {
            append("Não foi possível iniciar: \(error)", level: .error)
        }
    }

    func stop() {
        let wasStarted = listener != nil
        listener?.cancel()
        listener = nil
        isRunning = false
        ipRefreshTimer?.invalidate()
        ipRefreshTimer = nil
        publicIPTimer?.invalidate()
        publicIPTimer = nil
        keepAlive.stop()
        relay.stop()
        if wasStarted { append("Proxy parado; novas conexões não serão aceitas.") }
    }

    /// Starts/stops the silent-audio background keepalive to match current state.
    /// Call after the listener becomes ready, after stop, and when the toggle flips.
    func updateKeepAlive() {
        keepAlive.onLog = { [weak self] line in
            self?.logLine(line, level: line.contains("failed") ? .error : .info, category: .background)
        }
        if isRunning && keepAliveEnabled {
            keepAlive.start()
        } else {
            keepAlive.stop()
        }
    }

    nonisolated func recordUp(_ n: Int) {
        Task { @MainActor in self.bytesUp &+= UInt64(n) }
    }
    nonisolated func recordDown(_ n: Int) {
        Task { @MainActor in self.bytesDown &+= UInt64(n) }
    }
    nonisolated func connectionClosed(_ client: NWConnection) {
        let id = ObjectIdentifier(client)
        Task { @MainActor in
            guard self.connectionIDs.remove(id) != nil else { return }
            self.activeConnections = self.connectionIDs.count
        }
    }
    nonisolated func logLine(_ s: String, level: ProxyLogLevel = .info, category: ProxyLogCategory = .connection) {
        Task { @MainActor in self.append(s, level: level, category: category) }
    }

    private func append(_ s: String, level: ProxyLogLevel = .info, category: ProxyLogCategory = .server) {
        logBuffer.append(ProxyLogEntry(s, level: level, category: category))
    }

    func clearLog() {
        logBuffer.clear()
        append("Histórico local limpo. Novos eventos aparecerão aqui.")
    }

    private func refreshIPs() {
        if rotation.expire() {
            append(rotation.message, level: .warning, category: .rotation)
            finishRelayJob(ok: false, detail: "rotation result not confirmed")
        }
        let newLocalIP = NetworkInterface.address(for: .wifi) ?? "—"
        if newLocalIP != localIP {
            append(newLocalIP == "—" ? "Wi-Fi indisponível. O acesso USB depende do túnel no Mac." : "Endereço Wi-Fi atual: \(newLocalIP):\(port).", category: .network)
            localIP = newLocalIP
        }
        let newCellular = NetworkInterface.address(for: .cellular) ?? "—"
        if newCellular != cellularIP {
            // A new carrier-internal address (e.g. after airplane mode) is the
            // moment the CGNAT public address may have changed too — re-check now
            // instead of waiting for the 30 s timer.
            if cellularIP != "—" || newCellular != "—" {
                append("Endereço interno da rede móvel: \(cellularIP) → \(newCellular).", category: .network)
            }
            cellularIP = newCellular
            if isRunning, newCellular != "—" {
                refreshPublicIP()
                relay.reconnectNow()
            }
        }
        tailscaleIP = NetworkInterface.tailscaleAddress() ?? "—"
        guidedAccess = UIAccessibility.isGuidedAccessEnabled
        if let until = pairingOpenUntil, until <= Date() { pairingOpenUntil = nil }
    }

    // MARK: - Control endpoint (GET /__status, /__log, /__rotate, /__pair)

    func handleControl(path: String) -> (status: String, json: String) {
        switch path {
        case "/__status":
            return ("200 OK", statusJSON())
        case "/__log":
            return ("200 OK", logJSON())
        case "/__rotate":
            return requestRotate()
        case "/__pair":
            return pair()
        #if targetEnvironment(simulator)
        case "/__open-pairing":
            // Simulator-only stand-in for tapping "Pair Mac".
            openPairingWindow()
            return ("200 OK", #"{"ok":true}"#)
        case let p where p.hasPrefix("/__callback/"):
            // Simulator-only stand-in for the shortcut's x-success / x-error
            // (the simulator has no "Rotate IP" shortcut, and simctl openurl
            // prompts before opening the app).
            handleCallback(URL(string: "mobilephoneproxy://" + p.dropFirst("/__callback/".count))!)
            return ("200 OK", #"{"ok":true}"#)
        case let p where p.hasPrefix("/__verify/"):
            // Simulator-only hook to test Mac-side signing against CryptoKit.
            let msg = String(p.dropFirst("/__verify/".count)).removingPercentEncoding ?? ""
            let v = RotateAuth.verify(msg)
            return ("200 OK", "{\"verdict\":\"\(v.description)\"}")
        #endif
        default:
            return ("404 Not Found", #"{"error":"unknown path"}"#)
        }
    }

    private func statusJSON(extra: [String: Any] = [:]) -> String {
        var d: [String: Any] = [
            "publicIP": publicIP,
            "cellularIP": cellularIP,
            "tailscaleIP": tailscaleIP,
            "wifiIP": localIP,
            "appActive": UIApplication.shared.applicationState == .active,
            "guidedAccess": UIAccessibility.isGuidedAccessEnabled,
            "rotating": rotateStartedAt != nil,
            "paired": RotateAuth.isPaired,
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
            "isRunning": isRunning,
            "port": port,
            "activeConnections": activeConnections,
            "keepAliveEnabled": keepAliveEnabled,
            "keepAliveActive": keepAlive.isActive,
            "rotationMode": "user-created-shortcut",
            "rotationShortcut": Self.rotateShortcutName,
            "rotationShortcutConfigured": "not-verified",
            "rotationPhase": rotation.phase.rawValue,
            "rotationMessage": rotation.message,
            "automaticRotationScheduled": false,
            "usbTunnelStatus": "not-observable-from-iphone",
        ]
        if let error = publicIPLastError { d["publicIPLastError"] = error }
        if let at = publicIPCheckedAt { d["publicIPCheckedAt"] = ISO8601DateFormatter().string(from: at) }
        if let last = lastRotateCommand { d["lastRotateCommand"] = last }
        d.merge(extra) { _, new in new }
        let data = (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// In-memory app log plus the persistent App Intent record (see IntentEventLog).
    private func logJSON() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let events = (try? JSONSerialization.jsonObject(with: encoder.encode(logBuffer.entries))) ?? []
        // Historical intent records may include the caller's message. Export
        // outcome metadata only; command payloads are not needed for diagnosis.
        let intentEvents = IntentEventLog.events.map { event in
            event.filter { ["at", "event", "pid", "serverLive", "appState"].contains($0.key) }
                .mapValues { value in (value as? String).map(ProxyLogEntry.sanitize) ?? value }
        }
        let d: [String: Any] = ["lines": log, "events": events, "limit": ProxyLogBuffer.limit, "intentEvents": intentEvents]
        let data = (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// iOS gives apps no API to toggle Airplane Mode, but Shortcuts has a
    /// "Set Airplane Mode" action. We launch the user's shortcut by URL; the
    /// x-success/x-error callbacks bring this app back to the foreground.
    /// Opening another app only works while we are the foreground app.
    @discardableResult
    func requestRotate() -> (status: String, json: String) {
        if rotation.expire() { append(rotation.message, level: .warning, category: .rotation) }
        if rotation.isBusy {
            return ("409 Conflict", statusJSON(extra: ["error": "rotation already in progress"]))
        }
        guard isRunning, UIApplication.shared.applicationState == .active, !UIAccessibility.isGuidedAccessEnabled else {
            rotation.fail("Inicie o proxy, mantenha este app aberto e desligue o Acesso Guiado para abrir Atalhos.")
            append(rotation.message, level: .warning, category: .rotation)
            return ("409 Conflict", statusJSON(extra: ["error": "app is not in the foreground; iOS only lets the foreground app open Shortcuts"]))
        }
        let recent = publicIPCheckedAt.map { Date().timeIntervalSince($0) <= 60 } ?? false
        let baseline = recent && publicIPLastError == nil && publicIP != "—" && cellularIP != "—" ? publicIP : nil
        _ = rotation.begin(previousIP: baseline)
        guard let url = rotation.shortcutURL, let attempt = rotation.id else {
            rotation.fail("Não foi possível preparar a abertura do atalho.")
            return ("500 Internal Server Error", #"{"error":"bad url"}"#)
        }
        append(rotation.message, category: .rotation)
        // Delay so the HTTP 202 reaches the Mac before airplane mode cuts the link.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.rotation.id == attempt, self.rotation.phase == .requested else { return }
            UIApplication.shared.open(url) { [weak self] ok in
                guard let self, !ok, self.rotation.id == attempt, self.rotation.phase == .requested else { return }
                self.rotation.fail("O iOS recusou abrir Atalhos. Confira se o app está instalado e se Acesso Guiado/Assistivo está desligado.")
                self.append(self.rotation.message, level: .error, category: .rotation)
                self.finishRelayJob(ok: false, detail: "iOS refused to open Shortcuts (Guided or Assistive Access on?)")
            }
        }
        return ("202 Accepted", statusJSON(extra: ["started": true]))
    }

    // MARK: - iMessage rotate command pairing

    /// Opens a short window during which GET /__pair hands the HMAC secret to
    /// the Mac. Requiring a tap on the phone keeps other tailnet devices from
    /// silently fetching it.
    func openPairingWindow() {
        pairingOpenUntil = Date().addingTimeInterval(120)
        append("Pairing window open for 2 min — run: macos/rotate-ip.sh --pair")
    }

    func unpair() {
        RotateAuth.unpair()
        isPaired = false
        relay.stop()
        append("Unpaired — signed rotate commands now rejected")
    }

    private func pair() -> (status: String, json: String) {
        guard let until = pairingOpenUntil, until > Date() else {
            return ("403 Forbidden", #"{"error":"pairing window closed — tap 'Pair Mac' in the app"}"#)
        }
        let secret = RotateAuth.secretForPairing()
        pairingOpenUntil = nil
        isPaired = true
        if isRunning { startRelay() }
        append("Paired with Mac — signed iMessage rotate commands enabled")
        return ("200 OK", "{\"secret\":\"\(secret.base64EncodedString())\"}")
    }

    func rotateCommandVerified(_ verdict: RotateAuth.Verdict, via source: String = "iMessage") {
        let ts = Self.timeFormatter.string(from: Date())
        lastRotateCommand = "\(ts) \(source) \(verdict.description)"
        append("\(source): comando de rotação \(verdict.description)", category: .rotation)
    }

    // MARK: - Relay

    private func startRelay() {
        relay.onState = { [weak self] s in self?.relayState = s }
        relay.onLog = { [weak self] line in self?.append(line, category: .rotation) }
        relay.helloInfo = { [weak self] in
            var d: [String: Any] = ["build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"]
            if let ip = self?.publicIP, ip != "—" { d["publicIP"] = ip }
            return d
        }
        relay.onCommand = { [weak self] jobId, command in self?.relayCommand(jobId: jobId, command: command) }
        relay.start()
    }

    /// A signed command from the relay: verify it here (the relay can't), then
    /// run the same URL trigger as GET /__rotate.
    private func relayCommand(jobId: String, command: String) {
        let verdict = RotateAuth.verify(command)
        rotateCommandVerified(verdict, via: "Relay")
        var ack: [String: Any] = ["type": "ack", "jobId": jobId, "verdict": verdict.description]
        if publicIP != "—" { ack["publicIP"] = publicIP }
        relay.send(ack)
        guard verdict.isAccepted else { return }

        let (status, json) = requestRotate()
        if status.hasPrefix("202") {
            relayJob = (jobId, publicIP, false)
            relay.send(["type": "rotating", "jobId": jobId])
        } else {
            let why = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["error"] as? String
            relay.send(["type": "result", "jobId": jobId, "ok": false, "detail": why ?? status])
        }
    }

    /// Called once the shortcut has returned; reports when the public IP is known.
    private func finishRelayJob(ok: Bool, detail: String? = nil) {
        // Once the shortcut has reported success, a later callback can't undo it.
        guard let job = relayJob, !job.awaitingIP else { return }
        if ok {
            // Wait for the post-airplane public IP lookup (refreshPublicIP),
            // but don't hold the job forever if lookups keep failing.
            relayJob?.awaitingIP = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                guard let self, self.relayJob?.id == job.id else { return }
                self.sendRelayResult(detail: "public IP lookup did not succeed within 60 s")
            }
            return
        }
        relayJob = nil
        relay.send(["type": "result", "jobId": job.id, "ok": ok, "detail": detail ?? ""])
    }

    private func sendRelayResult(detail: String? = nil) {
        guard let job = relayJob else { return }
        relayJob = nil
        var msg: [String: Any] = ["type": "result", "jobId": job.id, "ok": true]
        if job.oldIP != "—" { msg["oldIP"] = job.oldIP }
        if publicIP != "—" { msg["newIP"] = publicIP }
        if let detail { msg["detail"] = detail }
        relay.send(msg)
    }

    /// Callback from Shortcuts (x-success / x-cancel / x-error).
    func handleCallback(_ url: URL) {
        guard rotation.receive(url) else { return }
        let completed = rotation.phase == .checking
        append(rotation.message, level: completed ? .info : .warning, category: .rotation)
        finishRelayJob(ok: completed, detail: completed ? nil : "shortcut did not complete")
        refreshIPs()
        refreshPublicIP()
    }

    /// Asks an external service for the public (post-CGNAT) address over cellular.
    func refreshPublicIP() {
        guard !isCheckingPublicIP else { return }
        isCheckingPublicIP = true
        let lookupStartedAt = Date()
        PublicIP.fetch(queue: lookupQueue) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isCheckingPublicIP = false
                switch result {
                case .success(let ip):
                    if self.lastPublicIPFailure != nil {
                        self.append("Consulta do IP móvel voltou a responder.", category: .network)
                    }
                    self.lastPublicIPFailure = nil
                    self.publicIPLastError = nil
                    if ip != self.publicIP {
                        self.append(self.publicIP == "—" ? "IP público móvel consultado: \(ip)." : "Mudança de IP móvel observada: \(self.publicIP) → \(ip).", category: .network)
                        self.publicIP = ip
                    }
                    self.publicIPCheckedAt = Date()
                    let previousPhase = self.rotation.phase
                    self.rotation.observe(ip, lookupStartedAt: lookupStartedAt)
                    if self.rotation.phase != previousPhase {
                        self.append(self.rotation.message, category: .rotation)
                    }
                    if self.relayJob?.awaitingIP == true && !self.rotation.isBusy {
                        self.sendRelayResult()
                    } else if ip != self.relayReportedIP {
                        self.relay.send(["type": "ip", "publicIP": ip])
                    }
                    self.relayReportedIP = ip
                case .failure(let error):
                    let detail = ProxyLogEntry.sanitize(error.localizedDescription)
                    self.publicIPLastError = detail
                    if detail != self.lastPublicIPFailure {
                        self.append("Falha na consulta do IP móvel: \(detail). O último valor pode estar desatualizado.", level: .warning, category: .network)
                    }
                    self.lastPublicIPFailure = detail
                }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
