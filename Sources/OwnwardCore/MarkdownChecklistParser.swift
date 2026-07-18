import Foundation

public struct ParsedTaskContent: Equatable, Sendable {
    public var notesMarkdown: String
    public var miniTasks: [MiniTask]
    public var links: [TaskLink]
}

public enum MarkdownChecklistParser {
    private static let checklistPattern = #"^(\s*)[-*+]\s+\[([ xX])\]\s+(.+)$"#
    private static let linkPattern = #"\[([^\]]+)\]\((https?://[^\s)]+)\)"#
    private static let categoryPattern = #"^\s*##\s+(.+?)\s*$"#

    public static func parse(_ markdown: String, taskID: TaskID) -> ParsedTaskContent {
        let checklistRegex = try! NSRegularExpression(pattern: checklistPattern)
        let linkRegex = try! NSRegularExpression(pattern: linkPattern)
        let categoryRegex = try! NSRegularExpression(pattern: categoryPattern)
        var notes: [String] = []
        var miniTasks: [MiniTask] = []
        let lines = markdown.components(separatedBy: .newlines)
        let categoryLines = Set(lines.indices.filter { index in
            let line = lines[index]
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard categoryRegex.firstMatch(in: line, range: range) != nil else { return false }
            let nextHeading = lines[(index + 1)...].firstIndex { candidate in
                let candidateRange = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
                return categoryRegex.firstMatch(in: candidate, range: candidateRange) != nil
            } ?? lines.endIndex
            return lines[(index + 1)..<nextHeading].contains { candidate in
                let candidateRange = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
                return checklistRegex.firstMatch(in: candidate, range: candidateRange) != nil
            }
        })
        var currentCategory: String?

        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = categoryRegex.firstMatch(in: line, range: range),
               let titleRange = Range(match.range(at: 1), in: line) {
                if categoryLines.contains(index) {
                    currentCategory = String(line[titleRange]).trimmingCharacters(in: .whitespaces)
                    continue
                }
                currentCategory = nil
            }
            guard let match = checklistRegex.firstMatch(in: line, range: range),
                  let indentRange = Range(match.range(at: 1), in: line),
                  let stateRange = Range(match.range(at: 2), in: line),
                  let titleRange = Range(match.range(at: 3), in: line) else {
                if currentCategory != nil, line.trimmingCharacters(in: .whitespaces) == "---" { continue }
                notes.append(line)
                continue
            }
            let indentation = line[indentRange]
            let depth = indentation.reduce(into: 0) { count, character in
                count += character == "\t" ? 2 : 1
            } / 2
            miniTasks.append(MiniTask(
                taskID: taskID,
                title: String(line[titleRange]).trimmingCharacters(in: .whitespaces),
                isCompleted: line[stateRange].lowercased() == "x",
                depth: depth,
                order: miniTasks.count,
                category: currentCategory
            ))
        }

        let fullRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let links = linkRegex.matches(in: markdown, range: fullRange).compactMap { match -> TaskLink? in
            guard let titleRange = Range(match.range(at: 1), in: markdown),
                  let urlRange = Range(match.range(at: 2), in: markdown) else { return nil }
            return TaskLink(title: String(markdown[titleRange]), url: String(markdown[urlRange]))
        }

        let compactNotes = notes.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedTaskContent(notesMarkdown: compactNotes, miniTasks: miniTasks, links: Array(Set(links)).sorted { $0.title < $1.title })
    }
}
