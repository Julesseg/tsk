import Darwin
import XCTest

@MainActor
extension XCTestCase {
    func storedTasks(_ app: XCUIApplication, checkpoint: String, function: String = #function) async throws -> [String: [String: String]] {
        let session = try XCTUnwrap(ProcessInfo.processInfo.environment["TSK_UI_NATIVE_READBACK_TOKEN"], "Use scripts/run-ui-tests.sh for Native readback")
        let replica = try XCTUnwrap(app.launchEnvironment["TSK_TEST_REPLICA_NAME"])
        let nonce = UUID().uuidString
        let method = String(describing: type(of: self)) + "/" + function.replacingOccurrences(of: "()", with: "")
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("TskNativeReadback")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let request: [String: Any] = ["schema": 1, "nonce": nonce, "session": session, "replica": replica, "method": method, "checkpoint": checkpoint]
        try JSONSerialization.data(withJSONObject: request).write(to: folder.appendingPathComponent(nonce + ".request.json"), options: .atomic)
        print("TSK_NATIVE_READBACK_REQUEST " + nonce)
        fflush(nil)
        let response = folder.appendingPathComponent(nonce + ".response.json")
        try await StoredTaskResponse(response).wait()
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: response)) as? [String: Any])
        XCTAssertNil(value["error"], String(describing: value["error"]))
        XCTAssertEqual(value["nonce"] as? String, nonce)
        XCTAssertTrue(value["session"] as? String == session, "Native readback session mismatch")
        XCTAssertEqual(value["replica"] as? String, replica)
        XCTAssertEqual(value["method"] as? String, method)
        XCTAssertEqual(value["checkpoint"] as? String, checkpoint)
        let records = try XCTUnwrap(value["records"] as? [[String: Any]])
        var result: [String: [String: String]] = [:]
        for record in records {
            let id = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(record["id"] as? String)))
            let entries = try XCTUnwrap(record["attributes"] as? [[String: String]])
            var attributes: [String: String] = [:]
            for entry in entries { attributes[try XCTUnwrap(entry["key"])] = try XCTUnwrap(entry["value"]) }
            XCTAssertNil(result[id.uuidString], "Duplicate native task identity")
            result[id.uuidString] = attributes
        }
        return result
    }
}

@MainActor
private final class StoredTaskResponse {
    private let response: URL
    private var source: DispatchSourceFileSystemObject?
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ response: URL) { self.response = response }

    func wait() async throws {
        let descriptor = open(response.deletingLastPathComponent().path, O_EVTONLY)
        guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        self.source = source
        source.setCancelHandler { close(descriptor) }
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.received() }
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            source.resume()
            received()
        }
    }

    private func received() {
        guard FileManager.default.fileExists(atPath: response.path), let continuation else { return }
        self.continuation = nil
        source?.cancel()
        source = nil
        continuation.resume()
    }
}
