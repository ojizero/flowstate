import SwiftUI
import UniformTypeIdentifiers
#if canImport(FlowCore)
import FlowCore
#endif

@main struct FlowstateApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 860, minHeight: 640)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 820)
        #endif
    }
}

struct JSONDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor @Observable final class AppModel {
    var url: URL?
    var mode = TranscriptionMode.dual
    var allowDownloads = true
    var tryUnsupportedArabic = true
    var margin = 0.15
    var capabilities: Capabilities?
    var experiment: Experiment?
    var draft = ""
    var status = "Choose an exported Voice Memo to begin."
    var error: String?
    var busy = false
    private var task: Task<Void, Never>?

    func run() {
        guard let url, !busy else { return }
        busy = true; error = nil; experiment = nil; draft = ""
        task = Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
                busy = false; task = nil
            }
            do {
                experiment = try await ExperimentRunner().run(
                    url: url, mode: mode, allowDownloads: allowDownloads,
                    tryUnsupportedArabic: tryUnsupportedArabic, margin: margin,
                    status: { [weak self = self] in self?.status = $0 },
                    update: { [weak self = self] in self?.experiment = $0; self?.draft = $0.cleanupInput }
                )
                status = experiment?.passes.isEmpty == true ? "No transcription completed. See the errors below." :
                    "Experiments finished. Compare the results against your recording."
                capabilities = await Capabilities.inspect()
            } catch is CancellationError { status = "Cancelled. Completed stages are still available." }
            catch { self.error = error.localizedDescription; status = "Stopped." }
        }
    }

    func cleanDraft() {
        guard !busy, !draft.isEmpty else { return }
        busy = true; error = nil
        let input = draft
        task = Task {
            defer { busy = false; task = nil }
            let begin = Date()
            var trial = CleanupTrial(id: UUID().uuidString, title: "Edited draft → LLM cleanup", input: input)
            do {
                trial.result = try await LocalCleaner().clean(input, tryUnsupportedArabic: tryUnsupportedArabic,
                    status: { [weak self = self] in self?.status = $0 })
                status = "Draft cleanup finished."
            } catch is CancellationError { status = "Cancelled."; return }
            catch { trial.error = error.localizedDescription; status = "Draft cleanup failed. The input is preserved." }
            trial.elapsedSeconds = Date().timeIntervalSince(begin)
            experiment?.trials.append(trial)
        }
    }
    func cancel() { task?.cancel(); status = "Cancelling…" }

    func loadReport(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(Experiment.self, from: Data(contentsOf: url))
        experiment = report; draft = report.cleanupInput
        mode = report.mode; margin = report.mergeMargin
        tryUnsupportedArabic = report.attemptedUnsupportedArabic
        self.url = nil; error = nil
        status = "Loaded results for \(report.sourceName)."
    }
}

struct ContentView: View {
    @State private var model = AppModel()
    @State private var importing = false
    @State private var importingResults = false
    @State private var exporting = false
    @State private var exportDocument = JSONDocument(data: Data())
    @State private var selection = "results"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Flowstate").font(.title2.bold())
                    Text("Local speech + cleanup experiments").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open results…") { importingResults = true }.disabled(model.busy)
                Button("Export JSON") {
                    do { exportDocument = JSONDocument(data: try model.experiment?.json() ?? Data()); exporting = true }
                    catch { model.error = error.localizedDescription }
                }.disabled(model.experiment == nil)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("Choose recording…") { importing = true }.disabled(model.busy)
                        Text(model.url?.lastPathComponent ?? "Voice Memos .m4a, WAV, AIFF, or another audio file")
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Spacer()
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { controls }
                        VStack(alignment: .leading) { controls }
                    }
                    Toggle("Allow Apple speech model downloads if needed", isOn: $model.allowDownloads).disabled(model.busy)
                    Toggle("Try LLM Arabic cleanup even when Apple lists it as unsupported", isOn: $model.tryUnsupportedArabic).disabled(model.busy)
                    Text("Audio and text processing stay on this device. Initial model downloads need internet access.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(5)
            }
            HStack(spacing: 8) {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout).textSelection(.enabled)
                Spacer()
            }
            if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let issues = model.experiment?.issues {
                ForEach(issues, id: \.self) { Text($0).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            }
            Picker("View", selection: $selection) {
                Text("Outputs & timings").tag("results")
                Text("Merge & edit").tag("merge")
                Text("Device support").tag("support")
            }.pickerStyle(.segmented)

            switch selection {
            case "merge": mergeView
            case "support": supportView
            default: resultsView
            }
        }
        .padding(20)
        .task {
            model.capabilities = await Capabilities.inspect()
            let args = CommandLine.arguments
            if let index = args.firstIndex(of: "--results"), args.indices.contains(index + 1), model.experiment == nil {
                do { try model.loadReport(URL(fileURLWithPath: args[index + 1])) }
                catch { model.error = error.localizedDescription }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            do { model.url = try result.get().first; model.error = nil }
            catch { model.error = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                      defaultFilename: "flowstate-experiment") { result in
            if case .failure(let error) = result { model.error = error.localizedDescription }
        }
        .fileImporter(isPresented: $importingResults, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                try model.loadReport(url)
                selection = "results"
            } catch { model.error = error.localizedDescription }
        }
    }

    @ViewBuilder private var controls: some View {
        Picker("Passes", selection: $model.mode) {
            ForEach(TranscriptionMode.allCases) { Text($0.title).tag($0) }
        }.frame(maxWidth: 400).disabled(model.busy)
        if model.busy { Button("Cancel", role: .cancel) { model.cancel() } }
        else {
            Button("Run experiments") { model.run() }
                .buttonStyle(.borderedProminent).disabled(model.url == nil)
        }
    }

    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let experiment = model.experiment {
                    ForEach(experiment.passes, id: \.locale) { pass in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(pass.locale) · \(pass.engine)").font(.headline)
                                    Spacer()
                                    Text("\(pass.transcriptionSeconds, specifier: "%.2f") s transcription").monospacedDigit()
                                }
                                Text("Preparation: \(pass.preparationSeconds, specifier: "%.2f") s · Audio: \(pass.audioDurationSeconds, specifier: "%.1f") s · RTF: \(pass.realtimeFactor ?? 0, specifier: "%.3f")")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("RTF below 1 means faster than the recording's duration. Preparation includes any model download.")
                                    .font(.caption2).foregroundStyle(.secondary)
                                transcriptText(pass.text)
                            }.padding(5)
                        }
                    }
                    ForEach(experiment.trials) { trial in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(trial.title).font(.headline)
                                    Spacer()
                                    Text("\(trial.elapsedSeconds, specifier: "%.2f") s").monospacedDigit()
                                }
                                if let result = trial.result {
                                    Text(result.method).font(.caption).foregroundStyle(.secondary)
                                    if trial.id == "reconcile" {
                                        transcriptText(result.text)
                                    } else {
                                        ViewThatFits(in: .horizontal) {
                                            HStack(alignment: .top, spacing: 20) {
                                                comparisonColumn("Input", text: trial.input).frame(minWidth: 280)
                                                Divider()
                                                comparisonColumn("Cleaned", text: result.text).frame(minWidth: 280)
                                            }.fixedSize(horizontal: false, vertical: true)
                                            VStack(alignment: .leading, spacing: 12) {
                                                comparisonColumn("Input", text: trial.input)
                                                comparisonColumn("Cleaned", text: result.text)
                                            }
                                        }
                                    }
                                    Text(result.note).font(.caption).foregroundStyle(.secondary)
                                }
                                if let error = trial.error {
                                    Text("Failed: \(error)").foregroundStyle(.orange).textSelection(.enabled)
                                }
                                DisclosureGroup("Input for this trial") { transcriptText(trial.input) }
                            }.padding(5)
                        }
                    }
                } else {
                    ContentUnavailableView("Choose a recording", systemImage: "waveform",
                        description: Text("Dual mode tests both recognizers, each transcript's cleanup, a confidence merge, and LLM reconciliation. Raw outputs are always kept."))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var mergeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("The confidence merge is an experimental baseline. The two engines' scores are not calibrated. Ambiguous overlaps keep the Arabic candidate.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Text("English confidence margin")
                    Slider(value: $model.margin, in: 0...0.5, step: 0.05).frame(maxWidth: 200).disabled(model.busy)
                    Text(model.margin, format: .number.precision(.fractionLength(2))).monospacedDigit()
                }
                Text("The margin applies to the next run. Edit this draft to test cleanup independently.").font(.caption)
                TextEditor(text: $model.draft).frame(minHeight: 180).border(.quaternary).disabled(model.busy)
                Button("Clean edited draft") { model.cleanDraft() }.disabled(model.busy || model.draft.isEmpty)
                if let merge = model.experiment?.merge {
                    ForEach(merge.decisions) { decision in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(decision.start, specifier: "%.2f")–\(decision.end, specifier: "%.2f") s · Selected \(decision.selectedLocale)").font(.headline)
                                Text("Arabic pass: \(decision.arabicCandidate)").textSelection(.enabled)
                                Text("English pass: \(decision.englishCandidate)").textSelection(.enabled)
                                Text(decision.reason).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                        }
                    }
                }
            }
        }
    }

    private var supportView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let c = model.capabilities {
                    Text(c.osVersion).font(.headline)
                    Text("Foundation Models: \(c.modelAvailability)")
                    Text("Advertised Arabic cleanup support: \(c.arabicCleanupSupported ? "yes" : "no")")
                    Text("An unsupported language may still produce output, refuse, or fail. The experiment records what happens.")
                    DisclosureGroup("LLM languages") { Text(c.modelLanguages.joined(separator: ", ")).textSelection(.enabled) }
                    DisclosureGroup("SpeechTranscriber locales") { Text(c.speechLocales.joined(separator: ", ")).textSelection(.enabled) }
                    DisclosureGroup("DictationTranscriber locales") { Text(c.dictationLocales.joined(separator: ", ")).textSelection(.enabled) }
                    Text("Installed speech: \(c.installedSpeechLocales.joined(separator: ", "))")
                    Text("Installed dictation: \(c.installedDictationLocales.joined(separator: ", "))")
                }
                Button("Refresh support") { Task { model.capabilities = await Capabilities.inspect() } }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func transcriptText(_ text: String) -> some View {
        Text(text).font(.body).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
    }

    private func comparisonColumn(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            transcriptText(text)
        }
    }
}
