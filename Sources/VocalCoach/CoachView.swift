import SwiftUI

struct CoachView: View {
    @StateObject private var session = CoachSession()

    private var isReviewing: Bool { session.activity == .ready && session.latest != nil }

    private var focusWords: Set<Int> {
        Set(session.marks.filter { $0.value != .close }.keys).union(session.prosodyCues.keys)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PromptEditor(
                text: Binding(get: { session.draft }, set: { session.edit($0) }),
                isEditable: session.canEdit,
                reference: session.baseline?.traces ?? [:],
                recording: isReviewing ? (session.latest?.contour.traces ?? [:]) : [:],
                focusWords: isReviewing ? focusWords : [],
                selection: session.activity == .ready ? session.selectedWord : nil,
                onWord: session.selectWord
            )
            .frame(minHeight: 110)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .topLeading) {
                if session.draft.isEmpty {
                    Text("Type a word or sentence")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(24)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .help("Height shows pitch relative to each speaker’s usual pitch. Thicker lines show greater emphasis.")

            if let baseline = session.baseline {
                HStack(spacing: 14) {
                    legend("Emma", color: Color(nsColor: .systemTeal))
                    if isReviewing, session.latest?.contour.traces.isEmpty == false {
                        legend("You", color: Color(nsColor: .systemPurple))
                    }
                    if isReviewing && !focusWords.isEmpty {
                        legend("Practise", color: Color(nsColor: .systemOrange))
                    }
                    Spacer()
                    if baseline.estimated || (isReviewing && session.latest?.contour.estimated == true) {
                        Text("Approx. word timing")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }

            if session.activity == .ready, let coaching = session.selectedCoaching {
                coachingPanel(coaching)
            } else if isReviewing {
                Text(session.marks.isEmpty
                     ? "No word-level measurement for this take. Compare by ear or select a word for guidance."
                     : "Select a word to review it, or replay your take.")
                    .font(.callout)
                    .padding(.vertical, 4)
            }

            HStack(spacing: 8) {
                let hearing = session.playback == .emma
                Button {
                    session.toggleHear()
                } label: {
                    Label(hearing ? "Stop Emma" : "Hear Emma",
                          systemImage: hearing ? "stop.fill" : "speaker.wave.2")
                }
                .disabled(!hearing && (session.activity != .ready || !session.canHear))
                .contextMenu {
                    if let latest = session.latest {
                        Button("Replay latest take") { session.replay(latest.audio, source: .latest) }
                        if let word = session.selectedCoaching?.myAudio {
                            Button("Replay selected word") { session.replay(word, source: .myWord) }
                        }
                    }
                    if let previous = session.previous {
                        Button("Replay previous take") { session.replay(previous.audio, source: .previous) }
                    }
                }

                if let latest = session.latest {
                    Button(session.previous == nil ? "Play my take" : "Play latest") {
                        session.replay(latest.audio, source: .latest)
                    }
                    .disabled(session.activity != .ready)
                    if session.previous != nil {
                        Button(session.playback?.isComparison == true ? "Stop comparison" : "Compare takes") {
                            session.compareTakes()
                        }
                        .disabled(session.activity != .ready)
                        .help("Play your previous take, then your latest take")
                    }
                }

                Spacer(minLength: 0)
                let recording = session.activity == .recording
                Button {
                    session.toggleRecording()
                } label: {
                    Label(recording ? "Stop" : (session.latest == nil ? "Record" : "Record again"),
                          systemImage: recording ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(recording ? .red : .accentColor)
                .disabled(!session.canRecord || (session.activity != .ready && !recording))
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            HStack(spacing: 9) {
                if session.activity == .recording {
                    ProgressView(value: Double(session.inputLevel))
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .frame(width: 64)
                        .accessibilityLabel("Microphone input level")
                }
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 18, alignment: .leading)
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 320)
        .onDisappear { session.endPractice() }
    }

    private func coachingPanel(_ coaching: CoachSession.WordCoaching) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(verbatim: coaching.word).font(.headline)
                Spacer()
                if let audio = coaching.emmaAudio {
                    Button("Hear Emma’s word") { session.replay(audio, source: .emmaWord) }
                }
                if let audio = coaching.myAudio {
                    Button("Hear my word") { session.replay(audio, source: .myWord) }
                }
            }
            .controlSize(.small)

            if let observation = coaching.observation {
                Text("From your take · \(observation)")
            }
            if let tip = coaching.tip {
                Text("Practice tip · \(tip)")
            }
            if coaching.observation == nil && coaching.tip == nil {
                Text("Listen to the recordings to compare this word by ear.")
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    private func legend(_ name: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 17, height: 3)
            Text(name)
        }
    }

    private var status: String {
        if let notice = session.notice { return notice }
        switch session.activity {
        case .requesting: return "Waiting for microphone access…"
        case .recording: return "Recording · Speak at your own pace."
        case .synthesising: return session.baseline == nil ? "Preparing Emma’s voice…" : "Aligning Emma’s words…"
        case .analysing: return "Aligning your take…"
        case .preparingTiming: return "Downloading British English speech data…"
        case .ready:
            if let playback = session.playback { return playback.status }
            if !session.canHear { return "" }
            if !session.withinLimit { return "Record up to \(CoachSession.maxWords) words at a time." }
            if !session.heardReference { return "Hear Emma read the prompt before recording." }
            if let take = session.latest, take.contour.traces.isEmpty {
                return "Couldn’t place your voice on the words. Try another take."
            }
            return session.latest == nil ? "Ready to record." : ""
        }
    }
}
