import Foundation

struct PracticeSentence: Sendable {
    static let maximumWords = 24

    struct Word: Sendable {
        let text: String
        let range: Range<String.Index>

        var key: String {
            text.replacingOccurrences(of: "’", with: "'").lowercased()
        }
    }

    let text: String
    let words: [Word]

    private static let wordPattern = try! NSRegularExpression(
        pattern: #"[\p{L}\p{M}\p{N}]+(?:['’][\p{L}\p{M}]+)*"#
    )

    init(_ text: String) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        words = Self.words(in: self.text)
    }

    static func words(in sentence: String) -> [Word] {
        wordPattern.matches(in: sentence, range: NSRange(sentence.startIndex..., in: sentence))
            .compactMap { match in
                guard let range = Range(match.range, in: sentence) else { return nil }
                return Word(text: String(sentence[range]), range: range)
            }
    }

    var canRecord: Bool { !words.isEmpty && words.count <= Self.maximumWords }
}
