import Foundation
import KeyboardStore
import KeyboardCore
import Observation

/// Your `Vocabulary`, put on every dictation before it's typed, kept in the app's own container as vocabulary.json.
@Observable final class VoiceVocabulary {
    static let shared = VoiceVocabulary()

    private(set) var vocabulary: Vocabulary
    @ObservationIgnored private let file = StoredFile<Vocabulary>(URL.applicationSupportDirectory.appending(path: "vocabulary.json"))

    private init() {
        vocabulary = file.read().value ?? Vocabulary()
    }

    func set(_ terms: [Vocabulary.Term]) {
        vocabulary.terms = terms
        file.save(vocabulary)
        Backup.syncApp()
    }
}
