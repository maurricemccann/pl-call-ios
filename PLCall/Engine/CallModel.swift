import AppIntents
import AVFoundation
import Foundation
import Observation
import UIKit
import WidgetKit

struct SessionChoice: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

/// "I heard: ..., right?" waiting for his one tap (or his spoken yes / again). Shown when the ears were unsure of a word.
struct HeardCheck: Equatable {
    let text: String
    let alts: [String]
    let confidence: Double
}

struct Turn: Identifiable, Equatable {
    let id: UUID
    var who: Who
    var text: String
    var date: Date
    var image: String? = nil   // a picture Claude showed: its path on the line

    enum Who { case me, claude, system }
}

/// The call. One object drives the screen, the Live Activity, the widgets, the controls and the notifications.
/// The loop: listen, a pause ends his turn, send, speak the answer, listen again.
@MainActor @Observable final class CallModel {
    static let shared = CallModel()

    // MARK: state the screens read

    var state: CallState = .idle
    var statusLine = Say.load
    var turns: [Turn] = []
    var isInCall = false
    var handsFree = true
    var spokenCues = true                // the tone before Claude talks, "Listening" and "Got it"
    var musicMode = false                // no phone-style call: other audio keeps playing
    var workBeat = 0                     // one per session event while Claude works: the avatar's glow sweeps on each
    var workingSounds = true             // a soft tick on those events, so a long turn is not silence
    var isMuted = false                  // his mic is muted (the AirPods press in AUTO, or the screen)
    var stayReachable = true             // no call up: keep the line open in the background so Claude can ring
    var wakeWord = false                 // hands-free: only words after "Claude" are sent
    var speakProgress = true             // short lines Claude writes while it works are spoken too
    var shortAnswers = true              // a long answer is said as a few sentences (on-device model), the full text stays on screen
    var voices: [PLCallConfig.Voice] = []
    var voiceID = Speaker.phone {
        didSet { speaker.chosenVoice = voiceID }   // the cues follow the chosen voice
    }
    var quickReplies: [PLCallConfig.QuickReply] = []
    var armedReply: String?
    var pendingAsk: Ask?
    var hasConfig = false
    var configError: String?
    var micLevel: Double = 0
    var meterLevel: Double = 0           // the live mic meter: the level in any state of a call, not only while he is heard
    var heardCheck: HeardCheck?
    @ObservationIgnored private var heardTask: Task<Void, Never>?
    @ObservationIgnored private var nextAlt: (alts: [String], conf: Double?)?   // other readings that ride with the next message
    var isClaudeTyping = false
    var sessionTitle: String?
    var sessions: [SessionChoice] = []   // the live sessions on the PC, for the picker
    var chosenSession: String?           // nil = the newest live session
    var lastError: String?
    var restoring = true                 // the saved config is still being read back at launch
    let probe = ProbeModel()

    // MARK: the parts

    @ObservationIgnored fileprivate var line: LineClient?
    fileprivate let callKit = CallKitManager()
    fileprivate let activity = LiveActivityController()
    fileprivate let head = HeadMotion()
    private let store = ConfigStore()
    private let listener = SpeechListener()
    private let speaker = Speaker()
    private let remote = RemoteCommands()
    private let keepAlive = KeepAlive()
    @ObservationIgnored private var idleRingTask: Task<Void, Never>?
    @ObservationIgnored private var awakeTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var reachRetries = 0   // the gap between a ring and the background line
    @ObservationIgnored private var config: PLCallConfig?
    @ObservationIgnored private var reducer = EventReducer()
    @ObservationIgnored private var arm = QuickReplyArm()
    @ObservationIgnored private let imageCache = NSCache<NSString, UIImage>()
    @ObservationIgnored private var sid: String?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var lineGeneration = 0
    @ObservationIgnored private var lineRetry = 5.0
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var armed = false            // PUSH mode: one turn was asked for
    @ObservationIgnored private var awaitingReply = false    // something was sent and Claude's turn has not ended
    @ObservationIgnored private var heldReply: String?       // an answer that arrived while he was mid-sentence
    @ObservationIgnored private var ownsAudio = false        // the session was activated here, not by CallKit
    @ObservationIgnored private var earsRetried = false      // the ears are rebuilt once per call after a speech error
    @ObservationIgnored private var interimTask: Task<Void, Never>?
    @ObservationIgnored private var awakeUntil = Date.distantPast   // wake word mode: no name needed until then
    @ObservationIgnored private var lastSpoke = Date.distantPast    // when the voice last stopped
    @ObservationIgnored private var lastHearingPublish = Date.distantPast
    @ObservationIgnored private var onHold = false
    @ObservationIgnored private var connectedOnce = false    // the mic started at least once in this call
    @ObservationIgnored private var micRetries = 0           // a real call has Claude on hold
    @ObservationIgnored private var spokenAsk: String?       // the ask already read out, so it is not read again
    @ObservationIgnored private var lockLine = ""            // the last thing said by either side, for the Lock Screen
    @ObservationIgnored private var spokenParts: [String] = []   // progress lines already said and shown, so the turn end does not repeat them

    private enum Say {
        static let load = "Load your config"
        static let ready = "Line ready. Press to call"
        static let connecting = "Connecting"
        static let listening = "Listening"
        static let hearing = "Hearing"
        static let pressToTalk = "Press to talk"
        static let working = "Claude is working"
        static let speaking = "Speaking"
        static let waiting = "Waiting for your answer"
        static let noSession = "No live session. Start Claude Code on the PC first."
        static let keyRefused = "The call key was refused. Load your config again."
        static let title = "Claude"
    }

    private enum Keys {
        static let voice = "plcall.voice"
        static let handsFree = "plcall.handsFree"
        static let systemFont = "plcall.usesSystemFont"
        static let cues = "plcall.spokenCues"
        static let music = "plcall.musicMode"
        static let progress = "plcall.speakProgress"
        static let wake = "plcall.wakeWord"
        static let workTicks = "plcall.workingSounds"
        static let session = "plcall.session"
        static let reach = "plcall.stayReachable"
        static let idle = "plcall.idleRingMinutes"
        static let short = "plcall.shortAnswers"
        static let confirm = "plcall.confirmUnsure"
        static let confirmBelow = "plcall.confirmBelow"
    }

    private init() {
        handsFree = UserDefaults.standard.object(forKey: Keys.handsFree) as? Bool ?? true
        spokenCues = UserDefaults.standard.object(forKey: Keys.cues) as? Bool ?? true
        musicMode = UserDefaults.standard.bool(forKey: Keys.music)
        speakProgress = UserDefaults.standard.object(forKey: Keys.progress) as? Bool ?? true
        wakeWord = UserDefaults.standard.bool(forKey: Keys.wake)
        workingSounds = UserDefaults.standard.object(forKey: Keys.workTicks) as? Bool ?? true
        stayReachable = UserDefaults.standard.object(forKey: Keys.reach) as? Bool ?? true
        chosenSession = UserDefaults.standard.string(forKey: Keys.session)
        shortAnswers = UserDefaults.standard.object(forKey: Keys.short) as? Bool ?? false   // off: he hears everything (his report 11-12)
        wire()
        let center = NotificationCenter.default
        _ = center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in CallModel.shared.stayReachableIfWanted() }
        }
        _ = center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in CallModel.shared.cameToFront() }
        }
        activity.endStale()
        loading = Task { await self.restore() }
        Task {
            for await event in self.listener.events { self.heard(event) }
        }
    }

    // MARK: config

    func loadConfig(from url: URL) async {
        do {
            let loaded = try await store.load(from: url)
            dropLine()
            apply(loaded)
        } catch let problem as PLCallConfig.Problem {
            configError = problem.description
        } catch let failure as Keychain.Failure {
            configError = "The config was read, but this iPhone would not store it (Keychain error \(failure.status))."
        } catch {
            configError = "That file could not be read."
        }
    }

    func forgetConfig() {
        if isInCall { endCall() }
        dropLine()
        config = nil
        line = nil
        hasConfig = false
        voices = []
        quickReplies = []
        sessionTitle = nil
        isClaudeTyping = false
        awaitingReply = false
        if let ask = pendingAsk { resolve(ask) }
        UserDefaults.standard.removeObject(forKey: Keys.systemFont)
        let store = self.store
        Task { await store.forget() }
        set(.idle, Say.load)
    }

    private func restore() async {
        if let saved = await store.saved() { apply(saved) }
        restoring = false
    }

    private func apply(_ config: PLCallConfig) {
        self.config = config
        line = LineClient(config: config)
        voices = [PLCallConfig.Voice(id: Speaker.phone, label: "iPhone"), PLCallConfig.Voice(id: Speaker.personal, label: "My Personal Voice")]
        quickReplies = Self.builtInReplies + config.quickReplyList.filter { r in !Self.builtInReplies.contains { $0.label == r.label } }
        if let saved = UserDefaults.standard.string(forKey: Keys.voice), voices.contains(where: { $0.id == saved }) {
            voiceID = saved
        } else {
            voiceID = Speaker.phone
        }
        UserDefaults.standard.set(config.usesSystemFont, forKey: Keys.systemFont)
        let base = ["Claude", "Psyclaupse", "Claude Code"] + (config.words ?? [])
        let listener = self.listener
        Task { await listener.setWords(Vocabulary.merged(base, Vocabulary.cached(), Vocabulary.bundled())) }
        refreshVocabulary(base)
        hasConfig = true
        configError = nil
        lastError = nil
        set(.idle, Say.ready)
        connect()
    }

    private func dropLine() {
        lineGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        sid = nil
        reducer = EventReducer()
    }

    private func refuseKey() {
        configError = Say.keyRefused
        hasConfig = false
        dropLine()
        if isInCall { endCall() }
        set(.idle, Say.load)
    }

    // MARK: the call

    func startCall() {
        guard hasConfig, !isInCall else { return }
        Task { _ = try? await IntentDonationManager.shared.donate(intent: StartCallIntent()) }   // Siri learns when he calls
        keepAlive.stop()
        idleRingTask?.cancel()
        isInCall = true
        lastError = nil
        activity.start(title: Say.title)   // in the same step as the mic: a call started from a control stops recording without it
        set(.connecting, Say.connecting)
        // A first-time prompt cannot show from the background (a control on the lock screen): the call would wait on it.
        if AVAudioApplication.shared.recordPermission == .undetermined, UIApplication.shared.applicationState != .active {
            finishCall("Open Call once to allow the microphone.")
            return
        }
        Task {
            guard await AudioSessionManager.micAllowed() else {
                self.finishCall("Allow the microphone for Call in Settings.")
                return
            }
            guard self.isInCall else { return }
            if self.musicMode { self.startInMusicMode() } else { self.callKit.startCall() }
            _ = await NotificationHub.shared.authorize()   // after the call is up, so a pending prompt never holds the call back
        }
    }

    /// A control can launch the process cold, before the saved config is read back. The Live Activity must still start
    /// inside the intent's own step, so it starts first and the call follows once the config is in.
    private func startFromIntent() {
        guard !hasConfig else {
            startCall()
            return
        }
        activity.start(title: Say.title)
        Task {
            _ = await self.loading?.value
            if self.hasConfig { self.startCall() } else { self.activity.end() }
        }
    }

    func endCall() {
        guard isInCall else { return }
        if !callKit.endCall() { finishCall() }
    }

    /// PUSH mode, the headset press and the Talk button: stop the voice and take one turn.
    func talk() {
        heardFromHim()
        if isInCall, state == .lost, micRetries > 8 {
            micRetries = 0
            audioActivated()
            return
        }
        if callKit.isRinging {
            callKit.answerRing()
            return
        }
        guard isInCall else {
            startCall()
            return
        }
        if !handsFree, armed, state == .hearing {
            // a second press while he is mid-sentence ends the turn now: in a loud place the pause rule can hold it open for seconds
            let listener = self.listener
            Task { await listener.endNow() }
            return
        }
        speaker.stop()
        armed = true
        updateGate()
        let listener = self.listener
        Task {
            await listener.discard()
            guard self.pendingAsk == nil, self.isInCall else { return }
            let fresh = self.state != .listening
            self.set(.listening, Say.listening)
            if fresh, self.spokenCues { self.speaker.cue("Listening") }
        }
    }

    func replay() {
        if callKit.isRinging {
            _ = callKit.endCall()
            return
        }
        let last = reducer.lastSaid
        guard !last.isEmpty else {
            statusLine = "Nothing to replay yet."
            return
        }
        voice(last)
    }

    /// Chips the app owns (they need the PC's answer, not a message): the config's own chips follow them.
    static let builtInReplies = [PLCallConfig.QuickReply(label: "STATUS", send: "@status", arm: nil),
                                 PLCallConfig.QuickReply(label: "WHAT'S LEFT", send: "@left", arm: nil)]

    /// STATUS: the PC answers at once from real state (so it works while the session is busy), and the session is asked too.
    func askStatus() {
        guard hasConfig else { return }
        speaker.stop()
        append(.me, "Status?")
        tellFromPC("status")
        deliver("Status check from the phone. In two short sentences: what are you doing right now, and what comes next?")
    }

    /// WHAT'S LEFT: the open items of the queue, from the PC.
    func askWhatsLeft() {
        guard hasConfig else { return }
        speaker.stop()
        append(.me, "What's left?")
        tellFromPC("left")
    }

    private func tellFromPC(_ kind: String) {
        guard let line else { return }
        Task {
            do {
                let text = try await line.status(kind)
                self.append(.claude, text)
                self.lockLine = "Claude: " + text
                if self.isInCall, !self.onHold { self.voice(text, tone: self.spokenCues) }
            } catch {
                self.note("Could not get that from the PC: \(plainSentence(error))")
            }
        }
    }

    /// One tap: Claude stops talking now (the voice and anything queued behind it). Does not stop his work.
    func stopTalking() {
        guard isInCall else { return }
        interimTask?.cancel()
        speaker.stop()
        heldReply = nil
        lastSpoke = Date()
        rest()
    }

    /// A picture Claude showed on the call, fetched once and kept.
    func loadImage(_ path: String) async -> UIImage? {
        if let kept = imageCache.object(forKey: path as NSString) { return kept }
        guard let line, let data = try? await line.image(path: path), let image = UIImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: path as NSString)
        return image
    }

    func tapQuickReply(_ r: PLCallConfig.QuickReply) {
        if r.send == "@status" { askStatus(); return }
        if r.send == "@left" { askWhatsLeft(); return }
        switch arm.tap(r, now: Date().timeIntervalSinceReferenceDate) {
        case .send(let text):
            armedReply = nil
            send(text: text)
        case .armed(let label):
            armedReply = label
            Task {
                try? await Task.sleep(for: .seconds(QuickReplyArm.window))
                if self.armedReply == label { self.armedReply = nil }
            }
        }
    }

    /// A picture or a screenshot: it goes to the PC's inbox, then the session is told where it is so Claude can look.
    func sendPicture(_ image: UIImage, note: String? = nil) {
        guard let line, hasConfig else { return }
        let scaled = Self.shrink(image, longest: 2048)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else { return }
        append(.system, "Sending a picture")
        Task {
            do {
                let path = try await line.upload(jpeg: jpeg)
                let words = (note?.isEmpty == false ? note! + " " : "") + "I sent you a picture. It is at \(path). Open it and look."
                self.append(.me, words)
                self.deliver(words)   // never an answer to a waiting question or permission
            } catch {
                self.note("The picture did not send: \(plainSentence(error))")
            }
        }
    }

    private static func shrink(_ image: UIImage, longest: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, longest / max(size.width, size.height))
        guard scale < 1 else { return image }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }

    /// Typed text and quick replies go down the same road as his voice.
    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, hasConfig else { return }
        speaker.stop()
        took(trimmed)
    }

    func answerPermission(allow: Bool, message: String?) {
        probe.sawIntent()
        guard let ask = pendingAsk, case .permission(let requestID, let toolUseID, _, _) = ask else { return }
        resolve(ask)
        note(allow ? "Allowed." : "Denied.")
        guard let line, let sid else {
            note(Say.noSession)
            rest()
            return
        }
        sentSomething()
        Task {
            do {
                try await line.permission(sid: sid, requestID: requestID, toolUseID: toolUseID, allow: allow, message: message)
            } catch {
                self.sendFailed(error)
            }
        }
    }

    func answerQuestion(option: Int) {
        guard let ask = pendingAsk, case .question(let requestID, let toolUseID, let question, let input) = ask,
              question.options.indices.contains(option) else { return }
        resolve(ask)
        note("Answered: \(question.options[option])")
        guard let line, let sid else {
            note(Say.noSession)
            rest()
            return
        }
        sentSomething()
        Task {
            do {
                try await line.dialog(sid: sid, requestID: requestID, toolUseID: toolUseID, question: question, option: option, input: input)
            } catch {
                self.sendFailed(error)
            }
        }
    }

    func selectVoice(_ id: String) {
        guard voices.contains(where: { $0.id == id }) else { return }
        if id == Speaker.personal, Speaker.personalVoice() == nil {
            Task {
                if await Speaker.allowPersonalVoice(), Speaker.personalVoice() != nil {
                    self.voiceID = id
                    UserDefaults.standard.set(id, forKey: Keys.voice)
                } else {
                    self.lastError = "Personal Voice is not allowed or not set up. Settings > Accessibility > Personal Voice, then allow Psyclaupse."
                }
            }
            return
        }
        voiceID = id
        UserDefaults.standard.set(id, forKey: Keys.voice)
    }

    func previewVoice(_ id: String) {
        voice("This is the voice I will use on the call.", voiceID: id)
    }

    func setHandsFree(_ on: Bool) {
        handsFree = on
        UserDefaults.standard.set(on, forKey: Keys.handsFree)
        armed = false
        updateGate()
        if isInCall, !speaker.isSpeaking, state != .hearing { rest() }
        publish()   // the Lock Screen shows or hides its Talk button
    }

    /// A button on the watch app. It can only steer a call that is already up: the mic cannot start from the background.
    func watchCommand(_ command: String, text: String?) {
        switch command {
        case "approve": answerPermission(allow: true, message: text)
        case "deny": answerPermission(allow: false, message: text)
        case "replay": replay()
        case "talk": if isInCall { talk() }
        case "end": endCall()
        case "state": publish()
        default: break
        }
    }

    /// The AirPods press, as the system's mute. In AUTO it mutes; in PUSH it is push-to-talk: the system's mute is
    /// undone at once (so the mic stays live) and the press takes a turn (his ask 11-12: push to talk from the AirPods).
    private func systemMuteChanged(_ muted: Bool) {
        guard isInCall else { return }
        if handsFree {
            setMuted(muted, fromSystem: true)
            return
        }
        if muted { try? AVAudioApplication.shared.setInputMuted(false) }
        if Date().timeIntervalSince(lastPushPress) > 0.6 {   // the CallKit mute action and this notice can both arrive for one press
            lastPushPress = Date()
            talk()
        }
    }

    @ObservationIgnored private var lastPushPress = Date.distantPast

    /// Mutes his mic like a phone call: nothing he says is sent, and if he talks while muted the call tells him once.
    func setMuted(_ on: Bool, fromSystem: Bool = false) {
        guard isInCall, on != isMuted else { return }
        isMuted = on
        if !fromSystem { try? AVAudioApplication.shared.setInputMuted(on) }
        listener.setMuted(on) {
            Task { @MainActor in CallModel.shared.spokeWhileMuted() }
        }
        updateGate()
        if on {
            speaker.cue("Muted")
            set(.idle, "Muted. Press again to unmute")
        } else {
            speaker.cue("Unmuted")
            rest()
        }
    }

    @ObservationIgnored private var lastMutedWarning = Date.distantPast
    @ObservationIgnored private var lastTick = Date.distantPast
    @ObservationIgnored private var lastFromHim = Date()          // his last words, tap or press in this call
    @ObservationIgnored private var idleWatch: Task<Void, Never>?
    @ObservationIgnored private var warnedIdle = false

    /// Hangs up after about 50 minutes with nothing from him (asleep), with a spoken warning a minute before.
    private func watchForSleep() {
        idleWatch?.cancel()
        lastFromHim = Date()
        warnedIdle = false
        idleWatch = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, self.isInCall else { return }
                let quiet = Date().timeIntervalSince(self.lastFromHim)
                if quiet >= 50 * 60 {
                    RingLog.note("call ended after 50 minutes with nothing from him")
                    self.endCall()
                    return
                }
                if quiet >= 49 * 60, !self.warnedIdle {
                    self.warnedIdle = true
                    self.speaker.cue("Still there? I'll hang up in a minute.")
                }
            }
        }
    }

    private func heardFromHim() {
        lastFromHim = Date()
        warnedIdle = false
    }

    func setWorkingSounds(_ on: Bool) {
        workingSounds = on
        UserDefaults.standard.set(on, forKey: Keys.workTicks)
    }

    private func spokeWhileMuted() {
        guard isMuted, Date().timeIntervalSince(lastMutedWarning) > 10 else { return }
        lastMutedWarning = Date()
        speaker.cue("You're muted")
    }

    func setSpokenCues(_ on: Bool) {
        spokenCues = on
        UserDefaults.standard.set(on, forKey: Keys.cues)
    }

    /// Asks the PC for the live sessions again (the picker's pull to refresh).
    func refreshSessions() async {
        guard let line else { return }
        if let live = try? await line.sessions() {
            sessions = live.map { SessionChoice(id: $0.id, title: $0.title ?? $0.id) }
        }
    }

    /// nil = always the newest. Switching drops the line and connects to the new one; a call in progress keeps going on it.
    func chooseSession(_ id: String?) {
        guard id != chosenSession else { return }
        chosenSession = id
        UserDefaults.standard.set(id, forKey: Keys.session)
        if let ask = pendingAsk { resolve(ask) }
        awaitingReply = false
        isClaudeTyping = false
        dropLine()
        connect()
        if isInCall, spokenCues { speaker.cue("Switched session") }
    }

    func setStayReachable(_ on: Bool) {
        stayReachable = on
        UserDefaults.standard.set(on, forKey: Keys.reach)
        if !on { keepAlive.stop() }
    }

    /// Minutes after Claude's turn ends before the phone rings, when no call is up and he has not answered. 0 = never.
    private var idleRingMinutes: Int { UserDefaults.standard.object(forKey: Keys.idle) as? Int ?? 10 }

    /// In the background with no call: hold the line open so an ask or a waiting session can ring the phone.
    fileprivate func stayReachableIfWanted() {
        guard stayReachable, hasConfig, !isInCall, !callKit.isBusy, UIApplication.shared.applicationState != .active else {
            if isInCall || UIApplication.shared.applicationState == .active { letGoOfAwake() }
            return
        }
        keepAlive.start()
        if keepAlive.isOn {
            if reachRetries > 0 { RingLog.note("background line on (after \(reachRetries) retries)") }
            reachRetries = 0
            letGoOfAwake()
            return
        }
        // his Ring log 11-12 9:04 PM: "background line FAILED to start" with nothing after it. Another app can hold the
        // audio for a moment (a call, a recording, Siri); try again every 3 s for about 30 s, inside held background time.
        RingLog.note("background line FAILED to start: \(keepAlive.lastError)")
        guard reachRetries < 10 else { return }
        reachRetries += 1
        holdAwake("background line retry")
        Task {
            try? await Task.sleep(for: .seconds(3))
            self.stayReachableIfWanted()
        }
    }

    /// A real call put Claude on hold: stop talking and listening. Coming back, the audio returns through CallKit.
    private func heldByOtherCall(_ held: Bool) {
        guard isInCall else { return }
        RingLog.note(held ? "on hold for another call" : "back from the other call")
        if held {
            onHold = true
            speaker.stop()
            listener.setAccepting(false)
            set(.lost, "On hold for another call")
            return
        }
        onHold = false
        spokenAsk = nil   // back from the other call: a waiting question is read again
        if heldReply == nil, pendingAsk == nil, !reducer.lastSaid.isEmpty, spokenCues { speaker.cue("Welcome back") }
        // CallKit gives the audio back and the call picks up from there; if it has not after a second, pick up anyway
        Task {
            try? await Task.sleep(for: .seconds(1))
            if self.isInCall, !self.onHold, self.state == .lost { self.audioActivated() }
        }
    }

    /// Asks iOS for up to about 30 seconds of running time while the background line is down, so the app is not
    /// suspended between a ring (or a call) ending and the line coming back.
    private func holdAwake(_ why: String) {
        guard awakeTask == .invalid else { return }
        awakeTask = UIApplication.shared.beginBackgroundTask(withName: why) { [weak self] in
            Task { @MainActor in
                RingLog.note("background time ran out before the line came back")
                self?.letGoOfAwake()
            }
        }
    }

    private func letGoOfAwake() {
        guard awakeTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(awakeTask)
        awakeTask = .invalid
    }

    /// Rings the phone. The silent background line lets go of the audio first, so the call can take it cleanly.
    /// While he is on another call it does not ring: the notification waits instead.
    private func ringNow(_ reason: String) async -> String? {
        if callKit.otherCallActive {
            RingLog.note("no ring: another call is up")
            return nil
        }
        if !CallFocusFilter.ringsAllowed {
            RingLog.note("no ring: a Focus filter says notifications only")
            return nil
        }
        holdAwake("ring")   // until the background line is back after the ring, or a call takes over
        head.start()   // two nods answer the ring, two shakes decline it
        remote.enable()   // the AirPods stem: one press answers, two decline
        keepAlive.stop()
        AudioSessionManager.deactivate()
        let refused = await callKit.ring(reason: reason)
        RingLog.note(refused.map { "ring refused: \($0)" } ?? "rang: \(reason)")
        if refused != nil {
            if !isInCall { remote.disable() }
            if !(pendingAsk.map { if case .permission = $0 { return true } else { return false } } ?? false) { head.stop() }
            stayReachableIfWanted()
        }
        return refused
    }

    /// After a ring: the system has just released the audio, so wait a moment, then hold the line again.
    private func backToReachable() {
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            self.stayReachableIfWanted()
        }
    }

    fileprivate func cameToFront() {
        keepAlive.stop()
        idleRingTask?.cancel()   // he is looking at it
    }

    /// The session moved while no call is up. A turn that ended starts the wait for the "Claude is waiting" ring;
    /// anything newer starts it again, so a session he is driving at the PC never rings.
    private func sessionMoved(turnEnded: Bool) {
        idleRingTask?.cancel()
        let minutes = idleRingMinutes
        guard turnEnded, minutes > 0 else { return }
        idleRingTask = Task {
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard !Task.isCancelled, !self.isInCall, self.pendingAsk == nil, self.hasConfig,
                  UIApplication.shared.applicationState != .active else { return }
            if let refused = await self.ringNow("Psyclaupse is waiting") {
                self.lastError = "The ring was refused: \(refused)"
            }
        }
    }

    func setWakeWord(_ on: Bool) {
        wakeWord = on
        UserDefaults.standard.set(on, forKey: Keys.wake)
    }

    func setSpeakProgress(_ on: Bool) {
        speakProgress = on
        UserDefaults.standard.set(on, forKey: Keys.progress)
    }

    func setShortAnswers(_ on: Bool) {
        shortAnswers = on
        UserDefaults.standard.set(on, forKey: Keys.short)
    }

    /// Takes effect at the next call.
    func setMusicMode(_ on: Bool) {
        musicMode = on
        UserDefaults.standard.set(on, forKey: Keys.music)
    }

    // MARK: called by the other engine parts

    /// A notification action. It may arrive in a process the system just launched in the background, so it waits for the config.
    @ObservationIgnored var sessionFromNotice: String?   // set by the notification handler before an answer is sent

    func notificationAction(_ action: String, text: String?, identifier: String, requestID: String?, toolUseID: String?) async {
        if identifier.hasPrefix(NotificationHub.probePrefix) {
            probe.sawNotification(action: action, text: text)
            return
        }
        if action.hasPrefix(NotificationHub.optionPrefix) || (action == NotificationHub.replyID && isQuestion(requestID)) {
            _ = await loading?.value
            guard let ask = pendingAsk, case .question(let waiting, _, _, _) = ask, waiting == requestID else { return }
            if let index = Int(action.dropFirst(NotificationHub.optionPrefix.count)), action.hasPrefix(NotificationHub.optionPrefix) {
                answerQuestion(option: index)
            } else if let words = text?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty {
                resolve(ask)
                append(.me, words)
                deliver(words)
            }
            return
        }
        let allow: Bool
        switch action {
        case NotificationHub.approveID: allow = true
        case NotificationHub.denyID: allow = false
        case NotificationHub.replyID: allow = SpokenAnswer.decision(text ?? "") ?? false   // a reply that is not a clear yes denies, with his words
        default: return                                                                     // a plain tap only opens the app
        }
        _ = await loading?.value
        guard let requestID, !requestID.isEmpty, let line else { return }
        if let ask = pendingAsk, case .permission(let waiting, _, _, _) = ask, waiting == requestID {
            resolve(ask)
            note(allow ? "Allowed." : "Denied.")
        } else if reducer.lastSeq > 0 {
            // the app was running and this request is no longer waiting: it was answered already (by voice, the watch, the PC)
            RingLog.note("a notice answer for a request that is no longer waiting was not sent")
            return
        }
        do {
            if sid == nil {
                let live = try await line.sessions()
                sid = (live.first { $0.id == sessionFromNotice } ?? live.first { $0.id == chosenSession } ?? live.first)?.id
            }
            guard let sid else { return }
            sentSomething()
            let tool = (toolUseID?.isEmpty ?? true) ? nil : toolUseID
            try await line.permission(sid: sid, requestID: requestID, toolUseID: tool, allow: allow, message: text)
        } catch {
            sendFailed(error)
        }
    }

    /// A permission keeps the head reader on after the ring: a nod then answers it.
    private var pendingIsPermission: Bool {
        if case .permission? = pendingAsk { return true }
        return false
    }

    private func isQuestion(_ requestID: String?) -> Bool {
        guard let requestID, let ask = pendingAsk, case .question(let waiting, _, _, _) = ask else { return false }
        return waiting == requestID
    }

    /// A ring that was declined or not picked up leaves a "Missed call" notice with the ask's buttons, like a real missed call.
    private func noteMissedRing() {
        switch pendingAsk {
        case .permission(let requestID, let toolUseID, let forWhat, _)?:
            NotificationHub.shared.postPermission(requestID: requestID, toolUseID: toolUseID, body: forWhat, missed: true, sid: sid)
        case .question(let requestID, _, let question, _)?:
            NotificationHub.shared.postQuestion(requestID: requestID, body: question.question, options: question.options, missed: true)
        case nil:
            break
        }
    }

    /// A nod approves and a shake denies, only while a permission waits.
    func headGesture(_ gesture: HeadGesture) {
        if callKit.isRinging, !probe.isRingProbe {
            if gesture == .nod { callKit.answerRing() } else { _ = callKit.endCall() }
            return
        }
        if probe.sawHead(gesture) { return }
        guard let ask = pendingAsk, case .permission = ask else { return }
        answerPermission(allow: gesture == .nod, message: nil)
    }

    // MARK: wiring

    private func wire() {
        speaker.engineVoice = listener.voice   // one audio engine for the mic, the voice and the tones (his pick)
        speaker.onFinished = { [weak self] in self?.spokeDone() }
        speaker.onFailed = { [weak self] message in self?.voiceFailed(message) }
        callKit.onStarted = { [weak self] in self?.remote.enable() }
        callKit.onStartFailed = { [weak self] reason in self?.startWithoutCallKit(reason) }
        callKit.onAudioActive = { [weak self] in self?.audioActivated() }
        callKit.onAudioInactive = { [weak self] in self?.audioDeactivated() }
        callKit.onEnded = { [weak self] in self?.finishCall() }
        callKit.onAnswered = { [weak self] in self?.ringAnswered() }
        callKit.onDeclined = { [weak self] in
            guard let self else { return }
            RingLog.note("ring ended without an answer")
            if !self.isInCall {
                self.remote.disable()
                self.head.stop()
            }
            if !self.probe.sawRing(answered: false) { self.noteMissedRing() }
            if !self.isInCall { self.head.stop() }
            self.backToReachable()
        }
        // the AirPods press arrives as mute: in PUSH it takes a turn, in AUTO it mutes and unmutes like a phone call
        callKit.onMuteToggled = { [weak self] in
            guard let self else { return }
            if self.handsFree {
                self.setMuted(!self.isMuted)
            } else if Date().timeIntervalSince(self.lastPushPress) > 0.6 {
                self.lastPushPress = Date()
                self.talk()
            }
        }
        _ = NotificationCenter.default.addObserver(forName: AVAudioApplication.inputMuteStateChangeNotification, object: nil, queue: .main) { note in
            let muted = (note.userInfo?[AVAudioApplication.muteStateKey] as? NSNumber)?.boolValue ?? false
            Task { @MainActor in CallModel.shared.systemMuteChanged(muted) }
        }
        callKit.onHeld = { [weak self] held in self?.heldByOtherCall(held) }
        IntentBridge.approve = { [weak self] message in self?.answerPermission(allow: true, message: message) }
        IntentBridge.deny = { [weak self] message in self?.answerPermission(allow: false, message: message) }
        IntentBridge.endCall = { [weak self] in
            self?.probe.sawIntent()
            self?.endCall()
        }
        IntentBridge.startCall = { [weak self] in
            self?.probe.sawIntent()
            self?.startFromIntent()
        }
        IntentBridge.replay = { [weak self] in
            self?.probe.sawIntent()
            self?.replay()
        }
        IntentBridge.talk = { [weak self] in
            self?.probe.sawIntent()
            self?.talk()
        }
        NotificationHub.shared.register()
        WatchLink.shared.start()
        AudioSessionManager.observe { change in
            Task { @MainActor in CallModel.shared.audioChanged(change) }
        }
    }

    // MARK: the line

    private func connect() {
        guard let line, hasConfig, streamTask == nil else { return }
        let generation = lineGeneration
        streamTask = Task { await self.runLine(line, generation: generation) }
    }

    private func runLine(_ line: LineClient, generation: Int) async {
        do {
            let live = try await line.sessions()
            sessions = live.map { SessionChoice(id: $0.id, title: $0.title ?? $0.id) }
            // the chosen session when it is live, else the newest; a chosen one that ended falls back without forgetting the choice
            guard let session = live.first(where: { $0.id == chosenSession }) ?? live.first else { throw LineClient.Failure.noSession }
            let backlog = try await line.events(sid: session.id, limit: 60)
            guard generation == lineGeneration else { return }
            if sid == session.id, reducer.lastSeq > 0 {
                // the same session after a drop: take what was missed (a turn end, a permission) instead of skipping it
                for event in backlog where event.sequenceNum > reducer.lastSeq { took(event) }
            } else {
                reducer.prime(backlog)
                if pendingAsk == nil, let waiting = EventReducer.waitingAsk(backlog) {
                    sid = session.id
                    raise(waiting)   // the PC is blocked on it: ring or post it now
                }
            }
            sid = session.id
            lineRetry = 5
            sessionTitle = session.title ?? session.id
            lineIsUp(true)
            let stream = line.stream(sid: session.id, fromSeq: reducer.lastSeq) { up in
                Task { @MainActor in CallModel.shared.lineIsUp(up, generation: generation) }
            }
            for try await event in stream {
                guard generation == lineGeneration else { return }
                took(event)
            }
        } catch {
            guard generation == lineGeneration else { return }
            lineFailed(error)
        }
        guard generation == lineGeneration else { return }
        streamTask = nil
        // then look for the session again: every 5 s in a call, backing off to 2 minutes with no call (the PC may be asleep)
        let wait = isInCall ? 5.0 : lineRetry
        lineRetry = min(lineRetry * 2, 120)
        try? await Task.sleep(for: .seconds(wait))
        guard generation == lineGeneration else { return }
        connect()
    }

    private func lineIsUp(_ up: Bool, generation: Int? = nil) {
        if let generation, generation != lineGeneration { return }
        if up {
            lastError = nil
            if state == .lost { rest() }
        } else if isInCall {
            if state != .lost, spokenCues { speaker.cue("Line dropped") }
            set(.lost, "The line dropped. Reconnecting")
        } else {
            lastError = "The PC is not answering. Check that Tailscale is on."
        }
    }

    private func lineFailed(_ error: any Error) {
        RingLog.note("line to the PC failed: \(plainSentence(error))")
        if let failure = error as? LineClient.Failure, failure == .unauthorized {
            refuseKey()
            return
        }
        let message = plainSentence(error)
        lastError = message
        if isInCall { set(.lost, message) }
    }

    private func took(_ event: SessionEvent) {
        let before = reducer.lastSeq
        let outputs = reducer.ingest(event)
        guard reducer.lastSeq != before else { return }
        if event.type == "permission_answered" { clearedAsk(event); return }
        if event.type == "announce" { announced(event.text); return }
        if let picture = event.image, event.role == "assistant" { append(.claude, "", image: picture) }   // the words follow the usual road
        if !isInCall { sessionMoved(turnEnded: event.type == "result" || event.isTurnEnd == true) }
        if isInCall, awaitingReply, pendingAsk == nil, event.type != "result", event.isTurnEnd != true {
            workBeat += 1
            if workingSounds, !speaker.isSpeaking, state != .hearing, Date().timeIntervalSince(lastTick) > 3 {
                lastTick = Date()
                speaker.tick()
            }
        }
        let moved = event.type == "result" || event.isTurnEnd == true || event.role == "user"
            || (event.role == "assistant" && !(event.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if outputs.isEmpty, let ask = pendingAsk, moved, event.type != "control_request", event.isBlockingControl != true {
            // The session moved on: the ask was answered on the PC or another screen.
            resolve(ask)
            rest()
        }
        if outputs.isEmpty, speakProgress, isInCall, awaitingReply, event.role == "assistant",
           let words = event.text?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty {
            // A line written while the work goes on. The last line of a turn is followed at once by the turn end,
            // so only a line still standing after 2.5 seconds is progress.
            interimTask?.cancel()
            interimTask = Task {
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled, self.isInCall, self.awaitingReply, self.pendingAsk == nil,
                      !self.speaker.isSpeaking, self.state != .hearing else { return }
                self.spokenParts.append(words)
                self.append(.claude, words)
                self.lockLine = "Claude: " + SpokenText.make(words).sentences.joined(separator: " ")
                self.set(.speaking, Say.speaking)
                self.speaker.speak(words, voiceID: self.voiceID, line: self.line)
            }
        }
        for output in outputs {
            switch output {
            case .transcript(let text):
                let rest = notYetSaid(text)
                if !rest.isEmpty { append(.claude, rest) }
            case .speak(let text):
                interimTask?.cancel()
                awaitingReply = false
                isClaudeTyping = false
                let rest = notYetSaid(text)
                spokenParts = []
                if rest.isEmpty {
                    if !speaker.isSpeaking { self.rest() }   // all of it was already said as progress lines
                    continue
                }
                if state == .hearing { heldReply = rest } else { say(rest) }   // never talk over him mid-sentence
            case .ask(let ask):
                awaitingReply = false
                isClaudeTyping = false
                raise(ask)
            }
        }
    }

    /// The PC says an approval card is settled: answered in the terminal or elsewhere, or the session moved on, or it timed out.
    private func clearedAsk(_ event: SessionEvent) {
        guard let ask = pendingAsk, Self.id(of: ask) == event.requestId else { return }
        resolve(ask)
        note(event.expired == true ? "That approval was cleared: the session moved on." : "Answered on another screen.")
        rest()
    }

    /// A build landed on the feed: shown always, said when the call is quiet, a notification when the app is not in front.
    private func announced(_ text: String?) {
        guard let words = text?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else { return }
        note(words)
        if isInCall {
            if !onHold, !speaker.isSpeaking, state != .hearing, pendingAsk == nil, !awaitingReply { voice(words, tone: spokenCues) }
        } else if UIApplication.shared.applicationState != .active {
            NotificationHub.shared.postNote(title: "A new build", body: words)
        }
    }

    /// His words, spoken or typed: an answer when something is waiting, else a message to the session.
    private func took(_ text: String) {
        heardFromHim()
        armed = false
        lockLine = "You: " + text
        append(.me, text)
        if let ask = pendingAsk { answer(text, to: ask) } else { deliver(text) }
    }

    private func deliver(_ text: String) {
        guard let line, let sid else {
            note(Say.noSession)
            rest()
            return
        }
        sentSomething()
        let extra = nextAlt
        nextAlt = nil
        Task {
            do {
                try await line.send(sid: sid, text: text, alt: extra?.alts ?? [], conf: extra?.conf)
            } catch {
                self.sendFailed(error)
            }
        }
    }

    private func sentSomething() {
        reducer.sent()
        awaitingReply = true
        isClaudeTyping = true
        rest()
    }

    private func sendFailed(_ error: any Error) {
        awaitingReply = false
        isClaudeTyping = false
        if let failure = error as? LineClient.Failure, failure == .unauthorized {
            refuseKey()
            return
        }
        let message = "Could not send: " + plainSentence(error)
        note(message)
        lastError = message
        rest()
    }

    // MARK: asks

    private func raise(_ ask: Ask) {
        RingLog.note("ask arrived (in call: \(isInCall), line kept open: \(keepAlive.isOn))")
        if let earlier = pendingAsk, earlier != ask {
            // a second ask replaces the first: the first one's notification must not stay answerable
            switch earlier {
            case .permission(let requestID, _, _, _): NotificationHub.shared.clear(requestID: requestID)
            case .question(let requestID, _, _, _): NotificationHub.shared.clear(requestID: requestID)
            }
        }
        pendingAsk = ask
        switch ask {
        case .permission(let requestID, let toolUseID, let forWhat, let what):
            let line = forWhat + " Say yes or no."
            append(.claude, what.isEmpty ? line : line + "\n" + what)
            NotificationHub.shared.postPermission(requestID: requestID, toolUseID: toolUseID, body: forWhat, sid: sid)
            if isInCall { head.start() }   // a ring starts its own head reading; with no call nothing needs it (battery)
        case .question(let requestID, _, let question, _):
            append(.claude, spokenLine(for: ask))
            NotificationHub.shared.postQuestion(requestID: requestID, body: question.question, options: question.options)
        }
        updateGate()
        state = .waitingApproval
        statusLine = Say.waiting
        publish(alert: true)
        if isInCall, !onHold {
            spokenAsk = Self.id(of: ask)
            speaker.speak(spokenLine(for: ask), voiceID: voiceID, line: line, tone: spokenCues)
        } else if isInCall {
            // on hold for a real call: read when he comes back
        } else if UIApplication.shared.applicationState != .active {
            let reason = "Psyclaupse needs you"
            Task {
                if let refused = await self.ringNow(reason) { self.lastError = "The ring was refused: \(refused)" }
            }
        }
    }

    private func spokenLine(for ask: Ask) -> String {
        switch ask {
        case .permission(_, _, let forWhat, _):
            return forWhat + " Say yes or no."
        case .question(_, _, let question, _):
            let options = question.options.enumerated().map { "Option \($0.offset + 1): \($0.element)." }.joined(separator: " ")
            return question.question + " " + options
        }
    }

    private static func id(of ask: Ask) -> String {
        switch ask {
        case .permission(let requestID, _, _, _): return requestID
        case .question(let requestID, _, _, _): return requestID
        }
    }

    /// The ask is settled, here or anywhere else: take it off every surface at once.
    private func resolve(_ ask: Ask) {
        spokenAsk = nil
        if callKit.isRinging {
            RingLog.note("ring stopped: answered somewhere else")
            _ = callKit.endCall()
        }
        switch ask {
        case .permission(let requestID, _, _, _): NotificationHub.shared.clear(requestID: requestID)
        case .question(let requestID, _, _, _): NotificationHub.shared.clear(requestID: requestID)
        }
        pendingAsk = nil
        head.stop()
        speaker.stop()
        updateGate()
        publish()
    }

    private func answer(_ text: String, to ask: Ask) {
        switch ask {
        case .permission:
            if let allow = SpokenAnswer.decision(text) {
                answerPermission(allow: allow, message: nil)
                return
            }
            Task {
                // the plain word match could not tell: the on-device model reads a loose answer, and doubt stays unclear
                let judged = await OnDeviceJudge.decision(text)
                guard self.pendingAsk == ask else { return }
                if let judged {
                    self.answerPermission(allow: judged, message: nil)
                } else if self.isInCall {
                    self.speaker.speak("I did not catch that. Say yes or no.", voiceID: self.voiceID, line: self.line)
                } else {
                    self.statusLine = "Press Approve or Deny."
                }
            }
        case .question(_, _, let question, _):
            if let index = SpokenAnswer.option(text, of: question) {
                answerQuestion(option: index)
                return
            }
            Task {
                let judged = await OnDeviceJudge.option(text, question: question.question, options: question.options)
                guard self.pendingAsk == ask else { return }
                if let judged {
                    self.answerQuestion(option: judged)
                } else if self.isInCall {
                    let names = question.options.prefix(4).joined(separator: ", or ")
                    self.speaker.speak("I did not catch which one. Say \(names).", voiceID: self.voiceID, line: self.line)
                } else {
                    self.statusLine = "Pick an option."
                }
            }
        }
    }

    private var askText: String? {
        switch pendingAsk {
        case .permission(_, _, let forWhat, _)?: return forWhat
        case .question(_, _, let question, _)?: return question.question
        case nil: return nil
        }
    }

    // MARK: ears

    private func heard(_ event: SpeechListener.Event) {
        guard isInCall else { return }
        switch event {
        case .level(let level):
            probe.micHeard(level, inBackground: UIApplication.shared.applicationState != .active)
            micLevel = (state == .listening || state == .hearing) ? level : 0
            meterLevel = level
        case .hearing(let raw):
            let text = speaker.withoutCue(raw)
            guard Self.hasWords(text) else { return }   // noise comes back as a lone "."
            if speaker.isSpeaking {
                guard isBargeIn(text) || VoiceCommand.parse(text) == .stop else { return }
                speaker.stop()   // he spoke over the voice: it stops at once
                lastSpoke = Date()
            }
            if state != .hearing { set(.hearing, Say.hearing) }
            statusLine = "Hearing: \(text)"
            if Date().timeIntervalSince(lastHearingPublish) > 1 {
                lastHearingPublish = Date()
                publish()   // the Lock Screen shows what the mic is catching, about once a second
            }
        case .turn(let raw, let alts, let confidence):
            let text = Self.tidy(speaker.withoutCue(raw))
            guard Self.hasWords(text) else {
                if state == .hearing { rest() }
                return
            }
            if heardCheck != nil {
                switch ConfirmReply.parse(text) {
                case .yes: settleHeard(yes: true); return
                case .again: settleHeard(yes: false); return
                case .other: clearHeard()   // he said it another way: this turn replaces the one being checked
                }
            }
            guard speaker.isSpeaking else {
                if pendingAsk == nil, let command = VoiceCommand.parse(text), runs(command) { return }
                guard let words = awake(text) else {
                    if state == .hearing { rest() }
                    return
                }
                if askToConfirm(words, alts: alts, confidence: confidence) { return }
                if words == text { nextAlt = (alts, confidence) }   // a wake word trims the words, and then the readings no longer match
                took(words)
                if spokenCues, awaitingReply, pendingAsk == nil, !speaker.isSpeaking { speaker.cue("Got it") }
                return
            }
            if let answer = permissionAnswer(text) ?? questionAnswer(text) {
                speaker.stop()   // a clear answer said over the prompt counts, and the voice stops
                took(answer)
            }
        case .failed(let message):
            lastError = message
            set(.lost, message)
            if !earsRetried {
                earsRetried = true
                audioActivated()   // the listener dropped its finished analyzer, so this builds the ears again, once per call
            }
        }
    }

    // MARK: unsure ears

    /// When the ears were unsure of a word, the call says what it heard and waits for Yes or Again instead of sending a guess.
    /// True when it asked (the words are then held, not sent).
    private func askToConfirm(_ words: String, alts: [String], confidence: Double?) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Keys.confirm) as? Bool ?? true, pendingAsk == nil, let confidence,
              Heard.isUnsure(confidence: confidence, below: defaults.object(forKey: Keys.confirmBelow) as? Double ?? Heard.defaultThreshold) else { return false }
        let check = HeardCheck(text: words, alts: alts, confidence: confidence)
        heardCheck = check
        heardTask?.cancel()
        heardTask = Task {
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, self.heardCheck == check else { return }
            self.clearHeard()
            self.note("Not sent, no answer: \(check.text)")
            if self.state == .hearing || self.state == .speaking { self.rest() }
        }
        lockLine = "Heard: " + words
        let said = words.count > 160 ? String(words.prefix(160)) + " and so on" : words
        voice("I heard: \(said). Right?", tone: spokenCues)
        if state == .hearing { rest() }
        return true
    }

    private func clearHeard() {
        heardTask?.cancel()
        heardTask = nil
        heardCheck = nil
    }

    private func settleHeard(yes: Bool) {
        guard let check = heardCheck else { return }
        clearHeard()
        speaker.stop()
        if yes {
            nextAlt = (check.alts, check.confidence)
            took(check.text)
            if spokenCues, awaitingReply, pendingAsk == nil, !speaker.isSpeaking { speaker.cue("Got it") }
        } else {
            note("Again.")
            if handsFree { rest() } else { talk() }
        }
    }

    /// The Yes / Again buttons on the call screen.
    func answerHeard(yes: Bool) { settleHeard(yes: yes) }

    /// Asks the PC for the freshest words list (built from his notes) and keeps it for the next call.
    private func refreshVocabulary(_ base: [String]) {
        guard let line else { return }
        let listener = self.listener
        Task {
            guard let fresh = try? await line.vocabulary(), !fresh.isEmpty else { return }
            Vocabulary.remember(fresh)
            await listener.setWords(Vocabulary.merged(base, fresh, Vocabulary.bundled()))
        }
    }

    /// Runs a spoken command. False when it should go to the session as a message instead:
    /// "stop" and its kind only count while the voice is talking or has just stopped.
    private func runs(_ command: VoiceCommand) -> Bool {
        switch command {
        case .stop:
            guard Date().timeIntervalSince(lastSpoke) < 4 else { return false }
            speaker.stop()
            heldReply = nil
            rest()
        case .again:
            replay()
        case .slower, .faster:
            let step = command == .slower ? -0.04 : 0.04
            let pace = min(max(VoiceTuning.rate + step, VoiceTuning.rateRange.lowerBound), VoiceTuning.rateRange.upperBound)
            UserDefaults.standard.set(pace, forKey: VoiceTuning.rateKey)
            replay()
        case .end:
            endCall()
        }
        return true
    }

    /// Wake word mode: his words after "Claude", or everything for 20 seconds after the name or after an answer. nil = not for the session.
    private func awake(_ text: String) -> String? {
        guard wakeWord, handsFree, pendingAsk == nil else { return text }
        if let rest = WakeWord.after(text) {
            awakeUntil = Date().addingTimeInterval(20)
            let words = Self.tidy(rest)
            if Self.hasWords(words) { return words }
            speaker.cue("Yes?")
            return nil
        }
        guard Date() < awakeUntil else { return nil }
        awakeUntil = Date().addingTimeInterval(20)
        return text
    }

    /// The turn's text minus the progress lines already said and shown.
    private func notYetSaid(_ text: String) -> String {
        var left = text
        for part in spokenParts { left = left.replacingOccurrences(of: part, with: "") }
        return left.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasWords(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }

    /// The transcriber sometimes opens a turn with stray punctuation (". yes, I heard").
    private static func tidy(_ text: String) -> String {
        String(text.drop { !$0.isLetter && !$0.isNumber })
    }

    /// His words minus the words the voice is saying, when a permission waits and they are a clear yes or no; else nil.
    /// The prompt itself says "approve or deny", so its echo can never answer. Questions are not taken over the voice:
    /// the spoken "Option 2" can come back from the mic as "two".
    private func permissionAnswer(_ heard: String) -> String? {
        guard let ask = pendingAsk, case .permission = ask else { return nil }
        let spoken = Set(speaker.speakingText.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init))
        let own = heard.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init).filter { !spoken.contains($0) }
        let words = own.joined(separator: " ")
        return SpokenAnswer.decision(words) != nil ? words : nil
    }

    /// His words minus the words the voice is saying, when a question waits and they name one of its options.
    /// Only names count here, never numbers: the spoken "Option 2" can come back from the mic as "two".
    private func questionAnswer(_ heard: String) -> String? {
        guard let ask = pendingAsk, case .question(_, _, let question, _) = ask else { return nil }
        let spoken = Set(speaker.speakingText.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init))
        let own = heard.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init).filter { !spoken.contains($0) }
        let words = own.joined(separator: " ")
        guard !words.isEmpty else { return nil }
        // the option whose name shares a word with what he said (option names are in the spoken text, so match on his own words)
        let said = Set(own)
        let hits = question.options.filter { option in
            let name = Set(option.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init))
            return !name.isEmpty && name.isSubset(of: said)
        }
        return hits.count == 1 ? hits[0] : nil
    }

    /// Echo cancellation is not proven on this path, so the voice's own words coming back through the mic are not a barge-in:
    /// it needs two words or more, at least half of them words Claude is not saying right now.
    private func isBargeIn(_ heard: String) -> Bool {
        let words = heard.lowercased().split { !$0.isLetter }.map(String.init)
        guard words.count >= 2 else { return false }
        let spoken = Set(speaker.speakingText.lowercased().split { !$0.isLetter }.map(String.init))
        let own = words.filter { !spoken.contains($0) }.count
        return own * 2 >= words.count
    }

    /// The mic feeds the transcriber only when a turn is wanted: hands-free, one pressed turn, or an answer.
    private func updateGate() {
        listener.setAccepting(isInCall && !isMuted && (handsFree || armed || pendingAsk != nil))
    }

    // MARK: voice

    private func say(_ text: String) {
        guard isInCall else {
            rest()
            return
        }
        if onHold {
            heldReply = text   // said when he comes back from the other call
            return
        }
        let written = SpokenText.make(text).sentences.joined(separator: " ")
        guard shortAnswers, written.count > 450, OnDeviceJudge.isAvailable else {
            voice(text, tone: spokenCues)
            return
        }
        Task {
            // a long answer: said as a few sentences, with the full text on the screen
            let short = await OnDeviceJudge.spoken(written)
            guard self.isInCall else { return }
            let words = short.map { $0 + " " + SpokenText.restOnScreen } ?? text
            if self.state == .hearing { self.heldReply = words } else { self.voice(words, tone: self.spokenCues) }
        }
    }

    private func voice(_ text: String, voiceID id: String? = nil, tone: Bool = false) {
        if !isInCall {
            do {
                try AudioSessionManager.activate()
            } catch {
                lastError = "The speaker is not available: \(error.localizedDescription)"
                return
            }
        }
        lockLine = "Claude: " + SpokenText.make(text).sentences.joined(separator: " ")
        set(.speaking, Say.speaking)
        speaker.speak(text, voiceID: id ?? voiceID, line: line, tone: tone)
    }

    private func spokeDone() {
        lastSpoke = Date()
        awakeUntil = Date().addingTimeInterval(20)   // wake word mode: a follow-up needs no name
        guard isInCall else {
            keepAlive.stop()
            AudioSessionManager.deactivate()
            rest()
            stayReachableIfWanted()
            return
        }
        let listener = self.listener
        Task {
            await listener.discard()   // whatever the mic caught of the voice itself
            self.rest()
        }
    }

    private func voiceFailed(_ message: String) {
        note(message)
        lastError = message
        if !isInCall {
            keepAlive.stop()
            AudioSessionManager.deactivate()
            stayReachableIfWanted()
        }
        rest(message)
    }

    // MARK: call lifecycle

    /// Music mode: the session mixes with other audio and no system call is placed, so Apple Music keeps playing.
    /// The headset buttons are left to the music.
    private func startInMusicMode() {
        do {
            try AudioSessionManager.activate(music: true)
            ownsAudio = true
            note("Music mode: your music keeps playing. The iPhone's own microphone listens.")
            audioActivated()
        } catch {
            finishCall("The microphone could not be opened.")
        }
    }

    private func startWithoutCallKit(_ reason: String) {
        guard isInCall else { return }
        do {
            try AudioSessionManager.activate()
            ownsAudio = true
            remote.enable()
            note("The system refused the call (\(reason)). It runs without it, and may stop when the phone locks.")
            audioActivated()
        } catch {
            finishCall("The microphone could not be opened.")
        }
    }

    private func audioActivated() {
        guard isInCall, config != nil else { return }
        keepAlive.stop()
        connect()
        let listener = self.listener
        Task {
            do {
                do {
                    try await listener.start(endOfTurn: VoiceTuning.pause, endOfTurnInterim: VoiceTuning.pause + 0.8)
                } catch {
                    // the audio can still be settling just after a ring is answered: one more try
                    try? await Task.sleep(for: .milliseconds(600))
                    try? AudioSessionManager.configure(music: self.musicMode && !self.callKit.hasCall)
                    try await listener.start(endOfTurn: VoiceTuning.pause, endOfTurnInterim: VoiceTuning.pause + 0.8)
                }
            } catch {
                RingLog.note("mic did not start: \(plainSentence(error))")
                if self.connectedOnce {
                    // Back from a hold or an interruption: a real call can hold the audio for a few seconds after it
                    // ends. Never drop the call for that (his report 11-12: "when that call ended both calls dropped").
                    self.set(.lost, "Getting the mic back")
                    self.micRetries += 1
                    if self.micRetries <= 8 {
                        try? await Task.sleep(for: .seconds(2))
                        if self.isInCall { self.audioActivated() }
                    } else {
                        self.set(.lost, "The mic did not come back. Press Talk to try again")
                    }
                    return
                }
                self.finishCall(plainSentence(error))
                if self.callKit.hasCall { self.callKit.endCall() }
                return
            }
            guard self.isInCall else {
                await listener.stop()
                return
            }
            self.connectedOnce = true
            self.micRetries = 0
            self.callKit.reportConnected()
            if self.idleWatch == nil { self.watchForSleep() }
            self.matchProximityToRoute()
            if self.state == .connecting { self.speaker.chime(.connected) }
            guard self.state == .connecting || self.state == .lost else { return }
            self.rest()
            if let ask = self.pendingAsk, self.spokenAsk != Self.id(of: ask) {
                self.spokenAsk = Self.id(of: ask)
                self.speaker.speak(self.spokenLine(for: ask), voiceID: self.voiceID, line: self.line, tone: self.spokenCues)
            }
        }
    }

    private func audioDeactivated() {
        guard isInCall else {
            backToReachable()   // a ring ended: the system took the audio, take the background line back
            return
        }
        speaker.stop()
        set(.lost, "The call's audio was taken by something else.")
    }

    /// Held to the ear on the earpiece: the proximity sensor darkens the screen, as in a phone call. Off on speaker and AirPods.
    private func matchProximityToRoute() {
        let earpiece = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInReceiver }
        UIDevice.current.isProximityMonitoringEnabled = isInCall && earpiece
    }

    private func audioChanged(_ change: AudioSessionManager.Change) {
        if change == .routeChanged || change == .engineReset { matchProximityToRoute() }
        guard isInCall else {
            switch change {
            case .interrupted:
                if keepAlive.isOn {
                    RingLog.note("background line interrupted")
                    holdAwake("interrupted")
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        self.keepAlive.resume()
                        self.stayReachableIfWanted()
                    }
                }
            case .resumed:
                keepAlive.resume()
                stayReachableIfWanted()
            default:
                break
            }
            return
        }
        let listener = self.listener
        switch change {
        case .interrupted:
            speaker.stop()
            set(.lost, "The call's audio was interrupted.")
        case .resumed:
            Task {
                await listener.restartMic()
                if self.isInCall, self.state == .lost { self.rest() }
            }
        case .routeChanged, .engineReset:
            let onlyIfStopped = change == .engineReset   // a configuration change that left the engine running needs nothing
            routeTask?.cancel()
            routeTask = Task {
                try? await Task.sleep(for: .milliseconds(400))   // several notices arrive for one AirPods change
                guard !Task.isCancelled else { return }
                await listener.restartMic(onlyIfStopped: onlyIfStopped)
            }
        }
    }

    private func ringAnswered() {
        RingLog.note("ring answered")
        keepAlive.stop()
        if !pendingIsPermission { head.stop() }
        if probe.sawRing(answered: true) {
            callKit.endCall()
            return
        }
        guard hasConfig, !isInCall else {
            if !hasConfig { callKit.endCall() }
            return
        }
        isInCall = true
        activity.start(title: Say.title)
        remote.enable()
        set(.connecting, Say.connecting)
    }

    private func finishCall(_ message: String? = nil) {
        guard isInCall else { return }
        RingLog.note("call ended" + (message.map { ": " + $0 } ?? ""))
        isInCall = false
        isMuted = false
        armed = false
        earsRetried = false
        armedReply = nil
        heldReply = nil
        interimTask?.cancel()
        spokenParts = []
        connectedOnce = false
        micRetries = 0
        idleWatch?.cancel()
        idleWatch = nil
        onHold = false
        lockLine = ""
        micLevel = 0
        meterLevel = 0
        clearHeard()
        nextAlt = nil
        speaker.stop()
        speaker.chime(.ended)
        UIDevice.current.isProximityMonitoringEnabled = false
        remote.disable()
        let listener = self.listener
        let releaseAudio = ownsAudio
        ownsAudio = false
        holdAwake("call ended")
        Task {
            await listener.stop()
            if releaseAudio { AudioSessionManager.deactivate() }
            self.stayReachableIfWanted()
        }
        note("Call ended.")
        if let message { lastError = message }
        rest(message)
        activity.end()
    }

    // MARK: state

    /// Where the call settles when nothing is being said: the one place that decides the resting state.
    private func rest(_ line: String? = nil) {
        updateGate()
        if let held = heldReply, isInCall {
            heldReply = nil
            say(held)
            return
        }
        if pendingAsk != nil {
            set(.waitingApproval, line ?? Say.waiting)
        } else if awaitingReply {
            set(.working, line ?? Say.working)
        } else if !isInCall {
            set(.idle, line ?? (hasConfig ? Say.ready : Say.load))
        } else if handsFree || armed {
            let fresh = state != .listening && state != .hearing
            set(.listening, line ?? Say.listening)
            if fresh, spokenCues { speaker.cue("Listening") }   // his turn: the mic is open
        } else {
            set(.idle, line ?? Say.pressToTalk)   // PUSH mode between turns: in the call, mic closed
        }
    }

    private func set(_ newState: CallState, _ line: String) {
        state = newState
        statusLine = line
        if newState != .listening && newState != .hearing { micLevel = 0 }
        publish()
    }

    /// Every surface outside the app hears about every change.
    private func publish(alert: Bool = false) {
        SharedState.write(state: state, line: statusLine, ask: askText)
        ControlCenter.shared.reloadAllControls()
        // The Lock Screen shows the conversation: his words while he talks, otherwise the last thing either side said.
        let shown = (state == .hearing || state == .lost || state == .connecting || lockLine.isEmpty) ? statusLine : lockLine
        activity.update(state: state, line: shown, ask: pendingAsk, alert: alert, push: isInCall && !handsFree)
        var canAnswer = false
        if case .permission? = pendingAsk { canAnswer = true }
        WatchLink.shared.send(state: state.rawValue, line: String(shown.prefix(200)), ask: askText.map { String($0.prefix(200)) },
                              canAnswer: canAnswer, push: !handsFree, inCall: isInCall)
    }

    private func append(_ who: Turn.Who, _ text: String, image: String? = nil) {
        turns.append(Turn(id: UUID(), who: who, text: text, date: Date(), image: image))
        if turns.count > 400 { turns.removeFirst(turns.count - 400) }
    }

    private func note(_ text: String) {
        append(.system, text)
    }
}

/// The capability probe: each item really exercises the feature and says pass or fail with the reason.
/// Nothing about a free-signed install is believed until it passes here.
@MainActor @Observable final class ProbeModel {
    struct Item: Identifiable {
        let id: String
        var title: String
        var detail: String
        var result: Result

        enum Result { case untested, running, pass, fail(String) }
    }

    var items: [Item] = [
        Item(id: "line", title: "Line to the PC", detail: "Reaches the PC and checks the certificate name.", result: .untested),
        Item(id: "speech", title: "On-device transcription", detail: "Checks the speech model.", result: .untested),
        Item(id: "voice", title: "Voice", detail: "Speaks one line in the chosen voice.", result: .untested),
        Item(id: "lockedMic", title: "Mic while locked", detail: "During a call: lock the phone and talk.", result: .untested),
        Item(id: "notification", title: "Notification reply", detail: "Sends a notice with Approve, Deny and Reply.", result: .untested),
        Item(id: "liveActivity", title: "Live Activity buttons", detail: "Starts the Live Activity and waits for a button.", result: .untested),
        Item(id: "control", title: "Control Center control", detail: "Waits for the Call control to be pressed.", result: .untested),
        Item(id: "widgetFetch", title: "Widget state", detail: "Checks the store the Lock Screen widget reads.", result: .untested),
        Item(id: "headMotion", title: "Head nod and shake", detail: "Reads AirPods head motion.", result: .untested),
        Item(id: "incomingCall", title: "Claude rings you", detail: "Rings the phone with a local call.", result: .untested),
        Item(id: "model", title: "On-device model", detail: "Reads a loose yes and a loose no with Apple's model.", result: .untested)
    ]

    @ObservationIgnored private var backgroundBuffers = 0
    @ObservationIgnored private var backgroundLoudest = 0.0
    @ObservationIgnored private var ownsActivity = false

    func run(_ id: String) async {
        let model = CallModel.shared
        mark(id, .running)
        switch id {
        case "line":
            guard let line = model.line else {
                mark(id, .fail("Load your config first."))
                return
            }
            do {
                try await line.ping()
                let count = try await line.sessions().count
                let via = await line.usingFallback ? "the fallback address" : "the main address"
                mark(id, .pass, detail: "Reached on \(via), certificate name checked, \(count) session(s) live.")
            } catch {
                mark(id, .fail(plainSentence(error)))
            }

        case "speech":
            let check = await SpeechListener.check()
            let result: Item.Result = check.ready ? .pass : .fail(check.detail)
            mark(id, result, detail: check.detail)

        case "voice":
            guard let summary = Speaker.phoneVoiceSummary() else {
                mark(id, .fail("No English voice is installed."))
                return
            }
            model.previewVoice(model.voiceID)
            mark(id, .pass, detail: model.voiceID == Speaker.personal ? "Your Personal Voice." : summary)

        case "lockedMic":
            guard model.isInCall else {
                mark(id, .fail("Start a call first, then run this and lock the phone."))
                return
            }
            backgroundBuffers = 0
            backgroundLoudest = 0
            mark(id, .running, detail: "Lock the phone now and talk for 20 seconds.")
            try? await Task.sleep(for: .seconds(30))
            if backgroundBuffers > 20, backgroundLoudest > 0.15 {
                mark(id, .pass, detail: "\(backgroundBuffers) mic buffers arrived with the app off screen, your voice among them.")
            } else if backgroundBuffers > 20 {
                mark(id, .fail("Audio arrived with the app off screen, but only silence."))
            } else {
                mark(id, .fail("No audio arrived with the app off screen (or the phone was never locked)."))
            }

        case "notification":
            guard await NotificationHub.shared.authorize() else {
                mark(id, .fail("Notifications are off for Call in Settings."))
                return
            }
            NotificationHub.shared.postProbe()
            mark(id, .running, detail: "Sent. Pull down on it, press Reply and send a word.")
            await expire(id)

        case "liveActivity":
            ownsActivity = !model.isInCall
            if let refused = model.activity.start(title: "Probe") {
                mark(id, .fail(refused))
                return
            }
            model.activity.update(state: model.state, line: "Probe: press a button here", ask: nil)
            guard model.activity.isLive else {
                mark(id, .fail("The system did not start a Live Activity."))
                return
            }
            mark(id, .running, detail: "It is up. Lock the phone and press End on it (during a call that ends the call).")
            await expire(id)
            if ownsActivity, !model.isInCall { model.activity.end() }

        case "control":
            ControlCenter.shared.reloadAllControls()
            mark(id, .running, detail: "Add the Call control to Control Center if it is not there, then press it.")
            await expire(id)

        case "widgetFetch":
            guard SharedState.isAvailable else {
                mark(id, .fail("This signing has no shared container, so the Lock Screen widget cannot read the app's state."))
                return
            }
            let before = SharedState.read()
            let token = "probe \(Int(Date().timeIntervalSince1970))"
            SharedState.write(state: before.state, line: token, ask: before.ask)
            let back = SharedState.read().line
            SharedState.write(state: before.state, line: before.line, ask: before.ask)
            if back == token {
                mark(id, .pass, detail: "The shared store works. The widget reads it; it does not fetch from the PC.")
            } else {
                mark(id, .fail("The shared store did not hold what was written."))
            }

        case "headMotion":
            guard GestureReader.selfCheck() else {
                mark(id, .fail("The nod and shake maths failed its own check."))
                return
            }
            guard !model.head.isDenied else {
                mark(id, .fail("Motion access is off for Call in Settings."))
                return
            }
            guard model.head.isAvailable else {
                mark(id, .fail("No AirPods with head tracking are connected."))
                return
            }
            model.head.start()
            mark(id, .running, detail: "Nod twice or shake twice within 20 seconds.")
            try? await Task.sleep(for: .seconds(20))
            if isRunning(id) { mark(id, .fail("No nod or shake was seen in 20 seconds.")) }
            if model.pendingAsk == nil { model.head.stop() }

        case "incomingCall":
            guard !model.isInCall else {
                mark(id, .fail("End the call first: the system allows one call at a time."))
                return
            }
            if let refused = await model.callKit.ring(reason: "Probe") {
                mark(id, .fail("The system refused the ring: \(refused)"))
                return
            }
            mark(id, .running, detail: "Ringing. Answer with a nod or the green button, or decline with a shake.")
            await expire(id)
            if isRunning(id) || model.callKit.hasCall { model.callKit.endCall() }

        case "model":
            guard OnDeviceJudge.isAvailable else {
                mark(id, .fail(OnDeviceJudge.unavailableReason))
                return
            }
            let yes = await OnDeviceJudge.decision("yeah go for it")
            let no = await OnDeviceJudge.decision("nah leave that alone")
            if yes == true, no == false {
                mark(id, .pass, detail: "It read a loose yes and a loose no correctly.")
            } else {
                mark(id, .fail("It answered, but not as expected (yes read as \(String(describing: yes)), no read as \(String(describing: no)))."))
            }

        default:
            mark(id, .fail("There is no such check."))
        }
    }

    // MARK: what the engine reports back

    fileprivate func sawNotification(action: String, text: String?) {
        guard isRunning("notification") else { return }
        switch action {
        case NotificationHub.replyID: mark("notification", .pass, detail: "Reply reached the app with: \(text ?? "")")
        case NotificationHub.approveID: mark("notification", .pass, detail: "Approve reached the app. Try Reply too.")
        case NotificationHub.denyID: mark("notification", .pass, detail: "Deny reached the app. Try Reply too.")
        default: mark("notification", .fail("The notice was opened, but no action was pressed."))
        }
    }

    /// A Live Activity button or a control ran its intent inside the app.
    fileprivate func sawIntent() {
        for id in ["liveActivity", "control"] where isRunning(id) {
            mark(id, .pass, detail: "The press reached the app.")
        }
    }

    /// True when the probe was waiting for it, so the gesture answers nothing real.
    fileprivate func sawHead(_ gesture: HeadGesture) -> Bool {
        guard isRunning("headMotion") else { return false }
        mark("headMotion", .pass, detail: gesture == .nod ? "A nod was read." : "A shake was read.")
        return true
    }

    var isRingProbe: Bool { isRunning("incomingCall") }

    /// True when the ring was the probe's own.
    fileprivate func sawRing(answered: Bool) -> Bool {
        guard isRunning("incomingCall") else { return false }
        mark("incomingCall", .pass, detail: answered ? "The ring was answered." : "The ring was declined.")
        return true
    }

    fileprivate func micHeard(_ level: Double, inBackground: Bool) {
        guard inBackground, isRunning("lockedMic") else { return }
        backgroundBuffers += 1
        backgroundLoudest = max(backgroundLoudest, level)
    }

    // MARK: helpers

    private func expire(_ id: String) async {
        try? await Task.sleep(for: .seconds(60))
        if isRunning(id) { mark(id, .fail("Nothing came back within a minute.")) }
    }

    private func isRunning(_ id: String) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        if case .running = item.result { return true }
        return false
    }

    private func mark(_ id: String, _ result: Item.Result, detail: String? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].result = result
        if let detail { items[index].detail = detail }
    }
}
