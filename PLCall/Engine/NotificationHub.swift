import UserNotifications

/// Local notifications for approvals: Approve first (the watch's Double Tap runs the first non-destructive action),
/// then Deny, then Reply with a short typed or dictated message. No push, no time-sensitive level.
/// Unchecked Sendable: it holds no state.
final class NotificationHub: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationHub()

    static let category = "ask.permission"
    static let approveID = "ask.approve"
    static let denyID = "ask.deny"
    static let replyID = "ask.reply"
    static let probePrefix = "probe."
    static let questionCategory = "ask.question"
    static let optionPrefix = "ask.opt."   // + the option's index

    private let lock = NSLock()
    private var questionActions: [UNNotificationAction] = []   // the last question's buttons, kept when the categories are set again

    /// Called from the app's init: the delegate and categories must exist before launch ends,
    /// and waking the model here sets the intent hooks even when no screen is ever shown.
    @MainActor func start() {
        register()
        _ = CallModel.shared
    }

    func register() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        setCategories()
    }

    private func setCategories() {
        let center = UNUserNotificationCenter.current()
        let approve = UNNotificationAction(identifier: Self.approveID, title: "Approve", options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: Self.denyID, title: "Deny", options: [.destructive])
        // A reply can approve ("yes, go ahead"), so it needs the same unlock as Approve.
        let reply = UNTextInputNotificationAction(identifier: Self.replyID, title: "Reply", options: [.authenticationRequired],
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "A short message")
        lock.lock()
        let options = questionActions
        lock.unlock()
        // A question's reply is not an answer to it: it goes to the session as a message.
        let say = UNTextInputNotificationAction(identifier: Self.replyID, title: "Reply", options: [],
                                                textInputButtonTitle: "Send", textInputPlaceholder: "Say something else")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [approve, deny, reply], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.questionCategory, actions: options + [say], intentIdentifiers: [], options: [])
        ])
    }

    func authorize() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { @Sendable granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func postPermission(requestID: String, toolUseID: String?, body: String, missed: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = missed ? "Missed call from Psyclaupse" : "Claude needs your answer"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.userInfo = ["requestId": requestID, "toolUseId": toolUseID ?? ""]
        post(content, identifier: "ask." + requestID)
    }

    /// A question with its options as buttons (up to four), so it can be answered from the Lock Screen or the watch.
    func postQuestion(requestID: String, body: String, options: [String], missed: Bool = false) {
        let buttons = options.prefix(4).enumerated().map { index, name in
            UNNotificationAction(identifier: Self.optionPrefix + String(index), title: String(name.prefix(40)), options: [])
        }
        lock.lock()
        questionActions = Array(buttons)
        lock.unlock()
        setCategories()
        let content = UNMutableNotificationContent()
        content.title = missed ? "Missed call from Psyclaupse" : "Claude has a question"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.questionCategory
        content.userInfo = ["requestId": requestID]
        post(content, identifier: "ask." + requestID)
    }

    func postProbe() {
        let content = UNMutableNotificationContent()
        content.title = "Probe"
        content.body = "Pull down, press Reply and send a word."
        content.sound = .default
        content.categoryIdentifier = Self.category
        post(content, identifier: Self.probePrefix + UUID().uuidString)
    }

    func clear(requestID: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["ask." + requestID])
    }

    private func post(_ content: UNMutableNotificationContent, identifier: String) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)   // nil = now
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        // The response is not Sendable: copy plain strings out before the task.
        let action = response.actionIdentifier
        let typed = (response as? UNTextInputNotificationResponse)?.userText
        let request = response.notification.request
        let identifier = request.identifier
        let requestID = request.content.userInfo["requestId"] as? String
        let toolUseID = request.content.userInfo["toolUseId"] as? String
        Task { @MainActor in
            await CallModel.shared.notificationAction(action, text: typed, identifier: identifier, requestID: requestID, toolUseID: toolUseID)
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        // With the app open the approve card is already on screen; only the probe's notice shows on top.
        let isProbe = notification.request.identifier.hasPrefix(Self.probePrefix)
        completionHandler(isProbe ? [.banner, .list, .sound] : [])
    }
}
