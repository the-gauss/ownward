import Foundation

public actor WorkspaceRepository {
    private static let writingOptions: Data.WritingOptions = [
        .atomic,
        .completeFileProtectionUntilFirstUserAuthentication,
    ]

    private var current: OwnwardSnapshot
    private let fileURL: URL?
    public nonisolated let initialSnapshot: OwnwardSnapshot
    private var continuations: [UUID: AsyncStream<OwnwardSnapshot>.Continuation] = [:]

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            current = try JSONDecoder.ownward.decode(OwnwardSnapshot.self, from: data)
            try Self.normalizeProtection(at: fileURL)
        } else {
            current = .empty
        }
        initialSnapshot = current
    }

    public init(fileURL: URL, initialSnapshot: OwnwardSnapshot) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder.ownward.decode(OwnwardSnapshot.self, from: data)
            current = SnapshotMigrator.upgrade(decoded, using: initialSnapshot)
            if current != decoded {
                try JSONEncoder.ownward.encode(current).write(to: fileURL, options: Self.writingOptions)
            } else {
                try Self.normalizeProtection(at: fileURL)
            }
        } else {
            current = SnapshotMigrator.upgrade(initialSnapshot)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.ownward.encode(current).write(to: fileURL, options: Self.writingOptions)
        }
        self.initialSnapshot = current
    }

    public init(inMemory snapshot: OwnwardSnapshot) throws {
        current = snapshot
        initialSnapshot = snapshot
        fileURL = nil
    }

    public func snapshot() -> OwnwardSnapshot { current }

    public func changes() -> AsyncStream<OwnwardSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    @discardableResult
    public func mutate(_ mutation: @Sendable (inout OwnwardSnapshot) throws -> Void) throws -> OwnwardSnapshot {
        var candidate = current
        try mutation(&candidate)
        try persist(candidate)
        current = candidate
        for continuation in continuations.values { continuation.yield(candidate) }
        return candidate
    }

    public func replace(with snapshot: OwnwardSnapshot) throws {
        try persist(snapshot)
        current = snapshot
        for continuation in continuations.values { continuation.yield(snapshot) }
    }

    private func persist(_ snapshot: OwnwardSnapshot) throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.ownward.encode(snapshot)
        try data.write(to: fileURL, options: Self.writingOptions)
    }

    private func removeContinuation(_ id: UUID) { continuations.removeValue(forKey: id) }

    private static func normalizeProtection(at fileURL: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }
}
