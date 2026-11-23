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

/// Counts network path changes, so an address choice is redone after switching between Wi-Fi and cellular.
final class NetworkPathWatcher: @unchecked Sendable {
    static let shared = NetworkPathWatcher()

    private let monitor = NWPathMonitor()
    private let counter = OSAllocatedUnfairLock(initialState: 0)

    private init() {
        let counter = counter
        monitor.pathUpdateHandler = { _ in
            counter.withLock { $0 += 1 }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkPathWatcher", qos: .utility))
    }

    var generation: Int {
        counter.withLock { $0 }
    }
}
