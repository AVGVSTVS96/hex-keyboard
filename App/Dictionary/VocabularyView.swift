import KeyboardCore
import SwiftUI

/// The words the voice model gets wrong, each with what it writes instead, under Add Word.
struct VocabularyView: View {
    private let store = VoiceVocabulary.shared
    @State private var editing: Edited?

    /// Each word with its place in the vocabulary, in alphabetical order.
    private var words: [(index: Int, term: Vocabulary.Term)] {
        store.vocabulary.terms.enumerated()
            .map { (index: $0.offset, term: $0.element) }
            .sorted { $0.term.term.localizedStandardCompare($1.term.term) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Box(footer: "iikb types each word as you spell it here, in place of what the voice model wrote, or of the same word with other spaces, hyphens or capitals. Only whole words change.") {
                ActionRow(title: "Add Word", symbol: "plus") { editing = Edited(index: nil) }
            }
            if !words.isEmpty {
                Box(header: words.count == 1 ? "1 Word" : "\(words.count.formatted()) Words") {
                    ForEach(words, id: \.index) { word in
                        Button { editing = Edited(index: word.index) } label: { row(word.term) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(word.index) }
                            }
                    }
                }
            }
        }
        .sheet(item: $editing) { edited in
            TermEditor(term: edited.index.map { store.vocabulary.terms[$0] } ?? Vocabulary.Term(""), isNew: edited.index == nil) { term in
                var terms = store.vocabulary.terms
                if let index = edited.index { terms[index] = term } else { terms.append(term) }
                store.set(terms)
            } delete: {
                if let index = edited.index { delete(index) }
            }
        }
    }

    private func row(_ term: Vocabulary.Term) -> some View {
        HStack(spacing: 12) {
            RowText(title: term.term, detail: term.heardAs.isEmpty ? nil : "Written as " + term.heardAs.joined(separator: ", "))
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.hexSecondary)
                .accessibilityHidden(true)
        }
        .row()
    }

    private func delete(_ index: Int) {
        var terms = store.vocabulary.terms
        guard terms.indices.contains(index) else { return }
        terms.remove(at: index)
        store.set(terms)
    }

    private struct Edited: Identifiable {
        let index: Int?
        var id: Int { index ?? -1 }
    }
}

/// A word and what the voice model writes for it, as a form like Add Source's.
private struct TermEditor: View {
    @State var term: Vocabulary.Term
    let isNew: Bool
    let save: (Vocabulary.Term) -> Void
    let delete: () -> Void
    @State private var heardAs = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Column {
                Box(header: "Word", footer: "Spelled and capitalized as iikb should type it.") {
                    TextField("Claude", text: $term.term)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .row()
                }
                Box(header: "Written Instead", footer: "What the voice model writes when you say it, separated by commas. Leave it empty to fix only spaces, hyphens and capitals.") {
                    TextField("clawed, clod", text: $heardAs)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .row()
                }
                if !isNew {
                    Box {
                        ActionRow(title: "Delete Word", role: .destructive) {
                            delete()
                            dismiss()
                        }
                    }
                }
            }
            .pushedPage(isNew ? "Add Word" : "Edit Word")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        term.term = term.term.trimmingCharacters(in: .whitespaces)
                        term.heardAs = heardAs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        save(term)
                        dismiss()
                    }
                    .disabled(term.term.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.hexPage)
        .onAppear { heardAs = term.heardAs.joined(separator: ", ") }
    }
}
