import Foundation
import FlowCore

@main struct FlowCLI {
    @MainActor static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args == ["capabilities"] {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let capabilities = await Capabilities.inspect()
                print(String(decoding: try encoder.encode(capabilities), as: UTF8.self))
            } else if args.first == "profile", args.count >= 2 {
                let store = try profileStore(args)
                var profile = try store.load()
                switch args[1] {
                case "show": break
                case "add-term":
                    guard args.count >= 3, !args[2].hasPrefix("--") else { throw FlowError("Supply the preferred term.") }
                    try profile.addTerm(GlossaryEntry(term: args[2],
                        aliases: (value("--aliases", in: args) ?? "").components(separatedBy: ","),
                        note: value("--note", in: args) ?? ""))
                    try store.save(profile)
                case "learn":
                    guard args.count >= 4 else { throw FlowError("Supply original.txt and corrected.txt.") }
                    let before = try String(contentsOfFile: args[2], encoding: .utf8)
                    let after = try String(contentsOfFile: args[3], encoding: .utf8)
                    let count = try profile.learn(before: before, after: after)
                    try store.save(profile)
                    FileHandle.standardError.write(Data(("Saved \(count) examples.\n").utf8))
                default: throw FlowError("Use profile show, add-term, or learn.")
                }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                print(String(decoding: try encoder.encode(profile), as: UTF8.self))
            } else if args.first == "transcribe", args.count >= 2 {
                let modeName = value("--mode", in: args) ?? "dual"
                guard let mode = TranscriptionMode(rawValue: modeName) else {
                    throw FlowError("Unknown mode '\(modeName)'. Use dual, english, or arabic.")
                }
                let url = URL(fileURLWithPath: args[1])
                let outputURL = value("--output", in: args).map { URL(fileURLWithPath: $0) }
                let report = try await ExperimentRunner().run(url: url, mode: mode,
                    allowDownloads: args.contains("--download-models"),
                    tryUnsupportedArabic: !args.contains("--respect-language-support"),
                    personalization: try readProfile(args),
                    status: { message in FileHandle.standardError.write(Data((message + "\n").utf8)) },
                    update: { report in
                        guard let outputURL else { return }
                        do { try report.json().write(to: outputURL, options: .atomic) }
                        catch { FileHandle.standardError.write(Data(("Could not save intermediate result: \(error.localizedDescription)\n").utf8)) }
                    })
                let data = try report.json()
                if let path = value("--output", in: args) {
                    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                } else { print(String(decoding: data, as: UTF8.self)) }
                if report.passes.isEmpty { exit(2) }
            } else if args.first == "clean", args.count >= 2 {
                let input = try String(contentsOfFile: args[1], encoding: .utf8)
                let result = try await LocalCleaner().clean(input, personalization: try readProfile(args))
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(result), as: UTF8.self))
            } else {
                print("""
                flowstate-cli capabilities
                flowstate-cli transcribe recording.m4a [--mode dual|english|arabic] [--download-models] [--output result.json]
                flowstate-cli clean transcript.txt
                flowstate-cli profile show
                flowstate-cli profile add-term Todoist --aliases 'to-doist,to doist' --note 'Task app'
                flowstate-cli profile learn original.txt corrected.txt

                Commands use the local profile. --profile path.json selects a separate profile.
                --no-personalization disables all vocabulary hints, aliases, and correction examples.

                Arabic LLM experiments run by default, even if advertised as unsupported.
                Use --respect-language-support to skip unsupported Arabic LLM trials.
                Model downloads require network access; audio and text inference stay local.
                """)
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
    static func profileStore(_ args: [String]) throws -> PersonalizationStore {
        if let path = value("--profile", in: args) { return PersonalizationStore(url: URL(fileURLWithPath: path)) }
        return try PersonalizationStore.local()
    }
    static func readProfile(_ args: [String]) throws -> PersonalizationProfile {
        if args.contains("--no-personalization") {
            var profile = PersonalizationProfile(); profile.enabled = false
            return profile
        }
        return try profileStore(args).load()
    }
    static func value(_ flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
}
