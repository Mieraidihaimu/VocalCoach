import AVFoundation
import Combine
import Foundation
@preconcurrency import Speech

enum ListeningPhase: Equatable {
    case idle
    case requesting
    case listening
    case processing
    case finished
    case failed
}

@MainActor
final class ListeningSession: ObservableObject {
    @Published private(set) var phase: ListeningPhase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var level = 0.0
    @Published private(set) var errorMessage: String?
    @Published private(set) var pronunciationFeedback: CoachingFeedback?
    @Published private(set) var sentenceFeedback: SentenceFeedback?

    private enum Prompt {
        case drill(PracticeDrill)
        case sentence(PracticeSentence)

        var usesPhonemes: Bool {
            switch self {
            case .drill(let drill): drill.phonemeContrast != nil
            case .sentence: true
            }
        }

        var recordingLimit: Duration {
            switch self {
            case .drill(let drill): drill.phonemeContrast == nil ? .seconds(20) : .seconds(12)
            case .sentence: .seconds(20)
            }
        }
    }

    private lazy var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var attempt: UUID?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var recording: PracticeRecording?
    private var evaluation: Task<Void, Never>?
    private var activePrompt: Prompt?

    func start(drill: PracticeDrill) {
        start(.drill(drill))
    }

    func start(sentence: PracticeSentence) {
        guard sentence.canRecord else { return }
        start(.sentence(sentence))
    }

    private func start(_ prompt: Prompt) {
        guard phase == .idle || phase == .finished || phase == .failed else { return }
        reset()
        if prompt.usesPhonemes, let message = PhonemeCoach.unavailableMessage {
            fail(message)
            return
        }
        let attempt = UUID()
        self.attempt = attempt
        phase = .requesting

        Task { [weak self] in
            let canRecord = await AVAudioApplication.requestRecordPermission()
            guard let self, self.attempt == attempt else { return }
            guard canRecord else {
                fail("Allow microphone access in System Settings → Privacy & Security → Microphone, then try again.")
                return
            }

            if prompt.usesPhonemes {
                beginCapture(for: attempt, prompt: prompt)
                return
            }

            let speechPermission = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { @Sendable status in
                    continuation.resume(returning: status)
                }
            }
            guard self.attempt == attempt else { return }
            switch speechPermission {
            case .authorized:
                beginCapture(for: attempt, prompt: prompt)
            case .denied:
                fail("Allow speech recognition in System Settings → Privacy & Security → Speech Recognition, then try again.")
            case .restricted:
                fail("Speech recognition is restricted on this Mac.")
            case .notDetermined:
                fail("Speech recognition permission is still pending. Try again.")
            @unknown default:
                fail("Speech recognition permission is unavailable on this Mac.")
            }
        }
    }

    func stop() {
        guard phase == .listening, let attempt else { return }
        phase = .processing
        stopCapture()
        if let recording, let prompt = activePrompt {
            timeout?.cancel()
            let audio = recording.snapshot()
            self.recording = nil
            evaluation = Task { [weak self] in
                do {
                    switch prompt {
                    case .drill(let drill):
                        let result = try await PhonemeCoach.shared.evaluate(audio, drill: drill)
                        guard let self, self.attempt == attempt else { return }
                        self.pronunciationFeedback = result
                    case .sentence(let sentence):
                        let result = try await PhonemeCoach.shared.evaluate(audio, sentence: sentence)
                        guard let self, self.attempt == attempt else { return }
                        self.sentenceFeedback = result
                    }
                    guard let self, self.attempt == attempt else { return }
                    self.clearAttempt()
                    self.phase = .finished
                } catch {
                    guard let self, self.attempt == attempt else { return }
                    self.fail((error as? PhonemeError)?.errorDescription
                              ?? "The on-device model couldn’t run. Try again.")
                }
            }
        } else {
            request?.endAudio()
            scheduleTimeout(after: .seconds(6), for: attempt)
        }
    }

    func reset() {
        clearAttempt()
        transcript = ""
        errorMessage = nil
        pronunciationFeedback = nil
        sentenceFeedback = nil
        phase = .idle
    }

    private func beginCapture(for attempt: UUID, prompt: Prompt) {
        let usesPhonemes = prompt.usesPhonemes
        let recognizer = usesPhonemes ? nil : self.recognizer
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let hardwareFormat = input.inputFormat(forBus: 0)
        guard hardwareFormat.channelCount > 0, hardwareFormat.sampleRate > 0,
              format.channelCount > 0, format.sampleRate > 0 else {
            fail("No microphone input is available. Choose a microphone in System Settings → Sound → Input.")
            return
        }

        let recording = usesPhonemes ? PracticeRecording(sampleRate: format.sampleRate) : nil
        self.recording = recording
        activePrompt = prompt

        let request: SFSpeechAudioBufferRecognitionRequest?
        if usesPhonemes {
            request = nil
        } else {
            guard let recognizer, recognizer.isAvailable else {
                fail("English (US) speech recognition is temporarily unavailable. Try again in a moment.")
                return
            }
            let speechRequest = SFSpeechAudioBufferRecognitionRequest()
            speechRequest.shouldReportPartialResults = true
            speechRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request = speechRequest
            self.request = speechRequest
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [weak self] buffer, _ in
            request?.append(buffer)
            recording?.append(buffer)
            let sample = Self.measureLevel(buffer)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.attempt == attempt, self.phase == .listening else { return }
                self.level = max(sample, self.level * 0.76)
            }
        }
        audioEngine = engine

        if let recognizer, let request {
            recognitionTask = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal == true
                let errorMessage = error.map(Self.recognitionMessage)
                DispatchQueue.main.async { [weak self] in
                    self?.receive(text: text, isFinal: isFinal, error: errorMessage, for: attempt)
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            phase = .listening
            scheduleTimeout(after: prompt.recordingLimit, for: attempt)
        } catch {
            fail("The microphone could not start. Check your input in System Settings → Sound, then try again.")
        }
    }

    private func receive(text: String?, isFinal: Bool, error: String?, for attempt: UUID) {
        guard self.attempt == attempt else { return }
        if let text {
            transcript = text
        }
        if isFinal {
            stopCapture()
            if phase == .listening {
                request?.endAudio()
            }
            clearAttempt()
            phase = .finished
        } else if let error {
            fail(error)
        }
    }

    private func scheduleTimeout(after duration: Duration, for attempt: UUID) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard let self, self.attempt == attempt else { return }
            if phase == .listening {
                stop()
            } else {
                fail("Speech recognition took too long. Try a short phrase and speak close to the microphone.")
            }
        }
    }

    private func fail(_ message: String) {
        clearAttempt()
        errorMessage = message
        phase = .failed
    }

    private func clearAttempt() {
        attempt = nil
        timeout?.cancel()
        timeout = nil
        evaluation?.cancel()
        evaluation = nil
        stopCapture()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        recording = nil
        activePrompt = nil
    }

    private func stopCapture() {
        if let audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
        }
        level = 0
    }

    nonisolated private static func recognitionMessage(for error: Error) -> String {
        let error = error as NSError
        // SFSpeechRecognitionTask.error documents these service errors.
        switch (error.domain, error.code) {
        case ("kAFAssistantErrorDomain", 1110):
            return "No speech was recognized. Say the phrase close to your microphone, then try again."
        case ("kLSRErrorDomain", 102):
            return "English (US) speech recognition assets are unavailable. Try again after enabling this language for Dictation in System Settings → Keyboard."
        case ("kLSRErrorDomain", 201):
            return "Turn on Dictation in System Settings → Keyboard, then try again."
        default:
            return "Speech recognition couldn’t finish. Try again in a moment."
        }
    }

    nonisolated private static func measureLevel(_ buffer: AVAudioPCMBuffer) -> Double {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channels = buffer.floatChannelData else { return 0 }

        let stride = buffer.stride
        var peakMeanSquare = 0.0
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            var sumOfSquares = 0.0
            for frame in 0..<frameCount {
                let sample = Double(samples[frame * stride])
                sumOfSquares += sample * sample
            }
            peakMeanSquare = max(peakMeanSquare, sumOfSquares / Double(frameCount))
        }

        let decibels = 10 * log10(max(peakMeanSquare, 0.000001))
        return min(1, max(0, (decibels + 52) / 42))
    }
}
