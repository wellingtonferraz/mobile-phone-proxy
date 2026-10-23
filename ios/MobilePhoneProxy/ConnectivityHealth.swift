import Foundation

/// Local listener readiness is deliberately independent of this HTTPS evidence.
struct ConnectivityHealth {
    private(set) var desiredRunning = false
    private(set) var lastSuccessAt: TimeInterval?
    private(set) var lastAttemptAt: TimeInterval?
    private(set) var nextAttemptAt: TimeInterval?
    private var attempt: UUID?
    private var failures = 0
    private var lastSucceeded = false
    private var lastCompletedAt: TimeInterval?
    private var launchHandled = false
    static let validity: TimeInterval = 45
    var isChecking: Bool { attempt != nil }

    mutating func start(at now: TimeInterval) {
        launchHandled = true
        desiredRunning = true
        attempt = nil
        failures = 0
        lastSucceeded = false
        nextAttemptAt = now
    }

    mutating func stop() {
        launchHandled = true
        desiredRunning = false
        attempt = nil
        nextAttemptAt = nil
        lastSucceeded = false
    }

    mutating func startOnLaunch(at now: TimeInterval) -> Bool {
        guard !launchHandled else { return false }
        start(at: now)
        return true
    }

    mutating func begin(at now: TimeInterval, force: Bool = false) -> UUID? {
        guard desiredRunning, attempt == nil,
              force || now >= (nextAttemptAt ?? .infinity) else { return nil }
        let token = UUID()
        attempt = token
        lastAttemptAt = now
        nextAttemptAt = nil
        return token
    }

    @discardableResult
    mutating func complete(_ token: UUID, success: Bool, at now: TimeInterval) -> Bool {
        guard desiredRunning, attempt == token else { return false }
        attempt = nil
        lastCompletedAt = now
        // Include delivery delay/suspension, not only time spent in Network.framework.
        let started = lastAttemptAt ?? now
        lastSucceeded = success && now >= started && now - started <= 10
        if lastSucceeded {
            // Conservative proof age: never refresh evidence just by delivering it late.
            lastSuccessAt = started
            failures = 0
            nextAttemptAt = now + 30
        } else {
            scheduleFailure(at: now)
        }
        return true
    }

    mutating func listenerFailed(at now: TimeInterval) {
        guard desiredRunning else { return }
        attempt = nil
        lastSucceeded = false
        scheduleFailure(at: now)
    }

    private mutating func scheduleFailure(at now: TimeInterval) {
        let waits: [TimeInterval] = [5, 10, 20, 30]
        nextAttemptAt = now + waits[min(failures, waits.count - 1)]
        failures = min(failures + 1, waits.count)
    }

    func status(at now: TimeInterval) -> String {
        guard desiredRunning else { return "stopped" }
        if isChecking { return "checking" }
        if lastSucceeded, let at = lastSuccessAt, now >= (lastCompletedAt ?? at), now - at <= Self.validity {
            return "confirmed"
        }
        return "unconfirmed"
    }
}
