import Foundation
import Testing
@testable import FlowCore

@Test func chunkingPreservesEveryCharacterInMixedScriptInput() {
    let text = String(repeating: "مرحبا، خلينا نراجع الـ pull request. Version 2.5 is ready! 👨‍👩‍👧‍👦\n", count: 100)
    let chunks = TextProcessing.chunks(text, maxBytes: 120)
    #expect(chunks.joined() == text)
    #expect(chunks.allSatisfy { !$0.isEmpty && $0.utf8.count <= 120 })
}

@Test func chunkingHandlesLongUnbrokenInputAndEmptyInput() {
    #expect(TextProcessing.chunks("").isEmpty)
    let text = String(repeating: "ع", count: 4000)
    let chunks = TextProcessing.chunks(text, maxBytes: 99)
    #expect(chunks.joined() == text)
    #expect(chunks.allSatisfy { $0.utf8.count <= 99 })
}

@Test func confidenceMergeCanRetainArabicAndSelectEnglishInOneSentence() {
    let result = TranscriptMerger.merge(arabic: [
        SpeechToken(text: "افتح", start: 0, end: 0.5, confidence: 0.95),
        SpeechToken(text: "بول", start: 0.6, end: 1, confidence: 0.3),
        SpeechToken(text: "ريكويست", start: 1.1, end: 1.5, confidence: 0.3)
    ], english: [
        SpeechToken(text: "after", start: 0, end: 0.5, confidence: 0.2),
        SpeechToken(text: "pull", start: 0.6, end: 1, confidence: 0.95),
        SpeechToken(text: "request", start: 1.1, end: 1.5, confidence: 0.95)
    ])
    #expect(result.text == "افتح pull request")
    #expect(result.decisions.count == 3)
}

@Test func missingConfidenceDoesNotSilentlyFavorEnglish() {
    let result = TranscriptMerger.merge(
        arabic: [SpeechToken(text: "مرحبا", start: 0, end: 1)],
        english: [SpeechToken(text: "maybe", start: 0, end: 1, confidence: 0.99)]
    )
    #expect(result.text == "مرحبا")
    #expect(result.decisions[0].englishCandidate == "maybe")
}

@Test func mergeKeepsUnopposedTailAndAvoidsDuplicatingOverlaps() {
    let result = TranscriptMerger.merge(
        arabic: [SpeechToken(text: "واحد اثنين", start: 0, end: 2, confidence: 0.9)],
        english: [SpeechToken(text: "one", start: 0, end: 1), SpeechToken(text: "two", start: 1, end: 2),
                  SpeechToken(text: "done", start: 3, end: 4)]
    )
    #expect(result.text == "واحد اثنين done")
    #expect(result.decisions.count == 2)
}

@Test func fallbackDoesNotRemoveWordsOrChangeLanguages() {
    #expect(TextProcessing.whitespaceOnly("  مرحبا   world \n\n  123 ") == "مرحبا world\n\n123")
    #expect(TextProcessing.containsArabic("hello مرحبا"))
    #expect(!TextProcessing.containsArabic("hello 123"))
}
