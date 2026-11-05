import KeyboardCore
import Testing

struct HapticFeedbackTests {
    @Test func standardSitsInTheMiddleOfSevenStrengths() {
        let levels = HapticFeedback.levels
        #expect(levels.count == 7)
        #expect(levels[levels.count / 2] == .standard)
        #expect(HapticFeedback.standard.strength == 1)
    }

    @Test func eachLevelIsStrongerThanTheOneBefore() {
        let strengths = HapticFeedback.levels.map(\.strength)
        #expect(zip(strengths, strengths.dropFirst()).allSatisfy { $0 < $1 })
    }
}
