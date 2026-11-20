import SwiftUI

struct FreePracticeView: View {
    @Binding var draft: String
    @ObservedObject var session: ListeningSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sentence: PracticeSentence { PracticeSentence(draft) }
    private var isRecording: Bool { session.phase == .listening }
    private var isBusy: Bool { session.phase == .requesting || session.phase == .processing }
    private var modelMessage: String? { PhonemeCoach.unavailableMessage }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Free practice")
                    .font(.system(size: 53, weight: .regular, design: .serif))
                    .tracking(-2.6)
                    .accessibilityAddTraits(.isHeader)
                Text("Write a sentence and read it aloud.")
                    .font(.system(size: 15))
                    .foregroundStyle(StudioColor.muted)
            }
            .padding(.bottom, 5)

            sentenceCard
            feedbackCard
                .id("sentence-feedback")
        }
        .onChange(of: draft) {
            if !isRecording && !isBusy && session.phase != .idle {
                session.reset()
            }
        }
    }

    private var sentenceCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Your sentence", systemImage: "text.bubble")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if sentence.words.count > PracticeSentence.maximumWords {
                    Text("Use up to \(PracticeSentence.maximumWords) words.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(StudioColor.accent)
                }
            }

            TextField("Type or paste a sentence", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 23, design: .serif))
                .lineLimit(2...5)
                .padding(14)
                .modifier(StudioSurface(fill: StudioColor.paper, radius: 10))
                .disabled(isRecording || isBusy)
                .accessibilityLabel("Your sentence")

            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isRecording ? StudioColor.accent : StudioColor.muted.opacity(0.65))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(isRecording ? "Listening" : "Microphone off")
                        .foregroundStyle(isRecording ? StudioColor.accent : StudioColor.muted)
                }
                .font(.system(size: 12, weight: .medium))
                Spacer()
                Label("On-device feedback", systemImage: "lock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(StudioColor.muted)
            }

            WaveformMeter(level: session.level, active: isRecording)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: session.level)

            Button {
                if isRecording {
                    session.stop()
                } else {
                    session.start(sentence: sentence)
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
                    Text(buttonTitle)
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(StudioButtonStyle(primary: true))
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(isBusy || modelMessage != nil || (!isRecording && !sentence.canRecord))
        }
        .padding(21)
        .modifier(StudioSurface())
    }

    private var buttonTitle: String {
        switch session.phase {
        case .idle: "Start speaking"
        case .requesting: "Checking microphone access…"
        case .listening: "Done speaking"
        case .processing: "Checking words…"
        case .finished, .failed: "Try again"
        }
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Words to practise", systemImage: "quote.bubble")
                .font(.system(size: 14, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            if let feedback = session.sentenceFeedback, !feedback.tips.isEmpty {
                let current = sentence
                let tips = feedback.tips.filter { current.words.indices.contains($0.wordIndex) }
                Text(highlighted(current, tips: tips))
                    .font(.system(size: 23, design: .serif))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(tips) { tip in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(current.words[tip.wordIndex].text)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(StudioColor.accent)
                            Text(tip.instruction)
                                .font(.system(size: 13))
                                .foregroundStyle(StudioColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                Text(feedbackMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(StudioColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(StudioSurface(radius: 14))
    }

    private var feedbackMessage: String {
        if let problem = modelMessage ?? session.errorMessage { return problem }
        if let feedback = session.sentenceFeedback {
            return feedback.matchedSentence
                ? "No clear changes to suggest for this take."
                : "I couldn’t match enough sounds to your sentence. Read it once more at a steady pace."
        }
        return switch session.phase {
        case .listening: "Read the sentence once, then choose Done speaking."
        case .processing: "Checking which words could use a tip."
        default: "Tips will appear here after you read your sentence."
        }
    }

    private func highlighted(_ sentence: PracticeSentence, tips: [SentenceFeedback.Tip]) -> AttributedString {
        var output = AttributedString()
        var start = sentence.text.startIndex
        for tip in tips {
            let word = sentence.words[tip.wordIndex]
            output += AttributedString(sentence.text[start..<word.range.lowerBound])
            var marked = AttributedString(word.text)
            marked.foregroundColor = StudioColor.accent
            marked.backgroundColor = StudioColor.accentWash
            output += marked
            start = word.range.upperBound
        }
        output += AttributedString(sentence.text[start...])
        return output
    }
}
