import AVFoundation
import Speech

struct HeardWord: Sendable {
    let key: String
    let seconds: Range<Double>?
}

enum SentenceTiming {
    enum TimingError: Error { case unavailable }

    // A word can be timed only when its match is required and unique across optimal alignments.
    static func match(_ expected: [String], to heard: [HeardWord]) -> [Int: Range<Double>] {
        let n = expected.count
        let m = heard.count
        guard n > 0, m > 0 else { return [:] }
        let blank = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        var prefixes = blank
        var suffixes = blank
        for i in 0..<n {
            for j in 0..<m {
                prefixes[i + 1][j + 1] = expected[i] == heard[j].key
                    ? prefixes[i][j] + 1 : max(prefixes[i][j + 1], prefixes[i + 1][j])
            }
        }
        for i in (0..<n).reversed() {
            for j in (0..<m).reversed() {
                suffixes[i][j] = expected[i] == heard[j].key
                    ? suffixes[i + 1][j + 1] + 1 : max(suffixes[i + 1][j], suffixes[i][j + 1])
            }
        }
        let matched = prefixes[n][m]
        guard matched * 2 >= n else { return [:] }
        var timings: [Int: Range<Double>] = [:]
        for i in 0..<n {
            let canSkip = (0...m).contains { prefixes[i][$0] + suffixes[i + 1][$0] == matched }
            guard !canSkip else { continue }
            let candidates = (0..<m).filter {
                expected[i] == heard[$0].key && prefixes[i][$0] + 1 + suffixes[i + 1][$0 + 1] == matched
            }
            if candidates.count == 1, let j = candidates.first, let timing = heard[j].seconds {
                timings[i] = timing
            }
        }
        return timings
    }

    static func locate(_ sentence: PracticeSentence, in audio: PracticeAudio,
                       preparing: @Sendable () async -> Void) async throws -> [Int: Range<Double>] {
        guard #available(macOS 26.0, *), SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-GB"))
        else { throw TimingError.unavailable }

        let transcriber = SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )
        let modules = [transcriber]
        if await AssetInventory.status(forModules: modules) != .installed,
           let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            await preparing()
            try await request.downloadAndInstall()
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules),
              let buffer = audio.converted(to: format) else { throw TimingError.unavailable }
        let input = AnalyzerInput(buffer: buffer)
        let stream = AsyncStream<AnalyzerInput> { continuation in
            continuation.yield(input)
            continuation.finish()
        }
        let analyzer = SpeechAnalyzer(modules: modules)
        async let heard = readResults(transcriber)
        do {
            if let last = try await analyzer.analyzeSequence(stream) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return match(sentence.words.map(\.key), to: try await heard)
        } catch {
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    @available(macOS 26.0, *)
    private static func readResults(_ transcriber: SpeechTranscriber) async throws -> [HeardWord] {
        var words: [HeardWord] = []
        for try await result in transcriber.results where result.isFinal {
            words.append(contentsOf: timedWords(in: result.text))
        }
        return words
    }

    @available(macOS 26.0, *)
    static func timedWords(in text: AttributedString) -> [HeardWord] {
        let string = String(text.characters)
        let words = PracticeSentence.words(in: string)
        let ranges = words.map { Range($0.range, in: text) }
        let runs = text.runs.compactMap { run -> (Range<AttributedString.Index>, Range<Double>?)? in
            guard let time = run.audioTimeRange, time.start.seconds.isFinite, time.end.seconds.isFinite,
                  time.start.seconds >= 0, time.start.seconds < time.end.seconds else { return nil }
            let usable = run.transcriptionConfidence.map { $0 >= 0.35 } ?? true
            return (run.range, usable ? time.start.seconds..<time.end.seconds : nil)
        }

        return words.indices.map { index in
            let key = words[index].key
            guard let range = ranges[index] else { return HeardWord(key: key, seconds: nil) }
            let overlaps = runs.filter { $0.0.overlaps(range) }
            guard !overlaps.isEmpty, overlaps.allSatisfy({ run, timing in
                timing != nil && ranges.compactMap { $0 }.filter { $0.overlaps(run) }.count == 1
            }) else { return HeardWord(key: key, seconds: nil) }
            let times = overlaps.compactMap { $0.1 }
            let start = times.map(\.lowerBound).min()!
            let end = times.map(\.upperBound).max()!
            return HeardWord(key: key, seconds: start..<end)
        }
    }
}
