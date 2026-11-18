import Foundation

/// How the call listens. Tap hears and says nothing: every question waits for a tap.
public enum ListenMode: String, Sendable, CaseIterable {
    case handsFree, push, tap

    /// The stored mode, or the old hands-free bool from before Tap existed.
    public static func resolve(stored: String?, legacyHandsFree: Bool?) -> ListenMode {
        if let stored, let mode = ListenMode(rawValue: stored) { return mode }
        return (legacyHandsFree ?? true) ? .handsFree : .push
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
