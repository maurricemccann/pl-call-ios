import Foundation

/// How the call listens. Tap hears and says nothing: every question waits for a tap.
public enum ListenMode: String, Sendable, CaseIterable {
    case handsFree, push, tap

    /// The stored mode; else the old settings: the separate music mode becomes Push to talk (music stays out of the way
    /// until he pushes), then the old hands-free bool.
    public static func resolve(stored: String?, legacyHandsFree: Bool?, legacyMusicMode: Bool? = nil) -> ListenMode {
        if let stored, let mode = ListenMode(rawValue: stored) { return mode }
        if legacyMusicMode == true { return .push }
        return (legacyHandsFree ?? true) ? .handsFree : .push
    }
}

/// What each mode does to the phone's audio, as plain values the app turns into an AVAudioSession.
/// Tap: the mic never opens and his music or video plays on untouched. Push to talk: no phone call; the session is taken only
/// for a turn, so his music pauses while he talks and resumes after. Auto: a phone call, the mic always open, no other media.
public struct AudioPlan: Equatable, Sendable {
    public enum Category: Sendable { case playback, playAndRecord }
    public enum Mode: Sendable { case standard, voiceChat }

    public var category: Category
    public var mode: Mode
    public var mixWithOthers: Bool         // other audio keeps playing, at full volume (never ducked)
    public var usesCallKit: Bool           // a system phone call
    public var opensMic: Bool              // the mic is ever opened
    public var micAlwaysOpen: Bool         // open for the whole call, not only for a turn
    public var holdsSessionBetweenTurns: Bool   // false: the session is let go between turns, so other players resume
    public var bluetoothHFP: Bool

    public static func plan(for mode: ListenMode) -> AudioPlan {
        switch mode {
        case .tap:
            return AudioPlan(category: .playback, mode: .standard, mixWithOthers: true, usesCallKit: false, opensMic: false,
                             micAlwaysOpen: false, holdsSessionBetweenTurns: false, bluetoothHFP: false)
        case .push:
            return AudioPlan(category: .playAndRecord, mode: .standard, mixWithOthers: false, usesCallKit: false, opensMic: true,
                             micAlwaysOpen: false, holdsSessionBetweenTurns: false, bluetoothHFP: false)
        case .handsFree:
            return AudioPlan(category: .playAndRecord, mode: .voiceChat, mixWithOthers: false, usesCallKit: true, opensMic: true,
                             micAlwaysOpen: true, holdsSessionBetweenTurns: true, bluetoothHFP: true)
        }
    }
}

/// The question or approval he is looking at, and the ones behind it.
/// There is no way in here to answer: only his tap (settle) or the session itself (withdraw) removes an ask.
public struct AskQueue: Sendable, Equatable {
    public private(set) var current: Ask?
    public private(set) var waiting: [Ask] = []

    public init() {}

    public static func id(of ask: Ask) -> String {
        switch ask {
        case .permission(let requestId, _, _, _): return requestId
        case .question(let requestId, _, _, _): return requestId
        }
    }

    public enum Raised: Equatable, Sendable {
        case showing                  // it is now the one on screen
        case already                  // the same request again: nothing changes
        case queued(position: Int)    // it waits behind the one on screen
        case replaced(Ask)            // classic modes: it took the place of the earlier one
    }

    /// `queueing` is Tap: a newer ask never takes the screen from an older one. Without it, a newer ask replaces the older.
    public mutating func raise(_ ask: Ask, queueing: Bool) -> Raised {
        let id = Self.id(of: ask)
        guard let earlier = current else { current = ask; return .showing }
        if Self.id(of: earlier) == id { current = ask; return .already }
        if waiting.contains(where: { Self.id(of: $0) == id }) { return .already }
        if queueing {
            waiting.append(ask)
            return .queued(position: waiting.count)
        }
        current = ask
        waiting = []
        return .replaced(earlier)
    }

    /// He answered the one on screen (or it is dropped): the next one steps up. Returns it.
    @discardableResult
    public mutating func settle() -> Ask? {
        current = waiting.isEmpty ? nil : waiting.removeFirst()
        return current
    }

    public enum Withdrawn: Equatable, Sendable {
        case current(next: Ask?)
        case queued
        case none
    }

    /// The session says this request is settled (answered at the PC, or it ran out there).
    public mutating func withdraw(requestId: String) -> Withdrawn {
        if let c = current, Self.id(of: c) == requestId { return .current(next: settle()) }
        if let i = waiting.firstIndex(where: { Self.id(of: $0) == requestId }) {
            waiting.remove(at: i)
            return .queued
        }
        return .none
    }

    /// The session changed or the config was forgotten: nothing here belongs to a live request any more.
    public mutating func clear() { current = nil; waiting = [] }
}
