import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers

/// The front door: no config shows "Load your config" and nothing else; with a config, Face ID (or the passcode)
/// opens the call screen. A failed check stays closed, with Retry.
struct RootView: View {
    let model: CallModel
    @State private var unlocked = false
    @State private var checking = false
    @State private var askedThisVisit = false
    @Environment(\.scenePhase) private var scenePhase

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(model: CallModel) { self.model = model }

    var body: some View {
        ZStack {
            Backdrop()
            if model.restoring {
                // the saved config is still being read back: show nothing rather than a "Load your config" flash
                Color.clear
            } else if !model.hasConfig {
                ConfigGateView(model: model)
            } else if unlocked {
                CallScreen(model: model)
            } else {
                lockedView
            }
        }
        .task(id: model.hasConfig) {
            await unlockIfDue()
        }
        .onChange(of: scenePhase) { _, phase in
            // a launch in the background (a notification action, a control) cannot show Face ID: ask when he opens the app.
            // Face ID's own sheet only makes the scene inactive, so a cancel does not bring the prompt straight back.
            if phase == .background { askedThisVisit = false }
            if phase == .active { Task { await unlockIfDue() } }
        }
    }

    /// One automatic ask per visit to the foreground; Retry asks again by hand.
    private func unlockIfDue() async {
        guard model.hasConfig, !unlocked, !askedThisVisit, scenePhase == .active else { return }
        askedThisVisit = true
        await unlock()
    }

    private var lockedView: some View {
        VStack(spacing: T.margin) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Locked")
                .plHand(34, relativeTo: .largeTitle)
                .accessibilityAddTraits(.isHeader)
            Text("This app steers a live session. Unlock to open it.")
                .plFont(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !checking {
                Button {
                    Task { await unlock() }
                } label: {
                    Text("Retry")
                        .plFont(.headline)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 28)
                        .frame(minHeight: 50)
                        .contentShape(Capsule())
                }
                .glassControl(tint: T.orange)
            }
        }
        .padding(T.margin * 2)
    }

    private func unlock() async {
        if checking { return }
        checking = true
        unlocked = await authenticate()
        checking = false
    }

    /// Face ID, Touch ID or the passcode. A device with no passcode has nothing to check, so it opens.
    private func authenticate() async -> Bool {
        let context = LAContext()
        var problem: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problem) else { return true }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open the call") { passed, _ in
                continuation.resume(returning: passed)
            }
        }
    }
}

/// No config yet: one title, one button, the error line. No network call happens from here.
struct ConfigGateView: View {
    let model: CallModel
    @State private var picking = false
    @State private var loading = false
    @State private var importError: String? = nil
    @State private var errorTick = 0

    // explicit: a view with private state must not depend on the synthesized initializer staying internal
    init(model: CallModel) { self.model = model }

    private var errorLine: String? { importError ?? model.configError }

    var body: some View {
        VStack(spacing: T.margin) {
            Text("Load your config")
                .plHand(34, relativeTo: .largeTitle)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Button {
                picking = true
            } label: {
                Text("Choose the file")
                    .plFont(.headline)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 28)
                    .frame(minHeight: 50)
                    .contentShape(Capsule())
            }
            .glassControl(tint: T.orange)
            .disabled(loading)
            if let line = errorLine {
                NoteLine(symbol: "exclamationmark.triangle.fill", tint: T.end, text: line)
            }
        }
        .padding(T.margin * 2)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importError = nil
                load(url)
            case .failure(let error):
                importError = error.localizedDescription
                errorTick += 1
            }
        }
        .onChange(of: model.configError) { _, new in
            if new != nil { errorTick += 1 }
        }
        .sensoryFeedback(PLHaptic.error, trigger: errorTick)
    }

    private func load(_ url: URL) {
        loading = true
        Task {
            let scoped = url.startAccessingSecurityScopedResource()   // a picked file is readable only inside this pair
            await model.loadConfig(from: url)
            if scoped { url.stopAccessingSecurityScopedResource() }
            loading = false
        }
    }
}
