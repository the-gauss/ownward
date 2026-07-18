import Foundation

public enum LocalAPICredentialsError: LocalizedError {
    case emptyToken

    public var errorDescription: String? {
        switch self {
        case .emptyToken: "The existing Ownward API token is empty."
        }
    }
}

public enum LocalAPICredentials {
    public static func loadOrCreateToken(at url: URL) throws -> String {
        if FileManager.default.fileExists(atPath: url.path) {
            let token = try String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { throw LocalAPICredentialsError.emptyToken }
            try protectToken(at: url)
            return token
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let token = "\(UUID().uuidString.lowercased())\(UUID().uuidString.lowercased())"
        try Data((token + "\n").utf8).write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try protectToken(at: url)
        return token
    }

    private static func protectToken(at url: URL) throws {
        try FileManager.default.setAttributes(
            [
                .posixPermissions: 0o600,
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
            ],
            ofItemAtPath: url.path
        )
    }
}
