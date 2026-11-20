import Foundation

struct SentenceFeedback: Sendable {
    struct Tip: Identifiable, Sendable {
        let wordIndex: Int
        let instruction: String

        var id: Int { wordIndex }
    }

    let tips: [Tip]
    let matchedSentence: Bool
}

struct BritishPronunciations {
    struct Pronunciation {
        let phones: [String]
        let stressedShortI: Set<Int>
        let longA: Set<Int>

        var addingLinkingR: Pronunciation {
            Pronunciation(phones: phones + ["R"], stressedShortI: stressedShortI, longA: longA)
        }
    }

    private static let phoneMap = [
        "aɪ": ["AY"], "aʊ": ["AW"], "b": ["B"], "d": ["D"], "dʒ": ["JH"],
        "eɪ": ["EY"], "f": ["F"], "g": ["G"], "h": ["HH"], "i": ["IY"],
        "iː": ["IY"], "j": ["Y"], "k": ["K"], "l": ["L"], "m": ["M"], "n": ["N"],
        "p": ["P"], "s": ["S"], "t": ["T"], "tʃ": ["CH"], "uː": ["UW"],
        "v": ["V"], "w": ["W"], "z": ["Z"], "æ": ["AE"], "ð": ["DH"], "ŋ": ["NG"],
        "ɐ": ["AH"], "ɑː": ["AA"], "ɒ": ["AA"], "ɔɪ": ["OY"], "ɔː": ["AA"],
        "ə": ["AH"], "əʊ": ["OW"], "ɛ": ["EH"], "ɛə": ["EH", "AH"],
        "ɜː": ["ER"], "ɪ": ["IH"], "ɪə": ["IH", "AH"], "ɹ": ["R"], "ʃ": ["SH"],
        "ʊ": ["UH"], "ʊə": ["UH", "AH"], "ʒ": ["ZH"], "θ": ["TH"]
    ]
    static let vowels: Set<String> = [
        "AA", "AE", "AH", "AW", "AY", "EH", "ER", "EY", "IH", "IY", "OW", "OY", "UH", "UW"
    ]

    private let entries: [String: [Pronunciation]]

    init(contentsOf url: URL) throws {
        let contents = try String(contentsOf: url, encoding: .utf8)
        var entries: [String: [Pronunciation]] = [:]

        for line in contents.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: ",", maxSplits: 1)
            guard fields.count == 2, let name = fields[0].split(separator: "(").first else { continue }
            let key = name.lowercased()
            var phones: [String] = []
            var stressedShortI: Set<Int> = []
            var longA: Set<Int> = []
            var complete = true
            for token in fields[1].split(whereSeparator: \.isWhitespace) {
                let ipa = String(token.drop(while: { $0 == "ˈ" || $0 == "ˌ" }))
                guard let mapped = Self.phoneMap[ipa] else {
                    complete = false
                    break
                }
                if ipa == "ɪ", token.hasPrefix("ˈ") { stressedShortI.insert(phones.count) }
                if ipa == "ɑː" { longA.insert(phones.count) }
                phones.append(contentsOf: mapped)
            }
            guard complete, !phones.isEmpty, entries[key]?.contains(where: { $0.phones == phones }) != true else {
                continue
            }
            entries[key, default: []].append(Pronunciation(phones: phones, stressedShortI: stressedShortI, longA: longA))
        }
        self.entries = entries
    }

    subscript(word: PracticeSentence.Word) -> [Pronunciation] {
        entries[word.key] ?? []
    }
}

struct SentenceCoach {
    private struct Match {
        let heard: Range<Int>
        let edits: Int
    }

    private struct Path {
        let rank: Int
        let match: Match
    }

    private struct Correction {
        let contextEdits: Int
        let reference: [String]
        let instruction: String
    }

    private static let bathWords: Set<String> = [
        "after", "afternoon", "afterwards", "ask", "asked", "asking", "bath", "baths", "bathroom",
        "cast", "class", "classes", "classroom", "can't", "dance", "danced", "dancing",
        "fast", "faster", "glass", "glasses", "grass", "half", "last", "laugh", "laughed",
        "laughing", "pass", "passed", "passing", "past", "path", "paths", "staff", "task"
    ]
    private static let startWords: Set<String> = [
        "arm", "arms", "art", "bar", "barn", "car", "card", "cards", "cars", "cart", "dark",
        "far", "farm", "farmer", "hard", "harder", "large", "mark", "market", "park", "parked",
        "parking", "part", "parts", "shark", "smart", "star", "stars", "start", "started", "yard"
    ]

    static func evaluate(_ sentence: PracticeSentence, evidence: PhoneEvidence,
                         dictionary: BritishPronunciations) -> SentenceFeedback {
        let heard = evidence.decodedPhones
        let labels = heard.map(\.label)
        guard sentence.canRecord, !labels.isEmpty else { return SentenceFeedback(tips: [], matchedSentence: false) }

        let words = sentence.words
        let references = words.map { dictionary[$0] }
        var pronunciations = references.map { $0.map(\.phones) }
        let linkingPositions = words.indices.map { canLinkR(at: $0, words: words, pronunciations: pronunciations) }
        for index in words.indices where linkingPositions[index] {
            pronunciations[index].append(contentsOf: references[index]
                .filter { $0.phones.last.map(BritishPronunciations.vowels.contains) == true }
                .map { $0.addingLinkingR.phones })
        }
        let rhoticVariants = words.indices.map { index -> Set<[String]> in
            guard !linkingPositions[index], startWords.contains(words[index].key) else { return [] }
            return Set(references[index].flatMap { pronunciation in
                pronunciation.longA.map { vowel in
                    var phones = pronunciation.phones
                    phones.insert("R", at: vowel + 1)
                    return phones
                }
            })
        }

        guard let matches = align(labels, with: pronunciations, rhoticVariants: rhoticVariants) else {
            return SentenceFeedback(tips: [], matchedSentence: false)
        }
        let known = words.indices.filter { !pronunciations[$0].isEmpty }
        let expectedCount = known.reduce(0) { $0 + (pronunciations[$1].first?.count ?? 0) }
        let editCount = known.reduce(0) { $0 + matches[$1].edits }
        guard expectedCount >= 2, known.count * 2 >= words.count,
              editCount <= max(1, expectedCount / 3) else {
            return SentenceFeedback(tips: [], matchedSentence: false)
        }

        let tips = known.compactMap { index -> SentenceFeedback.Tip? in
            let match = matches[index]
            guard !match.heard.isEmpty, (1...2).contains(match.edits),
                  words.count == 1 || matches.indices.contains(where: {
                      (1...2).contains(abs($0 - index)) && !pronunciations[$0].isEmpty && matches[$0].edits == 0
                  }) else { return nil }

            let observed = Array(labels[match.heard])
            let suggestions = references[index].flatMap {
                corrections(for: words[index].key, expected: $0, observed: observed,
                            permitsLinkingR: linkingPositions[index])
            }.sorted { $0.contextEdits < $1.contextEdits }
            guard !suggestions.isEmpty else { return nil }

            // Keep the blank frames at the word's edges and leave neighbouring speech outside.
            let start = match.heard.lowerBound
            let end = match.heard.upperBound
            let first = start == 0 ? 0 : (heard[start - 1].frames.upperBound + heard[start].frames.lowerBound) / 2
            let last = end == heard.count ? evidence.rows.count
                : (heard[end - 1].frames.upperBound + heard[end].frames.lowerBound) / 2
            let wordEvidence = evidence.slice(first..<last)
            for suggestion in suggestions {
                let contrast = PhonemeContrast(
                    target: (pronunciations[index] + [suggestion.reference]).map { $0.joined(separator: " ") },
                    alternative: [observed.joined(separator: " ")],
                    correction: suggestion.instruction
                )
                if wordEvidence.compare(contrast) == .alternative {
                    return SentenceFeedback.Tip(wordIndex: index, instruction: suggestion.instruction)
                }
            }
            return nil
        }
        return SentenceFeedback(tips: tips, matchedSentence: true)
    }

    private static func canLinkR(at index: Int, words: [PracticeSentence.Word],
                                 pronunciations: [[[String]]]) -> Bool {
        let word = words[index].key
        guard index + 1 < words.count, word.hasSuffix("r") || word.hasSuffix("re") else { return false }
        return pronunciations[index + 1].contains { $0.first.map(BritishPronunciations.vowels.contains) == true }
    }

    private static func corrections(for word: String, expected: BritishPronunciations.Pronunciation,
                                    observed: [String], permitsLinkingR: Bool) -> [Correction] {
        let phones = expected.phones
        var suggestions: [Correction] = []
        for index in phones.indices {
            for heardIndex in observed.indices {
                if let instruction = substitutionTip(for: word, expected: expected, at: index,
                                                     heard: observed[heardIndex]) {
                    let before = phoneEditDistance(observed[..<heardIndex], Array(phones[..<index]))
                    let after = phoneEditDistance(observed[(heardIndex + 1)...], Array(phones[(index + 1)...]))
                    guard before + after <= 1, observed.count > 1 else { continue }
                    var reference = observed
                    reference[heardIndex] = phones[index]
                    suggestions.append(Correction(contextEdits: before + after,
                                                  reference: reference, instruction: instruction))
                }

                if !permitsLinkingR, startWords.contains(word), expected.longA.contains(index),
                   heardIndex > 0, observed[heardIndex - 1] == "AA", observed[heardIndex] == "R" {
                    let before = phoneEditDistance(observed[..<heardIndex], Array(phones[...index]))
                    let after = phoneEditDistance(observed[(heardIndex + 1)...], Array(phones[(index + 1)...]))
                    guard before + after <= 1 else { continue }
                    var reference = observed
                    reference.remove(at: heardIndex)
                    suggestions.append(Correction(contextEdits: before + after, reference: reference,
                        instruction: "Let the ‘ah’ carry through without curling your tongue into an R."))
                }
            }
        }
        return suggestions
    }

    private static func substitutionTip(for word: String, expected: BritishPronunciations.Pronunciation,
                                        at index: Int, heard: String) -> String? {
        switch (expected.phones[index], heard) {
        case ("AA", "AE") where bathWords.contains(word) && expected.longA.contains(index):
            return "Open your jaw and let your tongue sit low for ‘ah’."
        case ("TH", "T"), ("TH", "S"), ("TH", "F"):
            return "Rest your tongue tip at your upper front teeth and let air flow past it."
        case ("V", "W"), ("V", "F"), ("V", "B"):
            return "Touch your upper teeth to your lower lip and keep a gentle buzz going."
        case ("IH", "IY") where expected.stressedShortI.contains(index):
            return "Lower your tongue slightly and keep the vowel short, like the ‘i’ in ‘sit’."
        case ("SH", "S"), ("SH", "CH"):
            return "Round your lips slightly and let the ‘sh’ air flow steadily."
        default:
            return nil
        }
    }

    private static func align(_ heard: [String], with words: [[[String]]],
                              rhoticVariants: [Set<[String]>]) -> [Match]? {
        var paths = Array(repeating: [Path?](repeating: nil, count: heard.count + 1), count: words.count + 1)
        paths[0][0] = Path(rank: 0, match: Match(heard: 0..<0, edits: 0))

        for (index, variants) in words.enumerated() {
            let maxLength = (variants.map(\.count).max() ?? 8) + 2
            for start in 0...heard.count {
                guard let previous = paths[index][start] else { continue }
                for length in 0...min(maxLength, heard.count - start) {
                    let span = start..<(start + length)
                    let edits = variants.map { phoneEditDistance(heard[span], $0) }.min() ?? 0
                    // Prefer full known words across otherwise equivalent word boundaries.
                    let penalty = variants.isEmpty ? (length == 0 ? 10 : 5 + length)
                        : 10 * edits + (edits == 0 ? 0 : 1) + (length == 0 ? 3 : 0)
                    // An extra R belongs with a plausible rhotic word when boundaries otherwise tie.
                    let rFitsWord = edits == 1 && !rhoticVariants[index].isEmpty
                        && rhoticVariants[index].contains(Array(heard[span]))
                    let rank = previous.rank + penalty - (rFitsWord ? 1 : 0)
                    guard rank < (paths[index + 1][span.upperBound]?.rank ?? Int.max) else { continue }
                    paths[index + 1][span.upperBound] = Path(rank: rank, match: Match(heard: span, edits: edits))
                }
            }
        }

        var endpoint = heard.count
        var matches: [Match] = []
        for count in (1...words.count).reversed() {
            guard let path = paths[count][endpoint] else { return nil }
            matches.append(path.match)
            endpoint = path.match.heard.lowerBound
        }
        return matches.reversed()
    }

}
