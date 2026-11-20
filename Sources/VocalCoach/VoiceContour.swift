import Accelerate
import Foundation

/// Frame times are in the original recording, including leading silence.
struct VoiceFrame: Sendable {
    let time: Double
    let pitch: Float?
    let decibels: Float

    static func window(_ rate: Double) -> Int { max(1, Int(rate * 0.04)) }
    static func hop(_ rate: Double) -> Int { max(1, Int(rate * 0.02)) }

    static func measure(_ audio: PracticeAudio) -> [Self] {
        let rate = audio.sampleRate
        let window = window(rate)
        guard audio.samples.count >= window else { return [] }
        // Average adjacent samples before decimation. Speech pitch needs only a low bandwidth.
        let factor = max(1, Int(rate / 4_000))
        let count = window / factor
        let analysisRate = Float(rate) / Float(factor)
        let minLag = max(2, Int(analysisRate / 500))
        let maxLag = min(count / 2, Int(analysisRate / 60))
        guard minLag < maxLag else { return [] }
        var signal = [Float](repeating: 0, count: count)
        var scores = [Float](repeating: 0, count: maxLag + 1)
        return stride(from: 0, through: audio.samples.count - window, by: hop(rate)).map { start in
            for i in signal.indices {
                let base = start + i * factor
                var sum: Float = 0
                for j in base..<(base + factor) { sum += audio.samples[j] }
                signal[i] = sum / Float(factor)
            }
            let mean = vDSP.mean(signal)
            vDSP.add(-mean, signal, result: &signal)
            let db = 20 * log10(max(0.000001, vDSP.rootMeanSquare(signal)))
            var hz: Float?
            if db > -55 {
                signal.withUnsafeBufferPointer { buffer in
                    let first = buffer.baseAddress!
                    for lag in minLag...maxLag {
                        let n = vDSP_Length(count - lag)
                        let next = first + lag
                        var cross: Float = 0, left: Float = 0, right: Float = 0
                        vDSP_dotpr(first, 1, next, 1, &cross, n)
                        vDSP_dotpr(first, 1, first, 1, &left, n)
                        vDSP_dotpr(next, 1, next, 1, &right, n)
                        scores[lag] = cross / max(1e-12, sqrt(left * right))
                    }
                }
                // Choose the earliest strong peak to avoid following octave subharmonics.
                let threshold = max(0.72, (scores.max() ?? 0) * 0.93)
                if let lag = ((minLag + 1)..<maxLag).first(where: {
                    scores[$0] >= threshold && scores[$0] >= scores[$0 - 1] && scores[$0] > scores[$0 + 1]
                }) {
                    hz = analysisRate / Float(lag)
                }
            }
            return Self(time: Double(start + window / 2) / rate, pitch: hz, decibels: db)
        }
    }
}

struct ContourPoint: Equatable, Sendable {
    let position: Double
    let semitones: Float?
    let emphasis: Float
}

struct VoiceContour: Sendable {
    typealias Traces = [Int: [ContourPoint]]
    let ranges: [Int: Range<Double>]
    let traces: Traces
    let estimated: Bool

    static func speechSpan(_ frames: [VoiceFrame]) -> Range<Double>? {
        guard let first = frames.first(where: { $0.pitch != nil }),
              let last = frames.last(where: { $0.pitch != nil }) else { return nil }
        return max(0, first.time - 0.02)..<(last.time + 0.02)
    }

    static func make(_ frames: [VoiceFrame], words: [PracticeSentence.Word],
                     timings: [Int: Range<Double>]?, fillMissing: Bool) -> Self {
        guard let span = speechSpan(frames), !words.isEmpty else {
            return Self(ranges: [:], traces: [:], estimated: false)
        }
        var ranges = timings ?? [:]
        let estimated = words.count > 1 && ranges.count < words.count && (fillMissing || ranges.isEmpty)
        if words.count == 1 {
            ranges = [0: span]
        } else if estimated {
            // Fit untimed stretches between recognized anchors, preserving known word boundaries.
            var i = 0
            while i < words.count {
                if ranges[i] != nil { i += 1; continue }
                let start = i
                while i < words.count && ranges[i] == nil { i += 1 }
                var cursor = ranges[start - 1]?.upperBound ?? span.lowerBound
                let end = ranges[i]?.lowerBound ?? span.upperBound
                guard end > cursor else { continue }
                let weights = words[start..<i].map { sqrt(Double($0.text.count)) }
                let unit = (end - cursor) / weights.reduce(0, +)
                for (j, weight) in weights.enumerated() {
                    let next = cursor + weight * unit
                    ranges[start + j] = cursor..<next
                    cursor = next
                }
            }
        }
        return Self(ranges: ranges, traces: project(frames, into: ranges), estimated: estimated)
    }

    private static func project(_ frames: [VoiceFrame], into ranges: [Int: Range<Double>]) -> Traces {
        let pitches = frames.compactMap(\.pitch).sorted()
        guard !pitches.isEmpty else { return [:] }
        let center = pitches[pitches.count / 2]
        let levels = frames.filter { $0.pitch != nil }.map(\.decibels).sorted()
        let loud = levels[levels.count * 9 / 10]
        let ordered = ranges.sorted { $0.value.lowerBound < $1.value.lowerBound }
        var result: Traces = [:]
        var index = 0
        for frame in frames {
            let time = frame.time
            while index < ordered.count && time >= ordered[index].value.upperBound { index += 1 }
            guard index < ordered.count else { break }
            let (word, range) = ordered[index]
            guard range.contains(time) else { continue }
            result[word, default: []].append(ContourPoint(
                position: (time - range.lowerBound) / (range.upperBound - range.lowerBound),
                semitones: frame.pitch.map { 12 * log2($0 / center) },
                emphasis: min(1, max(0, (frame.decibels - loud + 24) / 24))
            ))
        }
        return result.filter { $0.value.contains(where: { $0.semitones != nil }) }
    }
}

extension VoiceContour {
    /// Compare only voiced portions present in both readings at the same part of a timed word.
    func practiceCues(comparedTo reference: Self) -> [Int: String] {
        guard !estimated, !reference.estimated else { return [:] }
        var cues: [Int: String] = [:]
        for (word, points) in traces {
            guard let target = reference.traces[word] else { continue }
            let own = Self.bins(points)
            let model = Self.bins(target)
            let shared = own.indices.filter { own[$0].count > 0 && model[$0].count > 0 }
            guard shared.count >= 3 else { continue }
            var pitchDifferences: [Float] = []
            var emphasis: Float = 0
            for i in shared {
                pitchDifferences.append(own[i].pitch / own[i].count - model[i].pitch / model[i].count)
                emphasis += own[i].emphasis / own[i].count - model[i].emphasis / model[i].count
            }
            let pitch = pitchDifferences.reduce(0, +) / Float(shared.count)
            emphasis /= Float(shared.count)
            // A rise and a fall can have the same average pitch. Compare the ends as well.
            let change = (pitchDifferences.suffix(2).reduce(0, +) - pitchDifferences.prefix(2).reduce(0, +)) / 2
            if shared.count >= 4, abs(change) > 4 {
                cues[word] = change > 0 ? "Bring the end of the word lower." : "Lift the pitch toward the end."
            } else if abs(pitch) > 3 {
                cues[word] = pitch > 0 ? "Try a lower pitch here." : "Try a higher pitch here."
            } else if abs(emphasis) > 0.30 {
                cues[word] = emphasis > 0 ? "Try a lighter emphasis here." : "Give this word a little more emphasis."
            }
        }
        return cues
    }

    private static func bins(_ points: [ContourPoint]) -> [(pitch: Float, emphasis: Float, count: Float)] {
        var bins = Array(repeating: (pitch: Float.zero, emphasis: Float.zero, count: Float.zero), count: 6)
        for point in points {
            guard let pitch = point.semitones else { continue }
            let i = min(5, max(0, Int(point.position * 6)))
            bins[i].pitch += pitch
            bins[i].emphasis += point.emphasis
            bins[i].count += 1
        }
        return bins
    }
}
