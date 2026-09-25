import Foundation
import Testing
@testable import FlowCore

@Test func aliasesRespectArabicAndEnglishBoundariesAndPreferLongestMatch() throws {
    var profile = PersonalizationProfile()
    try profile.addTerm(GlossaryEntry(term: "Todoist", aliases: ["to do", "to do list", "تودويست"]))
    let result = profile.applyingAliases(to: "to do list; TO DO. تودويست والتودويست. todoing")
    #expect(result.text == "Todoist; Todoist. Todoist والتودويست. todoing")
    #expect(result.count == 3)
}

@Test func conflictingGlossaryAliasesAreRejectedWithoutChangingExistingEntries() throws {
    var profile = PersonalizationProfile()
    try profile.addTerm(GlossaryEntry(term: "Todoist", aliases: ["to doist"]))
    #expect(throws: FlowError.self) { try profile.addTerm(GlossaryEntry(term: "Tasks", aliases: ["to doist"])) }
    #expect(throws: FlowError.self) { try profile.addTerm(GlossaryEntry(term: "to doist")) }
    #expect(profile.glossary.count == 1)
}

@Test func learningExtractsSeparateChangesWithContextAndDoesNotMakeReplacementRules() throws {
    let before = "Please check the pool request today and then open to-doist for our tasks"
    let after = "Please check the pull request today and then open Todoist for our tasks"
    var profile = PersonalizationProfile()
    #expect(try profile.learn(before: before, after: after) == 2)
    #expect(profile.corrections[0].matchPhrase == "pool")
    #expect(profile.corrections[0].after.contains("pull request"))
    #expect(profile.speechHints.contains("Todoist"))
    #expect(profile.applyingAliases(to: before).text == before)
    #expect(profile.context(for: "Review the pool request today").contains("pull request"))
    #expect(profile.context(for: "متى يصل القطار؟").isEmpty)
}

@Test func learningHandlesInsertionDeletionAndMixedScriptWithoutDroppingEdits() throws {
    let before = "يعني لازم نراجع pull request بكرة"
    let after = "لازم نراجع the pull request بكرة."
    let examples = try CorrectionLearning.examples(before: before, after: after)
    #expect(examples.count == 3)
    #expect(examples.contains { $0.matchPhrase == "يعني" })
    #expect(examples.contains { $0.speechHint == "the" })
    #expect(examples.contains { $0.after.contains("بكرة.") })
}

@Test func disabledPersonalizationHasNoEffectAndContextHasStrictBudget() throws {
    var profile = PersonalizationProfile()
    try profile.addTerm(GlossaryEntry(term: "Todoist", aliases: ["to-doist"], note: "A task manager"))
    try profile.learn(before: "open to-doist now", after: "open Todoist now")
    #expect(profile.context(for: "open to-doist now", maxBytes: 80).utf8.count <= 80)
    profile.enabled = false
    #expect(profile.context(for: "open to-doist now").isEmpty)
    #expect(profile.speechHints.isEmpty)
    #expect(profile.applyingAliases(to: "to-doist").text == "to-doist")
}

@Test func savedProfileSurvivesRestartAndCorruptionIsNotSilentlyOverwritten() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = PersonalizationStore(url: dir.appendingPathComponent("profile.json"))
    var profile = try store.load()
    try profile.addTerm(GlossaryEntry(term: "مرحبا", aliases: ["marhaba"]))
    try profile.learn(before: "افتح تودويست الآن", after: "افتح Todoist الآن")
    try store.save(profile)
    let reloaded = try PersonalizationStore(url: store.url).load()
    #expect(reloaded.glossary == profile.glossary)
    #expect(reloaded.corrections.map(\.before) == profile.corrections.map(\.before))
    try Data("not json".utf8).write(to: store.url)
    #expect(throws: (any Error).self) { try store.load() }
    #expect(try String(contentsOf: store.url, encoding: .utf8) == "not json")
}

@Test func legacyExperimentWithoutPersonalizationFieldsStillOpens() throws {
    let report = Experiment(sourceName: "memo.m4a", mode: .dual)
    var json = try #require(JSONSerialization.jsonObject(with: report.json()) as? [String: Any])
    json.removeValue(forKey: "personalization")
    json["pipelineVersion"] = "2"
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let loaded = try decoder.decode(Experiment.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(loaded.personalization == nil)
    #expect(loaded.sourceName == "memo.m4a")
}
