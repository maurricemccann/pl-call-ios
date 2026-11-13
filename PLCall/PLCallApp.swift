import SwiftUI

@main
struct PLCallApp: App {
    init() {
        PLFonts.register()
        NotificationHub.shared.start()   // ENGINE: registers the Approve / Deny / Reply categories and the delegate before launch ends
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: CallModel.shared)
                .tint(T.orange)
                .preferredColorScheme(.dark)   // matches the R1 Call
                // tapping Claude in the Phone app's Recents opens Call with a start-call activity: call back
                .onContinueUserActivity("INStartCallIntent") { _ in CallModel.shared.startCall() }
                .onContinueUserActivity("INStartAudioCallIntent") { _ in CallModel.shared.startCall() }
        }
    }
}
