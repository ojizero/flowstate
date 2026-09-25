import Foundation
import FoundationModels
import Speech

public struct Capabilities: Codable, Sendable {
    public var osVersion: String
    public var modelAvailability: String
    public var modelAvailable: Bool
    public var arabicCleanupSupported: Bool
    public var englishCleanupSupported: Bool
    public var modelLanguages: [String]
    public var speechLocales: [String]
    public var dictationLocales: [String]
    public var installedSpeechLocales: [String]
    public var installedDictationLocales: [String]

    @MainActor public static func inspect() async -> Capabilities {
        let model = SystemLanguageModel.default
        return await Capabilities(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            modelAvailability: String(describing: model.availability),
            modelAvailable: model.isAvailable,
            arabicCleanupSupported: model.supportsLocale(Locale(identifier: "ar-SA")),
            englishCleanupSupported: model.supportsLocale(Locale(identifier: "en-US")),
            modelLanguages: model.supportedLanguages.map(\.minimalIdentifier).sorted(),
            speechLocales: SpeechTranscriber.isAvailable ? SpeechTranscriber.supportedLocales.map(\.identifier).sorted() : [],
            dictationLocales: DictationTranscriber.supportedLocales.map(\.identifier).sorted(),
            installedSpeechLocales: SpeechTranscriber.installedLocales.map(\.identifier).sorted(),
            installedDictationLocales: DictationTranscriber.installedLocales.map(\.identifier).sorted()
        )
    }
}
