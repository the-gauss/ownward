import Foundation

public enum SnapshotMigrator {
    public static let currentSchemaVersion = 8

    public static func upgrade(_ snapshot: OwnwardSnapshot, using seed: OwnwardSnapshot = .empty) -> OwnwardSnapshot {
        var upgraded = snapshot
        guard upgraded.schemaVersion < currentSchemaVersion else {
            return applyingScheduledLogRetention(to: upgraded)
        }

        if upgraded.schemaVersion < 2 {
            var laneOrders: [LaneKey: Int] = [:]
            for taskIndex in upgraded.tasks.indices {
                let key = LaneKey(boardID: upgraded.tasks[taskIndex].boardID, status: upgraded.tasks[taskIndex].status)
                if upgraded.tasks[taskIndex].manualOrder == nil {
                    upgraded.tasks[taskIndex].manualOrder = laneOrders[key, default: 0]
                }
                laneOrders[key] = max(laneOrders[key, default: 0], (upgraded.tasks[taskIndex].manualOrder ?? 0) + 1)

                guard let seededTask = seed.tasks.first(where: { $0.id == upgraded.tasks[taskIndex].id }) else { continue }
                for miniIndex in upgraded.tasks[taskIndex].miniTasks.indices where upgraded.tasks[taskIndex].miniTasks[miniIndex].category == nil {
                    let existingMini = upgraded.tasks[taskIndex].miniTasks[miniIndex]
                    let seededMini = seededTask.miniTasks.first {
                        $0.order == existingMini.order && $0.title == existingMini.title
                    }
                    upgraded.tasks[taskIndex].miniTasks[miniIndex].category = seededMini?.category
                }
                let categories = Set(seededTask.miniTasks.compactMap(\.category))
                upgraded.tasks[taskIndex].notesMarkdown = removingCategoryScaffolding(
                    from: upgraded.tasks[taskIndex].notesMarkdown,
                    categories: categories
                )
            }
        }

        if upgraded.schemaVersion < 5 {
            let tracksByRoleID = Dictionary(
                uniqueKeysWithValues: upgraded.jobSearch.roles.map { ($0.id, $0.track) }
            )
            for activityIndex in upgraded.jobSearch.activities.indices
            where upgraded.jobSearch.activities[activityIndex].detail == legacyMalformedJobActivityDetail {
                let roleID = upgraded.jobSearch.activities[activityIndex].roleID
                if let roleID, let track = tracksByRoleID[roleID] {
                    upgraded.jobSearch.activities[activityIndex].detail =
                        "Verified role added to the \(track.title) track."
                } else {
                    upgraded.jobSearch.activities[activityIndex].detail = "Verified role added."
                }
            }
        }

        if upgraded.schemaVersion < 7 {
            JobSearchEngine.reconcileContactDirectory(in: &upgraded.jobSearch)
        }

        if upgraded.schemaVersion < 8 {
            JobSearchEngine.removePlaceholderDirectoryContacts(in: &upgraded.jobSearch)
        }

        upgraded.schemaVersion = currentSchemaVersion
        return applyingScheduledLogRetention(to: upgraded)
    }

    private static let legacyMalformedJobActivityDetail =
        "Verified role added to the (verified.track.title) track."

    private static func applyingScheduledLogRetention(to snapshot: OwnwardSnapshot) -> OwnwardSnapshot {
        var normalized = snapshot
        normalized.scheduledLogs = ScheduledLogRetention.prune(normalized.scheduledLogs)
        return normalized
    }

    private static func removingCategoryScaffolding(from markdown: String, categories: Set<String>) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        let categoryIndices = Set(lines.indices.filter { index in
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("## ") else { return false }
            return categories.contains(String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces))
        })
        let retained = lines.indices.compactMap { index -> String? in
            if categoryIndices.contains(index) { return nil }
            if lines[index].trimmingCharacters(in: .whitespaces) == "---" {
                let previous = lines.indices.reversed().first { $0 < index && !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }
                let next = lines.indices.first { $0 > index && !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }
                if previous.map(categoryIndices.contains) == true || next.map(categoryIndices.contains) == true { return nil }
            }
            return lines[index]
        }
        return retained.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct LaneKey: Hashable {
    var boardID: BoardID
    var status: TaskStatus
}
