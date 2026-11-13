import AVFoundation
import CallKit

/// The call as the system sees it: an outgoing CallKit call keeps the mic alive behind the lock screen,
/// and a local incoming call is how "Claude rings you". No PushKit anywhere.
@MainActor final class CallKitManager: NSObject, CXProviderDelegate {
    var onStarted: (() -> Void)?           // the system accepted the outgoing call
    var onStartFailed: ((String) -> Void)? // the system refused it; the reason in its words
    var onAudioActive: (() -> Void)?       // start audio I/O now
    var onAudioInactive: (() -> Void)?     // stop audio I/O now
    var onEnded: (() -> Void)?             // ended from the app, the lock screen or a headset
    var onAnswered: (() -> Void)?          // he answered a ring
    var onDeclined: (() -> Void)?          // he declined a ring
    var onMuteToggled: (() -> Void)?       // the headset's press during a call arrives as mute
    var onHeld: ((Bool) -> Void)?          // another call put this one on hold (true) or let it go (false)

    private let observer = CXCallObserver()

    /// Another call (a real phone call, FaceTime) is up on this iPhone: a ring from Claude would cut into it.
    var otherCallActive: Bool {
        let mine = Set([callID, ringID].compactMap { $0 })
        return observer.calls.contains { !mine.contains($0.uuid) && !$0.hasEnded }
    }

    private static let caller = "Claude"

    private let provider: CXProvider
    private let controller = CXCallController()
    private var callID: UUID?
    private var ringID: UUID?
    private var outgoing = false

    override init() {
        let setup = CXProviderConfiguration()
        setup.supportsVideo = false
        setup.supportedHandleTypes = [.generic]
        setup.maximumCallGroups = 1
        setup.maximumCallsPerCallGroup = 1
        setup.includesCallsInRecents = true
        provider = CXProvider(configuration: setup)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    var hasCall: Bool { callID != nil }
    var isRinging: Bool { ringID != nil }

    /// Picks up the ring from inside the app (a nod), as the green button would.
    func answerRing() {
        guard let id = ringID else { return }
        controller.request(CXTransaction(action: CXAnswerCallAction(call: id))) { @Sendable _ in }
    }

    var isBusy: Bool { callID != nil || ringID != nil }   // a call up, or the phone ringing

    func startCall() {
        let id = UUID()
        callID = id
        outgoing = true
        let action = CXStartCallAction(call: id, handle: CXHandle(type: .generic, value: Self.caller))
        action.isVideo = false
        controller.request(CXTransaction(action: action)) { @Sendable error in
            guard let error else { return }
            let reason = error.localizedDescription
            Task { @MainActor in self.startRefused(id, reason) }
        }
    }

    /// Tell the system the line is up, so the call timer starts.
    func reportConnected() {
        guard outgoing, let callID else { return }
        provider.reportOutgoingCall(with: callID, connectedAt: nil)
    }

    /// False when there was no system call to end.
    @discardableResult func endCall() -> Bool {
        guard let id = callID ?? ringID else { return false }
        controller.request(CXTransaction(action: CXEndCallAction(call: id))) { @Sendable error in
            guard error != nil else { return }
            Task { @MainActor in self.forceEnd(id) }
        }
        return true
    }

    /// Rings the phone like a call. Returns nil when it rang, or the system's reason (a Focus or Do Not Disturb can refuse it).
    func ring(reason: String) async -> String? {
        guard callID == nil, ringID == nil else { return "A call is already up." }
        let id = UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: Self.caller)
        update.localizedCallerName = String(reason.prefix(60))
        update.hasVideo = false
        update.supportsHolding = true
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        ringID = id
        let refused: String? = await withCheckedContinuation { continuation in
            provider.reportNewIncomingCall(with: id, update: update) { @Sendable error in
                continuation.resume(returning: error?.localizedDescription)
            }
        }
        if refused != nil, ringID == id { ringID = nil }
        if refused == nil {
            // Like a real call: a ring nobody picks up stops after 30 seconds and becomes a missed call.
            // (On a locked iPhone the system screen has no Decline button, and two side presses do not always decline.)
            Task {
                try? await Task.sleep(for: .seconds(30))
                guard self.ringID == id else { return }
                self.provider.reportCall(with: id, endedAt: nil, reason: .unanswered)
                self.ended(id)
            }
        }
        return refused
    }

    private func startRefused(_ id: UUID, _ reason: String) {
        guard callID == id else { return }
        callID = nil
        onStartFailed?(reason)
    }

    private func forceEnd(_ id: UUID) {
        provider.reportCall(with: id, endedAt: nil, reason: .failed)   // the request failed: clear the system's call ourselves
        ended(id)
    }

    private func started(_ id: UUID) {
        guard id == callID else { return }
        provider.reportOutgoingCall(with: id, startedConnectingAt: nil)
        let update = CXCallUpdate()
        update.supportsHolding = true   // a real call can hold Claude and come back to it
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        provider.reportCall(with: id, updated: update)
        onStarted?()
    }

    private func answered(_ id: UUID) {
        guard id == ringID else { return }
        ringID = nil
        callID = id
        outgoing = false
        onAnswered?()
    }

    private func ended(_ id: UUID) {
        if id == callID {
            callID = nil
            onEnded?()
        } else if id == ringID {
            ringID = nil
            onDeclined?()
        }
    }

    private func reset() {
        let hadCall = callID != nil
        callID = nil
        ringID = nil
        if hadCall { onEnded?() }
    }

    // Delegate calls arrive on the main queue. Each one answers the system at once, copies what it needs, then hops to the main actor.

    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in self.reset() }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        try? AudioSessionManager.configure()   // category and mode only: the system activates the session itself
        let id = action.callUUID
        action.fulfill()
        Task { @MainActor in self.started(id) }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        try? AudioSessionManager.configure()
        let id = action.callUUID
        action.fulfill()
        Task { @MainActor in self.answered(id) }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let id = action.callUUID
        action.fulfill()
        Task { @MainActor in self.ended(id) }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        action.fulfill()
        Task { @MainActor in self.onMuteToggled?() }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        let held = action.isOnHold
        action.fulfill()
        Task { @MainActor in self.onHeld?(held) }
    }

    nonisolated func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Task { @MainActor in self.onAudioActive?() }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Task { @MainActor in self.onAudioInactive?() }
    }
}
