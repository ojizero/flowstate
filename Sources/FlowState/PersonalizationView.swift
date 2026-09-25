import SwiftUI
#if canImport(FlowCore)
import FlowCore
#endif

struct PersonalizationView: View {
    @Bindable var model: AppModel
    @State private var term = ""
    @State private var aliases = ""
    @State private var note = ""
    @State private var editingID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Use glossary and saved edits", isOn: Binding(
                    get: { model.personalization.enabled },
                    set: { enabled in model.updatePersonalization { $0.enabled = enabled } }
                ))
                Text("Corrections and vocabulary stay on this device. Saved edits guide future prompts; they do not retrain Apple's models. Speech hints apply to DictationTranscriber. Cleanup uses the glossary for both languages.")
                    .font(.callout).foregroundStyle(.secondary)
                GroupBox("Glossary") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Preferred spelling, e.g. Todoist", text: $term)
                        TextField("Aliases or common mishearings, separated by commas", text: $aliases)
                        TextField("Optional meaning, e.g. task management app", text: $note)
                        Text("Aliases are replaced as whole phrases during cleanup. Use specific phrases to avoid changing unrelated text. Saving an existing term updates it.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(editingID == nil ? "Add term" : "Save term") {
                                model.updatePersonalization { profile in
                                    if let editingID { profile.glossary.removeAll { $0.id == editingID } }
                                    try profile.addTerm(GlossaryEntry(term: term,
                                        aliases: aliases.components(separatedBy: CharacterSet(charactersIn: ",،\n")), note: note))
                                }
                                if model.error == nil { resetForm() }
                            }.disabled(term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if editingID != nil { Button("Cancel edit") { resetForm() } }
                        }
                        ForEach(model.personalization.glossary) { entry in
                            Divider()
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.term).font(.headline)
                                    if !entry.aliases.isEmpty { Text("Aliases: " + entry.aliases.joined(separator: ", ")) }
                                    if !entry.note.isEmpty { Text(entry.note).foregroundStyle(.secondary) }
                                }.textSelection(.enabled)
                                Spacer()
                                Button("Edit") {
                                    editingID = entry.id; term = entry.term
                                    aliases = entry.aliases.joined(separator: ", "); note = entry.note
                                }
                                Button("Delete", role: .destructive) {
                                    model.updatePersonalization { $0.glossary.removeAll { $0.id == entry.id } }
                                    if editingID == entry.id { resetForm() }
                                }
                            }
                        }
                    }.padding(5)
                }
                GroupBox("Learned edits") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Use Edit & teach on a transcript or cleanup output, correct the text, then Save edits as examples. Relevant examples are selected for each later cleanup request. The most recent 200 are retained.")
                            .foregroundStyle(.secondary)
                        if model.personalization.corrections.isEmpty { Text("No saved corrections yet.") }
                        ForEach(model.personalization.corrections.reversed()) { correction in
                            Divider()
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Before: \(correction.before)")
                                    Text("After: \(correction.after)").fontWeight(.medium)
                                    if let hint = correction.speechHint {
                                        Text("Dictation vocabulary hint: \(hint)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.textSelection(.enabled)
                                Spacer()
                                Button("Forget", role: .destructive) {
                                    model.updatePersonalization { $0.corrections.removeAll { $0.id == correction.id } }
                                }
                            }
                        }
                        if !model.personalization.corrections.isEmpty {
                            Button("Forget all learned edits", role: .destructive) {
                                model.updatePersonalization { $0.corrections.removeAll() }
                            }
                        }
                    }.padding(5)
                }
                Text("Local file: \(model.personalizationPath)").font(.caption).textSelection(.enabled)
                Text("Exported experiments include the glossary and corrections used. Opening an old experiment does not import its preferences into your saved profile.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reload saved preferences") { model.loadPersonalization() }
            }.frame(maxWidth: .infinity, alignment: .leading).disabled(model.busy)
        }
    }

    private func resetForm() { term = ""; aliases = ""; note = ""; editingID = nil }
}
