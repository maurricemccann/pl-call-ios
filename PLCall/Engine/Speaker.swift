import AVFoundation

/// Claude's voice. "phone" speaks on the iPhone, sentence by sentence with no gap. Any other id is a PC voice,
/// fetched piece by piece. A PC voice that fails says NOTHING: no other voice ever stands in for it.
@MainActor final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let phone = "phone"

    var onFinished: (() -> Void)?
    var onFailed: ((String) -> Void)?
    private(set) var speakingText = ""   // what is being said now, so the model can tell his voice from an echo

    private let synthesizer = AVSpeechSynthesizer()   // kept for the app's life: the system does not retain it
    private var pending: [ObjectIdentifier: AVSpeechUtterance] = [:]
    private var player: AVAudioPlayer?
    private var pcTask: Task<Void, Never>?
    private var generation = 0

    override init() {
        super.init()
        synthesizer.usesApplicationAudioSession = true   // the call's own session, so it plays inside the call
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { !pending.isEmpty || pcTask != nil }

    func speak(_ text: String, voiceID: String, line: LineClient?) {
        stop()
        let sentences = SpokenText.make(text).sentences
        speakingText = sentences.joined(separator: " ")
        if voiceID == Self.phone {
            let voice = Self.bestVoice()
            for sentence in sentences {
                let utterance = AVSpeechUtterance(string: sentence)
                utterance.voice = voice
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
