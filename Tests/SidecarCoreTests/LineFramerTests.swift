import XCTest
@testable import SidecarCore

final class LineFramerTests: XCTestCase {
    func testEveryByteSplitAndMultibyteUTF8() {
        let bytes = Data("{\"value\":\"猫😀\"}\n".utf8)
        for split in 0...bytes.count {
            var framer = LineFramer()
            let lines = framer.append(bytes.prefix(split)) + framer.append(bytes.dropFirst(split))
            XCTAssertEqual(lines, [Data(bytes.dropLast())])
        }
        var framer = LineFramer()
        var lines: [Data] = []
        for byte in bytes { lines += framer.append(Data([byte])) }
        XCTAssertEqual(lines, [Data(bytes.dropLast())])
    }
    func testCRLFEmptyLinesAndIncompleteEOF() {
        var framer = LineFramer()
        XCTAssertEqual(framer.append(Data("a\r\n\nb\npartial".utf8)), [Data("a".utf8), Data(), Data("b".utf8)])
        XCTAssertTrue(framer.hasIncompleteLine)
        XCTAssertEqual(framer.append(Data("\n".utf8)), [Data("partial".utf8)])
        XCTAssertFalse(framer.hasIncompleteLine)
        _ = framer.append(Data("unfinished".utf8)); framer.reset()
        XCTAssertEqual(framer.bufferedByteCount, 0)
    }
    func testOversizedLineDiscardsThroughNewlineAndRecovers() {
        var framer = LineFramer()
        let chunk = Data(repeating: 65, count: 65536)
        for _ in 0..<129 {
            XCTAssertTrue(framer.append(chunk).isEmpty)
            XCTAssertLessThanOrEqual(framer.bufferedByteCount, 8 * 1024 * 1024)
        }
        XCTAssertEqual(framer.diagnostics.map(\.category), [.oversizedRecord])
        XCTAssertEqual(framer.append(Data("discard\nvalid\n".utf8)), [Data("valid".utf8)])
        XCTAssertFalse(framer.hasIncompleteLine)
    }
    func testMalformedCompleteLineDoesNotConsumeFollowingRecord() {
        var framer = LineFramer()
        let lines = framer.append(Data("bad\n{\"type\":\"future\"}\n".utf8))
        let decoder = RolloutDecoder()
        XCTAssertEqual(decoder.decodeLine(lines[0], at: .init(fileID: "synthetic", byteOffset: 0)).diagnostics.first?.category, .malformedRecord)
        XCTAssertNotNil(decoder.decodeLine(lines[1], at: .init(fileID: "synthetic", byteOffset: 4)).event)
    }
}
