import Foundation
import WidgetKit

/// The call state, shared from the app to the Lock Screen widget through an App Group.
/// A build signed without the group has no shared store: writes do nothing and reads say idle.
enum SharedState {
    static let baseGroup = "group.com.psychedluxuries.call"

    /// The group this install can really open, or nil. Some signers rename the group and list the new name in Info.plist.
    static let groupID: String? = {
        var bundles = [Bundle.main]
        if Bundle.main.bundleURL.pathExtension == "appex" {
            let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            if let app = Bundle(url: appURL) { bundles.append(app) }
        }
        var candidates: [String] = []
        for bundle in bundles {
            let listed = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
            candidates += listed.filter { $0.hasPrefix(SharedState.baseGroup) }
        }
        candidates.append(SharedState.baseGroup)
        return candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    }()

    static var isAvailable: Bool { groupID != nil }

    private static var store: UserDefaults? {
        guard let groupID else { return nil }
        return UserDefaults(suiteName: groupID)
    }

    /// Call on every state change. Redraws the Lock Screen widget only when something changed.
    static func write(state: CallState, line: String, ask: String?) {
        guard let store else { return }
        let same = store.string(forKey: "state") == state.rawValue
            && store.string(forKey: "line") == line
            && store.string(forKey: "ask") == ask
        if same { return }
        store.set(state.rawValue, forKey: "state")
        store.set(line, forKey: "line")
        store.set(ask, forKey: "ask")
        store.set(Date().timeIntervalSince1970, forKey: "updated")
        WidgetCenter.shared.reloadTimelines(ofKind: PLCallKinds.stateWidget)
    }

    static func read() -> (state: CallState, line: String, ask: String?) {
        guard let store else { return (.idle, "", nil) }
        let state = store.string(forKey: "state").flatMap { CallState(rawValue: $0) } ?? .idle
        return (state, store.string(forKey: "line") ?? "", store.string(forKey: "ask"))
    }

    /// When the state last changed, so a widget can show how old it is.
    static var updatedAt: Date? {
        guard let stamp = store?.double(forKey: "updated"), stamp > 0 else { return nil }
        return Date(timeIntervalSince1970: stamp)
    }
}
