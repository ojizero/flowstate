import Foundation

public enum TextProcessing {
    public static func containsArabic(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            // Include presentation forms as well as ordinary Arabic letters.
            CharacterSet.letters.contains($0) &&
            ((0x0600...0x06FF).contains($0.value) || (0x0750...0x077F).contains($0.value) ||
             (0x08A0...0x08FF).contains($0.value) || (0xFB50...0xFDFF).contains($0.value) ||
             (0xFE70...0xFEFF).contains($0.value))
        }
    }

    public static func whitespaceOnly(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lossless, Unicode-safe chunks. The byte budget is conservative for the OS 26 context window.
    /// Prefer sentence/word boundaries; never discard the tail of a long recording.
    public static func chunks(_ text: String, maxBytes: Int = 1200) -> [String] {
        precondition(maxBytes > 0)
        var remaining = text[...]
        var output: [String] = []
        while !remaining.isEmpty {
            var cursor = remaining.startIndex
            var bytes = 0
            var wordBreak: String.Index?
            var sentenceBreak: String.Index?
            while cursor < remaining.endIndex {
                let next = remaining.index(after: cursor)
                let size = remaining[cursor..<next].utf8.count
                if bytes + size > maxBytes && cursor > remaining.startIndex { break }
                bytes += size
                if remaining[cursor].isWhitespace { wordBreak = next }
                if ".!?؟\n".contains(remaining[cursor]) { sentenceBreak = next }
                cursor = next
            }
            let end: String.Index
            if cursor == remaining.endIndex { end = cursor }
            else if let boundary = sentenceBreak, remaining[..<boundary].utf8.count >= maxBytes / 2 { end = boundary }
            else { end = wordBreak ?? cursor }
            output.append(String(remaining[..<end]))
            remaining = remaining[end...]
        }
        return output
    }
}
