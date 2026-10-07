import Foundation

enum Fixture {
    static let threadID = "11111111-1111-4111-8111-111111111111"

    static func lines(_ name: String) throws -> [Data] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "jsonl") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url).split(separator: 0x0A).map { Data($0) }
    }
}
