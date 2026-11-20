import Foundation

struct VowelFocus: Sendable {
    let symbol: String
    let cue: String
    let supportsMeasurement: Bool
}

struct BritishVowelGuide: Sendable {
    private static let steadyCues = [
        "ɑː": "Drop your jaw and keep your tongue low and slightly back for “ah”.",
        "ɪ": "Start from “ee”, then let your tongue relax slightly down and back. Keep the vowel short.",
        "iː": "Lift the front of your tongue near the roof of your mouth and gently spread your lips for “ee”.",
        "i": "Lift the front of your tongue for a light “ee”.",
        "æ": "Open your jaw and keep the front of your tongue low, as in “cat”.",
        "ɛ": "Keep your jaw slightly open and the front of your tongue midway up, as in “bed”.",
        "ɒ": "Drop your jaw slightly and round your lips loosely, as in “lot”.",
        "ɔː": "Round your lips and lift the back of your tongue a little, as in “thought”.",
        "ʊ": "Round your lips gently and keep the back of your tongue relaxed. Keep the vowel short.",
        "uː": "Round your lips gently and lift your tongue for “oo”.",
        "ɐ": "Relax your lips and keep your tongue low and near the middle, as in “cup”.",
        "ʌ": "Relax your lips and keep your tongue low and near the middle, as in “cup”.",
        "ɜː": "Keep your tongue in the middle and your lips relaxed, as in “bird”.",
        "ə": "Relax your tongue and jaw for a light “uh”."
    ]
    private static let glideCues = [
        "aɪ": "Begin with an open jaw, then lift the front of your tongue toward “ih”, as in “time”.",
        "aʊ": "Begin with an open jaw, then gently round your lips, as in “mouth”.",
        "eɪ": "Start with the front of your tongue midway up, then lift it slightly, as in “day”.",
        "əʊ": "Start in the middle of your mouth, then round your lips gently, as in “go”.",
        "ɔɪ": "Start with rounded lips, then lift the front of your tongue, as in “boy”.",
        "ɛə": "Start with a relaxed “eh”, then ease your tongue toward the centre.",
        "ɪə": "Start from “ih”, then ease your tongue toward the centre.",
        "ʊə": "Start with lightly rounded lips, then relax toward the centre."
    ]

    static let bundled = BritishVowelGuide(contentsOf: Bundle.main.url(
        forResource: "britfone.main.3.0.1", withExtension: "csv", subdirectory: "Pronunciation"
    ))

    private let entries: [String: VowelFocus]

    init(contentsOf url: URL?) {
        let dictionary = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        var pronunciations: [String: [(vowel: String, steady: Bool)]] = [:]
        for line in dictionary.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: ",", maxSplits: 1)
            guard fields.count == 2, let name = fields[0].split(separator: "(").first else { continue }
            let vowels = fields[1].split(whereSeparator: \.isWhitespace).compactMap { token -> (String, Bool)? in
                let ipa = String(token.drop(while: { $0 == "ˈ" || $0 == "ˌ" }))
                guard Self.steadyCues[ipa] != nil || Self.glideCues[ipa] != nil else { return nil }
                return (ipa, token.hasPrefix("ˈ"))
            }
            guard let focus = vowels.first(where: { $0.1 }) ?? vowels.first else { continue }
            pronunciations[name.lowercased(), default: []].append((focus.0, vowels.count == 1 && Self.steadyCues[focus.0] != nil))
        }
        entries = pronunciations.compactMapValues { variants in
            guard let first = variants.first, variants.allSatisfy({ $0.vowel == first.vowel }),
                  let cue = Self.steadyCues[first.vowel] ?? Self.glideCues[first.vowel] else { return nil }
            return VowelFocus(symbol: first.vowel, cue: cue, supportsMeasurement: variants.allSatisfy(\.steady))
        }
    }

    subscript(key: String) -> VowelFocus? { entries[key] }
}
