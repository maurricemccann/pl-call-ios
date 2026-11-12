import Foundation

/// Reads the config file once, keeps its JSON in the Keychain, and hands it back at launch.
/// An actor so the file read and the Keychain calls never run on the main thread.
actor ConfigStore {
    private static let account = "config"

    /// `url` comes from the Files picker or AirDrop, so it is security-scoped.
    func load(from url: URL) throws -> PLCallConfig {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let config = try PLCallConfig.load(data)
        try Keychain.save(data, account: Self.account)
        return config
    }

    func saved() -> PLCallConfig? {
        guard let data = Keychain.load(account: Self.account) else { return nil }
        return try? PLCallConfig.load(data)
    }

    func forget() {
        Keychain.delete(account: Self.account)
    }
}
