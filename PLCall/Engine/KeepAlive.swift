import AVFoundation

/// Keeps the app running in the background with no call up, so the line to the PC stays open and Claude can ring.
/// It plays silence, mixed with other audio, so music and other apps are not touched. It costs some battery.
/// A free account has no push: without this, iOS suspends the app and nothing can ring.
@MainActor final class KeepAlive {
    private var player: AVAudioPlayer?

    var isOn: Bool { player != nil }

    func start() {
        guard player == nil else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let silence = try AVAudioPlayer(data: Self.silence)
            silence.numberOfLoops = -1
            silence.volume = 0
            guard silence.play() else { return }
            player = silence
        } catch {
            player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }

    /// After an interruption (another app's audio) the player is paused: start it again.
    func resume() {
        guard let player, !player.isPlaying else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        _ = player.play()
    }

    /// One second of 16-bit mono silence at 8 kHz, as a WAV file.
    private static let silence: Data = {
        let rate: UInt32 = 8_000
        let bytes = rate * 2
        var data = Data()
        func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        put32(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        put32(16)
        put16(1)
        put16(1)
        put32(rate)
        put32(rate * 2)
        put16(2)
        put16(16)
        data.append(contentsOf: Array("data".utf8))
        put32(bytes)
        data.append(Data(count: Int(bytes)))
        return data
    }()
}
