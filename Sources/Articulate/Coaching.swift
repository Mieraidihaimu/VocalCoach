import Foundation

enum PracticeAccent: String, CaseIterable, Identifiable {
    case british
    case american

    var id: Self { self }
    var title: String { self == .british ? "Modern British RP" : "American English" }
    var voiceLocale: String { self == .british ? "en-GB" : "en-US" }
    var drills: [PracticeDrill] { self == .british ? PracticeDrill.britishDrills : PracticeDrill.drills }
}

struct PracticeDrill: Identifiable, Equatable, Sendable {
    let id: String
    let symbol: String
    let category: String
    let title: String
    let phrase: String
    let focusWord: String
    let cueTitle: String
    let cue: String
    let check: String
    var recordedExample: String? = nil
    fileprivate var homophones: Set<String> = []
    fileprivate var contrasts: [String: String] = [:]
    var diagram: String? = nil
    var phonemeContrast: PhonemeContrast? = nil

    static let drills: [PracticeDrill] = [
        PracticeDrill(
            id: "th",
            symbol: "/θ/",
            category: "Tongue + teeth",
            title: "Quiet TH",
            phrase: "Try thin again.",
            focusWord: "thin",
            cueTitle: "Tongue at the front teeth",
            cue: "Touch your tongue tip lightly to your upper front teeth. Let a thin stream of air pass over it.",
            check: "Hold the airy ‘th’ for a beat before saying the rest of ‘thin.’",
            contrasts: [
                "tin": "Keep air flowing over your tongue tip at the front teeth. Stretch the ‘th’ before saying ‘in.’",
                "sin": "Bring your tongue tip forward to the edge of your upper front teeth. Keep the air flowing.",
                "fin": "Relax your lower lip and bring your tongue tip to your upper front teeth. Blow gently."
            ]
        ),
        PracticeDrill(
            id: "r",
            symbol: "/ɹ/",
            category: "Tongue",
            title: "American R",
            phrase: "Is that right?",
            focusWord: "right",
            cueTitle: "Raise the middle of your tongue",
            cue: "Lift the middle of your tongue toward the roof of your mouth. Keep the tip free.",
            check: "Try feeling the sides of your tongue against your upper back teeth.",
            homophones: ["write", "rite", "wright"],
            contrasts: [
                "light": "Keep your tongue tip clear of the ridge behind your top teeth. Lift the middle for the ‘r.’",
                "white": "Lift the middle of your tongue and feel its sides touch your upper back teeth. Then say ‘right.’"
            ]
        ),
        PracticeDrill(
            id: "v",
            symbol: "/v/",
            category: "Lips + teeth",
            title: "Voiced V",
            phrase: "Did you say vest?",
            focusWord: "vest",
            cueTitle: "Lower lip at the upper teeth",
            cue: "Touch your upper front teeth lightly to your lower lip. Let air pass while your voice buzzes.",
            check: "Hold the ‘v’ and feel for a gentle vibration in your throat.",
            contrasts: [
                "west": "Lift your lower lip until it brushes your upper teeth. Start ‘vest’ with a gentle buzz.",
                "best": "Touch your upper teeth to your lower lip. Keep the air moving as you start to buzz.",
                "fest": "Keep your upper teeth on your lower lip and turn your voice on. Feel for a gentle buzz in your throat."
            ]
        ),
        PracticeDrill(
            id: "short-i",
            symbol: "/ɪ/",
            category: "Tongue + jaw",
            title: "Short I",
            phrase: "Say ship again.",
            focusWord: "ship",
            cueTitle: "Relax your jaw and tongue",
            cue: "Start from the ‘ee’ in ‘sheep.’ Let your jaw open slightly and lower your tongue a little.",
            check: "Alternate ‘sheep’ and ‘ship’ and feel your tongue lower for ‘ship.’",
            contrasts: [
                "sheep": "Let your tongue sit a little lower and farther back than for ‘sheep.’ Keep the vowel in ‘ship’ brief."
            ]
        ),
        PracticeDrill(
            id: "short-a",
            symbol: "/æ/",
            category: "Jaw + tongue",
            title: "Short A",
            phrase: "Say bat one more time.",
            focusWord: "bat",
            cueTitle: "Open your jaw",
            cue: "Let your jaw drop and keep the front of your tongue low and forward. Keep your lips loose.",
            check: "Alternate ‘bet’ and ‘bat’ and feel your jaw open wider for ‘bat.’",
            contrasts: [
                "bet": "Open your jaw a little wider and lower the front of your tongue to get from ‘bet’ to ‘bat.’",
                "but": "With your jaw open, move the front of your tongue forward for the vowel in ‘bat.’"
            ]
        ),
        PracticeDrill(
            id: "sh",
            symbol: "/ʃ/",
            category: "Tongue + lips",
            title: "SH sound",
            phrase: "Try shoe again.",
            focusWord: "shoe",
            cueTitle: "Raise your tongue and round your lips",
            cue: "Raise your tongue just behind the ridge that makes ‘s.’ Round your lips slightly and let air flow.",
            check: "Hold the ‘sh’ for a beat, then glide into the ‘oo’ in ‘shoe.’",
            contrasts: [
                "sue": "Move your tongue slightly back from ‘s’ and round your lips a little before you start ‘shoe.’",
                "chew": "Start with a steady stream of air. Hold the ‘sh’ and let it flow into the vowel."
            ]
        )
    ]

    static let britishDrills: [PracticeDrill] = [
        PracticeDrill(
            id: "rp-bath",
            symbol: "/ɑː/",
            category: "Jaw + tongue",
            title: "BATH vowel",
            phrase: "Bath.",
            focusWord: "bath",
            cueTitle: "Open your jaw",
            cue: "Let your jaw drop. Let your tongue sit low and slightly back, with your lips relaxed.",
            check: "Keep the vowel steady for a beat, then release into a soft ‘th’.",
            recordedExample: "bath",
            diagram: "long-a",
            phonemeContrast: PhonemeContrast(
                leading: ["B"],
                target: ["AA"], alternative: ["AE"],
                trailing: ["TH"],
                correction: "Open your jaw a little more and let your tongue settle back. Hold ‘ah’ briefly before the ‘th’."
            )
        ),
        PracticeDrill(
            id: "rp-final-r",
            symbol: "/ɑː/",
            category: "Vowel + tongue",
            title: "Word-final R",
            phrase: "Park the car.",
            focusWord: "car",
            cueTitle: "Finish on the vowel",
            cue: "Let the open ‘ah’ ring out at the end of ‘car’. Keep your tongue low until the sound fades.",
            check: "Try ‘car’ on its own, then ‘park the car’. End both on ‘ah’.",
            recordedExample: "sports car",
            diagram: "long-a",
            phonemeContrast: PhonemeContrast(
                leading: ["P AA K DH AH K", "P AA R K DH AH K"],
                target: ["AA"], alternative: ["AA R", "ER"],
                correction: "Keep your tongue relaxed after ‘ah’. Let the vowel finish ‘car’ before your tongue lifts."
            )
        ),
        PracticeDrill(
            id: "rp-linking-r",
            symbol: "/ɹ/",
            category: "Tongue + timing",
            title: "Linking R",
            phrase: "Far away.",
            focusWord: "far",
            cueTitle: "Join the vowels with R",
            cue: "As you move into ‘away’, lift the middle of your tongue briefly for ‘r’ and keep the words flowing.",
            check: "Say ‘far’ by itself, then join it to ‘away’. Feel the brief lift between the vowels.",
            recordedExample: "far away",
            diagram: "r",
            phonemeContrast: PhonemeContrast(
                leading: ["F"],
                target: ["AA R AH"], alternative: ["AA AH"],
                trailing: ["W EY"],
                correction: "Add a light ‘r’ as you move from the ‘ah’ into ‘away’. Keep the two words connected."
            )
        ),
        PracticeDrill(
            id: "rp-th",
            symbol: "/θ/",
            category: "Tongue + teeth",
            title: "Quiet TH",
            phrase: "Try thin again.",
            focusWord: "thin",
            cueTitle: "Tongue at the front teeth",
            cue: "Rest the tip of your tongue lightly at the edge of your upper front teeth. Let air flow over it.",
            check: "Hold the airy ‘th’ briefly, then glide into ‘in’.",
            recordedExample: "thin",
            diagram: "th",
            phonemeContrast: PhonemeContrast(
                leading: ["T R AY", "CH R AY"],
                target: ["TH IH N"], alternative: ["T IH N", "S IH N", "F IH N"],
                trailing: ["AH G EH N", "AH G EY N"],
                correction: "Bring your tongue tip to the edge of your upper front teeth and let the air keep flowing."
            )
        ),
        PracticeDrill(
            id: "rp-short-i",
            symbol: "/ɪ/",
            category: "Tongue + jaw",
            title: "Short I",
            phrase: "Say ship again.",
            focusWord: "ship",
            cueTitle: "Relax your jaw and tongue",
            cue: "Start from the ‘ee’ in ‘sheep’. Let your jaw open slightly and your tongue settle a little lower.",
            check: "Alternate ‘sheep’ and ‘ship’ and feel the tongue lower for ‘ship’.",
            recordedExample: "a ship",
            diagram: "short-i",
            phonemeContrast: PhonemeContrast(
                leading: ["S EY"],
                target: ["SH IH P"], alternative: ["SH IY P"],
                trailing: ["AH G EH N", "AH G EY N"],
                correction: "Open your jaw slightly and lower your tongue from the ‘ee’ in ‘sheep’. Keep ‘ship’ brief."
            )
        ),
        PracticeDrill(
            id: "rp-v",
            symbol: "/v/",
            category: "Lips + teeth",
            title: "Voiced V",
            phrase: "Say vest again.",
            focusWord: "vest",
            cueTitle: "Lower lip at the upper teeth",
            cue: "Lightly touch your upper front teeth to your lower lip. Let air pass while your voice buzzes.",
            check: "Hold the ‘v’ briefly and feel a gentle vibration in your throat.",
            recordedExample: "vestige",
            diagram: "v",
            phonemeContrast: PhonemeContrast(
                leading: ["S EY"],
                target: ["V EH S T"], alternative: ["W EH S T", "F EH S T", "B EH S T"],
                trailing: ["AH G EH N", "AH G EY N"],
                correction: "Touch your upper teeth to your lower lip. Keep a gentle buzz going as the air moves past."
            )
        )
    ]
}

struct CoachingFeedback: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case recognized
        case adjust
        case retry
    }

    let kind: Kind
    let title: String
    let detail: String
    let transcript: String

    static func evaluate(transcript: String, drill: PracticeDrill) -> CoachingFeedback {
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let heard = words(in: transcript)
        let expected = words(in: drill.phrase)
        let targetWords = drill.homophones.union([drill.focusWord])

        // A contrast cue needs the rest of the phrase to match so the word is
        // compared at the intended position. An isolated target is also useful practice.
        if let focusIndex = expected.firstIndex(of: drill.focusWord),
           heard.count == expected.count,
           heard.indices.allSatisfy({ $0 == focusIndex || heard[$0] == expected[$0] }) {
            let heardWord = heard[focusIndex]
            if targetWords.contains(heardWord) {
                return recognized(transcript: transcript, drill: drill)
            }
            if let cue = drill.contrasts[heardWord] {
                return CoachingFeedback(
                    kind: .adjust,
                    title: "Heard ‘\(heardWord)’",
                    detail: cue,
                    transcript: transcript
                )
            }
        }

        if heard.count == 1, let word = heard.first, targetWords.contains(word) {
            return recognized(transcript: transcript, drill: drill)
        }

        return CoachingFeedback(
            kind: .retry,
            title: heard.isEmpty ? "No words heard yet" : "Try the whole phrase again",
            detail: heard.isEmpty ? "Speak the phrase once at a comfortable volume." : drill.cue,
            transcript: transcript
        )
    }

    private static func recognized(transcript: String, drill: PracticeDrill) -> CoachingFeedback {
        CoachingFeedback(
            kind: .recognized,
            title: "Heard ‘\(drill.focusWord)’",
            detail: drill.check,
            transcript: transcript
        )
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}
