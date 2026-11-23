import Foundation
import Network
import os

/// Chooses between a robot's home address and its address away from home.
struct EndpointSelector: Equatable, Sendable {
    enum Endpoint: String, Equatable, Sendable {
        case home, remote
    }

    static let remoteRecheckInterval: TimeInterval = 60

    let hasRemote: Bool
    private(set) var active: Endpoint = .home
    private var resolvedAt: Date?
    private var resolvedGeneration: Int?

    init(hasRemote: Bool) {
        self.hasRemote = hasRemote
    }

    func needsResolve(now: Date, pathGeneration: Int) -> Bool {
        guard hasRemote else { return false }
        guard let resolvedAt, resolvedGeneration == pathGeneration else { return true }
        // Away from home look for the home address again now and then; at home stay put until the network changes.
        return active == .remote && now.timeIntervalSince(resolvedAt) >= Self.remoteRecheckInterval
    }

    mutating func resolve(homeReachable: Bool, now: Date, pathGeneration: Int) {
        active = (homeReachable || !hasRemote) ? .home : .remote
        resolvedAt = now
        resolvedGeneration = pathGeneration
    }

    /// Address to retry after `failed` was unreachable; switches only if `failed` is still active, so parallel failures do not flip back.
    mutating func failover(from failed: Endpoint, now: Date, pathGeneration: Int) -> Endpoint? {
        guard hasRemote else { return nil }
        if active == failed {
            active = failed == .home ? .remote : .home
            resolvedAt = now
            resolvedGeneration = pathGeneration
        }
        return active
    }

    /// Errors that mean the address cannot be reached; HTTP errors and cancellations are not among them.
    static func isUnreachable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut,
             .notConnectedToInternet, .networkConnectionLost, .internationalRoamingOff, .dataNotAllowed:
            return true
        default:
            return false
        }
    }
}

/// Counts network changes, so an address choice is redone after switching between Wi-Fi and cellular.
final class NetworkPathWatcher: @unchecked Sendable {
    static let shared = NetworkPathWatcher()

    private struct State {
        var generation = 0
        var signature: PathSignature?
        var subscribers: [UUID: AsyncStream<Int>.Continuation] = [:]
    }

    private let monitor = NWPathMonitor()
    private let state = OSAllocatedUnfairLock(initialState: State())

    private init() {
        let state = state
        monitor.pathUpdateHandler = { path in
            let signature = PathSignature(path)
            let (changed, generation, subscribers) = state.withLock { current -> (Bool, Int, [AsyncStream<Int>.Continuation]) in
                // The monitor also reports minor updates; only a different link counts as a change.
                guard current.signature != signature else { return (false, current.generation, []) }
                current.signature = signature
                current.generation += 1
                return (true, current.generation, Array(current.subscribers.values))
            }
            guard changed else { return }
            subscribers.forEach { $0.yield(generation) }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkPathWatcher", qos: .utility))
    }

    var generation: Int {
        state.withLock { $0.generation }
    }

    /// Yields the new generation after each network change.
    func changes() -> AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            state.withLock { $0.subscribers[id] = continuation }
            continuation.onTermination = { [state] _ in
                state.withLock { $0.subscribers[id] = nil }
            }
        }
    }
}

/// The parts of a network path that decide which address is reachable.
struct PathSignature: Equatable, Sendable {
    let satisfied: Bool
    let wifi: Bool
    let cellular: Bool
    let wired: Bool
    let other: Bool

    init(satisfied: Bool, wifi: Bool, cellular: Bool, wired: Bool, other: Bool) {
        self.satisfied = satisfied
        self.wifi = wifi
        self.cellular = cellular
        self.wired = wired
        self.other = other
    }

    init(_ path: NWPath) {
        self.init(
            satisfied: path.status == .satisfied,
            wifi: path.usesInterfaceType(.wifi),
            cellular: path.usesInterfaceType(.cellular),
            wired: path.usesInterfaceType(.wiredEthernet),
            other: path.usesInterfaceType(.other)
        )
    }
}
