import Foundation

/// The private settings, loaded once from the config file and then kept in the Keychain.
/// Nothing in here is ever in the repository.
public struct PLCallConfig: Codable, Sendable, Equatable {
    public struct Line: Codable, Sendable, Equatable {
        public var base: String          // the PC's https address ending in /call/
        public var fallbackIp: String?   // tried second; the certificate must still carry certName
        public var certName: String      // the name the PC's certificate must carry
    }
    public struct Voice: Codable, Sendable, Equatable {
        public var id: String            // "phone" = the iPhone voice; anything else = a PC voice id
        public var label: String
    }
    public struct QuickReply: Codable, Sendable, Equatable {
        public var label: String
        public var send: String
        public var arm: Bool?            // true = first tap arms, a second tap within 3 s sends
    }
    public struct Speech: Codable, Sendable, Equatable {
        public var endOfTurnMs: Int?
        public var endOfTurnInterimMs: Int?
    }
    public struct Theme: Codable, Sendable, Equatable {
        public var fontFamily: String?   // "jost" (default) or "system"
    }

    public var v: Int
    public var line: Line
    public var callKey: String
    public var defaultVoice: String?
    public var voices: [Voice]?
    public var quickReplies: [QuickReply]?
    public var speech: Speech?
    public var theme: Theme?

    public enum Problem: Error, Equatable, CustomStringConvertible {
        case unsupportedVersion(Int), baseNotHTTPS, missingCertName, missingCallKey, notJSON(String)
        public var description: String {
            switch self {
            case .unsupportedVersion(let v): return "This config is version \(v); this app reads version 1."
            case .baseNotHTTPS: return "The line address must start with https://."
            case .missingCertName: return "The config has no certificate name."
            case .missingCallKey: return "The config has no call key."
            case .notJSON(let m): return "The file is not a readable config: \(m)"
            }
        }
    }

    /// Parses and checks a config file. The address is normalised to end with "/".
    public static func load(_ data: Data) throws -> PLCallConfig {
        var c: PLCallConfig
        do { c = try JSONDecoder().decode(PLCallConfig.self, from: data) }
        catch { throw Problem.notJSON(String(describing: error).prefix(160).description) }
        guard c.v == 1 else { throw Problem.unsupportedVersion(c.v) }
        guard c.line.base.lowercased().hasPrefix("https://") else { throw Problem.baseNotHTTPS }
        if !c.line.base.hasSuffix("/") { c.line.base += "/" }
        guard !c.line.certName.trimmingCharacters(in: .whitespaces).isEmpty else { throw Problem.missingCertName }
        guard !c.callKey.trimmingCharacters(in: .whitespaces).isEmpty else { throw Problem.missingCallKey }
        return c
    }

    public var endOfTurn: Double { Double(speech?.endOfTurnMs ?? 900) / 1000 }
    public var endOfTurnInterim: Double { Double(speech?.endOfTurnInterimMs ?? 1600) / 1000 }
    public var voiceList: [Voice] { voices?.isEmpty == false ? voices! : [Voice(id: "phone", label: "iPhone")] }
    public var startingVoice: String { defaultVoice ?? voiceList.first?.id ?? "phone" }
    public var quickReplyList: [QuickReply] { quickReplies ?? [] }
    public var usesSystemFont: Bool { theme?.fontFamily?.lowercased() == "system" }
}
