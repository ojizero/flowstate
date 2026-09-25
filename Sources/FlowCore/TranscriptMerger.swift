import Foundation

/// A deliberately inspectable baseline, not a multilingual recognizer.
/// Overlapping timestamp runs form groups. Prefer Arabic unless every English run
/// has confidence and its mean exceeds Arabic by the selected margin.
/// Scores from different engines are NOT calibrated; all choices remain reviewable.
public enum TranscriptMerger {
    private struct Tagged {
        let token: SpeechToken
        let arabic: Bool
    }

    public static func merge(arabic: [SpeechToken], english: [SpeechToken], margin: Double = 0.15) -> MergeResult {
        let items = (arabic.map { Tagged(token: $0, arabic: true) } +
                     english.map { Tagged(token: $0, arabic: false) })
            .filter { !$0.token.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                if $0.token.start == $1.token.start { return $0.arabic && !$1.arabic }
                return $0.token.start < $1.token.start
            }
        var groups: [[Tagged]] = []
        var group: [Tagged] = []
        var groupEnd = -Double.infinity
        for item in items {
            // A 20 ms tolerance avoids joining adjacent words through tiny timestamp jitter.
            if !group.isEmpty && item.token.start >= groupEnd - 0.02 {
                groups.append(group); group = []
                groupEnd = -Double.infinity
            }
            group.append(item)
            groupEnd = max(groupEnd, item.token.end)
        }
        if !group.isEmpty { groups.append(group) }

        var decisions: [MergeDecision] = []
        var selected: [String] = []
        for group in groups {
            let ar = group.filter(\.arabic).map(\.token)
            let en = group.filter { !$0.arabic }.map(\.token)
            let arText = joined(ar), enText = joined(en)
            let pickEnglish: Bool
            let reason: String
            if ar.isEmpty {
                pickEnglish = true; reason = "Only the English pass returned words here."
            } else if en.isEmpty {
                pickEnglish = false; reason = "Only the Arabic pass returned words here."
            } else if let a = meanConfidence(ar), let e = meanConfidence(en), e > a + margin {
                pickEnglish = true
                reason = "English confidence exceeds Arabic by the margin. Cross-engine scores are uncalibrated; review this choice."
            } else {
                pickEnglish = false
                reason = "Ambiguous overlap; kept the Arabic baseline. Missing confidence is not evidence of accuracy."
            }
            selected.append(pickEnglish ? enText : arText)
            decisions.append(MergeDecision(
                id: decisions.count, start: group.map(\.token.start).min() ?? 0,
                end: group.map(\.token.end).max() ?? 0,
                arabicCandidate: arText, englishCandidate: enText,
                selectedLocale: pickEnglish ? "en-US" : "ar-SA", reason: reason
            ))
        }
        return MergeResult(text: selected.joined(separator: " "), decisions: decisions)
    }

    private static func joined(_ tokens: [SpeechToken]) -> String {
        tokens.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " ")
    }
    private static func meanConfidence(_ tokens: [SpeechToken]) -> Double? {
        let scores = tokens.compactMap(\.confidence)
        guard scores.count == tokens.count, !scores.isEmpty, scores.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }
}
