import ActivityKit
import Foundation

/// The Live Activity: the call's state on the Lock Screen and Dynamic Island. Updated from the running app, never by push.
/// It can only START in the foreground or inside a Live Activity / audio recording intent; updates and the end work anywhere.
@MainActor final class LiveActivityController {
    private var chain: Task<Void, Never>?   // one update after another, so a late one never overwrites a newer one

    var isAllowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var isLive: Bool { !Activity<CallActivityAttributes>.activities.isEmpty }

    /// Returns nil when it started (or one is already up), else why not.
    @discardableResult func start(title: String) -> String? {
        guard isAllowed else { return "Live Activities are off for Call in Settings." }
        guard !isLive else { return nil }
        let state = CallActivityAttributes.ContentState(state: CallState.connecting.rawValue, line: "Connecting", askID: nil, askText: nil)
        do {
            _ = try Activity<CallActivityAttributes>.request(
                attributes: CallActivityAttributes(title: title),
                content: ActivityContent(state: state, staleDate: nil, relevanceScore: 0),
                pushType: nil)
            return nil
        } catch {
            return "The Live Activity did not start: \(error.localizedDescription)"
        }
    }

    /// `ask` non-nil shows the Approve / Deny buttons, so pass nil the moment it is answered.
    func update(state: CallState, line: String, ask: Ask?, alert: Bool = false) {
        var askID: String?
        var askText: String?
        switch ask {
        case .permission(let requestID, _, let forWhat, _)?:
            askID = requestID
            askText = String(forWhat.prefix(240))
        case .question(let requestID, _, let question, _)?:
            askID = requestID
            askText = String(question.question.prefix(240))
        case nil:
            break
        }
        let stateName = state.rawValue
        let shortLine = String(line.prefix(160))   // the whole activity must stay under 4 KB
        let id = askID
        let text = askText
        enqueue { await ActivityPush.update(state: stateName, line: shortLine, askID: id, askText: text, alert: alert) }
    }

    func end() {
        enqueue { await ActivityPush.endAll() }
    }

    /// At launch: an activity left over from a call that died with the app.
    func endStale() {
        end()
    }

    private func enqueue(_ work: @escaping @Sendable () async -> Void) {
        let previous = chain
        chain = Task {
            _ = await previous?.value
            await work()
        }
    }
}

/// The async ActivityKit calls, kept off the main actor: `Activity` is not Sendable, so it is fetched and used in one place.
enum ActivityPush {
    static func update(state: String, line: String, askID: String?, askText: String?, alert: Bool) async {
        let content = ActivityContent(
            state: CallActivityAttributes.ContentState(state: state, line: line, askID: askID, askText: askText),
            staleDate: nil, relevanceScore: alert ? 100 : 50)
        for activity in Activity<CallActivityAttributes>.activities {
            if alert {
                let body = askText ?? line
                await activity.update(content, alertConfiguration: AlertConfiguration(title: "Claude needs your answer", body: "\(body)", sound: .default))
            } else {
                await activity.update(content)
            }
        }
    }

    static func endAll() async {
        for activity in Activity<CallActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
