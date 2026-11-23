import Foundation

struct RobotConfig: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var username: String?
    var password: String?
    var useSSL: Bool
    var ignoreCertificateErrors: Bool
    /// Second address for use away from home, e.g. behind a reverse proxy.
    var remoteURL: String?

    var baseURL: URL? {
        let scheme = useSSL ? "https" : "http"
        return URL(string: "\(scheme)://\(host)")
    }

    /// Base URL of the address away from home; without a scheme it is https, a path is dropped.
    var remoteBaseURL: URL? {
        Self.parseRemoteURL(remoteURL)
    }

    var hasRemoteAddress: Bool {
        remoteBaseURL != nil
    }

    static func parseRemoteURL(_ text: String?) -> URL? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let parsed = URLComponents(string: withScheme),
              let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parsed.host, !host.isEmpty else { return nil }
        var base = URLComponents()
        base.scheme = scheme
        base.host = host
        base.port = parsed.port
        return base.url
    }

    /// Whether this robot is on a local network (private IP or .local mDNS)
    var isLocalNetwork: Bool {
        let h = host.lowercased()
        // mDNS / .local hostnames
        if h.hasSuffix(".local") { return true }
        // Private IPv4 ranges
        if h.starts(with: "192.168.") || h.starts(with: "10.") { return true }
        if h.starts(with: "172.") {
            let parts = h.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) { return true }
        }
        // Link-local
        if h.starts(with: "169.254.") { return true }
        return false
    }

    init(id: UUID = UUID(), name: String, host: String, username: String? = nil, password: String? = nil, useSSL: Bool = false, ignoreCertificateErrors: Bool = false, remoteURL: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.username = username
        self.password = password
        self.useSSL = useSSL
        self.ignoreCertificateErrors = ignoreCertificateErrors
        let trimmedRemote = remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.remoteURL = (trimmedRemote?.isEmpty ?? true) ? nil : trimmedRemote
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, host, username, useSSL, ignoreCertificateErrors, remoteURL
    }

    // Password is not in CodingKeys: it lives in the Keychain, never in UserDefaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        password = nil // Passwords are stored in Keychain, not in UserDefaults JSON
        useSSL = try container.decodeIfPresent(Bool.self, forKey: .useSSL) ?? false
        ignoreCertificateErrors = try container.decodeIfPresent(Bool.self, forKey: .ignoreCertificateErrors) ?? false
        remoteURL = try container.decodeIfPresent(String.self, forKey: .remoteURL)
    }
}
