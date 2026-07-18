import Foundation

public enum ReferenceSuggestionRanker {
    public static func score(sourceTitle: String, candidateTitle: String) -> Int {
        let candidate = candidateTitle.localizedLowercase
        return sourceTitle
            .localizedLowercase
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0.count > 2 }
            .reduce(into: 0) { total, term in
                if candidate.contains(term) { total += term.count }
            }
    }
}
