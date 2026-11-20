import AVFoundation

struct VowelReading: Sendable {
    let f1: Double
    let f2: Double
    let f1Spread: Double
    let f2Spread: Double
    let f3: Double?
    let f3Spread: Double
}

enum VowelMatch: Int, Sendable {
    case focus = 1
    case someDifference = 2
    case close = 3

    static func compare(_ take: VowelReading, with reference: VowelReading) -> Self? {
        guard let takeF3 = take.f3, let referenceF3 = reference.f3 else { return nil }
        // Ratios reduce the effect of one speaker's formants scaling together.
        let openness = abs(log((take.f1 / takeF3) / (reference.f1 / referenceF3)))
        let frontness = abs(log((take.f2 / takeF3) / (reference.f2 / referenceF3)))
        let scaleSpread = take.f3Spread / takeF3 + reference.f3Spread / referenceF3
        let opennessSpread = take.f1Spread / take.f1 + reference.f1Spread / reference.f1 + scaleSpread
        let frontnessSpread = take.f2Spread / take.f2 + reference.f2Spread / reference.f2 + scaleSpread
        guard opennessSpread < 0.26, frontnessSpread < 0.20 else { return nil }

        let distance = max(
            openness / max(0.19, opennessSpread * 1.5),
            frontness / max(0.13, frontnessSpread * 1.5)
        )
        if distance <= 1 { return .close }
        if distance <= 1.7 { return .someDifference }
        return .focus
    }
}

enum VowelAnalysis {
    private static let rate = 11_000.0
    private static let windowLength = 551

    static func measure(_ audio: PracticeAudio, singleVowel: Bool = false) -> VowelReading? {
        guard let resampled = resample(audio) else { return nil }
        let end = resampled.count - windowLength
        guard end >= 0 else { return nil }
        // A finer grid makes short vowels less sensitive to the crop's starting sample.
        let step = singleVowel ? 55 : 110
        let minVoicedFrames = 660 / step

        let samples = resampled.map(Double.init)
        let peak = samples.lazy.map(abs).max() ?? 0
        guard peak >= 0.005 else { return nil }

        let threshold = max(0.002, peak * 0.045)
        // Sentence-final vowels can drop below 65 Hz in natural speech.
        let maximumLag = singleVowel ? 220 : 170
        let voicedEnergy = stride(from: 0, through: end, by: step).map { offset in
            periodicEnergy(samples[offset..<(offset + windowLength)], rmsFloor: threshold, maximumLag: maximumLag)
        }
        var strongest = 0..<0
        var strongestEnergy = 0.0
        var runStart = 0
        var runEnergy = 0.0
        var voicedRuns: [Range<Int>] = []
        for (i, energy) in (voicedEnergy + [0]).enumerated() {
            if energy > 0 {
                runEnergy += energy
            } else {
                if i - runStart >= minVoicedFrames {
                    let run = runStart..<i
                    voicedRuns.append(run)
                    if runEnergy > strongestEnergy {
                        strongest = run
                        strongestEnergy = runEnergy
                    }
                }
                runStart = i + 1
                runEnergy = 0
            }
        }
        guard !strongest.isEmpty, let reading = measureRun(strongest, in: samples, step: step) else {
            return nil
        }
        if singleVowel {
            let gapFrames = 440 / step
            for run in voicedRuns {
                let separate = run.lowerBound - strongest.upperBound >= gapFrames
                    || strongest.lowerBound - run.upperBound >= gapFrames
                if separate, measureRun(run, in: samples, step: step) != nil { return nil }
            }
        }
        return reading
    }

    private static func measureRun(_ run: Range<Int>, in samples: [Double], step: Int) -> VowelReading? {
        let minMeasurementFrames = 440 / step
        let maxMeasurementFrames = 3_300 / step
        // Avoid consonant transitions. Measure at most 300 ms of the vowel.
        // Short natural vowels still need enough frames for a stable median.
        let margin = min(run.count / 5, (run.count - minMeasurementFrames) / 2)
        let center = (run.lowerBound + margin)..<(run.upperBound - margin)
        let centerStart = max(center.lowerBound, (center.lowerBound + center.upperBound) / 2 - maxMeasurementFrames / 2)
        let centerEnd = min(center.upperBound, centerStart + maxMeasurementFrames)
        let emphasis = exp(-2 * .pi * 50 / rate)
        let midpoint = Double(windowLength - 1) / 2
        let edge = exp(-12.0)
        let weights = (0..<windowLength).map { i in
            let position = (Double(i) - midpoint) / midpoint
            return (exp(-12 * position * position) - edge) / (1 - edge)
        }
        var f1s: [Double] = []
        var f2s: [Double] = []
        var f3s: [Double] = []
        for i in centerStart..<centerEnd {
            let offset = i * step
            let frame = weights.indices.map { j in
                let index = offset + j
                let previous = index > 0 ? samples[index - 1] : 0
                return (samples[index] - emphasis * previous) * weights[j]
            }
            let resonances = BurgFormants.estimate(frame, sampleRate: rate).filter {
                $0.frequency >= 155 && $0.bandwidth < 650
            }
            guard resonances.count >= 2 else { continue }
            // Reject a weak pair rather than treating a higher resonance as F1.
            let first = resonances[0]
            let second = resonances[1]
            let f1 = first.frequency
            let f2 = second.frequency
            guard second.bandwidth < 450,
                  (175...1_050).contains(f1), (650...3_600).contains(f2), f2 - f1 >= 190 else { continue }
            f1s.append(f1)
            f2s.append(f2)
            if resonances.count >= 3 {
                let third = resonances[2]
                if (1_650...4_500).contains(third.frequency), third.frequency - f2 >= 150,
                   third.bandwidth < 510 {
                    f3s.append(third.frequency)
                }
            }
        }

        guard f1s.count >= max(minMeasurementFrames, (centerEnd - centerStart + 1) / 2) else { return nil }
        let f1 = median(f1s)
        let f2 = median(f2s)
        let f1Spread = median(f1s.map { abs($0 - f1) })
        let f2Spread = median(f2s.map { abs($0 - f2) })
        guard f1Spread < 100, f2Spread < 180 else { return nil }
        let f3 = f3s.count >= max(minMeasurementFrames, (f1s.count + 1) / 2) ? median(f3s) : nil
        let f3Spread = f3.map { value in median(f3s.map { abs($0 - value) }) } ?? 0
        return VowelReading(f1: f1, f2: f2, f1Spread: f1Spread, f2Spread: f2Spread,
                            f3: f3Spread < 220 ? f3 : nil, f3Spread: f3Spread)
    }

    private static func periodicEnergy(_ frame: ArraySlice<Double>, rmsFloor: Double, maximumLag: Int) -> Double {
        let mean = frame.reduce(0, +) / Double(frame.count)
        let energy = frame.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        guard energy >= rmsFloor * rmsFloor * Double(frame.count) else { return 0 }

        // Periodicity distinguishes a held vowel from breath, fricatives and room noise.
        let start = frame.startIndex
        for lag in 24...maximumLag {
            var cross = 0.0
            var leftEnergy = 0.0
            var rightEnergy = 0.0
            for i in start..<(frame.endIndex - lag) {
                let left = frame[i] - mean
                let right = frame[i + lag] - mean
                cross += left * right
                leftEnergy += left * left
                rightEnergy += right * right
            }
            if cross > 0.72 * (leftEnergy * rightEnergy).squareRoot() { return energy }
        }
        return 0
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
    }

    private static func resample(_ audio: PracticeAudio) -> [Float]? {
        if audio.sampleRate == rate { return audio.samples }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = audio.converted(to: format), let samples = buffer.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
    }
}
