import Foundation

/// Owns cancellation of accepted clients and their current upstream socket.
/// Callbacks may arrive on listener/lookup queues; cancellation runs outside the lock.
final class ProxyConnections: @unchecked Sendable {
    private struct Entry {
        var cancelClient: () -> Void
        var upstream: ObjectIdentifier?
        var cancelUpstream: (() -> Void)?
        var forwarded = false
    }
    private let lock = NSLock()
    private var entries: [ObjectIdentifier: Entry] = [:]

    func register(_ client: AnyObject, cancel: @escaping () -> Void) {
        lock.lock(); defer { lock.unlock() }
        entries[ObjectIdentifier(client)] = Entry(cancelClient: cancel)
    }

    @discardableResult
    func attach(_ upstream: AnyObject, to client: AnyObject, cancel: @escaping () -> Void) -> Bool {
        lock.lock()
        let key = ObjectIdentifier(client)
        guard var entry = entries[key], !entry.forwarded else {
            lock.unlock(); cancel(); return false
        }
        let previous = entry.cancelUpstream
        entry.upstream = ObjectIdentifier(upstream)
        entry.cancelUpstream = cancel
        entries[key] = entry
        lock.unlock()
        previous?()
        return true
    }

    func isCurrent(_ client: AnyObject, upstream: AnyObject) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return entries[ObjectIdentifier(client)]?.upstream == ObjectIdentifier(upstream)
    }

    func canRetry(_ client: AnyObject, upstream: AnyObject) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[ObjectIdentifier(client)] else { return false }
        return entry.upstream == ObjectIdentifier(upstream) && !entry.forwarded
    }

    func markForwarding(_ client: AnyObject, upstream: AnyObject) {
        lock.lock(); defer { lock.unlock() }
        let key = ObjectIdentifier(client)
        guard entries[key]?.upstream == ObjectIdentifier(upstream) else { return }
        entries[key]?.forwarded = true
    }

    func close(_ client: AnyObject) {
        lock.lock()
        let entry = entries.removeValue(forKey: ObjectIdentifier(client))
        lock.unlock()
        entry?.cancelClient()
        entry?.cancelUpstream?()
    }

    func closeAll() {
        lock.lock()
        let owned = Array(entries.values)
        entries.removeAll()
        lock.unlock()
        for entry in owned { entry.cancelClient(); entry.cancelUpstream?() }
    }
}
