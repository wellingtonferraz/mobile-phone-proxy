import Foundation

@main struct ConnectivityTests {
    static func main() {
        var count = 0
        func check(_ value: Bool, _ name: String) {
            if !value { print("FAIL: \(name)"); exit(1) }
            count += 1
        }
        var health = ConnectivityHealth()
        check(health.status(at: 0) == "stopped", "no proof when stopped")
        var explicitlyStopped = ConnectivityHealth()
        explicitlyStopped.stop()
        check(!explicitlyStopped.startOnLaunch(at: 1), "delayed launch cannot override explicit Stop")
        var launched = ConnectivityHealth()
        check(launched.startOnLaunch(at: 1), "first launch starts once")
        launched.stop()
        check(!launched.startOnLaunch(at: 2), "foreground/view appearance cannot undo Stop")
        health.start(at: 100)
        let first = health.begin(at: 100)!
        check(health.begin(at: 101) == nil, "overlapping probe refused")
        check(health.status(at: 101) == "checking", "listener alone is not online")
        check(health.complete(first, success: true, at: 102), "current success accepted")
        check(health.status(at: 145) == "confirmed", "fresh HTTPS proof")
        check(health.status(at: 148) == "unconfirmed", "proof expires even without timer firing")
        check(health.status(at: 101) == "unconfirmed", "clock reversal is not fresh proof")
        for (now, wait) in [(150.0, 5.0), (155, 10), (165, 20), (185, 30), (215, 30)] {
            let token = health.begin(at: now)!
            check(health.complete(token, success: false, at: now), "failure settles")
            check(health.nextAttemptAt == now + wait, "bounded failure backoff")
            check(health.begin(at: now + wait - 0.1) == nil, "retry does not run early")
        }
        let old = health.begin(at: 245)!
        health.stop()
        check(!health.complete(old, success: true, at: 246), "late stopped probe cannot revive state")
        check(health.begin(at: 500) == nil && health.nextAttemptAt == nil, "manual stop cancels retries")
        health.start(at: 600)
        let current = health.begin(at: 600)!
        check(!health.complete(old, success: true, at: 601) && health.isChecking, "old callback cannot clear new probe")
        check(health.complete(current, success: true, at: 602), "new generation succeeds")
        let failure = health.begin(at: 632)!
        _ = health.complete(failure, success: false, at: 633)
        check(health.nextAttemptAt == 638, "success resets backoff")
        check(health.status(at: 634) == "unconfirmed", "failed probe invalidates prior proof")
        var delayed = ConnectivityHealth()
        delayed.start(at: 1000)
        let late = delayed.begin(at: 1000)!
        _ = delayed.complete(late, success: true, at: 1011)
        check(delayed.status(at: 1011) == "unconfirmed", "late delivery cannot create fresh proof after ten-second budget")
        delayed.start(at: 1100)
        let slower = delayed.begin(at: 1100)!
        _ = delayed.complete(slower, success: true, at: 1108)
        check(delayed.status(at: 1146) == "unconfirmed", "proof age starts at request, not delayed main-actor delivery")
        health.listenerFailed(at: 640)
        check(!health.isChecking && health.nextAttemptAt == 650, "listener failure uses bounded retry")

        let registry = ProxyConnections()
        let client = NSObject(), upstream = NSObject(), replacement = NSObject()
        var clientsClosed = 0, upstreamsClosed = 0
        registry.register(client) { clientsClosed += 1 }
        check(registry.attach(upstream, to: client) { upstreamsClosed += 1 }, "attach owned upstream")
        check(registry.canRetry(client, upstream: upstream), "retry allowed before forwarding")
        registry.markForwarding(client, upstream: upstream)
        check(!registry.canRetry(client, upstream: upstream), "never replay after forwarding begins")
        registry.closeAll()
        registry.close(client)
        check(clientsClosed == 1 && upstreamsClosed == 1, "reconnect closes both sockets once")
        check(!registry.attach(replacement, to: client) { upstreamsClosed += 1 }, "late upstream rejected after reconnect")
        check(upstreamsClosed == 2, "rejected upstream closed")
        check(!registry.isCurrent(client, upstream: upstream), "stale connection events ignored")
        registry.register(client) { clientsClosed += 1 }
        _ = registry.attach(upstream, to: client) { upstreamsClosed += 1 }
        check(registry.attach(replacement, to: client) { upstreamsClosed += 1 }, "pre-forwarding retry replaces upstream")
        check(!registry.isCurrent(client, upstream: upstream), "superseded socket cannot affect new attempt")
        registry.markForwarding(client, upstream: replacement)
        check(!registry.attach(upstream, to: client) { upstreamsClosed += 1 }, "no replacement/replay after forwarding")
        registry.closeAll()
        print("PASS: \(count) connectivity/recovery checks")
    }
}
