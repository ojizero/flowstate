import Foundation

public struct GlossaryEntry: Codable, Sendable, Identifiable, Equatable {
    public var id = UUID()
    public var term: String
    public var aliases: [String]
    public var note: String
    public init(term: String, aliases: [String] = [], note: String = "") {
        self.term = term; self.aliases = aliases; self.note = note
    }
}

public struct SavedCorrection: Codable, Sendable, Identifiable, Equatable {
    public var id = UUID()
    public var before: String
    public var after: String
    public var matchPhrase: String
    public var speechHint: String?
    public var replacementPhrase: String?
    public var savedAt = Date()
    public init(before: String, after: String, matchPhrase: String, speechHint: String? = nil, replacementPhrase: String? = nil) {
        self.before = before; self.after = after; self.matchPhrase = matchPhrase; self.speechHint = speechHint
        self.replacementPhrase = replacementPhrase
    }
}

public struct PersonalizationProfile: Codable, Sendable, Equatable {
    public var schemaVersion = 1
    public var enabled = true
    public var glossary: [GlossaryEntry] = []
    public var corrections: [SavedCorrection] = []
    public init() {}
    public static var disabled: Self {
        var profile = Self(); profile.enabled = false
        return profile
    }

    public mutating func addTerm(_ entry: GlossaryEntry) throws {
        let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = Array(Set(entry.aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare(term) != .orderedSame })).sorted()
        guard !term.isEmpty, term.utf8.count <= 120, entry.note.utf8.count <= 300,
              aliases.count <= 10, aliases.allSatisfy({ $0.utf8.count <= 120 }) else {
            throw FlowError("Use a term of up to 120 UTF-8 bytes, up to 10 short aliases, and a note of up to 300 bytes.")
        }
        let existing = glossary.firstIndex { $0.term.caseInsensitiveCompare(term) == .orderedSame }
        guard existing != nil || glossary.count < 100 else { throw FlowError("The glossary is limited to 100 terms.") }
        let otherEntries = glossary.filter { $0.term.caseInsensitiveCompare(term) != .orderedSame }
        for alias in aliases {
            if otherEntries.contains(where: { other in
                other.term.caseInsensitiveCompare(alias) == .orderedSame ||
                other.aliases.contains { $0.caseInsensitiveCompare(alias) == .orderedSame }
            }) { throw FlowError("The alias '\(alias)' already belongs to another term.") }
        }
        if otherEntries.contains(where: { $0.aliases.contains { $0.caseInsensitiveCompare(term) == .orderedSame } }) {
            throw FlowError("That term is already an alias for another glossary entry.")
        }
        var clean = GlossaryEntry(term: term, aliases: aliases, note: entry.note.trimmingCharacters(in: .whitespacesAndNewlines))
        if let existing { clean.id = glossary[existing].id; glossary[existing] = clean }
        else { glossary.append(clean) }
    }

    @discardableResult public mutating func learn(before: String, after: String) throws -> Int {
        let examples = try CorrectionLearning.examples(before: before, after: after)
        for example in examples {
            // A newer correction for the same local context replaces the older preference.
            corrections.removeAll { $0.before == example.before }
            corrections.append(example)
        }
        if corrections.count > 200 { corrections.removeFirst(corrections.count - 200) }
        return examples.count
    }

    public var speechHints: [String] {
        guard enabled else { return [] }
        var seen: Set<String> = []
        return (glossary.map(\.term) + corrections.reversed().compactMap(\.speechHint))
            .filter { seen.insert($0.lowercased()).inserted }.prefix(100).map { $0 }
    }

    /// Explicit aliases are simultaneous whole-phrase replacements, never recursive or substring replacements.
    /// Learned examples are only prompt context and are never unconditional replacement rules.
    public func applyingAliases(to text: String) -> (text: String, count: Int) {
        guard enabled else { return (text, 0) }
        struct Match { var range: NSRange; var term: String }
        var matches: [Match] = []
        let fullRange = NSRange(text.startIndex..., in: text)
        for entry in glossary {
            for alias in entry.aliases {
                guard let regex = Self.phraseRegex(alias) else { continue }
                matches += regex.matches(in: text, range: fullRange).map { Match(range: $0.range, term: entry.term) }
            }
        }
        matches.sort {
            $0.range.location == $1.range.location ? $0.range.length > $1.range.length : $0.range.location < $1.range.location
        }
        var selected: [Match] = []
        var end = 0
        for match in matches where match.range.location >= end {
            selected.append(match); end = NSMaxRange(match.range)
        }
        let output = NSMutableString(string: text)
        for match in selected.reversed() { output.replaceCharacters(in: match.range, with: match.term) }
        return (output as String, selected.count)
    }

    /// Only relevant examples enter the limited model context; unrelated personal text stays out.
    public func context(for text: String, maxBytes: Int = 1800) -> String {
        guard enabled else { return "" }
        var lines: [String] = []
        var remaining = maxBytes
        func append(_ value: String) {
            guard value.utf8.count + 1 <= remaining else { return }
            lines.append(value); remaining -= value.utf8.count + 1
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for entry in glossary where ([entry.term] + entry.aliases).contains(where: { Self.containsPhrase($0, in: text) }) {
            let data = try? encoder.encode(["preferredSpelling": entry.term, "meaning": entry.note])
            if let data { append(String(decoding: data, as: UTF8.self)) }
        }
        let words = Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let ranked = corrections.reversed().enumerated().compactMap { index, example -> (Int, Int, SavedCorrection)? in
            let sourceWords = Set(example.before.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            let overlap = sourceWords.intersection(words).count
            let direct = !example.matchPhrase.isEmpty && Self.containsPhrase(example.matchPhrase, in: text)
            guard direct || (overlap >= 3 && Double(overlap) / Double(max(sourceWords.count, 1)) >= 0.5) else { return nil }
            return (direct ? 100 + overlap : overlap, index, example)
        }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 > $1.0 }
        for (_, _, example) in ranked.prefix(6) {
            var record = ["previousOutput": example.before, "userCorrection": example.after]
            if let replacement = example.replacementPhrase {
                record["misrecognizedPhrase"] = example.matchPhrase
                record["preferredPhrase"] = replacement
            }
            if let data = try? encoder.encode(record) {
                append(String(decoding: data, as: UTF8.self))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func phraseRegex(_ phrase: String) -> NSRegularExpression? {
        guard !phrase.isEmpty else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        return try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}\\p{M}_])" + escaped + "(?![\\p{L}\\p{N}\\p{M}_])", options: [.caseInsensitive])
    }
    private static func containsPhrase(_ phrase: String, in text: String) -> Bool {
        phraseRegex(phrase)?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

public enum CorrectionLearning {
    /// Extract local edits with neighboring words, rather than treating an entire recording as one rule.
    public static func examples(before: String, after: String) throws -> [SavedCorrection] {
        guard before.utf8.count <= 32_000, after.utf8.count <= 32_000 else {
            throw FlowError("For learning, edit an excerpt smaller than 32 KB. The full transcript is still available.")
        }
        let old = before.split(whereSeparator: \.isWhitespace).map(String.init)
        let new = after.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !old.isEmpty, !new.isEmpty else { throw FlowError("Both the original and corrected text must contain words.") }
        let difference = new.difference(from: old)
        var removed: Set<Int> = [], inserted: Set<Int> = []
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var i = 0, j = 0
        var output: [SavedCorrection] = []
        while i < old.count || j < new.count {
            if !removed.contains(i), !inserted.contains(j), i < old.count, j < new.count {
                i += 1; j += 1; continue
            }
            let oldStart = i, newStart = j
            while i < old.count && removed.contains(i) { i += 1 }
            while j < new.count && inserted.contains(j) { j += 1 }
            guard i != oldStart || j != newStart else { break }
            let oldContext = old[max(0, oldStart - 3)..<min(old.count, i + 3)].joined(separator: " ")
            let newContext = new[max(0, newStart - 3)..<min(new.count, j + 3)].joined(separator: " ")
            guard oldContext.utf8.count + newContext.utf8.count <= 1200 else {
                throw FlowError("One change is too large to learn as a reusable example. Save smaller edits or add a glossary term.")
            }
            let changed = new[newStart..<j].joined(separator: " ")
            let match = old[oldStart..<i].joined(separator: " ")
            output.append(SavedCorrection(before: oldContext, after: newContext,
                matchPhrase: match.isEmpty ? oldContext : match,
                speechHint: !changed.isEmpty && j - newStart <= 3 && changed.utf8.count <= 120 ? changed : nil,
                replacementPhrase: match.isEmpty ? nil : changed))
        }
        return output
    }
}

public struct PersonalizationStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static func local() throws -> Self {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        // Retain the original storage path so a display-name change does not lose saved edits.
        return Self(url: root.appendingPathComponent("Flowstate/personalization.json"))
    }
    public func load() throws -> PersonalizationProfile {
        guard FileManager.default.fileExists(atPath: url.path) else { return PersonalizationProfile() }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let profile = try decoder.decode(PersonalizationProfile.self, from: Data(contentsOf: url))
        guard profile.schemaVersion == 1, profile.glossary.count <= 100, profile.corrections.count <= 200 else {
            throw FlowError("The personalization file has an unsupported version or exceeds its limits.")
        }
        return profile
    }
    public func save(_ profile: PersonalizationProfile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(profile).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var localURL = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try localURL.setResourceValues(values)
    }
}
