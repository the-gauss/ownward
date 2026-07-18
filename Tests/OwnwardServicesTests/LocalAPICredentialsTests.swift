import Foundation
import Testing
@testable import OwnwardServices

@Suite("Local API credentials")
struct LocalAPICredentialsTests {
    @Test("token is stable, private, and available after screen lock")
    func stableProtectedToken() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("api-token")
        defer { try? FileManager.default.removeItem(at: directory) }

        let created = try LocalAPICredentials.loadOrCreateToken(at: fileURL)
        let loaded = try LocalAPICredentials.loadOrCreateToken(at: fileURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)

        #expect(created == loaded)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(attributes[.protectionKey] as? FileProtectionType == .completeUntilFirstUserAuthentication)
    }

    @Test("an unreadable or empty existing token is never silently rotated")
    func rejectsEmptyExistingToken() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("api-token")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: fileURL)

        #expect(throws: LocalAPICredentialsError.self) {
            try LocalAPICredentials.loadOrCreateToken(at: fileURL)
        }
        #expect((try Data(contentsOf: fileURL)).isEmpty)
    }
}
