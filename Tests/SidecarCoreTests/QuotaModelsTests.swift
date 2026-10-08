import XCTest
@testable import SidecarCore

final class QuotaModelsTests: XCTestCase {
    let time = Date(timeIntervalSince1970: 1799999000)
    func testWeeklyPrimaryDoesNotBecomeFiveHours() throws {
        let s = try QuotaDecoder.decodeRead(Fixture.data("weekly-only", ext: "json"), receivedAt: time)
        let w = try XCTUnwrap(s.buckets.first?.windows.first)
        XCTAssertEqual(w.label, "Weekly"); XCTAssertEqual(w.durationMinutes, 10080)
        XCTAssertEqual(w.remainingPercent, 75)
        XCTAssertEqual(w.resetAt, Date(timeIntervalSince1970: 1800000000))
        XCTAssertEqual(s.buckets.first?.windows.count, 1)
        XCTAssertNil(s.ordinaryUsageAllowed)
    }
    func testMapPrecedenceAndDistinctSlotsBuckets() throws {
        let s = try QuotaDecoder.decodeRead(Fixture.data("multiple-buckets", ext: "json"), receivedAt: time)
        XCTAssertEqual(s.buckets.map(\.id), ["codex", "other"])
        XCTAssertEqual(s.buckets[0].windows.map(\.remainingPercent), [90, 80])
        XCTAssertEqual(Set(s.buckets[0].windows.map(\.id)).count, 2)
        XCTAssertEqual(s.buckets[0].windows.map(\.label), ["5h (primary)", "5h (secondary)"])
        XCTAssertEqual(s.buckets[1].windows[0].label, "30 minutes")
        XCTAssertEqual(s.buckets[0].normalModelSlug, "synthetic-alias")
        XCTAssertNil(s.buckets[0].spendControlReached); XCTAssertEqual(s.ordinaryUsageAllowed, false)
    }
    func testAuthoritativeEmptyMapAndLegacyFallback() throws {
        XCTAssertTrue(try QuotaDecoder.decodeRead(Fixture.data("empty-map", ext: "json"), receivedAt: time).buckets.isEmpty)
        let raw = try Fixture.data("legacy-null-map", ext: "json")
        XCTAssertEqual(try QuotaDecoder.decodeRead(raw, receivedAt: time).buckets.first?.id, "legacy")
        XCTAssertEqual(try decode(#"{"rateLimits":{"primary":null}}"#).buckets.first?.id, "legacy")
        XCTAssertThrowsError(try decode(#"{"rateLimitsByLimitId":[]}"#))
        XCTAssertThrowsError(try decode(#"{}"#))
    }
    func testMalformedAndNullableFieldsRemainUnknown() throws {
        let s = try QuotaDecoder.decodeRead(Fixture.data("malformed-quota", ext: "json"), receivedAt: time)
        for w in s.buckets[0].windows {
            XCTAssertNil(w.usedPercent); XCTAssertNil(w.remainingPercent)
            XCTAssertNil(w.durationMinutes); XCTAssertNil(w.resetAt); XCTAssertEqual(w.label, "Unknown window")
        }
        XCTAssertFalse(s.warnings.isEmpty)
        XCTAssertFalse(String(describing: s).contains("PRIVATE_MARKER"))
        let s2 = try decode(#"{"rateLimits":{"primary":{"usedPercent":true,"windowDurationMins":true,"resetsAt":true}}}"#)
        XCTAssertNil(s2.buckets[0].windows[0].usedPercent)
        XCTAssertNil(s2.buckets[0].windows[0].durationMinutes)
        XCTAssertNil(s2.buckets[0].windows[0].resetAt)
    }
    func testFiniteValidationAndClamping() throws {
        for (value, expected) in [("-20", 100.0), ("150", 0.0), ("\"NaN\"", Double.nan)] {
            let s = try decode("{\"rateLimits\":{\"primary\":{\"usedPercent\":\(value)}}}")
            let w = s.buckets[0].windows[0]
            if expected.isNaN { XCTAssertNil(w.remainingPercent) } else { XCTAssertEqual(w.remainingPercent, expected) }
            XCTAssertFalse(s.warnings.isEmpty)
        }
    }
    func testUnrepresentableJSONNumberFailsClosed() {
        XCTAssertThrowsError(try decode("{\"rateLimits\":{\"primary\":{\"usedPercent\":1e400}}}"))
    }
    func testFullReadMayRemoveWindowsAndUnknownFieldsAreIgnored() throws {
        let s = try decode(#"{"accountId":"PRIVATE_MARKER","rateLimitsByLimitId":{"codex":{"primary":null,"secondary":null}},"future":"PRIVATE_MARKER"}"#)
        XCTAssertTrue(s.buckets[0].windows.isEmpty)
        XCTAssertFalse(String(describing: s).contains("PRIVATE_MARKER"))
    }
    func decode(_ raw: String) throws -> QuotaSnapshot { try QuotaDecoder.decodeRead(Data(raw.utf8), receivedAt: time) }
}
