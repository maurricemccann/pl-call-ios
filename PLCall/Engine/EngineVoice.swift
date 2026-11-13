import AVFoundation

/// Claude's voice played through the SAME audio engine as his microphone (his pick 11-12, "one audio engine").
/// Playing through the voice-processing engine lets echo cancellation hear exactly what is being said, keeps the voice,
/// the tones and the mic on one path, and stops them fighting over the audio session.
/// Unchecked Sendable: the player node is thread-safe for scheduling; the converters and the flag sit behind the lock.
final class EngineVoice: @unchecked Sendable {
    let player = AVAudioPlayerNode()
    /// Everything is converted to this before it is scheduled, so one connection serves every voice and tone.
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

    private let lock = NSLock()
    private var converters: [String: AVAudioConverter] = [:]
    private var running = false
    private var attachedTo: ObjectIdentifier?

    /// True while the mic engine is running with the player connected.
    var isReady: Bool { lock.withLock { running } }

    /// Called by the mic before its engine starts.
    func attach(to engine: AVAudioEngine) {
        if attachedTo != ObjectIdentifier(engine) {
            engine.attach(player)
            attachedTo = ObjectIdentifier(engine)
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Called by the mic after its engine started.
    func started() {
        player.play()
        lock.withLock { running = true }
    }

    /// Called by the mic before its engine stops.
    func stopped() {
        lock.withLock { running = false }
        player.stop()
    }

    /// Plays a buffer after whatever is already scheduled. `done` runs when it has been heard.
    func schedule(_ buffer: AVAudioPCMBuffer, volume: Float = 1, done: (@Sendable () -> Void)? = nil) {
        guard let ready = convert(buffer, volume: volume) else {
            done?()
            return
        }
        player.scheduleBuffer(ready, completionCallbackType: .dataPlayedBack) { _ in done?() }
    }

    /// Barge-in and End: drops everything scheduled, at once.
    func flush() {
        player.stop()
        if isReady { player.play() }
    }

    /// A quiet gap of the given length.
    func silence(_ seconds: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames   // a new buffer is zeroed
        return buffer
    }

    /// Soft notes made in code, the same shapes as the old WAV tones.
    func notes(_ notes: [(Double, Double)]) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let total = notes.reduce(0) { $0 + Int(rate * $1.1) }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let out = buffer.floatChannelData?[0] else { return nil }
        var index = 0
        for (frequency, seconds) in notes {
            let count = Int(rate * seconds)
            for i in 0..<count {
                let edge = min(1.0, Double(min(i, count - i)) / (rate * 0.012))
                out[index] = Float(sin(2 * Double.pi * frequency * Double(i) / rate) * 0.35 * edge)
                index += 1
            }
        }
        buffer.frameLength = AVAudioFrameCount(total)
        return buffer
    }

    private func convert(_ buffer: AVAudioPCMBuffer, volume: Float) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0 else { return nil }
        var output: AVAudioPCMBuffer?
        if buffer.format == format {
            output = buffer
        } else {
            let key = buffer.format.description
            let converter: AVAudioConverter? = lock.withLock {
                if let found = converters[key] { return found }
                let made = AVAudioConverter(from: buffer.format, to: format)
                converters[key] = made
                return made
            }
            guard let converter else { return nil }
            let ratio = format.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
            var fed = false
            var failure: NSError?
            let status = converter.convert(to: out, error: &failure) { _, inputStatus in
                if fed {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                fed = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, failure == nil, out.frameLength > 0 else { return nil }
            output = out
        }
        if volume != 1, let out = output, let samples = out.floatChannelData?[0] {
            for i in 0..<Int(out.frameLength) { samples[i] *= volume }
        }
        return output
    }
}
