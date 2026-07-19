import Foundation
import OwnwardCore
import OwnwardServices

enum AppBootstrap {
    @MainActor
    static func makeModel() throws -> AppModel {
        let support: URL
        let override = ProcessInfo.processInfo.environment["OWNWARD_SUPPORT_DIRECTORY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if override.isEmpty {
            support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Ownward", isDirectory: true)
        } else {
            support = URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
                .standardizedFileURL
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        let seed = try bundledSnapshot()
        let repository = try WorkspaceRepository(fileURL: support.appendingPathComponent("workspace.json"), initialSnapshot: seed)
        let token = try LocalAPICredentials.loadOrCreateToken(at: support.appendingPathComponent("api-token"))
        let notifier = OwnwardNotificationScheduler()
        let server = LocalAPIServer(router: APIRouter(
            repository: repository,
            token: token,
            scheduledLogNotifier: notifier
        ))
        let model = AppModel(repository: repository, apiServer: server, initialSnapshot: repository.initialSnapshot)
        // The loopback API must be ready even when macOS launches Ownward while
        // the screen is locked and no SwiftUI window has appeared yet.
        model.start()
        return model
    }

    private static func bundledSnapshot() throws -> OwnwardSnapshot {
        let names = ["minkops-notion-export", "myndral-notion-export"]
        let snapshots = try names.map { name -> OwnwardSnapshot in
            guard let url = OwnwardResources.url(name: name, extension: "json") else { return .empty }
            return try NotionExportImporter.import(data: Data(contentsOf: url))
        }
        return NotionExportImporter.merge(snapshots)
    }
}
