import Foundation
@testable import SidecarCore

enum Fixture {
    static let threadID = "11111111-1111-4111-8111-111111111111"

    static func events(_ name: String) throws -> [MetricEvent] {
        let decoder = RolloutDecoder()
        var offset: Int64 = 0
        return try lines(name).compactMap { line in
            defer { offset += Int64(line.count) + 1 }
            let result = decoder.decodeLine(line, at: SourcePosition(fileID: name, byteOffset: offset))
            guard result.diagnostics.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            return result.event
        }
    }

    static func lines(_ name: String) throws -> [Data] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "jsonl") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url).split(separator: 0x0A).map { Data($0) }
    }
}
