import AVFoundation
import SwiftUI

struct PracticeView: View {
    @AppStorage("practiceAccent") private var accent: PracticeAccent = .british
    @AppStorage("guidedDrillIndex") private var guidedDrillIndex = 0
    @AppStorage("practisedDrills") private var practisedDrills = ""
    @State private var isFreePractice = false
    @State private var sentenceDraft = ""
    @StateObject private var session = ListeningSession()
    @StateObject private var sample = ExamplePlayback()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var drills: [PracticeDrill] { accent.drills }
    private var selectedIndex: Int { drills.indices.contains(guidedDrillIndex) ? guidedDrillIndex : 0 }
    private var drill: PracticeDrill { drills[selectedIndex] }
    private var practiced: Set<String> { Set(practisedDrills.split(separator: ",").map(String.init)) }
    private var practicedCount: Int { drills.lazy.filter { practiced.contains($0.id) }.count }
    private var usesPhonemes: Bool { drill.phonemeContrast != nil }
    private var modelMessage: String? { usesPhonemes ? PhonemeCoach.unavailableMessage : nil }
    private var isRecording: Bool { session.phase == .listening }
    private var isBusy: Bool {
        session.phase == .requesting || session.phase == .processing
    }
    private var feedback: CoachingFeedback? {
        guard session.phase == .finished else { return nil }
        if usesPhonemes { return session.pronunciationFeedback }
        return CoachingFeedback.evaluate(transcript: session.transcript, drill: drill)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(StudioColor.line)
                .frame(width: 1)
                .accessibilityHidden(true)
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead
                            .padding(.bottom, 29)
                        if isFreePractice {
                            FreePracticeView(draft: $sentenceDraft, session: session)
                        } else {
                            guidedPractice
                        }
                    }
                    .id("practice-top")
                    .frame(maxWidth: 990)
                    .padding(.horizontal, 32)
                    .padding(.top, 42)
                    .padding(.bottom, 27)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: isFreePractice) { scroll.scrollTo("practice-top", anchor: .top) }
                .onChange(of: session.phase) { _, phase in
                    if isFreePractice && (phase == .finished || phase == .failed) {
                        scroll.scrollTo("sentence-feedback", anchor: .bottom)
                    }
                }
            }
            .background(StudioColor.paper)
        }
        .foregroundStyle(StudioColor.ink)
        .task(id: accent) {
            if accent == .british, modelMessage == nil {
                await PhonemeCoach.shared.preload()
            }
        }
        .onChange(of: session.phase) { _, phase in
            if !isFreePractice, phase == .finished, let feedback, feedback.kind != .retry {
                practisedDrills = practiced.union([drill.id]).sorted().joined(separator: ",")
            }
        }
        .onDisappear {
            sample.stop()
            session.reset()
        }
    }

    private var guidedPractice: some View {
        VStack(alignment: .leading, spacing: 0) {
            soundHeader
                .padding(.bottom, 23)
            HStack(alignment: .top, spacing: 16) {
                speakingCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(StudioSurface())
                techniqueCard
                    .frame(width: 296)
                    .frame(maxHeight: .infinity)
                    .modifier(StudioSurface(fill: StudioColor.technique))
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 15)
            feedbackCard
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(StudioColor.paper)
                    .frame(width: 37, height: 37)
                    .background(StudioColor.ink, in: .rect(cornerRadius: 10))
                    .accessibilityHidden(true)
                Text("Articulate")
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .tracking(-1)
            }
            .padding(.leading, 5)
            .padding(.bottom, 25)

            freePracticeButton
                .padding(.bottom, 20)

            Text("SOUNDS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(StudioColor.muted)
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, 8)
                .padding(.bottom, 10)

            VStack(spacing: 5) {
                ForEach(Array(drills.enumerated()), id: \.element.id) { index, item in
                    soundButton(index: index, item: item)
                }
            }

            Spacer(minLength: 26)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Practice progress")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(practicedCount) / \(drills.count)")
                        .monospacedDigit()
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(StudioColor.muted)
                }
                HStack(spacing: 4) {
                    ForEach(drills) { item in
                        Capsule()
                            .fill(practiced.contains(item.id) ? StudioColor.accent : StudioColor.line)
                            .frame(height: 4)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(13)
            .modifier(StudioSurface(fill: StudioColor.paper, radius: 11))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Practice progress")
            .accessibilityValue("\(practicedCount) of \(drills.count) sounds practiced")
        }
        .padding(.horizontal, 19)
        .padding(.top, 56)
        .padding(.bottom, 25)
        .frame(width: 232)
        .frame(maxHeight: .infinity)
        .background(StudioColor.sidebar)
    }

    private var freePracticeButton: some View {
        Button {
            guard !isFreePractice else { return }
            sample.stop()
            session.reset()
            accent = .british
            isFreePractice = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isFreePractice ? .white : StudioColor.muted)
                    .frame(width: 37, height: 35)
                    .background(isFreePractice ? StudioColor.accent : StudioColor.paper,
                                in: .rect(cornerRadius: 8))
                Text("Free practice")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isFreePractice ? StudioColor.accentWash : .clear, in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Read your own sentence in Modern British RP.")
        .accessibilityAddTraits(isFreePractice ? .isSelected : [])
    }

    private func soundButton(index: Int, item: PracticeDrill) -> some View {
        let selected = !isFreePractice && selectedIndex == index

        return Button {
            selectSound(at: index)
        } label: {
            HStack(spacing: 10) {
                Text(item.symbol)
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(selected ? .white : StudioColor.muted)
                    .frame(width: 37, height: 35)
                    .background(selected ? StudioColor.accent : StudioColor.paper, in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(item.category)
                        .font(.system(size: 11))
                        .foregroundStyle(StudioColor.muted)
                }
                Spacer(minLength: 0)
                if practiced.contains(item.id) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(StudioColor.success)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? StudioColor.accentWash : .clear, in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.category)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var masthead: some View {
        HStack {
            Text("Practice studio")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Menu {
                ForEach(PracticeAccent.allCases) { option in
                    Button {
                        selectAccent(option)
                    } label: {
                        if option == accent {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Label(accent.title, systemImage: "globe")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 7)
            .modifier(StudioSurface(fill: StudioColor.card, radius: 9))
            .accessibilityLabel("Target accent: \(accent.title)")
        }
        .padding(.bottom, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(StudioColor.line)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    private var soundHeader: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SOUND \(String(format: "%02d", selectedIndex + 1)) / \(String(format: "%02d", drills.count))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(StudioColor.accent)
                    .accessibilityLabel("Sound \(selectedIndex + 1) of \(drills.count)")
                Text(drill.title)
                    .font(.system(size: 57, weight: .regular, design: .serif))
                    .tracking(-2.9)
                    .accessibilityAddTraits(.isHeader)
                Text("\(drill.symbol) as in “\(drill.focusWord)”")
                    .font(.system(size: 15))
                    .foregroundStyle(StudioColor.muted)
            }
            Spacer()
            Button {
                selectSound(at: (selectedIndex + 1) % drills.count)
            } label: {
                HStack(spacing: 7) {
                    Text(selectedIndex == drills.count - 1 ? "First sound" : "Next sound")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(StudioButtonStyle())
            .padding(.bottom, 2)
        }
    }

    private var speakingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(usesPhonemes ? "Say the prompt" : "Say the phrase", systemImage: "text.bubble")
                .font(.system(size: 14, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            Text(highlightedPhrase)
                .font(.system(size: 33, weight: .regular, design: .serif))
                .tracking(-0.9)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            HStack(spacing: 10) {
                Button {
                    if sample.isPlaying {
                        sample.stop()
                    } else {
                        sample.play(drill, accent: accent)
                    }
                } label: {
                    Label(sample.isPlaying ? "Stop example" : "Hear example",
                          systemImage: sample.isPlaying ? "stop.fill" : "speaker.wave.2")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(StudioButtonStyle())
                .disabled(isRecording || isBusy)

                if let error = sample.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(StudioColor.accent)
                } else if let recording = drill.recordedExample {
                    Text("British recording · “\(recording)”")
                        .font(.system(size: 11))
                        .foregroundStyle(StudioColor.muted)
                }
            }
            .padding(.top, 15)

            Spacer(minLength: 20)

            Rectangle()
                .fill(StudioColor.line)
                .frame(height: 1)
                .padding(.bottom, 15)
                .accessibilityHidden(true)

            HStack(spacing: 6) {
                Circle()
                    .fill(isRecording ? StudioColor.accent : StudioColor.muted.opacity(0.65))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(recordingStatus)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isRecording ? StudioColor.accent : StudioColor.muted)
                Spacer()
                if usesPhonemes, modelMessage == nil {
                    Label("On-device feedback", systemImage: "lock")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(StudioColor.muted)
                }
            }

            WaveformMeter(level: session.level, active: isRecording)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: session.level)
                .padding(.vertical, 8)

            Button {
                if isRecording {
                    session.stop()
                } else {
                    sample.stop()
                    session.start(drill: drill)
                }
            } label: {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(recordButtonTitle)
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(StudioButtonStyle(primary: true))
            .disabled(isBusy || modelMessage != nil)
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(21)
    }

    private var techniqueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Mouth position", systemImage: "scope")
                .font(.system(size: 14, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            MouthPositionDiagram(drillID: drill.diagram ?? drill.id)

            VStack(alignment: .leading, spacing: 5) {
                Text(drill.cueTitle)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                Text(drill.cue)
                    .font(.system(size: 13))
                    .foregroundStyle(StudioColor.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle()
                .fill(StudioColor.line)
                .frame(height: 1)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(StudioColor.accent)
                    .accessibilityHidden(true)
                Text(drill.check)
                    .font(.system(size: 12))
                    .foregroundStyle(StudioColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private var feedbackCard: some View {
        let state = feedbackState

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(state.color)
                .frame(width: 37, height: 37)
                .background(state.fill, in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(state.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(StudioColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let transcript = feedback?.transcript, !transcript.isEmpty {
                    Text("Transcript: “\(transcript)”")
                        .font(.system(size: 12))
                        .foregroundStyle(StudioColor.muted)
                        .textSelection(.enabled)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .modifier(StudioSurface(radius: 14))
        .accessibilityElement(children: .combine)
    }

    private var highlightedPhrase: AttributedString {
        var phrase = AttributedString(drill.phrase)
        if let range = phrase.range(of: drill.focusWord, options: .caseInsensitive) {
            phrase[range].foregroundColor = StudioColor.accent
        }
        return phrase
    }

    private var recordingStatus: String {
        switch session.phase {
        case .idle, .finished, .failed: "Microphone off"
        case .requesting: "Waiting for access"
        case .listening: "Listening"
        case .processing: "Microphone off"
        }
    }

    private var recordButtonTitle: String {
        switch session.phase {
        case .idle: "Start speaking"
        case .requesting: "Checking permissions…"
        case .listening: "Done speaking"
        case .processing: "Finishing…"
        case .finished, .failed: "Try again"
        }
    }

    private var feedbackState: (title: String, detail: String, icon: String, color: Color, fill: Color) {
        if let feedback {
            let matched = feedback.kind == .recognized
            return (feedback.title, feedback.detail, matched ? "checkmark" : "waveform",
                    matched ? StudioColor.success : StudioColor.accent,
                    matched ? StudioColor.successWash : StudioColor.accentWash)
        }

        if let error = session.errorMessage, session.phase == .failed {
            return ("Listening couldn’t finish", error, "exclamationmark", StudioColor.accent, StudioColor.accentWash)
        }

        if let modelMessage {
            return ("Sound check unavailable", modelMessage, "exclamationmark", StudioColor.accent, StudioColor.accentWash)
        }

        if usesPhonemes {
            switch session.phase {
            case .listening:
                return ("Listening", "Say the prompt once, then choose Done speaking.",
                        "waveform", StudioColor.accent, StudioColor.accentWash)
            case .processing:
                return ("Checking the sound", "HuPER is analysing your recording on this Mac.",
                        "waveform", StudioColor.accent, StudioColor.accentWash)
            default:
                return ("Feedback", "Say the prompt to get a tip on the highlighted sound.",
                        "quote.bubble", StudioColor.muted, StudioColor.sidebar)
            }
        }

        if session.phase == .listening || session.phase == .processing {
            let detail = session.transcript.isEmpty ? "Waiting for your words…" : session.transcript
            return ("Live transcript", detail, "waveform", StudioColor.accent, StudioColor.accentWash)
        }

        return ("Feedback", "Say the phrase to get a tip based on the words your Mac hears.",
                "quote.bubble", StudioColor.muted, StudioColor.sidebar)
    }

    private func selectSound(at index: Int) {
        guard isFreePractice || selectedIndex != index else { return }
        sample.stop()
        session.reset()
        guidedDrillIndex = index
        isFreePractice = false
    }

    private func selectAccent(_ option: PracticeAccent) {
        guard accent != option else { return }
        sample.stop()
        session.reset()
        guidedDrillIndex = 0
        accent = option
        if option == .american { isFreePractice = false }
    }
}

@MainActor
private final class ExamplePlayback: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private var recordingPlayer: AVAudioPlayer?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func play(_ drill: PracticeDrill, accent: PracticeAccent) {
        stop()
        if drill.recordedExample != nil {
            playRecording(for: drill.id)
            return
        }

        guard let voice = AVSpeechSynthesisVoice(language: accent.voiceLocale) else {
            errorMessage = "A system voice for \(accent.title) is unavailable."
            return
        }

        let utterance = AVSpeechUtterance(string: drill.phrase)
        utterance.voice = voice
        utterance.rate = 0.43
        activeUtterance = utterance
        isPlaying = true
        synthesizer.speak(utterance)
    }

    private func playRecording(for drillID: String) {
        guard let url = Bundle.main.url(forResource: drillID, withExtension: "wav", subdirectory: "AudioExamples"),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            errorMessage = "This British recording is unavailable."
            return
        }

        player.delegate = self
        guard player.play() else {
            errorMessage = "The recording couldn’t play. Check your sound output and try again."
            return
        }
        recordingPlayer = player
        isPlaying = true
    }

    func stop() {
        recordingPlayer?.stop()
        recordingPlayer = nil
        activeUtterance = nil
        isPlaying = false
        errorMessage = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(ObjectIdentifier(utterance))
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finish(ObjectIdentifier(player), error: flag ? nil : "The recording couldn’t finish playing.")
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finish(ObjectIdentifier(player), error: "The recording couldn’t be read.")
    }

    nonisolated private func finish(_ id: ObjectIdentifier, error: String? = nil) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let recordingPlayer, ObjectIdentifier(recordingPlayer) == id {
                self.recordingPlayer = nil
            } else if let activeUtterance, ObjectIdentifier(activeUtterance) == id {
                self.activeUtterance = nil
            } else {
                return
            }
            self.errorMessage = error
            self.isPlaying = false
        }
    }
}
