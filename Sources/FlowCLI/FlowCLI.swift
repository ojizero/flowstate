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
                let result = try await LocalCleaner().clean(input)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(result), as: UTF8.self))
            } else {
                print("""
                flowstate-cli capabilities
                flowstate-cli transcribe recording.m4a [--mode dual|english|arabic] [--download-models] [--output result.json]
                flowstate-cli clean transcript.txt

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
    static func value(_ flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
}
