import AVFoundation
import CoreMedia
import Speech
import os

/// An error that already reads as a plain sentence for the status line.
struct PlainError: Error, Sendable {
    let message: String
}

/// The microphone: an engine tap with voice processing (echo cancellation), converted to the analyzer's format.
/// The engine and its buffers never leave this class; only `AnalyzerInput` and numbers go out.
/// Unchecked Sendable: start/stop are called from the SpeechListener actor only, and the tap touches only the lock.
final class MicTap: @unchecked Sendable {
    private struct Clock: Sendable {
        var accepting = true
        var frames: Int64 = 0
        var lastLoud: Double = 0   // when the mic last heard something as loud as speech
    }

    private let engine = AVAudioEngine()
    private let clock = OSAllocatedUnfairLock(initialState: Clock())
    private var target: AVAudioFormat?
    private var onInput: (@Sendable (AnalyzerInput) -> Void)?
    private var onLevel: (@Sendable (Double) -> Void)?

    /// Downloads the speech model when it is missing. Needs the network once.
    static func install(_ transcriber: SpeechTranscriber) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    /// Finds the format the analyzer wants and restarts the audio clock at zero.
    func prepare(for transcriber: SpeechTranscriber) async throws {
        try await Self.install(transcriber)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw PlainError(message: "The speech model is not installed yet. Connect to the internet once and call again.")
        }
        target = format
        clock.withLock { $0.frames = 0 }
    }

    func start(onInput: @escaping @Sendable (AnalyzerInput) -> Void, onLevel: @escaping @Sendable (Double) -> Void) throws {
        guard let target else { throw PlainError(message: "The speech model is not ready.") }
        stop()
        self.onInput = onInput
        self.onLevel = onLevel
        let input = engine.inputNode
        // enabling it again can post a configuration change, which would restart the mic in a loop
        if !input.isVoiceProcessingEnabled { try input.setVoiceProcessingEnabled(true) }
        // gives the voice-processing I/O unit an output path in the graph
        _ = engine.mainMixerNode
        // Voice processing ducks other audio by default, which would quieten Claude's own voice.
        let level = UserDefaults.standard.integer(forKey: "plcall.duckLevel")   // 0 barely, 1 some, 2 a lot
        input.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
            enableAdvancedDucking: level > 0, duckingLevel: level == 2 ? .max : level == 1 ? .mid : .min)
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0, let converter = AVAudioConverter(from: source, to: target) else {
            throw PlainError(message: "The microphone is not available.")
        }
        let scale = CMTimeScale(target.sampleRate)
        let clock = self.clock
        // This closure is built in a nonisolated method on purpose: the system calls it on an audio thread.
        input.installTap(onBus: 0, bufferSize: 4096, format: source) { buffer, _ in
            let level = MicTap.level(of: buffer)
            onLevel(level)
            if level > 0.35 { clock.withLock { $0.lastLoud = CFAbsoluteTimeGetCurrent() } }
            guard let converted = MicTap.convert(buffer, with: converter, to: target) else { return }
            let frames = Int64(converted.frameLength)
            let start = clock.withLock { state -> CMTime? in
                guard state.accepting else { return nil }
                let time = CMTime(value: state.frames, timescale: scale)
                state.frames += frames
                return time
            }
            if let start { onInput(AnalyzerInput(buffer: converted, bufferStartTime: start)) }
        }
        engine.prepare()
        try engine.start()
    }

    /// After a route change (AirPods in or out) the input format changes, so the tap is rebuilt.
    func restart() throws {
        guard let onInput, let onLevel else { return }
        try start(onInput: onInput, onLevel: onLevel)
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
    }

    var isRunning: Bool { engine.isRunning }

    func forget() {
        stop()
        onInput = nil
        onLevel = nil
    }

    /// Muted at the source (the AirPods press, or the screen). While muted, speech is reported so the app can say so.
    func setMuted(_ on: Bool, onSpeech: (@Sendable () -> Void)?) {
        let input = engine.inputNode
        input.isVoiceProcessingInputMuted = on
        if on, let onSpeech {
            _ = input.setMutedSpeechActivityEventListener { event in
                if event == .started { onSpeech() }
            }
        } else {
            _ = input.setMutedSpeechActivityEventListener(nil)
        }
    }

    /// Closed = buffers are dropped before the analyzer (PUSH mode between presses). The level still reports.
    func setAccepting(_ on: Bool) {
        clock.withLock { $0.accepting = on }
    }

    /// Seconds since the mic last heard something as loud as speech.
    func quietSeconds() -> Double {
        CFAbsoluteTimeGetCurrent() - clock.withLock { $0.lastLoud }
    }

    /// Where the analyzer's timeline is now: everything before this has been handed over.
    func now() -> CMTime {
        let scale = CMTimeScale(target?.sampleRate ?? 16_000)
        let frames = clock.withLock { $0.frames }
        return CMTime(value: frames, timescale: scale)
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0, buffer.format.sampleRate > 0 else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
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
        return out
    }

    /// Loudness 0...1 from the buffer's RMS: about -50 dB (quiet room) to -10 dB (close speech).
    private static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        let samples = channels[0]
        var sum: Float = 0
        for index in 0..<count { sum += samples[index] * samples[index] }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        return Double(max(0, min(1, (decibels + 50) / 40)))
    }
}

/// The ears: on-device transcription for the whole call, and the pause that ends his turn.
actor SpeechListener {
    enum Event: Sendable {
        case level(Double)       // mic loudness 0...1
        case hearing(String)     // what he has said so far in this turn
        case turn(String)        // a pause ended his turn: the final words
        case failed(String)
    }

    nonisolated let events: AsyncStream<Event>
    private let out: AsyncStream<Event>.Continuation
    private let mic = MicTap()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    private var finalized = ""
    private var volatile = ""
    private var consumedThrough = CMTime.zero   // results that end before this were already used or thrown away
    private var endOfTurn = 0.9
    private var endOfTurnInterim = 1.6

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .bufferingNewest(64))
        events = stream
        out = continuation
    }

    /// Whether this iPhone can transcribe on the device, and why not.
    static func check() async -> (ready: Bool, detail: String) {
        guard SpeechTranscriber.isAvailable else { return (false, "This iPhone cannot transcribe speech on the device.") }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            return (false, "English is not a supported transcription language here.")
        }
        do {
            try await MicTap.install(SpeechTranscriber(locale: locale, preset: .progressiveTranscription))
        } catch {
            return (false, "The speech model could not be installed: \(error.localizedDescription)")
        }
        return (true, "On-device English transcription is ready.")
    }

    /// Call once the audio session is active. Calling it again while running only rebuilds the mic tap.
    /// Names the ears should recognise (Claude, Psyclaupse, his tools and pieces). Applied when the analyzer starts.
    private var words: [String] = []

    func setWords(_ list: [String]) {
        words = Array(list.prefix(100))
    }

    func start(endOfTurn: Double, endOfTurnInterim: Double) async throws {
        self.endOfTurn = endOfTurn
        self.endOfTurnInterim = endOfTurnInterim
        if analyzer != nil {
            try mic.restart()
            return
        }
        guard SpeechTranscriber.isAvailable else { throw PlainError(message: "This iPhone cannot transcribe speech on the device.") }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            throw PlainError(message: "English is not a supported transcription language here.")
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults],
                                            attributeOptions: [.audioTimeRange])
        try await mic.prepare(for: transcriber)
        let (inputs, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let fresh = SpeechAnalyzer(modules: [transcriber])
        try await fresh.start(inputSequence: inputs)
        if analyzer != nil {
            // A second start ran while this one was waiting: keep the first.
            builder.finish()
            await fresh.cancelAndFinishNow()
            return
        }
        analyzer = fresh
        input = builder
        if !words.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = words
            try? await fresh.setContext(context)   // a hint: if this transcriber ignores it, nothing breaks
        }
        finalized = ""
        volatile = ""
        consumedThrough = .zero
        resultsTask = Task.detached { [weak self] in
            do {
                for try await result in transcriber.results {
                    await self?.took(String(result.text.characters), isFinal: result.isFinal, end: result.range.end)
                }
            } catch {
                // a stop cancels this task; anything else (a CancellationError included) means the analyzer finished on an error
                if Task.isCancelled { return }
                await self?.failed("Speech recognition stopped: \(error.localizedDescription)")
            }
        }
        let out = self.out
        try mic.start(onInput: { input in _ = builder.yield(input) }, onLevel: { level in _ = out.yield(.level(level)) })
    }

    func stop() async {
        pauseTask?.cancel()
        pauseTask = nil
        mic.forget()
        input?.finish()
        input = nil
        resultsTask?.cancel()
        resultsTask = nil
        if let running = analyzer {
            analyzer = nil
            await running.cancelAndFinishNow()
        }
        finalized = ""
        volatile = ""
    }

    /// `onlyIfStopped`: an engine configuration change stops the engine; one that left it running needs nothing.
    func restartMic(onlyIfStopped: Bool = false) {
        guard analyzer != nil else { return }
        if onlyIfStopped, mic.isRunning { return }
        do { try mic.restart() } catch { report("The microphone did not come back: \(Self.words(error))") }
    }

    nonisolated func setAccepting(_ on: Bool) {
        mic.setAccepting(on)
    }

    nonisolated func setMuted(_ on: Bool, onSpeech: (@Sendable () -> Void)?) {
        mic.setMuted(on, onSpeech: onSpeech)
    }

    /// Throws away what was heard so far (Claude's own voice, or a turn that was cut short).
    func discard() async {
        pauseTask?.cancel()
        finalized = ""
        volatile = ""
        consumedThrough = mic.now()
        try? await analyzer?.finalize(through: nil)
    }

    /// A result is dropped only when ALL of it lies before the cut. Judging by its start threw away the first words
    /// of a turn whenever the transcriber's segment had begun before the cut (build 4: clipped sentence starts).
    private func took(_ text: String, isFinal: Bool, end: CMTime) {
        guard CMTimeCompare(end, consumedThrough) > 0 else { return }
        let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            finalized = Self.join(finalized, piece)
            volatile = ""
        } else {
            volatile = piece
        }
        let shown = Self.join(finalized, volatile)
        guard !shown.isEmpty else { return }
        out.yield(.hearing(shown))
        let wait = volatile.isEmpty ? endOfTurn : endOfTurnInterim   // still-changing words get a longer pause
        pauseTask?.cancel()
        pauseTask = Task { [weak self] in
            // The words stopped changing. The turn ends only once the mic is quiet too, so a breath or a slow
            // transcriber does not cut him off. Steady noise (music) cannot hold it open past three pauses.
            var waited = 0.0
            var next = wait
            while true {
                try? await Task.sleep(for: .seconds(next))
                guard !Task.isCancelled, let self else { return }
                waited += next
                if await self.quiet() >= 0.7 || waited >= wait * 3 {
                    await self.endTurn()
                    return
                }
                next = 0.3
            }
        }
    }

    private func quiet() -> Double {
        mic.quietSeconds()
    }

    private func endTurn() async {
        let text = Self.join(finalized, volatile)
        finalized = ""
        volatile = ""
        consumedThrough = mic.now()
        if !text.isEmpty { out.yield(.turn(text)) }
        try? await analyzer?.finalize(through: nil)   // the late final version of these words is then dropped by `took`
    }

    private func report(_ message: String) {
        out.yield(.failed(message))
    }

    /// After an error the analyzer is finished for good: drop it and the mic, so the next `start` builds both fresh.
    private func failed(_ message: String) async {
        pauseTask?.cancel()
        pauseTask = nil
        mic.forget()
        input?.finish()
        input = nil
        resultsTask = nil
        if let dead = analyzer {
            analyzer = nil
            await dead.cancelAndFinishNow()
        }
        finalized = ""
        volatile = ""
        report(message)
    }

    private static func join(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        let first = a.split(separator: " ")
        let second = b.split(separator: " ")
        var overlap = 0
        var size = min(first.count, second.count)
        while size >= 2 {
            if zip(first.suffix(size), second.prefix(size)).allSatisfy({ bare($0) == bare($1) }) {
                overlap = size
                break
            }
            size -= 1
        }
        if overlap == second.count { return a }
        return a + " " + second.dropFirst(overlap).joined(separator: " ")
    }

    private static func bare(_ word: Substring) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func words(_ error: any Error) -> String {
        (error as? PlainError)?.message ?? error.localizedDescription
    }
}
