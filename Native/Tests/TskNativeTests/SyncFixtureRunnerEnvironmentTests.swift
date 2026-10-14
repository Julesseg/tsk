import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import TskCore
import TskNative

final class SyncFixtureRunnerEnvironmentTests: XCTestCase {
    func testRealFixtureCanPublishForIndependentEncryptedVerification() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TSK_UI_VERIFY_PEER_FIXTURE"] == "1" else { throw XCTSkip("Executed separately by the real fixture peer probe") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = try XCTUnwrap(UUID(uuidString: XCTUnwrap(environment["TSK_UI_SYNC_CLIENT_ID"])))
        let configuration = try SyncConfiguration(serverURL: XCTUnwrap(environment["TSK_UI_SYNC_SERVER_URL"]), clientID: client, encryptionSecret: XCTUnwrap(environment["TSK_UI_SYNC_SECRET"]))
        let manager = TaskManager(replica: TaskChampionReplica(directory: root))
        _ = try await manager.create(TaskDraft(description: "Hosted task " + XCTUnwrap(environment["TSK_UI_SYNC_FIXTURE_TOKEN"])))
        _ = try await manager.synchronize(using: configuration)
    }

    func testRealFixtureSettingsReachTheXcodeTestRunner() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TSK_UI_VERIFY_RUNNER_ENV"] == "1" else { throw XCTSkip("Executed separately by the isolated xcodebuild runner probe") }
        let server = try XCTUnwrap(environment["TSK_UI_SYNC_SERVER_URL"])
        let client = try XCTUnwrap(environment["TSK_UI_SYNC_CLIENT_ID"])
        let token = try XCTUnwrap(environment["TSK_UI_SYNC_FIXTURE_TOKEN"])
        XCTAssertNotNil(UUID(uuidString: client))
        XCTAssertFalse(try XCTUnwrap(environment["TSK_UI_SYNC_SECRET"]).isEmpty)
        let (data, response) = try await URLSession.shared.data(from: try XCTUnwrap(URL(string: server)))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "TaskChampion sync server v0.7.1")
        let proof = try XCTUnwrap(environment["TSK_UI_RUNNER_PROOF_PATH"])
        let contents = try JSONSerialization.data(withJSONObject: ["token": token, "clientID": client, "serverURL": server, "runnerPID": ProcessInfo.processInfo.processIdentifier])
        try contents.write(to: URL(fileURLWithPath: proof), options: .atomic)
    }
}
