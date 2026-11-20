import AVFoundation

enum ReferenceVoice {
    private static let queue = DispatchQueue(label: "com.mier.vocalcoach.kokoro", qos: .userInitiated)

    static func generate(_ text: String) async throws -> PracticeAudio {
        guard let executable = Bundle.main.resourceURL?
            .appending(path: "PageHumVoice/pagehum"),
              FileManager.default.isExecutableFile(atPath: executable.path) else { throw VoiceError.missing }

        let job = RenderJob()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    continuation.resume(with: Result { try render(text, using: executable, job: job) })
                }
            }
        } onCancel: {
            job.cancel()
        }
    }

    private static func render(_ text: String, using executable: URL, job: RenderJob) throws -> PracticeAudio {
        let files = FileManager.default
        let scratch = files.temporaryDirectory.appending(path: "vocal-coach-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: scratch) }

        let input = scratch.appending(path: "prompt.txt")
        let output = scratch.appending(path: "reference.wav")
        try text.write(to: input, atomically: false, encoding: .utf8)
        let process = Process()
        process.executableURL = executable
        process.arguments = ["generate", "--file", input.path, "--voice", "bf_emma", "--output", output.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try job.start(process)

        let timeout = DispatchWorkItem {
            job.cancel()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 45, execute: timeout)
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else { throw VoiceError.synthesis }

        let file = try AVAudioFile(forReading: output)
        guard file.length > 0,
              let audio = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { throw VoiceError.synthesis }
        try file.read(into: audio)
        guard let channel = audio.floatChannelData?[0] else { throw VoiceError.synthesis }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(audio.frameLength)))
        return PracticeAudio(samples: samples, sampleRate: audio.format.sampleRate)
    }

    // Editing can supersede a queued or running synthesis while the serial renderer is busy.
    private final class RenderJob: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var process: Process?

        func start(_ process: Process) throws {
            lock.lock()
            defer { lock.unlock() }
            guard !cancelled else { throw CancellationError() }
            try process.run()
            self.process = process
        }

        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            cancelled = true
            if let process, process.isRunning { process.terminate() }
        }
    }

    private enum VoiceError: Error {
        case missing, synthesis
    }
}
