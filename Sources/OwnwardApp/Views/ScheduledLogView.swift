import SwiftUI
import OwnwardCore

struct ScheduledLogView: View {
    let kind: ScheduledLogKind
    let entries: [ScheduledLogEntry]
    let onToggleChecklist: (UUID, Int) -> Void
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(theme.uiFont(26, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text(subtitle)
                    .font(theme.uiFont(11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No \(kind.title) Entries Yet", systemImage: "text.book.closed")
                } description: {
                    Text("Scheduled results will appear here automatically.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(entry.createdAt.formatted(date: .complete, time: .shortened))
                                    .font(theme.metadataFont(11))
                                    .foregroundStyle(.secondary)
                                Divider()
                                ScheduledLogMarkdownView(markdown: entry.markdown) { checklistID in
                                    onToggleChecklist(entry.id, checklistID)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(theme.panelSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(theme.isSystem ? Color.clear : theme.surface)
    }

    private var subtitle: String {
        switch kind {
        case .dailyDayStarter: "Current daily run"
        case .weeklyCanadaRolesSearch: "Current weekly run"
        }
    }
}

private struct ScheduledLogMarkdownView: View {
    let document: ScheduledLogMarkdownDocument
    let onToggleChecklist: (Int) -> Void
    @Environment(\.ownwardTheme) private var theme

    init(markdown: String, onToggleChecklist: @escaping (Int) -> Void) {
        document = ScheduledLogMarkdownDocument(markdown: markdown)
        self.onToggleChecklist = onToggleChecklist
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(document.blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: ScheduledLogMarkdownBlock) -> some View {
        switch block {
        case let .heading(_, level, markdown):
            MarkdownInlineText(markdown: markdown)
                .font(theme.uiFont(headingSize(for: level), weight: .semibold))
                .foregroundStyle(theme.ink)
                .textSelection(.enabled)
                .padding(.top, level == 1 ? 5 : 1)

        case let .paragraph(_, markdown):
            MarkdownInlineText(markdown: markdown)
                .font(theme.uiFont(13))
                .foregroundStyle(theme.ink)
                .lineSpacing(3)
                .textSelection(.enabled)

        case let .table(table):
            ScheduledLogMarkdownTableView(table: table, onToggleChecklist: onToggleChecklist)

        case let .checklistItem(item):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button { onToggleChecklist(item.id) } label: {
                    Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                        .foregroundStyle(item.isCompleted ? OwnwardTheme.success : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isCompleted ? "Mark checklist item incomplete" : "Mark checklist item complete")
                .help(item.isCompleted ? "Mark incomplete" : "Mark complete")

                MarkdownInlineText(markdown: item.displayMarkdown)
                    .font(theme.uiFont(13))
                    .foregroundStyle(item.isCompleted ? .secondary : theme.ink)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(item.depth) * 18)

        case let .unorderedListItem(_, depth, markdown):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(theme.uiFont(13, weight: .semibold))
                    .foregroundStyle(.secondary)
                MarkdownInlineText(markdown: markdown)
                    .font(theme.uiFont(13))
                    .foregroundStyle(theme.ink)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            .padding(.leading, CGFloat(depth) * 18)

        case let .orderedListItem(_, depth, marker, markdown):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(theme.metadataFont(11))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22, alignment: .trailing)
                MarkdownInlineText(markdown: markdown)
                    .font(theme.uiFont(13))
                    .foregroundStyle(theme.ink)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            .padding(.leading, CGFloat(depth) * 18)

        case let .quote(_, markdown):
            HStack(alignment: .top, spacing: 9) {
                Rectangle()
                    .fill(theme.accent.opacity(0.65))
                    .frame(width: 3)
                MarkdownInlineText(markdown: markdown)
                    .font(theme.uiFont(13))
                    .foregroundStyle(theme.ink)
                    .italic()
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)

        case let .codeBlock(_, language, code):
            VStack(alignment: .leading, spacing: 5) {
                if !language.isEmpty {
                    Text(language)
                        .font(theme.metadataFont(10))
                        .foregroundStyle(.secondary)
                }
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(theme.panelSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

        case .divider:
            Divider()
        }
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: 20
        case 2: 17
        case 3: 15
        default: 13
        }
    }
}

private struct ScheduledLogMarkdownTableView: View {
    let table: ScheduledLogMarkdownTable
    let onToggleChecklist: (Int) -> Void
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                    MarkdownInlineText(markdown: header)
                        .font(theme.uiFont(12, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .textSelection(.enabled)
                }
            }

            Divider()
                .gridCellColumns(table.headers.count)

            ForEach(table.rows) { row in
                GridRow {
                    ForEach(row.cells.indices, id: \.self) { index in
                        cell(row: row, at: index)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func cell(row: ScheduledLogMarkdownTableRow, at index: Int) -> some View {
        if row.checklistCellIndex == index, let item = row.checklistItem {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button { onToggleChecklist(item.id) } label: {
                    Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                        .foregroundStyle(item.isCompleted ? OwnwardTheme.success : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isCompleted ? "Mark checklist item incomplete" : "Mark checklist item complete")
                .help(item.isCompleted ? "Mark incomplete" : "Mark complete")

                MarkdownInlineText(markdown: item.displayMarkdown)
                    .font(theme.uiFont(13))
                    .foregroundStyle(item.isCompleted ? .secondary : theme.ink)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            MarkdownInlineText(markdown: row.cells[index])
                .font(theme.uiFont(13))
                .foregroundStyle(theme.ink)
                .lineSpacing(3)
                .textSelection(.enabled)
        }
    }
}

private struct MarkdownInlineText: View {
    let markdown: String

    var body: some View {
        if let rendered = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(rendered)
        } else {
            Text(markdown)
        }
    }
}

struct ScheduledLogChecklistItem: Identifiable, Equatable {
    let id: Int
    let depth: Int
    let prefixMarkdown: String
    let contentMarkdown: String
    let isCompleted: Bool

    var displayMarkdown: String {
        prefixMarkdown.isEmpty ? contentMarkdown : "\(prefixMarkdown) \(contentMarkdown)"
    }
}

struct ScheduledLogMarkdownTable: Identifiable, Equatable {
    let id: Int
    let headers: [String]
    let rows: [ScheduledLogMarkdownTableRow]
}

struct ScheduledLogMarkdownTableRow: Identifiable, Equatable {
    let id: Int
    let cells: [String]
    let checklistCellIndex: Int?
    let checklistItem: ScheduledLogChecklistItem?
}

enum ScheduledLogMarkdownBlock: Identifiable, Equatable {
    case heading(Int, Int, String)
    case paragraph(Int, String)
    case table(ScheduledLogMarkdownTable)
    case checklistItem(ScheduledLogChecklistItem)
    case unorderedListItem(Int, Int, String)
    case orderedListItem(Int, Int, String, String)
    case quote(Int, String)
    case codeBlock(Int, String, String)
    case divider(Int)

    var id: Int {
        switch self {
        case let .heading(id, _, _), let .paragraph(id, _), let .unorderedListItem(id, _, _),
             let .orderedListItem(id, _, _, _), let .quote(id, _), let .codeBlock(id, _, _), let .divider(id):
            id
        case let .table(table):
            table.id
        case let .checklistItem(item):
            item.id
        }
    }
}

struct ScheduledLogMarkdownDocument {
    let blocks: [ScheduledLogMarkdownBlock]
    private let lines: [String]

    init(markdown: String) {
        lines = markdown.components(separatedBy: .newlines)
        blocks = Self.parse(lines: lines)
    }

    var checklistItems: [ScheduledLogChecklistItem] {
        blocks.reduce(into: []) { items, block in
            switch block {
            case let .checklistItem(item):
                items.append(item)
            case let .table(table):
                items.append(contentsOf: table.rows.compactMap(\.checklistItem))
            default:
                break
            }
        }
    }

    var tables: [ScheduledLogMarkdownTable] {
        blocks.compactMap { block in
            if case let .table(table) = block { return table }
            return nil
        }
    }

    func togglingChecklist(at checklistID: Int) -> String? {
        guard lines.indices.contains(checklistID),
              let range = Self.checkboxRange(in: lines[checklistID]) else {
            return nil
        }
        var updatedLines = lines
        let wasCompleted = updatedLines[checklistID][range].lowercased() == "[x]"
        updatedLines[checklistID].replaceSubrange(range, with: wasCompleted ? "[ ]" : "[x]")
        return updatedLines.joined(separator: "\n")
    }

    private static func parse(lines: [String]) -> [ScheduledLogMarkdownBlock] {
        var blocks: [ScheduledLogMarkdownBlock] = []
        var paragraphStart: Int?
        var paragraphLines: [String] = []
        var lineIndex = 0

        func flushParagraph() {
            guard let start = paragraphStart, !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(start, paragraphLines.joined(separator: " ")))
            paragraphLines = []
            paragraphStart = nil
        }

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                flushParagraph()
                lineIndex += 1
                continue
            }

            if let fence = codeFence(in: trimmed) {
                flushParagraph()
                let start = lineIndex
                lineIndex += 1
                var codeLines: [String] = []
                while lineIndex < lines.count,
                      !lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(fence.marker) {
                    codeLines.append(lines[lineIndex])
                    lineIndex += 1
                }
                if lineIndex < lines.count { lineIndex += 1 }
                blocks.append(.codeBlock(start, fence.language, codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = heading(in: line) {
                flushParagraph()
                blocks.append(.heading(lineIndex, heading.level, heading.markdown))
                lineIndex += 1
                continue
            }

            if isDivider(trimmed) {
                flushParagraph()
                blocks.append(.divider(lineIndex))
                lineIndex += 1
                continue
            }

            if let headerCells = tableCells(in: line),
               lineIndex + 1 < lines.count,
               let dividerCells = tableCells(in: lines[lineIndex + 1]),
               headerCells.count == dividerCells.count,
               dividerCells.allSatisfy(isTableDividerCell) {
                flushParagraph()
                let tableStart = lineIndex
                lineIndex += 2
                var rows: [ScheduledLogMarkdownTableRow] = []

                while lineIndex < lines.count,
                      let cells = tableCells(in: lines[lineIndex]),
                      cells.count == headerCells.count {
                    rows.append(tableRow(cells: cells, lineIndex: lineIndex))
                    lineIndex += 1
                }

                blocks.append(.table(ScheduledLogMarkdownTable(
                    id: tableStart,
                    headers: headerCells,
                    rows: rows
                )))
                continue
            }

            if let list = listPrefix(for: line) {
                flushParagraph()
                if let item = checklistItem(in: list.content, id: lineIndex, depth: list.depth) {
                    blocks.append(.checklistItem(item))
                } else if list.isOrdered {
                    blocks.append(.orderedListItem(lineIndex, list.depth, list.marker, list.content))
                } else {
                    blocks.append(.unorderedListItem(lineIndex, list.depth, list.content))
                }
                lineIndex += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                let quote = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(lineIndex, quote))
                lineIndex += 1
                continue
            }

            if paragraphStart == nil { paragraphStart = lineIndex }
            paragraphLines.append(trimmed)
            lineIndex += 1
        }

        flushParagraph()
        return blocks
    }

    private static func heading(in line: String) -> (level: Int, markdown: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }
        let afterHashes = trimmed.dropFirst(hashes.count)
        guard afterHashes.first?.isWhitespace == true else { return nil }
        let markdown = String(afterHashes).trimmingCharacters(in: .whitespaces)
        guard !markdown.isEmpty else { return nil }
        return (hashes.count, markdown)
    }

    private static func isDivider(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, ["-", "*", "_"].contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func codeFence(in trimmed: String) -> (marker: String, language: String)? {
        for marker in ["```", "~~~"] where trimmed.hasPrefix(marker) {
            return (marker, String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private static func tableCells(in line: String) -> [String]? {
        var content = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.contains("|") else { return nil }
        if content.first == "|" { content.removeFirst() }
        if content.last == "|" { content.removeLast() }

        var cells: [String] = []
        var cell = ""
        var isEscaped = false
        for character in content {
            if character == "|" && !isEscaped {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
                continue
            }
            cell.append(character)
            isEscaped = character == "\\" && !isEscaped
            if character != "\\" { isEscaped = false }
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells.count > 1 ? cells : nil
    }

    private static func isTableDividerCell(_ cell: String) -> Bool {
        var marker = cell.filter { !$0.isWhitespace }
        if marker.first == ":" { marker.removeFirst() }
        if marker.last == ":" { marker.removeLast() }
        return marker.count >= 3 && marker.allSatisfy { $0 == "-" }
    }

    private static func tableRow(cells: [String], lineIndex: Int) -> ScheduledLogMarkdownTableRow {
        for (index, cell) in cells.enumerated() {
            let checklistContent = listPrefix(for: cell)?.content ?? cell
            if let item = checklistItem(in: checklistContent, id: lineIndex, depth: 0) {
                return ScheduledLogMarkdownTableRow(
                    id: lineIndex,
                    cells: cells,
                    checklistCellIndex: index,
                    checklistItem: item
                )
            }
        }
        return ScheduledLogMarkdownTableRow(
            id: lineIndex,
            cells: cells,
            checklistCellIndex: nil,
            checklistItem: nil
        )
    }

    private static func checklistItem(in content: String, id: Int, depth: Int) -> ScheduledLogChecklistItem? {
        guard let checkbox = checkbox(in: content) else { return nil }
        let prefix = String(content[..<checkbox.range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let itemContent = String(content[checkbox.range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ScheduledLogChecklistItem(
            id: id,
            depth: depth,
            prefixMarkdown: prefix,
            contentMarkdown: itemContent,
            isCompleted: checkbox.isCompleted
        )
    }

    private static func listPrefix(for line: String) -> ListPrefix? {
        let indentation = line.prefix { $0 == " " || $0 == "\t" }
        let depth = indentation.reduce(into: 0) { count, character in
            count += character == "\t" ? 2 : 1
        } / 2
        let remainder = line.dropFirst(indentation.count)

        if let marker = remainder.first, ["-", "*", "+"].contains(marker) {
            let afterMarker = remainder.dropFirst()
            guard afterMarker.first?.isWhitespace == true else { return nil }
            return ListPrefix(
                depth: depth,
                marker: String(marker),
                content: String(afterMarker).trimmingCharacters(in: .whitespaces),
                isOrdered: false
            )
        }

        var digitEnd = remainder.startIndex
        while digitEnd < remainder.endIndex, remainder[digitEnd].isWholeNumber {
            digitEnd = remainder.index(after: digitEnd)
        }
        guard digitEnd > remainder.startIndex, digitEnd < remainder.endIndex else { return nil }
        let punctuation = remainder[digitEnd]
        guard punctuation == "." || punctuation == ")" else { return nil }
        let afterPunctuation = remainder.index(after: digitEnd)
        guard afterPunctuation < remainder.endIndex, remainder[afterPunctuation].isWhitespace else { return nil }
        return ListPrefix(
            depth: depth,
            marker: "\(remainder[..<digitEnd])\(punctuation)",
            content: String(remainder[afterPunctuation...]).trimmingCharacters(in: .whitespaces),
            isOrdered: true
        )
    }

    private static func checkbox(in content: String) -> (range: Range<String.Index>, isCompleted: Bool)? {
        guard let range = checkboxRange(in: content) else { return nil }
        return (range, content[range].lowercased() == "[x]")
    }

    private static func checkboxRange(in content: String) -> Range<String.Index>? {
        content.range(of: #"\[([ xX])\]"#, options: .regularExpression)
    }
}

private struct ListPrefix {
    let depth: Int
    let marker: String
    let content: String
    let isOrdered: Bool
}
