import Foundation

public struct SyncConfiguration: Codable, Equatable, Sendable {
    public let serverURL: String
    public let clientID: UUID
    public let encryptionSecret: String

    public init(serverURL: String, clientID: UUID, encryptionSecret: String) throws {
        let address = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: address),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              !address.contains(where: \.isWhitespace),
              components.port.map({ (1...65535).contains($0) }) ?? true else {
            throw SynchronizationError.invalidServerURL
        }
        guard !encryptionSecret.isEmpty else { throw SynchronizationError.emptyEncryptionSecret }
        self.serverURL = address
        self.clientID = clientID
        self.encryptionSecret = encryptionSecret
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(serverURL: values.decode(String.self, forKey: .serverURL),
                      clientID: values.decode(UUID.self, forKey: .clientID),
                      encryptionSecret: values.decode(String.self, forKey: .encryptionSecret))
    }
}

public enum SynchronizationError: Error, Equatable, LocalizedError, Sendable {
    case invalidServerURL
    case emptyEncryptionSecret
    case notConfigured
    case unsupportedReplica
    case failed(String)
    case interrupted
    case configurationChanged

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL: "Enter an HTTP or HTTPS TaskChampion server address without embedded credentials."
        case .emptyEncryptionSecret: "Enter the encryption secret used by your other Taskwarrior clients."
        case .notConfigured: "Configure a TaskChampion server before synchronizing."
        case .unsupportedReplica: "This task storage adapter does not support synchronization."
        case .configurationChanged: "Connection settings changed before synchronization finished. Retry using the saved connection."
        case .interrupted: "Synchronization paused to prioritize local task access."
        case .failed(let message): "Synchronization failed: \(message). Your locally saved tasks remain on this device."
        }
    }
}
