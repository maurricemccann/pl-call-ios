import MediaPlayer

/// Headset buttons outside CallKit's own handling: press = talk, double = replay, triple = back to hands-free listening.
/// Whether a press reaches here during a CallKit call is unproven (the system may send it as mute instead): the probe tells.
@MainActor final class RemoteCommands {
    private var enabled = false

    func enable() {
        guard !enabled else { return }
        enabled = true
        let center = MPRemoteCommandCenter.shared()
        // Handlers are explicitly @Sendable so they carry no actor: the system may call them off the main thread.
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand] {
            command.isEnabled = true
            _ = command.addTarget { @Sendable _ in
                Task { @MainActor in CallModel.shared.talk() }
                return .success
            }
        }
        center.nextTrackCommand.isEnabled = true
        _ = center.nextTrackCommand.addTarget { @Sendable _ in
            Task { @MainActor in CallModel.shared.replay() }
            return .success
        }
        center.previousTrackCommand.isEnabled = true
        _ = center.previousTrackCommand.addTarget { @Sendable _ in
            Task { @MainActor in CallModel.shared.setHandsFree(true) }
            return .success
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Call with Claude",
            MPNowPlayingInfoPropertyIsLiveStream: true
        ]
    }

    func disable() {
        guard enabled else { return }
        enabled = false
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand, center.nextTrackCommand, center.previousTrackCommand] {
            command.removeTarget(nil)
            command.isEnabled = false
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
