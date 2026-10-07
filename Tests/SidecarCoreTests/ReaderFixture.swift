import Foundation
import Darwin
@testable import SidecarCore

final class ReaderFixture {
    let root: URL
    init() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        guard let path = realpath(temporary.path, nil) else { throw CocoaError(.fileReadUnknown) }
        defer { free(path) }
        root = URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    @discardableResult func write(_ data: Data, _ name: String = "sessions/source.jsonl") throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }
    static func header(_ id: String = Fixture.threadID, parent: String? = nil) -> Data {
        Data(("{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\",\"cli_version\":\"0.160.1\",\"cwd\":\"/invented/example-project\"" + (parent.map { ",\"parent_thread_id\":\"\($0)\"" } ?? "") + "}}\n").utf8)
    }
    static func native(_ count: Int, id: String = Fixture.threadID) -> Data {
        var data = header(id)
        data.append(Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"task\"}}\n".utf8))
        for index in 1...max(1, count) where index <= count {
            data.append(request(index, id: id))
        }
        return data
    }
    static func request(_ index: Int, id: String = Fixture.threadID) -> Data {
        Data("{\"type\":\"token_usage_record\",\"payload\":{\"thread_id\":\"\(id)\",\"turn_id\":\"task\",\"response_id\":\"response-\(index)\",\"usage\":{\"total_tokens\":1},\"thread_token_usage\":{\"total_tokens\":\(index)}}}\n".utf8)
    }
    static func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: data)
    }
}
