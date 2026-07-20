import Foundation

enum JobSearchLayout: Equatable {
    case compact
    case regular
    case wide
}

enum JobSearchLayoutPolicy {
    static func layout(for contentWidth: CGFloat) -> JobSearchLayout {
        if contentWidth < 620 { return .compact }
        if contentWidth < 900 { return .regular }
        return .wide
    }

    static func availableListWidth(
        windowWidth: CGFloat,
        sidebarWidth: CGFloat,
        inspectorWidth: CGFloat
    ) -> CGFloat {
        max(0, windowWidth - sidebarWidth - inspectorWidth)
    }

    static func columns(for layout: JobSearchLayout) -> [JobSearchColumn] {
        switch layout {
        case .compact:
            [.opportunity, .location, .stage, .nextDate]
        case .regular:
            [.opportunity, .location, .stage, .nextDate]
        case .wide:
            [.opportunity, .location, .stage, .track, .nextDate]
        }
    }
}

enum JobSearchColumn: Equatable {
    case opportunity
    case location
    case stage
    case track
    case nextDate
}

enum JobSearchContactRoutes {
    static func mailtoURL(for email: String) -> URL? {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.contains("@"), !value.contains(where: { $0.isWhitespace }) else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = value
        return components.url
    }

    static func phoneURL(for phone: String) -> URL? {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLeadingPlus = trimmed.hasPrefix("+")
        let digits = trimmed.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map(String.init)
            .joined()
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:" + (hasLeadingPlus ? "+" : "") + digits)
    }

    static func publicSourceURL(for value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }

    static func publicSourceTitle(for value: String) -> String {
        guard let host = publicSourceURL(for: value)?.host, !host.isEmpty else { return "Public source" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

enum JobResumeSourceLocator {
    static func resolve(
        recordedPath: String,
        employer: String,
        role: String,
        searchRoot: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        let expandedPath = NSString(string: recordedPath).expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !expandedPath.isEmpty {
            let recordedURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
            if recordedURL.pathExtension.lowercased() == "tex",
               fileManager.fileExists(atPath: recordedURL.path) {
                return recordedURL
            }
            let siblingTeX = recordedURL.deletingPathExtension().appendingPathExtension("tex")
            if fileManager.fileExists(atPath: siblingTeX.path) { return siblingTeX.standardizedFileURL }
        }

        let root = searchRoot ?? inferredSearchRoot(from: expandedPath)
        guard let root, fileManager.fileExists(atPath: root.path) else { return nil }
        let employerTokens = tokens(in: employer)
        let roleTokens = tokens(in: role)
        let targetTokens = employerTokens.union(roleTokens)
        guard !employerTokens.isEmpty, !roleTokens.isEmpty else { return nil }

        var scored: [(url: URL, score: Int)] = []
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        for case let url as URL in enumerator where url.pathExtension.lowercased() == "tex" {
            let candidateTokens = tokens(in: url.deletingPathExtension().lastPathComponent)
            guard !candidateTokens.isDisjoint(with: employerTokens),
                  !candidateTokens.isDisjoint(with: roleTokens) else { continue }
            let score = candidateTokens.intersection(targetTokens).count
            if score >= 2 { scored.append((url.standardizedFileURL, score)) }
        }

        guard let bestScore = scored.map(\.score).max() else { return nil }
        let best = scored.filter { $0.score == bestScore }
        return best.count == 1 ? best[0].url : nil
    }

    private static func inferredSearchRoot(from recordedPath: String) -> URL? {
        if !recordedPath.isEmpty {
            let components = URL(fileURLWithPath: recordedPath).pathComponents
            if let resumeIndex = components.lastIndex(of: "Resumes") {
                return URL(fileURLWithPath: NSString.path(withComponents: Array(components[...resumeIndex])))
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Job Search/Resumes", isDirectory: true)
    }

    private static func tokens(in value: String) -> Set<String> {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let pieces = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let ignored: Set<String> = ["kartik", "kumar", "resume", "final", "cv", "the", "and", "inc", "ltd"]
        return Set(pieces.filter { $0.count > 1 && !ignored.contains($0) })
    }
}
