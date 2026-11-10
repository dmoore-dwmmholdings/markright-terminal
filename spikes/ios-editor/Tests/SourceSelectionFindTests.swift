import Foundation
import XCTest
@testable import MarkrightEditorSpike

final class SourceSelectionFindTests: XCTestCase {
    func testForwardBackwardAndWrapExcludeCurrentSelection() throws {
        let source = "cat cat cat"
        let middle = SourceSelectionFind.make(source: source, selection: .init(location: 4, length: 3))
        XCTAssertNil(middle.message)
        XCTAssertEqual(middle.next?.destination, NSRange(location: 8, length: 3))
        XCTAssertEqual(middle.previous?.destination, NSRange(location: 0, length: 3))
        XCTAssertEqual(SourceSelectionFind.make(source: source, selection: .init(location: 8, length: 3)).next?.destination,
                       NSRange(location: 0, length: 3))
        XCTAssertEqual(SourceSelectionFind.make(source: source, selection: .init(location: 0, length: 3)).previous?.destination,
                       NSRange(location: 8, length: 3))
    }

    func testLiteralCaseCanonicalUnicodeAndUTF16Coordinates() {
        let source = "e\u{301} É é e\u{301} 😀 😀"
        let nfd = SourceSelectionFind.make(source: source, selection: .init(location: 0, length: 2))
        XCTAssertEqual(nfd.next?.destination, NSRange(location: 7, length: 2))
        XCTAssertEqual(nfd.previous?.destination, nfd.next?.destination)
        for selection in [NSRange(location: 3, length: 1), NSRange(location: 5, length: 1)] {
            XCTAssertEqual(SourceSelectionFind.make(source: source, selection: selection).message, "No other exact occurrence.")
        }
        XCTAssertEqual(SourceSelectionFind.make(source: source, selection: .init(location: 10, length: 2)).next?.destination,
                       NSRange(location: 13, length: 2))
        let markup = "[a.*] [A.*] [a.*]"
        XCTAssertEqual(SourceSelectionFind.make(source: markup, selection: .init(location: 0, length: 5)).next?.destination,
                       NSRange(location: 12, length: 5))
    }

    func testMultilineExactEndingsAndBOMRemainLiteral() {
        let query = "😀\r\ne\u{301}"
        let source = "\u{FEFF}" + query + " / 😀\ne\u{301} / " + query
        let selection = NSRange(location: 1, length: query.utf16.count)
        let report = SourceSelectionFind.make(source: source, selection: selection)
        XCTAssertEqual(report.next?.destination, NSRange(location: source.utf16.count - query.utf16.count, length: query.utf16.count))
        XCTAssertTrue(report.next?.source.utf8.elementsEqual(source.utf8) == true)
    }

    func testCRLFInteriorRawCandidatesAreSkippedInBothDirections() {
        let source = "\n\r\n\r\n\n"
        let first = SourceSelectionFind.make(source: source, selection: .init(location: 0, length: 1))
        XCTAssertEqual(first.next?.destination, NSRange(location: 5, length: 1))
        XCTAssertEqual(first.previous?.destination, NSRange(location: 5, length: 1))
        let last = SourceSelectionFind.make(source: source, selection: .init(location: 5, length: 1))
        XCTAssertEqual(last.previous?.destination, NSRange(location: 0, length: 1))
        XCTAssertEqual(last.next?.destination, NSRange(location: 0, length: 1))
        // Query starts/ends at valid boundaries, raw matching inside CRLF does not.
        let cr = SourceSelectionFind.make(source: "\r\r\n\r", selection: .init(location: 0, length: 1))
        XCTAssertEqual(cr.next?.destination, NSRange(location: 3, length: 1))
        XCTAssertEqual(SourceSelectionFind.make(source: "\n\r\n", selection: .init(location: 0, length: 1)).message,
                       "No other exact occurrence.")
    }

    func testOverlapsAreExcludedButAdjacentMatchesAllowed() {
        for selection in [NSRange(location: 0, length: 3), NSRange(location: 1, length: 3)] {
            XCTAssertEqual(SourceSelectionFind.make(source: "aaaa", selection: selection).message, "No other exact occurrence.")
        }
        let adjacent = SourceSelectionFind.make(source: "aaaaaa", selection: .init(location: 0, length: 3))
        XCTAssertEqual(adjacent.next?.destination, NSRange(location: 3, length: 3))
        XCTAssertEqual(adjacent.previous?.destination, adjacent.next?.destination)
        let middle = SourceSelectionFind.make(source: "aaaaa", selection: .init(location: 1, length: 3))
        XCTAssertNil(middle.next)
        XCTAssertNil(middle.previous)
    }

    func testEmptyInvalidAndOverflowSelectionsHaveExplicitStatus() {
        XCTAssertTrue(SourceSelectionFind.make(source: "", selection: .init(location: 0, length: 0)).message?.contains("Select source") == true)
        let source = "😀\r\nx"
        for selection in [NSRange(location: 1, length: 1), NSRange(location: 3, length: 1),
                          NSRange(location: -1, length: 1), NSRange(location: 0, length: -1),
                          NSRange(location: NSNotFound, length: 1), NSRange(location: 0, length: Int.max),
                          NSRange(location: source.utf16.count, length: 1)] {
            let report = SourceSelectionFind.make(source: source, selection: selection)
            XCTAssertTrue(report.message?.contains("invalid") == true)
            XCTAssertNil(report.next); XCTAssertNil(report.previous)
        }
    }

    func testCapturedPlansRefuseChangedBytesOrSelectionAndFactoryValidates() throws {
        let source = "e\u{301} e\u{301}"
        let range = NSRange(location: 0, length: 2)
        let plan = try XCTUnwrap(SourceSelectionFind.make(source: source, selection: range).next)
        XCTAssertTrue(plan.matches(source: source, selection: range))
        XCTAssertFalse(plan.matches(source: source + "x", selection: range))
        XCTAssertFalse(plan.matches(source: source.precomposedStringWithCanonicalMapping, selection: range))
        XCTAssertFalse(plan.matches(source: source, selection: plan.destination))
        XCTAssertNil(SourceNavigationPlan.make(source: "😀\r\n", selection: .init(location: 1, length: 0), destination: .init(location: 0, length: 2)))
        XCTAssertNil(SourceNavigationPlan.make(source: "😀\r\n", selection: .init(location: 0, length: 2), destination: .init(location: 3, length: 1)))
    }

    func testSourceUTF8BudgetAtBoundaryAndOver() {
        let exact = "q q" + String(repeating: "😀", count: 262_143) + "x"
        XCTAssertEqual(exact.utf8.count, SourceSelectionFind.maximumSourceBytes)
        XCTAssertNotNil(SourceSelectionFind.make(source: exact, selection: .init(location: 0, length: 1)).next)
        let report = SourceSelectionFind.make(source: exact + "x", selection: .init(location: 0, length: 1))
        XCTAssertTrue(report.message?.contains("1 MiB") == true)
        XCTAssertNil(report.next); XCTAssertNil(report.previous)
    }

    func testQueryUTF8BudgetAtBoundaryAndOver() {
        let query = String(repeating: "😀", count: 16_384)
        let exact = SourceSelectionFind.make(source: query + " " + query, selection: .init(location: 0, length: query.utf16.count))
        XCTAssertNotNil(exact.next)
        let over = query + "x"
        let refused = SourceSelectionFind.make(source: over + " " + over, selection: .init(location: 0, length: over.utf16.count))
        XCTAssertTrue(refused.message?.contains("64 KiB") == true)
        XCTAssertNil(refused.next); XCTAssertNil(refused.previous)
    }

    func testCandidateBudgetAllows256ButRefuses257WithoutPartialPlans() {
        for count in [255, 256] {
            let source = "\n" + String(repeating: "\r\n", count: count) + "\n"
            for offset in [0, source.utf16.count - 1] {
                let report = SourceSelectionFind.make(source: source, selection: .init(location: offset, length: 1))
                if count == 255 {
                    XCTAssertNil(report.message); XCTAssertNotNil(report.next); XCTAssertNotNil(report.previous)
                } else {
                    XCTAssertTrue(report.message?.contains("256 candidate") == true)
                    XCTAssertNil(report.next); XCTAssertNil(report.previous)
                }
            }
        }
        let noOtherAtLimit = SourceSelectionFind.make(source: "\n" + String(repeating: "\r\n", count: 256), selection: .init(location: 0, length: 1))
        XCTAssertEqual(noOtherAtLimit.message, "No other exact occurrence.")
        let invalidOverLimit = SourceSelectionFind.make(source: "\n" + String(repeating: "\r\n", count: 257), selection: .init(location: 0, length: 1))
        XCTAssertTrue(invalidOverLimit.message?.contains("256 candidate") == true)
    }

    func testCandidateBudgetAccumulatesAcrossWrapSegmentsAndDirections() {
        for prefixCount in [127, 128] {
            let prefix = String(repeating: "\r\n", count: prefixCount)
            let source = prefix + "\nX\n" + String(repeating: "\r\n", count: 128)
            let selected = NSRange(location: prefix.utf16.count + 2, length: 1)
            let forward = SourceSelectionFind.make(source: source, selection: selected)
            let mirror = String(repeating: "\r\n", count: 128) + "\nX\n" + prefix
            let backward = SourceSelectionFind.make(source: mirror, selection: .init(location: 256, length: 1))
            for report in [forward, backward] {
                if prefixCount == 127 { XCTAssertNil(report.message); XCTAssertNotNil(report.next); XCTAssertNotNil(report.previous) }
                else { XCTAssertTrue(report.message?.contains("256 candidate") == true); XCTAssertNil(report.next); XCTAssertNil(report.previous) }
            }
        }
    }
}
