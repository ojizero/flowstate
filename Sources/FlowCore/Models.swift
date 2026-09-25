import Foundation

public enum TranscriptionMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case english, arabic, dual
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .english: "English"
        case .arabic: "Arabic"
        case .dual: "Arabic + English · experimental"
        }
    }
    public var locales: [String] {
        switch self {
        case .english: ["en-US"]
        case .arabic: ["ar-SA"]
        case .dual: ["ar-SA", "en-US"]
        }
    }
}

public struct SpeechToken: Codable, Sendable, Equatable {
    public var text: String
    public var start: Double
    public var end: Double
    public var confidence: Double?
    public init(text: String, start: Double, end: Double, confidence: Double? = nil) {
        self.text = text; self.start = start; self.end = end; self.confidence = confidence
    }
}

public struct TranscriptPass: Codable, Sendable {
    public var locale: String
    public var engine: String
    public var text: String
    public var tokens: [SpeechToken]
    public var elapsedSeconds: Double
    public var preparationSeconds: Double
    public var audioDurationSeconds: Double
    public var vocabularyHints: [String]?
    public var transcriptionSeconds: Double { max(0, elapsedSeconds - preparationSeconds) }
    public var realtimeFactor: Double? { audioDurationSeconds > 0 ? transcriptionSeconds / audioDurationSeconds : nil }
    public init(locale: String, engine: String, text: String, tokens: [SpeechToken], elapsedSeconds: Double,
                preparationSeconds: Double = 0, audioDurationSeconds: Double = 0) {
        self.locale = locale; self.engine = engine; self.text = text
        self.tokens = tokens; self.elapsedSeconds = elapsedSeconds
        self.preparationSeconds = preparationSeconds; self.audioDurationSeconds = audioDurationSeconds
    }
}

public struct MergeDecision: Codable, Sendable, Identifiable {
    public var id: Int
    public var start: Double
    public var end: Double
    public var arabicCandidate: String
    public var englishCandidate: String
    public var selectedLocale: String
    public var reason: String
}

public struct MergeResult: Codable, Sendable {
    public var text: String
    public var decisions: [MergeDecision]
}

public struct CleanupResult: Codable, Sendable {
    public var text: String
    public var method: String
    public var note: String
    public var elapsedSeconds: Double
    public var personalizationContext: [String]?
    public var aliasReplacements: Int?
}

public struct Experiment: Codable, Sendable {
    public var sourceName: String
    public var createdAt = Date()
    public var osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    public var mode: TranscriptionMode
    public var passes: [TranscriptPass] = []
    public var merge: MergeResult?
    public var cleanupInput = ""
    public var trials: [CleanupTrial] = []
    public var issues: [String] = []
    public var capabilities: Capabilities?
    public var mergeMargin: Double = 0.15
    public var attemptedUnsupportedArabic = true
    public var allowedModelDownloads = false
    public var pipelineVersion = "3"
    public var personalization: PersonalizationProfile?
    public init(sourceName: String, mode: TranscriptionMode) {
        self.sourceName = sourceName; self.mode = mode
    }
    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

public struct CleanupTrial: Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var input: String
    public var result: CleanupResult?
    public var error: String?
    public var elapsedSeconds: Double
    public var personalization: PersonalizationProfile?
    public init(id: String, title: String, input: String, result: CleanupResult? = nil,
                error: String? = nil, elapsedSeconds: Double = 0) {
        self.id = id; self.title = title; self.input = input
        self.result = result; self.error = error; self.elapsedSeconds = elapsedSeconds
    }
}

public struct FlowError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public typealias StatusHandler = @MainActor @Sendable (String) -> Void
