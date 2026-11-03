import KeyboardCore
import Observation
import SwiftUI

/// Your `Vocabulary`, put on every dictation before it's typed, kept in the app's own container as vocabulary.json.
@Observable final class VoiceVocabulary {
    static let shared = VoiceVocabulary()

    private(set) var vocabulary: Vocabulary
    @ObservationIgnored private let url = URL.applicationSupportDirectory.appending(path: "vocabulary.json")

    private init() {
        vocabulary = (try? JSONDecoder().decode(Vocabulary.self, from: Data(contentsOf: url))) ?? Vocabulary()
    }

    func set(_ terms: [Vocabulary.Term]) {
        vocabulary.terms = terms
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(vocabulary).write(to: url, options: .atomic)
    }
}

/// The words the voice model gets wrong, each with what it writes instead.
struct VocabularyView: View {
    private let store = VoiceVocabulary.shared
    @State private var editing: Edited?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                Button("Add Word", systemImage: "plus") { adding = true }
                ForEach(Array(store.vocabulary.terms.enumerated()), id: \.offset) { index, term in
                    Button { editing = Edited(index: index) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(term.term)
                                .foregroundStyle(.primary)
                            if !term.heardAs.isEmpty {
                                Text(term.heardAs.joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundStyle(Color.hexSecondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    var terms = store.vocabulary.terms
                    terms.remove(atOffsets: offsets)
                    store.set(terms)
                }
            } footer: {
                Text("Hex types each word as you spell it here, in place of what the voice model wrote instead, or of the word with other spaces, hyphens or capitals. Only whole words change, and nothing that isn’t listed.")
            }
            .listRowBackground(Color.hexCard)
        }
        .scrollContentBackground(.hidden)
        .pushedPage("Vocabulary")
        .sheet(isPresented: $adding) {
            TermEditor(term: Vocabulary.Term("")) { store.set(store.vocabulary.terms + [$0]) }
        }
        .sheet(item: $editing) { edited in
            TermEditor(term: store.vocabulary.terms[edited.index]) { term in
                var terms = store.vocabulary.terms
                terms[edited.index] = term
                store.set(terms)
            }
        }
    }

    private struct Edited: Identifiable {
        let index: Int
        var id: Int { index }
    }
}

private struct TermEditor: View {
    @State var term: Vocabulary.Term
    let save: (Vocabulary.Term) -> Void
    @State private var heardAs = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Word") {
                    TextField("Claude", text: $term.term)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    TextField("clawed, clod", text: $heardAs)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Written Instead")
                } footer: {
                    Text("What the voice model writes when you say it, separated by commas.")
                }
            }
            .navigationTitle(term.term.isEmpty ? "New Word" : term.term)
            .navigationBarTitleDisplayMode(.inline)
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
        .onAppear { heardAs = term.heardAs.joined(separator: ", ") }
    }
}
