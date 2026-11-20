import Accelerate
import AVFoundation
import Combine

struct PracticeAudio: Sendable {
    let samples: [Float]
    let sampleRate: Double

    func clip(_ seconds: Range<Double>) -> PracticeAudio? {
        guard sampleRate.isFinite, sampleRate > 0 else { return nil }
        let duration = Double(samples.count) / sampleRate
        guard seconds.lowerBound >= 0, seconds.upperBound.isFinite,
              seconds.lowerBound < duration, seconds.upperBound <= duration + 0.1,
              (0.07...3).contains(seconds.upperBound - seconds.lowerBound) else { return nil }
        let start = Int(seconds.lowerBound * sampleRate)
        let stop = min(samples.count, Int(ceil(seconds.upperBound * sampleRate)))
        let clip = samples[start..<stop]
        guard clip.contains(where: { abs($0) >= 0.005 }) else { return nil }
        return PracticeAudio(samples: Array(clip), sampleRate: sampleRate)
    }

    func converted(to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty, sampleRate.isFinite, sampleRate > 0,
              let inputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: UInt32(samples.count)),
              let channel = input.floatChannelData?[0] else { return nil }
        input.frameLength = input.frameCapacity
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
        guard inputFormat != format else { return input }
        guard let converter = AVAudioConverter(from: inputFormat, to: format),
              let output = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: UInt32(ceil(Double(samples.count) * format.sampleRate / sampleRate)) + 512
              ) else { return nil }

        var suppliedInput = false
        let result = converter.convert(to: output, error: nil) { _, status in
            if suppliedInput {
                status.pointee = .endOfStream
                return nil
            }
            suppliedInput = true
            status.pointee = .haveData
            return input
        }
        return result == .error ? nil : output
    }

    var wav: Data {
        let frequency = UInt32(sampleRate.rounded())
        let size = UInt32(samples.count * 2)
        var data = Data(capacity: 44 + Int(size))
        data.append(contentsOf: "RIFF".utf8)
        data.appendLE(size + 36)
        data.append(contentsOf: "WAVEfmt ".utf8)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(1))
        data.appendLE(frequency)
        data.appendLE(frequency * 2)
        data.appendLE(UInt16(2))
        data.appendLE(UInt16(16))
        data.append(contentsOf: "data".utf8)
        data.appendLE(size)
        for sample in samples {
            data.appendLE(Int16((min(1, max(-1, sample)) * 32767).rounded()))
        }
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}

@MainActor
final class CoachSession: ObservableObject {
    static let starterText = "The red bus went past the glass shop."
    static let maxWords = 48

    struct Take: Sendable {
        struct WordSample: Sendable {
            let audio: PracticeAudio
            let vowel: VowelReading?
        }

        let audio: PracticeAudio
        let words: [Int: WordSample]
        let contour: VoiceContour

        static func analyse(_ audio: PracticeAudio, for prompt: PracticeSentence,
                            frames: [VoiceFrame], isReference: Bool = false,
                            preparing: @Sendable () async -> Void) async -> Take {
            var timings: [Int: Range<Double>]?
            let clips: [Int: PracticeAudio]
            if prompt.words.count == 1 {
                clips = [0: audio]
            } else {
                timings = try? await SentenceTiming.locate(prompt, in: audio, preparing: preparing)
                clips = (timings ?? [:]).compactMapValues(audio.clip)
            }

            let guide = BritishVowelGuide.bundled
            var results: [Int: WordSample] = [:]
            for (index, clip) in clips where prompt.words.indices.contains(index) {
                if Task.isCancelled { break }
                let measurable = guide[prompt.words[index].key]?.supportsMeasurement == true
                let vowel = measurable ? VowelAnalysis.measure(clip, singleVowel: prompt.words.count > 1) : nil
                results[index] = WordSample(audio: clip, vowel: vowel)
            }
            return Take(audio: audio, words: results, contour: .make(frames, words: prompt.words, timings: timings, fillMissing: isReference))
        }

        func matches(_ reference: Take) -> [Int: VowelMatch] {
            var result: [Int: VowelMatch] = [:]
            for (index, word) in words {
                if let vowel = word.vowel, let target = reference.words[index]?.vowel,
                   let match = VowelMatch.compare(vowel, with: target) {
                    result[index] = match
                }
            }
            return result
        }
    }

    enum Activity: Equatable {
        case ready, requesting, recording, synthesising, analysing, preparingTiming
    }

    enum Playback {
        case emma, latest, previous, emmaWord, myWord, comparePrevious, compareLatest

        var isComparison: Bool { self == .comparePrevious || self == .compareLatest }

        var status: String {
            switch self {
            case .emma: return "Listening to Emma…"
            case .latest: return "Playing your latest take…"
            case .previous: return "Playing your previous take…"
            case .emmaWord: return "Playing Emma’s word…"
            case .myWord: return "Playing your word…"
            case .comparePrevious: return "Comparing · Previous take"
            case .compareLatest: return "Comparing · Latest take"
            }
        }
    }

    struct WordCoaching {
        let word: String
        let observation: String?
        let tip: String?
        let emmaAudio: PracticeAudio?
        let myAudio: PracticeAudio?
    }

    @Published private(set) var draft = CoachSession.starterText
    @Published private(set) var activity = Activity.ready
    @Published private(set) var playback: Playback?
    @Published private(set) var notice: String?
    @Published private(set) var marks: [Int: VowelMatch] = [:]
    @Published private(set) var prosodyCues: [Int: String] = [:]
    @Published private(set) var selectedWord: Int?
    @Published private(set) var latest: Take?
    @Published private(set) var previous: Take?

    @Published private(set) var baseline: VoiceContour?
    @Published private(set) var inputLevel: Float = 0
    @Published private(set) var heardReference = false
    private var reference: Take?
    private var autoHear: Task<Void, Never>?
    private var meterUpdate: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var capture: Capture?
    private var recordingTimer: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var playbackTimer: Task<Void, Never>?

    var prompt: PracticeSentence { PracticeSentence(draft) }
    var canHear: Bool { !prompt.words.isEmpty }
    var withinLimit: Bool { (1...Self.maxWords).contains(prompt.words.count) }
    var canEdit: Bool { activity == .ready || preparingReference }
    private var preparingReference: Bool { activity == .synthesising || (activity == .preparingTiming && reference == nil) }
    var canRecord: Bool { withinLimit && heardReference && reference != nil }

    var selectedCoaching: WordCoaching? {
        let words = prompt.words
        guard let index = selectedWord, words.indices.contains(index) else { return nil }
        let word = words[index]
        let guide = BritishVowelGuide.bundled[word.key]
        var observation: String?
        var tip = guide?.cue
        if let cue = prosodyCues[index], marks[index] != .focus {
            observation = cue
            tip = nil
        } else if let match = marks[index] {
            observation = match == .close
                ? "Your vowel sounded close to Emma’s."
                : "Your vowel sounded different from Emma’s."
        }
        return WordCoaching(word: word.text, observation: observation, tip: tip,
                            emmaAudio: words.count > 1 ? reference?.words[index]?.audio : nil,
                            myAudio: words.count > 1 ? latest?.words[index]?.audio : nil)
    }

    func edit(_ text: String) {
        guard canEdit, text != draft else { return }
        let oldText = prompt.text
        draft = text
        guard prompt.text != oldText else { return }
        autoHear?.cancel()
        operation?.cancel()
        activity = .ready
        stopPlayback()
        baseline = nil
        heardReference = false
        reference = nil
        latest = nil
        previous = nil
        marks = [:]
        prosodyCues = [:]
        selectedWord = nil
        notice = nil
        if withinLimit {
            autoHear = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1300))
                if !Task.isCancelled { self?.toggleHear() }
            }
        }
    }

    func selectWord(_ index: Int) {
        guard activity == .ready, prompt.words.indices.contains(index) else { return }
        if index != selectedWord, playback == .emmaWord || playback == .myWord { stopPlayback() }
        selectedWord = index
        notice = nil
    }

    func toggleHear() {
        autoHear?.cancel()
        if playback == .emma {
            stopPlayback()
            return
        }
        guard activity == .ready, canHear else { return }
        stopPlayback()
        notice = nil
        if let reference {
            play(reference.audio, source: .emma)
            return
        }

        activity = .synthesising
        let prompt = prompt
        operation = Task { [weak self] in
            do {
                let audio = try await ReferenceVoice.generate(prompt.text)
                guard let self, !Task.isCancelled else { return }
                guard self.withinLimit else {
                    self.activity = .ready
                    self.play(audio, source: .emma)
                    return
                }
                let frames = await Self.frames(for: audio)
                guard !Task.isCancelled else { return }
                self.baseline = .make(frames, words: prompt.words, timings: nil, fillMissing: true)
                self.play(audio, source: .emma)
                let reference = await Take.analyse(audio, for: prompt, frames: frames, isReference: true) { [weak self] in
                    await self?.showSpeechSetup()
                }
                guard !Task.isCancelled else { return }
                self.reference = reference
                self.baseline = reference.contour
                self.activity = .ready
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.activity = .ready
                self.notice = "Emma’s voice couldn’t play. Select Hear Emma to try again."
            }
        }
    }

    func replay(_ audio: PracticeAudio, source: Playback) {
        guard activity == .ready else { return }
        stopPlayback()
        notice = nil
        play(audio, source: source)
    }

    func compareTakes() {
        guard activity == .ready, let previous, let latest else { return }
        if playback?.isComparison == true {
            stopPlayback()
            return
        }
        stopPlayback()
        notice = nil
        play(previous.audio, source: .comparePrevious, followedBy: latest.audio)
    }

    func toggleRecording() {
        switch activity {
        case .recording:
            finishRecording()
        case .ready:
            guard canRecord else { return }
            stopPlayback()
            notice = nil
            activity = .requesting
            operation = Task { [weak self] in await self?.startRecording() }
        case .requesting, .synthesising, .analysing, .preparingTiming:
            break
        }
    }

    func endPractice() {
        autoHear?.cancel()
        meterUpdate?.cancel()
        inputLevel = 0
        operation?.cancel()
        recordingTimer?.cancel()
        recordingTimer = nil
        stopPlayback()
        capture?.stop()
        capture = nil
        activity = .ready
    }

    private func startRecording() async {
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard !Task.isCancelled else { return }
        guard allowed else {
            activity = .ready
            notice = "Allow Vocal Coach to use the microphone in System Settings."
            return
        }
        do {
            let limit = prompt.words.count == 1 ? 6 : 32
            let recorder = try Capture(limit: limit)
            capture = recorder
            inputLevel = 0
            meterUpdate = Task { [weak self] in
                while !Task.isCancelled {
                    self?.inputLevel = recorder.inputLevel
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
            activity = .recording
            recordingTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(limit))
                if !Task.isCancelled { self?.finishRecording() }
            }
        } catch {
            activity = .ready
            notice = "Microphone unavailable. Check the input in System Settings."
        }
    }

    private nonisolated static func frames(for audio: PracticeAudio) async -> [VoiceFrame] {
        VoiceFrame.measure(audio)
    }

    private func finishRecording() {
        guard let capture, let reference else { return }
        meterUpdate?.cancel()
        meterUpdate = nil
        inputLevel = 0
        recordingTimer?.cancel()
        recordingTimer = nil
        let audio = capture.finish()
        self.capture = nil
        guard !audio.samples.isEmpty else {
            activity = .ready
            notice = "No audio came through. Try recording again."
            return
        }

        activity = .analysing
        let prompt = prompt
        let preparing: @Sendable () async -> Void = { [weak self] in await self?.showSpeechSetup() }
        operation = Task { [weak self] in
            let frames = await Self.frames(for: audio)
            let measured = await Take.analyse(audio, for: prompt, frames: frames, preparing: preparing)
            guard let self, !Task.isCancelled else { return }
            self.previous = self.latest
            self.latest = measured
            let marks = measured.matches(reference)
            self.marks = marks
            self.prosodyCues = measured.contour.practiceCues(comparedTo: reference.contour)
            self.selectedWord = marks.keys.sorted().first { marks[$0] == .focus }
                ?? self.prosodyCues.keys.min()
                ?? marks.keys.sorted().first { marks[$0] == .someDifference }
                ?? (prompt.words.count == 1 ? 0 : nil)
            self.activity = .ready
        }
    }

    private func showSpeechSetup() { if !Task.isCancelled { activity = .preparingTiming } }

    private func play(_ audio: PracticeAudio, source: Playback, followedBy next: PracticeAudio? = nil) {
        do {
            let player = try AVAudioPlayer(data: audio.wav)
            guard player.play() else { throw AudioError.unavailable }
            self.player = player
            playback = source
            playbackTimer = Task { [weak self] in
                while !Task.isCancelled && player.isPlaying {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard !Task.isCancelled, let self else { return }
                if let next {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    self.play(next, source: .compareLatest)
                } else {
                    if source == .emma { self.heardReference = true }
                    self.stopPlayback()
                }
            }
        } catch {
            stopPlayback()
            notice = "Audio couldn’t play. Check the sound output in System Settings."
        }
    }

    private func stopPlayback() {
        playbackTimer?.cancel()
        playbackTimer = nil
        player?.stop()
        player = nil
        playback = nil
    }
}

private enum AudioError: Error {
    case unavailable
}

private final class Capture {
    private let engine = AVAudioEngine()
    private let buffer: SampleBuffer
    private let sampleRate: Double

    init(limit: Int) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioError.unavailable }
        sampleRate = format.sampleRate
        let buffer = SampleBuffer(capacity: Int(Double(limit) * format.sampleRate))
        self.buffer = buffer
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { audio, _ in
            buffer.append(audio)
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    var inputLevel: Float { buffer.inputLevel }

    func finish() -> PracticeAudio {
        stop()
        return PracticeAudio(samples: buffer.snapshot(), sampleRate: sampleRate)
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }
}

// The audio tap writes samples while the UI reads the most recent input level.
private final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var samples: [Float] = []
    private var level: Float = 0

    var inputLevel: Float {
        lock.lock()
        defer { lock.unlock() }
        return level
    }

    init(capacity: Int) {
        self.capacity = capacity
        samples.reserveCapacity(capacity)
    }

    func append(_ audio: AVAudioPCMBuffer) {
        guard let channel = audio.floatChannelData?[0] else { return }
        lock.lock()
        defer { lock.unlock() }
        let count = min(Int(audio.frameLength), capacity - samples.count)
        guard count > 0 else { return }
        var rms: Float = 0
        vDSP_rmsqv(channel, vDSP_Stride(audio.stride), &rms, vDSP_Length(count))
        level = min(1, max(0, (20 * log10(max(rms, 0.000001)) + 60) / 60))
        if audio.stride == 1 {
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        } else {
            for frame in 0..<count {
                samples.append(channel[frame * audio.stride])
            }
        }
    }

    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}
