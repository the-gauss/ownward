import SwiftUI
import OwnwardCore

struct ScheduledLogView: View {
    let kind: ScheduledLogKind
    let entries: [ScheduledLogEntry]
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
                    Label("No (kind.title) Entries Yet", systemImage: "text.book.closed")
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
                                MarkdownLogText(markdown: entry.markdown)
                                    .font(theme.uiFont(13))
                                    .foregroundStyle(theme.ink)
                                    .textSelection(.enabled)
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
        case .dailyDayStarter: "Most recent four daily runs"
        case .weeklyCanadaRolesSearch: "Current and previous week"
        }
    }
}

private struct MarkdownLogText: View {
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
