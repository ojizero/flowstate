import AVFoundation
import Foundation
import Speech

@MainActor public final class LocalTranscriber {
    public init() {}

    public func transcribe(url: URL, localeID: String, allowDownloads: Bool,
                           status: @escaping StatusHandler = { _ in }) async throws -> TranscriptPass {
        let begin = Date()
        let requested = Locale(identifier: localeID)
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { throw FlowError("This audio file is empty.") }

        if SpeechTranscriber.isAvailable,
           let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                                attributeOptions: [.audioTimeRange, .transcriptionConfidence])
            try await prepare(transcriber, locale: locale, allowDownloads: allowDownloads, status: status)
            let results = transcriber.results
            let pass = try await analyze(file: file, module: transcriber, results: results,
                                         locale: locale.identifier, engine: "SpeechTranscriber", begin: begin,
                                         text: { $0.text }, range: { $0.range }, status: status)
            return pass
        }
        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: requested) {
            let transcriber = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation],
                reportingOptions: [], attributeOptions: [.audioTimeRange, .transcriptionConfidence])
            try await prepare(transcriber, locale: locale, allowDownloads: allowDownloads, status: status)
            return try await analyze(file: file, module: transcriber, results: transcriber.results,
                locale: locale.identifier, engine: "DictationTranscriber", begin: begin,
                text: { $0.text }, range: { $0.range }, status: status)
        }
        throw FlowError("Apple has no supported on-device speech model for \(localeID) on this device. No server fallback was used.")
    }

    private func prepare(_ module: any SpeechModule, locale: Locale, allowDownloads: Bool,
                         status: StatusHandler) async throws {
        try Task.checkCancellation()
        if await AssetInventory.status(forModules: [module]) == .installed { return }
        guard allowDownloads else {
            throw FlowError("The \(locale.identifier) speech model is not installed. Enable model downloads for setup, then retry. Audio processing stays on this device.")
        }
        status("Downloading Apple's \(locale.identifier) speech model…")
        // Keep reservations for this app's two languages across runs. Never evict other locales.
        try await AssetInventory.reserve(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
        guard await AssetInventory.status(forModules: [module]) == .installed else {
            throw FlowError("Apple's \(locale.identifier) model is not ready. Try again after the download finishes.")
        }
    }

    private func analyze<R: SpeechModuleResult & Sendable, S: AsyncSequence & Sendable>(
        file: AVAudioFile, module: any SpeechModule, results: S, locale: String, engine: String, begin: Date,
        text: @escaping @Sendable (R) -> AttributedString, range: @escaping @Sendable (R) -> CMTimeRange,
        status: StatusHandler
    ) async throws -> TranscriptPass where S.Element == R {
        status("Transcribing \(locale) with \(engine)…")
        let preparationSeconds = Date().timeIntervalSince(begin)
        let audioDuration = Double(file.length) / file.processingFormat.sampleRate
        let analyzer = SpeechAnalyzer(modules: [module])
        // Consume results concurrently; finalize after EOF so the last words are not lost.
        let collector = Task { @MainActor in
            var raw = ""
            var tokens: [SpeechToken] = []
            for try await result in results {
                try Task.checkCancellation()
                let attributed = text(result)
                raw += String(attributed.characters)
                for run in attributed.runs {
                    let timing = run.audioTimeRange ?? range(result)
                    let start = CMTimeGetSeconds(timing.start)
                    let end = CMTimeGetSeconds(CMTimeRangeGetEnd(timing))
                    guard start.isFinite, end.isFinite, end >= start else { continue }
                    tokens.append(SpeechToken(text: String(attributed[run.range].characters), start: start, end: end,
                                              confidence: run.transcriptionConfidence))
                }
            }
            return (raw, tokens)
        }
        return try await withTaskCancellationHandler {
            do {
                if let last = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: last)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                let (raw, tokens) = try await collector.value
                try Task.checkCancellation()
                guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw FlowError("No speech was recognized by \(engine) for \(locale).")
                }
                return TranscriptPass(locale: locale, engine: engine, text: raw, tokens: tokens,
                                      elapsedSeconds: Date().timeIntervalSince(begin),
                                      preparationSeconds: preparationSeconds, audioDurationSeconds: audioDuration)
            } catch {
                collector.cancel()
                await analyzer.cancelAndFinishNow()
                _ = try? await collector.value
                throw error
            }
        } onCancel: {
            collector.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }
}
