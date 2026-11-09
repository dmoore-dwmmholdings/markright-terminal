import XCTest
@testable import MarkrightEditorSpike

final class DeclarativeDecoderTests: XCTestCase {
    private typealias Decoder = DeclarativeBitfieldDecoder
    private func field(id: String = "value", label: String = "Value", lsb: Int = 0, width: Int = 64, signed: Bool = false) -> Decoder.Field {
        .init(id: id, label: label, lsb: lsb, width: width, signed: signed)
    }
    private func spec(_ fields: [Decoder.Field], bits: Int = 64, kind: String = "markright.bitfields/0.1") -> Decoder.Specification {
        .init(kind: kind, bits: bits, fields: fields)
    }

    func testExactUnsignedAndSignedBoundaryValues() throws {
        XCTAssertEqual(try Decoder.decode(spec([field()]), input: "18446744073709551615").rows, [["Value", "18446744073709551615"]])
        XCTAssertEqual(try Decoder.decode(spec([field(signed: true)]), input: "0xffffffffffffffff").rows, [["Value", "-1"]])
        XCTAssertEqual(try Decoder.decode(spec([field(signed: true)]), input: "9223372036854775808").rows, [["Value", "-9223372036854775808"]])
        XCTAssertEqual(try Decoder.decode(spec([field(signed: true)]), input: "9223372036854775807").rows, [["Value", "9223372036854775807"]])
        XCTAssertEqual(try Decoder.decode(spec([field(lsb: 4, width: 4)]), input: "0xA0").rows, [["Value", "10"]])
        XCTAssertEqual(try Decoder.decode(spec([field(width: 1, signed: true)]), input: "1").rows, [["Value", "-1"]])
        XCTAssertEqual(try Decoder.decode(spec([field(width: 63, signed: true)]), input: "4611686018427387904").rows, [["Value", "-4611686018427387904"]])
    }

    func testAllSupportedWidthsAndDisjointFields() throws {
        for bits in [8, 16, 32, 64] {
            let value = bits == 64 ? UInt64.max : (UInt64(1) << bits) - 1
            let fields = (0..<bits).map { field(id: "b\($0)", label: "Bit \($0)", lsb: $0, width: 1) }
            let table = try Decoder.decode(spec(fields, bits: bits), input: String(value))
            XCTAssertEqual(table.rows.count, bits)
            XCTAssertTrue(table.rows.allSatisfy { $0[1] == "1" })
        }
        XCTAssertEqual(try Decoder.decode(spec([field(lsb: 63, width: 1)]), input: "0x8000000000000000").rows[0][1], "1")
    }

    func testMalformedAndOutOfRangeInputNeverCoercesOrOverflows() {
        for value in ["", "-1", "+1", "01", "1.0", "1e0", "1+2", " 1", "1\n", "0XFF", "0x", "0xgg", "１２", "18446744073709551616", "0x10000000000000000", String(repeating: "0", count: 21)] {
            XCTAssertThrowsError(try Decoder.decode(spec([field()]), input: value), value)
        }
        for bits in [8, 16, 32] {
            XCTAssertThrowsError(try Decoder.decode(spec([field(width: bits)], bits: bits), input: String(UInt64(1) << bits)))
        }
    }

    func testInvalidDeclarationsFailBeforeDangerousArithmetic() {
        let fields = [field(lsb: -1), field(lsb: Int.max), field(width: 0), field(width: -1), field(width: Int.max), field(lsb: 1), field(lsb: 64, width: 1)]
        for f in fields { XCTAssertThrowsError(try Decoder.decode(spec([f]), input: "0")) }
        for bits in [0, 1, 7, 65, Int.max] { XCTAssertThrowsError(try Decoder.decode(spec([field()], bits: bits), input: "0")) }
        XCTAssertThrowsError(try Decoder.decode(spec([field()], kind: "markright.bitfields/0.2"), input: "0"))
        XCTAssertThrowsError(try Decoder.decode(spec([]), input: "0"))
        XCTAssertThrowsError(try Decoder.decode(spec(Array(repeating: field(), count: 65)), input: "0"))
        XCTAssertThrowsError(try Decoder.decode(spec([field(), field(id: "other")]), input: "0"))
        XCTAssertThrowsError(try Decoder.decode(spec([field(width: 1), field(lsb: 1, width: 1)]), input: "0"))
    }

    func testASCIIIdentifiersAndUTF16LabelBounds() throws {
        for identifier in ["", "1x", "_x", "x.y", "x y", "é", "x\n", String(repeating: "a", count: 65)] {
            XCTAssertThrowsError(try Decoder.decode(spec([field(id: identifier)]), input: "0"))
        }
        XCTAssertNoThrow(try Decoder.decode(spec([field(id: "A-0_" + String(repeating: "z", count: 60))]), input: "0"))
        XCTAssertNoThrow(try Decoder.decode(spec([field(label: String(repeating: "😀", count: 2048))]), input: "0"))
        XCTAssertThrowsError(try Decoder.decode(spec([field(label: String(repeating: "😀", count: 2049))]), input: "0"))
        XCTAssertNoThrow(try Decoder.decode(spec([field(label: "")]), input: "0"))
    }

    func testOutputIsBoundedVersionedLiteralText() throws {
        let label = "<script>alert(1)</script> **bold** https://example.invalid/\n\"literal\""
        let table = try Decoder.decode(spec([field(label: label)]), input: "0")
        XCTAssertEqual(table.version, "0.1"); XCTAssertEqual(table.kind, "table")
        XCTAssertEqual(table.columns, ["Field", "Value"]); XCTAssertEqual(table.rows, [[label, "0"]])
        let encoded = try table.encodedJSON()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["version", "kind", "columns", "rows"]))
        XCTAssertEqual(object["rows"] as? [[String]], [[label, "0"]])
        let large = (0..<64).map { field(id: "f\($0)", label: String(repeating: "x", count: 4096), lsb: $0, width: 1) }
        XCTAssertThrowsError(try Decoder.decode(spec(large), input: "0"))
        let escaped = (0..<64).map { field(id: "f\($0)", label: String(repeating: "\u{0}", count: 1024), lsb: $0, width: 1) }
        XCTAssertThrowsError(try Decoder.decode(spec(escaped), input: "0"))
    }

    // JSONDecoder reads only the authored bundled test corpus, never document data.
    private struct Corpus: Decodable { let profile: String; let cases: [Vector] }
    private struct Vector: Decodable {
        let id: String; let spec: FixtureSpec; let input: String
        let expected: Expected?; let reject: Bool?
    }
    private struct FixtureSpec: Decodable {
        let kind: String; let bits: Int; let fields: [FixtureField]
        var typed: Decoder.Specification { .init(kind: kind, bits: bits, fields: fields.map { .init(id: $0.id, label: $0.label, lsb: $0.lsb, width: $0.width, signed: $0.signed) }) }
    }
    private struct FixtureField: Decodable { let id: String; let label: String; let lsb: Int; let width: Int; let signed: Bool }
    private struct Expected: Decodable { let version: String; let kind: String; let columns: [String]; let rows: [[String]] }

    func testSharedTrustedCalculatorVectors() throws {
        let url = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: "bitfields-0.1", withExtension: "json"))
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
        XCTAssertEqual(corpus.profile, "markright.bitfields/0.1")
        XCTAssertFalse(corpus.cases.isEmpty)
        for vector in corpus.cases {
            if vector.reject == true {
                XCTAssertThrowsError(try Decoder.decode(vector.spec.typed, input: vector.input), vector.id)
            } else {
                let expected = try XCTUnwrap(vector.expected, vector.id)
                let actual = try Decoder.decode(vector.spec.typed, input: vector.input)
                XCTAssertEqual(actual.version, expected.version, vector.id)
                XCTAssertEqual(actual.kind, expected.kind, vector.id)
                XCTAssertEqual(actual.columns, expected.columns, vector.id)
                XCTAssertEqual(actual.rows, expected.rows, vector.id)
            }
        }
    }
}
