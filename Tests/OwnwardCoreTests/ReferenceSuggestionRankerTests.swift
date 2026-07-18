import Testing
@testable import OwnwardCore

@Suite("Reference suggestions")
struct ReferenceSuggestionRankerTests {
    @Test("shared title terms rank close completion references first")
    func ranksByMatchingTitleTerms() {
        let source = "Database migration rollout"

        let close = ReferenceSuggestionRanker.score(
            sourceTitle: source,
            candidateTitle: "Rollout database migration"
        )
        let partial = ReferenceSuggestionRanker.score(
            sourceTitle: source,
            candidateTitle: "Database backup"
        )
        let unrelated = ReferenceSuggestionRanker.score(
            sourceTitle: source,
            candidateTitle: "Design navigation sidebar"
        )

        #expect(close > partial)
        #expect(partial > unrelated)
        #expect(unrelated == 0)
    }
}
