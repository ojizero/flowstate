import Foundation

@MainActor public final class ExperimentRunner {
    public init() {}

    public func run(url: URL, mode: TranscriptionMode, allowDownloads: Bool = false,
                    tryUnsupportedArabic: Bool = true, margin: Double = 0.15,
                    status: @escaping StatusHandler = { _ in },
                    update: @escaping @MainActor @Sendable (Experiment) -> Void = { _ in }) async throws -> Experiment {
        var experiment = Experiment(sourceName: url.lastPathComponent, mode: mode)
        experiment.capabilities = await Capabilities.inspect()
        experiment.mergeMargin = margin
        experiment.attemptedUnsupportedArabic = tryUnsupportedArabic
        experiment.allowedModelDownloads = allowDownloads
        let transcriber = LocalTranscriber()
        // Separate passes avoid competing speech models and make stage timings easier to interpret.
        for locale in mode.locales {
            try Task.checkCancellation()
            let attemptBegin = Date()
            do {
                let pass = try await transcriber.transcribe(url: url, localeID: locale, allowDownloads: allowDownloads, status: status)
                experiment.passes.append(pass)
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                let elapsed = String(format: "%.2f", Date().timeIntervalSince(attemptBegin))
                experiment.issues.append("\(locale) failed after \(elapsed) s: \(error.localizedDescription)")
            }
            update(experiment)
        }
        guard !experiment.passes.isEmpty else { return experiment }
        if let arabic = experiment.passes.first(where: { $0.locale.hasPrefix("ar") }),
           let english = experiment.passes.first(where: { $0.locale.hasPrefix("en") }) {
            experiment.merge = TranscriptMerger.merge(arabic: arabic.tokens, english: english.tokens, margin: margin)
        }
        experiment.cleanupInput = experiment.merge?.text ?? experiment.passes[0].text
        update(experiment)

        var inputs = experiment.passes.map { (id: $0.locale, title: "\($0.locale) transcript → LLM cleanup", text: $0.text) }
        if let merge = experiment.merge {
            inputs.append((id: "heuristic", title: "Confidence merge → LLM cleanup", text: merge.text))
        }
        let cleaner = LocalCleaner()
        for input in inputs {
            try Task.checkCancellation()
            status(input.title)
            let begin = Date()
            var trial = CleanupTrial(id: input.id, title: input.title, input: input.text)
            do {
                trial.result = try await cleaner.clean(input.text, tryUnsupportedArabic: tryUnsupportedArabic, status: status)
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                trial.error = error.localizedDescription
            }
            trial.elapsedSeconds = Date().timeIntervalSince(begin)
            experiment.trials.append(trial)
            update(experiment)
        }
        if let merge = experiment.merge, tryUnsupportedArabic {
            try Task.checkCancellation()
            let begin = Date()
            var trial = CleanupTrial(id: "reconcile", title: "Both candidates → LLM reconcile + clean",
                                     input: "Timestamped candidates in the exported merge decisions.")
            do { trial.result = try await cleaner.reconcile(merge, status: status) }
            catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                trial.error = error.localizedDescription
            }
            trial.elapsedSeconds = Date().timeIntervalSince(begin)
            experiment.trials.append(trial)
            update(experiment)
        }
        return experiment
    }
}
