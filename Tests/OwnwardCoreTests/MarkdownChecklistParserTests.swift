import Testing
@testable import OwnwardCore

@Suite("Markdown checklist import")
struct MarkdownChecklistParserTests {
    @Test("checklist lines become structured mini-tasks")
    func parsesNestedChecklist() {
        let markdown = """
        # Plan
        Context stays as a note.
        - [x] Requirements
          - [ ] API design
        - [ ] Data design
        """

        let result = MarkdownChecklistParser.parse(markdown, taskID: TaskID())

        #expect(result.miniTasks.map(\.title) == ["Requirements", "API design", "Data design"])
        #expect(result.miniTasks.map(\.depth) == [0, 1, 0])
        #expect(result.miniTasks.map(\.isCompleted) == [true, false, false])
        #expect(result.notesMarkdown.contains("Context stays as a note."))
        #expect(!result.notesMarkdown.contains("[x]"))
    }

    @Test("ordinary markdown links remain in notes and are extracted")
    func extractsLinks() {
        let markdown = "Read [System Design Primer](https://github.com/donnemartin/system-design-primer)."
        let result = MarkdownChecklistParser.parse(markdown, taskID: TaskID())

        #expect(result.links == [TaskLink(title: "System Design Primer", url: "https://github.com/donnemartin/system-design-primer")])
        #expect(result.notesMarkdown == markdown)
    }

    @Test("level-two headings categorize following mini-tasks")
    func categorizesChecklistItems() {
        let markdown = """
        # LeetCode Top Interview 150
        Preparation notes stay here.
        ## Math
        - [x] 9. Palindrome Number
        - [ ] 66. Plus One
        ## Two Pointers
        - [ ] 125. Valid Palindrome
        """

        let result = MarkdownChecklistParser.parse(markdown, taskID: TaskID())

        #expect(result.miniTasks.map(\.category) == ["Math", "Math", "Two Pointers"])
        #expect(result.notesMarkdown.contains("Preparation notes stay here."))
        #expect(!result.notesMarkdown.contains("## Math"))
        #expect(!result.notesMarkdown.contains("## Two Pointers"))
    }
}
