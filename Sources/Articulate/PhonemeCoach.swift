import AVFoundation
import CoreML
import Foundation

struct PhonemeContrast: Equatable, Sendable {
    var leading: [String] = [""]
    let target: [String]
    let alternative: [String]
    var trailing: [String] = [""]
    let correction: String
}

struct PracticeAudio: Sendable {
    let samples: [Float]
    let sampleRate: Double

    func forInference() throws -> [Float] {
        guard samples.count > 0, sampleRate > 0 else { throw PhonemeError.quietAudio }

        // Keep a little context around the speech and discard time spent reaching for Done.
        let blockSize = max(1, Int(sampleRate / 50))
        let blockLevels = stride(from: 0, to: samples.count, by: blockSize).map { start in
            let frames = samples[start..<min(start + blockSize, samples.count)]
            return sqrt(frames.reduce(Float.zero) { $0 + $1 * $1 } / Float(frames.count))
        }
        let peak = blockLevels.max() ?? 0
        let threshold = max(0.002, peak * 0.035)
        guard let first = blockLevels.firstIndex(where: { $0 >= threshold }),
              let last = blockLevels.lastIndex(where: { $0 >= threshold }) else {
            throw PhonemeError.quietAudio
        }
        guard last - first >= 5 else { throw PhonemeError.quietAudio }

        let start = max(0, first - 6) * blockSize
        let end = min(samples.count, (last + 7) * blockSize)
        var converted = try resample(samples[start..<end])
        guard converted.count <= 320_000 else { throw PhonemeError.longAudio }

        // The model accepts one to twenty seconds of normalized 16 kHz mono audio.
        if converted.count < 16_000 {
            converted.append(contentsOf: repeatElement(0, count: 16_000 - converted.count))
        }
        let mean = converted.reduce(0, +) / Float(converted.count)
        let variance = converted.reduce(Float.zero) { $0 + ($1 - mean) * ($1 - mean) }
            / Float(converted.count)
        let deviation = (variance + 1e-7).squareRoot()
        return converted.map { ($0 - mean) / deviation }
    }

    private func resample(_ frames: ArraySlice<Float>) throws -> [Float] {
        let modelRate = 16_000.0
        if sampleRate == modelRate { return Array(frames) }

        guard let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let targetFormat = AVAudioFormat(standardFormatWithSampleRate: modelRate, channels: 1),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
              let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(frames.count)),
              let inputChannel = input.floatChannelData?[0],
              let output = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(ceil(Double(frames.count) * modelRate / sampleRate)) + 32
              ),
              let outputChannel = output.floatChannelData?[0] else {
            throw PhonemeError.audioFormat
        }

        input.frameLength = input.frameCapacity
        for (index, sample) in frames.enumerated() {
            inputChannel[index] = sample
        }

        var providedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if providedInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            providedInput = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0 else { throw PhonemeError.audioFormat }
        return Array(UnsafeBufferPointer(start: outputChannel, count: Int(output.frameLength)))
    }
}

// The audio tap writes samples and the main actor takes a snapshot after removing the tap.
final class PracticeRecording: @unchecked Sendable {
    private let lock = NSLock()
    private let sampleRate: Double
    private let sampleLimit: Int
    private var samples: [Float] = []

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        sampleLimit = Int(sampleRate * 20)
        samples.reserveCapacity(sampleLimit)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let stride = buffer.stride

        lock.withLock {
            let count = min(Int(buffer.frameLength), sampleLimit - samples.count)
            if stride == 1 {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
            } else {
                for index in 0..<count {
                    samples.append(channel[index * stride])
                }
            }
        }
    }

    func snapshot() -> PracticeAudio {
        lock.withLock {
            PracticeAudio(samples: samples, sampleRate: sampleRate)
        }
    }
}

enum PhonemeError: LocalizedError {
    case modelUnavailable
    case quietAudio
    case longAudio
    case audioFormat
    case modelOutput
    case dictionaryUnavailable

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Install the HuPER model to enable the on-device sound check."
        case .quietAudio:
            "Speak the phrase once at a comfortable volume, then try again."
        case .longAudio:
            "Keep the attempt under twenty seconds and try again."
        case .audioFormat:
            "The audio couldn’t be prepared. Check your microphone and try again."
        case .modelOutput:
            "The sound check couldn’t read the model output. Try again."
        case .dictionaryUnavailable:
            "The British pronunciation dictionary is unavailable."
        }
    }
}

actor PhonemeCoach {
    static let shared = PhonemeCoach()

    nonisolated static var unavailableMessage: String? {
        guard #available(macOS 15, *) else { return "Modern RP listening requires macOS 15 or later." }
        return bundleModelDirectory == nil ? "The HuPER model is needed for Modern RP listening." : nil
    }

    private nonisolated static var bundleModelDirectory: URL? {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Models/HuPER"),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("HuPER.mlmodelc").path)
        else { return nil }
        return directory
    }

    private var model: HuPERModel?
    private var dictionary: BritishPronunciations?

    func preload() {
        guard model == nil, !Task.isCancelled, let directory = Self.bundleModelDirectory else { return }
        model = try? HuPERModel(directory: directory)
    }

    func evaluate(_ audio: PracticeAudio, drill: PracticeDrill) throws -> CoachingFeedback {
        guard let contrast = drill.phonemeContrast else { throw PhonemeError.modelUnavailable }
        let result = try evidence(for: audio).compare(contrast)
        switch result {
        case .target:
            return CoachingFeedback(kind: .recognized, title: "Target sound heard",
                                    detail: drill.check, transcript: "")
        case .alternative:
            return CoachingFeedback(kind: .adjust, title: "Try this adjustment",
                                    detail: contrast.correction, transcript: "")
        case .unclear:
            return CoachingFeedback(kind: .retry, title: "Say the prompt again",
                                    detail: "The sound was hard to pick out. \(drill.cue)", transcript: "")
        }
    }

    func evaluate(_ audio: PracticeAudio, sentence: PracticeSentence) throws -> SentenceFeedback {
        try Task.checkCancellation()
        if dictionary == nil {
            guard let url = Bundle.main.url(forResource: "britfone.main.3.0.1", withExtension: "csv",
                                            subdirectory: "Pronunciation"),
                  let loaded = try? BritishPronunciations(contentsOf: url) else {
                throw PhonemeError.dictionaryUnavailable
            }
            dictionary = loaded
        }
        guard let dictionary else { throw PhonemeError.dictionaryUnavailable }
        let evidence = try evidence(for: audio)
        try Task.checkCancellation()
        return SentenceCoach.evaluate(sentence, evidence: evidence, dictionary: dictionary)
    }

    private func evidence(for audio: PracticeAudio) throws -> PhoneEvidence {
        try Task.checkCancellation()
        guard let directory = Self.bundleModelDirectory else { throw PhonemeError.modelUnavailable }
        let samples = try audio.forInference()
        if model == nil {
            model = try HuPERModel(directory: directory)
        }
        guard let model else { throw PhonemeError.modelUnavailable }
        try Task.checkCancellation()
        return try model.evidence(for: samples)
    }
}

struct HuPERModel {
    private let model: MLModel
    private let tokens: [String: Int]
    private let blankTokens: Set<Int>

    init(directory: URL, computeUnits: MLComputeUnits = .cpuAndGPU) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        model = try MLModel(contentsOf: directory.appendingPathComponent("HuPER.mlmodelc"),
                            configuration: configuration)
        let decoder = JSONDecoder()
        let vocabulary = try decoder.decode([String: Int].self, from: Data(contentsOf: directory.appendingPathComponent("vocab.json")))
        let extras = try decoder.decode([String: Int].self, from: Data(contentsOf: directory.appendingPathComponent("added_tokens.json")))
        tokens = vocabulary.filter { !$0.key.hasPrefix("<") && $0.key != "|" }
        blankTokens = Set(vocabulary.values).subtracting(tokens.values).union(extras.values)
    }

    func evidence(for samples: [Float]) throws -> PhoneEvidence {
        let audio = try MLMultiArray(shape: [1, NSNumber(value: samples.count)], dataType: .float32)
        audio.withUnsafeMutableBufferPointer(ofType: Float.self) { input, _ in
            _ = input.update(from: samples)
        }
        let input = try MLDictionaryFeatureProvider(dictionary: ["audio": audio])
        let prediction = try model.prediction(from: input)
        guard let values = prediction.featureValue(for: "logprobs")?.multiArrayValue,
              values.dataType == .float32, values.shape.count == 3, values.shape[0].intValue == 1
        else { throw PhonemeError.modelOutput }

        let frameCount = values.shape[1].intValue
        let labelCount = values.shape[2].intValue
        guard frameCount > 0, Set(tokens.values).union(blankTokens) == Set(0..<labelCount) else {
            throw PhonemeError.modelOutput
        }

        let frameStride = values.strides[1].intValue
        let labelStride = values.strides[2].intValue
        let rows = values.withUnsafeBufferPointer(ofType: Float.self) { output in
            return (0..<frameCount).map { frame in
                (0..<labelCount).map { output[frame * frameStride + $0 * labelStride] }
            }
        }
        return PhoneEvidence(rows: rows, tokens: tokens, blankTokens: blankTokens)
    }
}

struct PhoneEvidence {
    enum Result: Equatable {
        case target
        case alternative
        case unclear
    }

    struct DecodedPhone {
        let label: String
        var frames: Range<Int>
    }

    let rows: [[Float]]
    let tokens: [String: Int]
    let blankTokens: Set<Int>

    private var blank: Int { blankTokens.min() ?? 0 }

    var decodedPhones: [DecodedPhone] {
        let labels = Dictionary(uniqueKeysWithValues: tokens.map { ($0.value, $0.key) })
        var previous = blank
        var phones: [DecodedPhone] = []
        for (frame, row) in rows.enumerated() {
            guard let top = row.indices.max(by: { row[$0] < row[$1] }) else { continue }
            let token = blankTokens.contains(top) ? blank : top
            if let label = labels[token] {
                if token == previous, let last = phones.indices.last {
                    phones[last].frames = phones[last].frames.lowerBound..<(frame + 1)
                } else {
                    phones.append(DecodedPhone(label: label, frames: frame..<(frame + 1)))
                }
            }
            previous = token
        }
        return phones
    }

    var transcription: String {
        decodedPhones.map(\.label).joined(separator: " ")
    }

    func slice(_ frames: Range<Int>) -> PhoneEvidence {
        PhoneEvidence(rows: Array(rows[frames]), tokens: tokens, blankTokens: blankTokens)
    }

    func compare(_ contrast: PhonemeContrast) -> Result {
        let heard = transcription.split(separator: " ")
        guard !heard.isEmpty else { return .unclear }
        let target = bestScores(for: contrast.target, contrast: contrast, heard: heard)
        let alternative = bestScores(for: contrast.alternative, contrast: contrast, heard: heard)
        let freeScore = score(heard.joined(separator: " "))

        // Allow small differences in the surrounding phrase. The highlighted phones must agree
        // with the unprompted decode and the expected phrase still needs a plausible alignment.
        let alignmentTolerance: Float = 7
        if target.supported >= freeScore - alignmentTolerance, target.supported - alternative.any >= 1.8 {
            return .target
        }
        if alternative.supported >= freeScore - alignmentTolerance, alternative.supported - target.any >= 2.3 {
            return .alternative
        }
        return .unclear
    }

    private func bestScores(for focuses: [String], contrast: PhonemeContrast, heard: [Substring])
        -> (any: Float, supported: Float) {
        var best: Float = -.infinity
        var supported: Float = -.infinity
        for leading in contrast.leading {
            let prefix = leading.split(separator: " ")
            for trailing in contrast.trailing {
                let suffix = trailing.split(separator: " ")
                for focus in focuses {
                    let sequence = [leading, focus, trailing].filter { !$0.isEmpty }.joined(separator: " ")
                    let likelihood = score(sequence)
                    best = max(best, likelihood)

                    let middle = focus.split(separator: " ")
                    let contextTolerance = prefix.count + suffix.count > 3 ? 2 : 1
                    guard heard.count >= middle.count else { continue }
                    for start in 0...(heard.count - middle.count) {
                        let end = start + middle.count
                        guard heard[start..<end].elementsEqual(middle) else { continue }
                        let edits = phoneEditDistance(heard[..<start], prefix) + phoneEditDistance(heard[end...], suffix)
                        if edits <= contextTolerance {
                            supported = max(supported, likelihood)
                        }
                    }
                }
            }
        }
        return (best, supported)
    }

    func score(_ sequence: String) -> Float {
        let symbols = sequence.split(separator: " ").map(String.init)
        let phones = symbols.compactMap { tokens[$0] }
        guard !phones.isEmpty, phones.count == symbols.count else { return -.infinity }

        // Forward CTC sums the likelihood of every timing that produces this phone sequence.
        let states = [blank] + phones.flatMap { [$0, blank] }
        var previous = Array(repeating: -Float.infinity, count: states.count)
        var next = previous
        previous[0] = 0

        for row in rows {
            let blankProbability = blankTokens.reduce(-Float.infinity) { logAdd($0, row[$1]) }
            for (index, token) in states.enumerated() {
                var total = previous[index]
                if index > 0 { total = logAdd(total, previous[index - 1]) }
                if index > 1, token != blank, token != states[index - 2] {
                    total = logAdd(total, previous[index - 2])
                }
                next[index] = total + (token == blank ? blankProbability : row[token])
            }
            swap(&previous, &next)
        }
        return logAdd(previous[states.count - 1], previous[states.count - 2])
    }

    private func logAdd(_ first: Float, _ second: Float) -> Float {
        let larger = max(first, second)
        if larger == -.infinity { return larger }
        return larger + log1p(exp(min(first, second) - larger))
    }
}

func phoneEditDistance<Phone: Equatable>(_ observed: ArraySlice<Phone>, _ expected: [Phone]) -> Int {
    var previous = Array(0...expected.count)
    for (position, phone) in observed.enumerated() {
        var next = [position + 1]
        for (index, expectedPhone) in expected.enumerated() {
            next.append(min(next[index] + 1, previous[index + 1] + 1,
                            previous[index] + (phone == expectedPhone ? 0 : 1)))
        }
        previous = next
    }
    return previous[expected.count]
}
