import XCTest
@testable import SidecarCore

final class TokenUsageTests: XCTestCase {
    func testSubsetsAreNotAddedToTotal() throws {
        let usage = TokenUsage(input: 100, cachedInput: 60, cacheWriteInput: 0,
                               output: 20, reasoning: 5, total: 120)
        XCTAssertNoThrow(try usage.validated())
        XCTAssertEqual(usage.total, 120)
    }

    func testCheckedSumPreservesAvailability() throws {
        let a = TokenUsage(input: 100, cachedInput: 60, cacheWriteInput: 0,
                           output: 20, reasoning: 5, total: 120)
        let b = TokenUsage(input: 50, cachedInput: 40, cacheWriteInput: 0,
                           output: 10, reasoning: 2, total: 60)
        XCTAssertEqual(try a.adding(b), TokenUsage(input: 150, cachedInput: 100,
            cacheWriteInput: 0, output: 30, reasoning: 7, total: 180))
        let partial = try a.adding(TokenUsage(total: 60))
        XCTAssertEqual(partial.total, 180)
        XCTAssertNil(partial.input)
        XCTAssertNil(partial.cachedInput)
        XCTAssertNil(partial.cacheWriteInput)
        XCTAssertNil(partial.output)
        XCTAssertNil(partial.reasoning)
    }

    func testEmptyAndZeroRemainDistinct() throws {
        XCTAssertNoThrow(try TokenUsage().validated())
        XCTAssertNil(TokenUsage().total)
        XCTAssertNoThrow(try TokenUsage(input: 0, cachedInput: 0, output: 0,
                                        reasoning: 0, total: 0).validated())
    }

    func testEveryNegativeCounterIsRejected() {
        let cases = [TokenUsage(input: -1), TokenUsage(cachedInput: -1),
                     TokenUsage(cacheWriteInput: -1), TokenUsage(output: -1),
                     TokenUsage(reasoning: -1), TokenUsage(total: -1)]
        for usage in cases { XCTAssertThrowsError(try usage.validated()) }
    }

    func testSubsetBoundsAreCheckedOnlyWhenComparable() {
        XCTAssertThrowsError(try TokenUsage(input: 10, cachedInput: 11).validated())
        XCTAssertThrowsError(try TokenUsage(output: 10, reasoning: 11).validated())
        XCTAssertNoThrow(try TokenUsage(cachedInput: 11, reasoning: 11).validated())
    }

    func testContradictoryTotalAndArithmeticOverflowAreRejected() {
        XCTAssertThrowsError(try TokenUsage(input: 100, output: 20, total: 121).validated())
        XCTAssertThrowsError(try TokenUsage(input: .max, output: 1, total: .max).validated())
        XCTAssertThrowsError(try TokenUsage(total: .max).adding(TokenUsage(total: 1)))
        XCTAssertThrowsError(try TokenUsage(input: .max).adding(TokenUsage(input: 1)))
    }

    func testSumRejectsInvalidOperands() {
        XCTAssertThrowsError(try TokenUsage(total: -1).adding(TokenUsage(total: 2)))
    }
    func testPartialCountersCannotExceedExplicitTotal() {
        for usage in [TokenUsage(input: 100, total: 1), TokenUsage(output: 100, total: 1),
                      TokenUsage(cachedInput: 100, total: 1), TokenUsage(reasoning: 100, total: 1),
                      TokenUsage(cachedInput: 60, reasoning: 5, total: 64)] {
            XCTAssertThrowsError(try usage.validated())
        }
        XCTAssertNoThrow(try TokenUsage(input: 100, total: 120).validated())
        XCTAssertNoThrow(try TokenUsage(cachedInput: 60, reasoning: 5, total: 65).validated())
        XCTAssertNoThrow(try TokenUsage(total: 0).validated())
    }

    func testPartialSubsetLowerBoundOverflowFailsClosed() {
        XCTAssertThrowsError(try TokenUsage(cachedInput: .max, reasoning: 1).validated())
    }

}
