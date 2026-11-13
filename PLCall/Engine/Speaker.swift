import AVFoundation

/// His own pace and pitch for the iPhone voice (Settings in the app).
enum VoiceTuning {
    static let rateKey = "plcall.voiceRate"
    static let pitchKey = "plcall.voicePitch"
    static let rateRange: ClosedRange<Double> = 0.38...0.58
    static let pitchRange: ClosedRange<Double> = 0.80...1.20
    static let defaultRate = 0.47     // a little under the system default of 0.5: closer to talking than reading
    static let defaultPitch = 0.97
    static var rate: Double { (UserDefaults.standard.object(forKey: rateKey) as? Double) ?? defaultRate }
    static var pitch: Double { (UserDefaults.standard.object(forKey: pitchKey) as? Double) ?? defaultPitch }

    /// How long a silence ends his turn. Build 6 used 0.9 s and cut him off mid-thought (his test, 11-12).
    static let pauseKey = "plcall.turnPause"
    static let pauseRange: ClosedRange<Double> = 1.0...4.0
    static let defaultPause = 2.0
    static var pause: Double { (UserDefaults.standard.object(forKey: pauseKey) as? Double) ?? defaultPause }
}

/// Claude's voice. "phone" speaks on the iPhone, sentence by sentence with no gap. Any other id is a PC voice,
/// fetched piece by piece. A PC voice that fails says NOTHING: no other voice ever stands in for it.
@MainActor final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let phone = "phone"
    static let personal = "personal"   // his own iOS Personal Voice, only when he picks it (his ruling, S348)

    var onFinished: (() -> Void)?
    var onFailed: ((String) -> Void)?
    private(set) var speakingText = ""   // what is being said now, so the model can tell his voice from an echo

    private let synthesizer = AVSpeechSynthesizer()   // kept for the app's life: the system does not retain it
    private var pending: [ObjectIdentifier: AVSpeechUtterance] = [:]
    private var player: AVAudioPlayer?
    private var pcTask: Task<Void, Never>?
    private var generation = 0
    private var tonePlayer: AVAudioPlayer?
    private var cueWords: [String] = []
    private var cueUntil = Date.distantPast


    override init() {
        super.init()
        synthesizer.usesApplicationAudioSession = true   // the call's own session, so it plays inside the call
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { !pending.isEmpty || pcTask != nil }

    func speak(_ text: String, voiceID: String, line: LineClient?, tone: Bool = false) {
        stop()
        if tone { playTone() }
        let sentences = SpokenText.make(text).sentences
        speakingText = sentences.joined(separator: " ")
        if voiceID == Self.phone || voiceID == Self.personal {
            let voice: AVSpeechSynthesisVoice?
            if voiceID == Self.personal {
                guard let mine = Self.personalVoice() else {
                    fail("Your Personal Voice is not available: allow it for Psyclaupse in Settings. Nothing is spoken in its place.")
                    return
                }
                voice = mine
            } else {
                voice = Self.bestVoice()
            }
            for sentence in sentences {
                let utterance = AVSpeechUtterance(string: sentence)
                utterance.voice = voice
                utterance.rate = Float(VoiceTuning.rate)
                utterance.pitchMultiplier = Float(VoiceTuning.pitch)
                utterance.postUtteranceDelay = 0.10
                if tone, pending.isEmpty { utterance.preUtteranceDelay = 0.22 }   // the tone plays first
                pending[ObjectIdentifier(utterance)] = utterance
                synthesizer.speak(utterance)   // the synthesizer queues them, so there is no gap between sentences
            }
            return
        }
        guard let line else {
            fail("That voice comes from the PC, and the line is not connected. Nothing is spoken in its place.")
            return
        }
        let pieces = Self.pack(sentences)
        let id = generation
        pcTask = Task { await self.playFromPC(pieces, voice: voiceID, line: line, id: id) }
    }

    /// A short spoken cue ("Listening", "Got it") in the iPhone voice. Never while an answer is being spoken,
    /// and it never calls `onFinished`: the delegate ignores utterances that are not in `pending`.
    func cue(_ words: String) {
        guard !isSpeaking else { return }
        let utterance = AVSpeechUtterance(string: words)
        utterance.voice = Self.bestVoice()
        utterance.rate = Float(VoiceTuning.rate)
        utterance.pitchMultiplier = Float(VoiceTuning.pitch)
        utterance.volume = 0.8
        cueWords = Self.letters(words)
        cueUntil = Date().addingTimeInterval(2.5)
        synthesizer.speak(utterance)
    }

    /// What he said, minus a cue's own words coming back through the mic at the start (only just after a cue).
    func withoutCue(_ heard: String) -> String {
        guard Date() < cueUntil, !cueWords.isEmpty else { return heard }
        var words = heard.split(separator: " ").map(String.init)
        var expected = cueWords[...]
        while let first = words.first, let next = expected.first, Self.letters(first).first == next {
            words.removeFirst()
            expected = expected.dropFirst()
        }
        return words.joined(separator: " ")
    }

    private static func letters(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
    }

    enum Chime { case connected, ended }

    /// The call connecting (rising) or ending (falling), like a phone call's own sounds.
    func chime(_ kind: Chime) {
        let notes: [(Double, Double)] = kind == .connected ? [(523, 0.07), (659, 0.07), (784, 0.11)] : [(659, 0.09), (523, 0.09), (392, 0.14)]
        guard let player = try? AVAudioPlayer(data: Self.wav(notes)) else { return }
        player.volume = 0.45
        tonePlayer = player
        _ = player.play()
    }

    /// A soft two-note tone: Claude is about to talk.
    private func playTone() {
        guard let player = try? AVAudioPlayer(data: Self.toneData) else { return }
        player.volume = 0.5
        tonePlayer = player
        _ = player.play()
    }

    /// 16-bit mono WAV, 24 kHz: 660 Hz then 880 Hz, 80 ms each, with soft edges so it does not click.
    private static let toneData: Data = wav([(660, 0.08), (880, 0.08)])

    /// 16-bit mono WAV at 24 kHz from (frequency, seconds) notes, each with soft edges so it does not click.
    private static func wav(_ notes: [(Double, Double)]) -> Data {
        let rate = 24_000.0
        var samples: [Int16] = []
        for (frequency, seconds) in notes {
            let count = Int(rate * seconds)
            for index in 0..<count {
                let edge = min(1.0, Double(min(index, count - index)) / (rate * 0.012))
                let value = sin(2 * Double.pi * frequency * Double(index) / rate) * 0.35 * edge
                samples.append(Int16(value * Double(Int16.max)))
            }
        }
        var data = Data()
        func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        put32(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        put32(16)
        put16(1)
        put16(1)
        put32(UInt32(rate))
        put32(UInt32(rate) * 2)
        put16(2)
        put16(16)
        data.append(contentsOf: Array("data".utf8))
        put32(bytes)
        for sample in samples { put16(UInt16(bitPattern: sample)) }
        return data
    }

    /// Barge-in and End: silence at once. Does not call `onFinished`.
    func stop() {
        generation += 1
        pending.removeAll()
        _ = synthesizer.stopSpeaking(at: .immediate)
        pcTask?.cancel()
        pcTask = nil
        player?.stop()
        player = nil
        speakingText = ""
    }

    /// His Personal Voice, when he has made one and allowed this app to use it.
    static func personalVoice() -> AVSpeechSynthesisVoice? {
        guard AVSpeechSynthesizer.personalVoiceAuthorizationStatus == .authorized else { return nil }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.voiceTraits.contains(.isPersonalVoice) }
    }

    /// Asks once for his Personal Voice. True when it may be used.
    static func allowPersonalVoice() async -> Bool {
        let status = await AVSpeechSynthesizer.requestPersonalVoiceAuthorization()
        return status == .authorized
    }

    /// The best installed English voice, never a novelty voice and never a personal voice.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let home = AVSpeechSynthesisVoice.currentLanguageCode()
        let english = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        let best = english.max { a, b in
            (a.quality.rawValue, a.language == home ? 1 : 0) < (b.quality.rawValue, b.language == home ? 1 : 0)
        }
        if let best, best.quality != .default { return best }
        return AVSpeechSynthesisVoice(language: home.hasPrefix("en") ? home : "en-US") ?? best
    }

    /// The iPhone voice in words, for the probe.
    static func phoneVoiceSummary() -> String? {
        guard let voice = bestVoice() else { return nil }
        switch voice.quality {
        case .premium: return "\(voice.name), premium quality."
        case .enhanced: return "\(voice.name), enhanced quality."
        default: return "\(voice.name), basic quality. A better one is in Settings > Accessibility > Spoken Content > Voices."
        }
    }

    /// Sentences packed into pieces for the PC: the first alone so it is ready fast, the rest up to about 280 characters.
    static func pack(_ sentences: [String], limit: Int = 280) -> [String] {
        var out: [String] = []
        for sentence in sentences {
            if out.count > 1, let last = out.last, last.count + sentence.count + 1 < limit {
                out[out.count - 1] = last + " " + sentence
            } else {
                out.append(sentence)
            }
        }
        return out
    }

    private func playFromPC(_ pieces: [String], voice: String, line: LineClient, id: Int) async {
        guard let first = pieces.first else {
            finish(id)
            return
        }
        var ahead: Task<Data, any Error>? = Task { try await line.tts(text: first, voice: voice) }
        for index in pieces.indices {
            guard let fetch = ahead else { break }
            let audio: Data
            do {
                audio = try await fetch.value
            } catch {
                guard generation == id else { return }
                pcTask = nil
                fail("That voice is unavailable: \(plainSentence(error)) Nothing is spoken in its place.")
                return
            }
            if index + 1 < pieces.count {
                let next = pieces[index + 1]
                ahead = Task { try await line.tts(text: next, voice: voice) }   // the next piece renders while this one plays
            } else {
                ahead = nil
            }
            guard generation == id else {
                ahead?.cancel()
                return
            }
            do {
                let piece = try AVAudioPlayer(data: audio)
                player = piece
                _ = piece.play()
                // shortcut: waits out the piece's length instead of a delegate callback; move to AVAudioPlayerDelegate if pieces overlap or gap
                try await Task.sleep(for: .seconds(piece.duration))
            } catch is CancellationError {
                ahead?.cancel()
                return
            } catch {
                guard generation == id else { return }
                pcTask = nil
                fail("The PC's audio could not be played. Nothing is spoken in its place.")
                return
            }
        }
        finish(id)
    }

    private func finish(_ id: Int) {
        guard generation == id else { return }
        pcTask = nil
        player = nil
        speakingText = ""
        onFinished?()
    }

    private func fail(_ message: String) {
        speakingText = ""
        onFailed?(message)
    }

    private func ended(_ id: ObjectIdentifier) {
        guard pending.removeValue(forKey: id) != nil, pending.isEmpty else { return }
        speakingText = ""
        onFinished?()
    }

    // The delegate protocol is Sendable and its calls come on the synthesizer's own thread: copy an id and hop to the main actor.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(id) }
    }
}
