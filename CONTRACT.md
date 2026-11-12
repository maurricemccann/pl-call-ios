# Build contract (read before writing any file)

Three writers work in this repo at once. Each owns folders; nobody edits another's folder. Shared names below are law.

## Layout and owners
- `PLCallCore/` (done, tested on Linux): Config, SSEParser, SessionEvent, PermissionRequest, EventReducer, CallState, Ask, SpokenText, SpokenAnswer, BridgeBody, QuickReplyArm, JSONValue. **App code compiles these files directly (same module): never write `import PLCallCore` outside the package tests.**
- `PLCall/Engine/` (ENGINE writer): everything without SwiftUI views: `CallModel`, audio, speech in/out, CallKit, network line, Keychain, config store, notifications, head motion, remote commands, Live Activity controller.
- `PLCall/UI/` (UI writer): every SwiftUI view, the theme/tokens, fonts, haptics, the Probe screen. Also `PLCall/PLCallApp.swift` and `PLCall/Resources/` (fonts, backdrop, asset catalog with the app icon).
- `Shared/` (PLATFORM writer): types compiled into BOTH the app and the widget extension: `CallActivityAttributes`, the App Intents, `SharedState`.
- `PLCallWidgets/` (PLATFORM writer): the widget extension (Live Activity views, Lock Screen widgets, Control Center controls).
- `PLCall.xcodeproj/`, `PLCall/Info.plist`, `PLCallWidgets/Info.plist`, `.github/workflows/`, `scripts/` (PLATFORM writer).

The Xcode project uses **file-system-synchronized groups** (objectVersion 77, `PBXFileSystemSynchronizedRootGroup`), so any `.swift` file placed in an owned folder is compiled automatically: no writer but PLATFORM touches the project file. Folder to target: `PLCall/` → app; `PLCallCore/Sources/PLCallCore/` → app and extension; `Shared/` → app and extension; `PLCallWidgets/` → extension.

## The model the UI binds to (ENGINE implements exactly this, in `PLCall/Engine/CallModel.swift`)
```swift
@MainActor @Observable final class CallModel {
    static let shared: CallModel
    // state
    var state: CallState            // idle, connecting, listening, hearing, working, speaking, waitingApproval, lost
    var statusLine: String          // e.g. "Line ready. Press to call", "Claude is working"
    var turns: [Turn]               // the transcript
    var isInCall: Bool
    var handsFree: Bool             // AUTO (true) / PUSH (false)
    var voices: [PLCallConfig.Voice]
    var voiceID: String             // "phone" = iPhone voice
    var quickReplies: [PLCallConfig.QuickReply]
    var armedReply: String?         // label of a quick reply waiting for its second tap
    var pendingAsk: Ask?            // a permission or a question waiting for him
    var hasConfig: Bool
    var configError: String?
    var micLevel: Double            // 0...1, for the Edge Light
    var isClaudeTyping: Bool
    var sessionTitle: String?
    var lastError: String?
    // actions
    func loadConfig(from url: URL) async
    func forgetConfig()
    func startCall()                // through CallKit
    func endCall()
    func talk()                     // PUSH mode: one turn
    func replay()
    func tapQuickReply(_ r: PLCallConfig.QuickReply)
    func send(text: String)
    func answerPermission(allow: Bool, message: String?)
    func answerQuestion(option: Int)
    func selectVoice(_ id: String)
    func previewVoice(_ id: String)
    func setHandsFree(_ on: Bool)
    var probe: ProbeModel { get }
}
struct Turn: Identifiable, Equatable { let id: UUID; var who: Who; var text: String; var date: Date
    enum Who { case me, claude, system } }
@MainActor @Observable final class ProbeModel {
    struct Item: Identifiable { let id: String; var title: String; var detail: String; var result: Result
        enum Result { case untested, running, pass, fail(String) } }
    var items: [Item]
    func run(_ id: String) async    // ids: "notification", "liveActivity", "control", "widgetFetch", "headMotion", "incomingCall", "lockedMic", "speech", "voice", "line"
}
```

## Shared (PLATFORM implements, both targets)
```swift
struct CallActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var state: String /* CallState rawValue */; var line: String; var askID: String?; var askText: String? }
    var title: String
}
enum SharedState { static func write(state: CallState, line: String, ask: String?); static func read() -> (state: CallState, line: String, ask: String?) }  // App Group if it works on a free ID, else the extension shows the Live Activity state only
// Intents (LiveActivityIntent, run in the app process): ApproveIntent, DenyIntent, PresetReplyIntent(text), EndCallIntent, StartCallIntent (AudioRecordingIntent), ReplayIntent, TalkIntent
// Intents call these hooks, which ENGINE sets at launch:
@MainActor enum IntentBridge { static var approve: ((String?) -> Void)?; static var deny: ((String?) -> Void)?; static var endCall: (() -> Void)?; static var startCall: (() -> Void)?; static var replay: (() -> Void)?; static var talk: (() -> Void)? }
```
ENGINE also provides `LiveActivityController` (`start(title:)`, `update(state:line:ask:)`, `end()`) which the model calls, and `NotificationHub` (categories registered at launch; "Approve" first, then "Deny" (destructive), then "Reply" text input).

## Rules for every writer
1. **Check Apple's own page before and after each API you use** (`https://developer.apple.com/documentation/<path>.md` returns the raw doc with availability). The verified notes are in the research files listed in your brief: read them first; they list exact signatures and the compile traps. A wrong name is a failed build that nobody can run locally.
2. Swift 6 language mode, deployment target iOS 26.0, built with Xcode 27.2. Guard anything iOS 27-only with `if #available(iOS 27, *)`.
3. Never put a key, address, hostname, email, account or session link in any file. The config file supplies them at run time.
4. No third-party libraries.
5. Comments say why, one line, at the end of the line or above it; never before code on the same line.
6. When you finish, list every file you wrote and anything you could not verify at Apple's pages.
