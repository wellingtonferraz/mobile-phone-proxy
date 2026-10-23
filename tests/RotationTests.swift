import Foundation

@main struct RotationTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { fatalError("FAIL: \(name)") }
            checks += 1
        }
        let now = Date(timeIntervalSince1970: 1000)
        var state = IPRotation()
        check(state.begin(previousIP: "1.2.3.4", at: now), "first manual request accepted")
        check(state.isBusy, "request waits for shortcut")
        check(!state.begin(previousIP: "1.2.3.4", at: now), "double tap rejected")
        let id = state.id!
        let components = URLComponents(url: state.shortcutURL!, resolvingAgainstBaseURL: false)!
        check(components.queryItems?.first(where: { $0.name == "name" })?.value == "Rotate IP", "exact shortcut name")
        let success = URL(string: components.queryItems!.first(where: { $0.name == "x-success" })!.value!)!
        check(!state.receive(URL(string: "mobilephoneproxy://rotate-done?attempt=old")!, at: now), "late previous callback ignored")
        check(!state.receive(URL(string: "mobilephoneproxy://unrecognized?attempt=\(id)")!, at: now), "unknown callback ignored")
        check(state.receive(success, at: now.addingTimeInterval(91)), "current callback accepted")
        check(state.isBusy && state.phase == .checking, "completion is not proof of new IP")
        state.observe("5.6.7.8", lookupStartedAt: now.addingTimeInterval(90))
        check(state.phase == .checking, "lookup started before callback ignored")
        state.observe("5.6.7.8", lookupStartedAt: now.addingTimeInterval(92))
        check(state.phase == .changed && !state.isBusy, "fresh different IP confirms change")
        check(state.begin(previousIP: "5.6.7.8", at: now.addingTimeInterval(100)), "retry after completion")
        let next = URL(string: "mobilephoneproxy://rotate-done?attempt=\(state.id!)")!
        _ = state.receive(next, at: now.addingTimeInterval(101))
        state.observe("5.6.7.8", lookupStartedAt: now.addingTimeInterval(102))
        check(state.phase == .unchanged, "same IP not called success")
        _ = state.begin(previousIP: nil, at: now)
        _ = state.receive(URL(string: "mobilephoneproxy://rotate-done?attempt=\(state.id!)")!, at: now)
        state.observe("1.2.3.4", lookupStartedAt: now.addingTimeInterval(1))
        check(state.phase == .unconfirmed, "missing baseline cannot prove IP changed")
        _ = state.begin(previousIP: "1.2.3.4", at: now)
        check(!state.expire(at: now.addingTimeInterval(179)), "allow shortcut execution time")
        check(state.expire(at: now.addingTimeInterval(181)) && !state.isBusy, "missing callback times out and unlocks retry")
        _ = state.begin(previousIP: "1.2.3.4", at: now)
        _ = state.receive(URL(string: "mobilephoneproxy://rotate-cancel?attempt=\(state.id!)")!, at: now)
        check(state.phase == .failed && !state.isBusy, "cancel unlocks retry")
        _ = state.begin(previousIP: "1.2.3.4", at: now)
        _ = state.receive(URL(string: "mobilephoneproxy://rotate-error?attempt=\(state.id!)&errorMessage=PRIVATE_VALUE")!, at: now)
        check(state.phase == .failed && !state.message.contains("PRIVATE_VALUE"), "external shortcut error text omitted")
        _ = state.begin(previousIP: "1.2.3.4", at: now)
        _ = state.receive(URL(string: "mobilephoneproxy://rotate-done?attempt=\(state.id!)")!, at: now)
        check(state.expire(at: now.addingTimeInterval(61)) && state.phase == .unconfirmed, "lookup failure ends as unconfirmed")
        print("PASS: \(checks) rotation checks")
    }
}
