import Foundation

// MRK-28 feasibility only. This takes typed values, NOT untrusted JSON or code.
// Document parsing/trust, UI invocation and transport validation remain separate.
enum DeclarativeBitfieldDecoder {
    enum Failure: Error, Equatable { case invalidData }

    struct Field {
        let id: String
        let label: String
        let lsb: Int
        let width: Int
        let signed: Bool
    }
    struct Specification {
        let kind: String
        let bits: Int
        let fields: [Field]
    }
    struct Table: Encodable, Equatable {
        let version = "0.1"
        let kind = "table"
        let columns = ["Field", "Value"]
        let rows: [[String]]

        fileprivate init(rows: [[String]]) { self.rows = rows }

        // Consumers must display these strings literally, never interpret markup.
        func encodedJSON() throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let result = try encoder.encode(self)
            guard result.count <= 65_536 else { throw Failure.invalidData }
            return result
        }
    }

    static func decode(_ specification: Specification, input: String) throws -> Table {
        guard specification.kind == "markright.bitfields/0.1",
              [8, 16, 32, 64].contains(specification.bits),
              (1...64).contains(specification.fields.count) else { throw Failure.invalidData }
        let number = try parseInput(input)
        if specification.bits < 64 && number >= UInt64(1) << specification.bits { throw Failure.invalidData }

        var occupied: UInt64 = 0
        var identifiers = Set<String>()
        var rows: [[String]] = []
        for field in specification.fields {
            // Check by subtraction before arithmetic or shifts, including Int.max.
            guard validIdentifier(field.id), identifiers.insert(field.id).inserted,
                  field.label.utf16.count <= 4_096,
                  field.lsb >= 0, field.lsb < specification.bits,
                  field.width > 0, field.width <= specification.bits - field.lsb else { throw Failure.invalidData }
            let mask: UInt64 = field.width == 64 ? .max : (UInt64(1) << field.width) - 1
            let located = mask << field.lsb
            guard occupied & located == 0 else { throw Failure.invalidData }
            occupied |= located
            let raw = (number >> field.lsb) & mask
            let value: String
            if field.signed && field.width == 64 {
                value = String(Int64(bitPattern: raw))
            } else if field.signed && raw & (UInt64(1) << (field.width - 1)) != 0 {
                // width < 64 makes this unsigned magnitude subtraction exact.
                value = "-" + String((UInt64(1) << field.width) - raw)
            } else {
                value = String(raw)
            }
            rows.append([field.label, value])
        }
        let result = Table(rows: rows)
        _ = try result.encodedJSON() // Enforce the encoded UTF-8 limit before returning.
        return result
    }

    private static func validIdentifier(_ value: String) -> Bool {
        let bytes = value.utf8
        func letter(_ b: UInt8) -> Bool { (65...90).contains(b) || (97...122).contains(b) }
        guard (1...64).contains(bytes.count), let first = bytes.first, letter(first) else { return false }
        return bytes.dropFirst().allSatisfy { letter($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }

    private static func parseInput(_ input: String) throws -> UInt64 {
        guard input.utf16.count <= 20 else { throw Failure.invalidData }
        let bytes = Array(input.utf8)
        let hexadecimal = bytes.starts(with: [48, 120])
        let digits = hexadecimal ? Array(bytes.dropFirst(2)) : bytes
        guard !digits.isEmpty else { throw Failure.invalidData }
        if !hexadecimal && digits.count > 1 && digits[0] == 48 { throw Failure.invalidData }
        let radix: UInt64 = hexadecimal ? 16 : 10
        var result: UInt64 = 0
        for byte in digits {
            let digit: UInt64
            switch byte {
            case 48...57: digit = UInt64(byte - 48)
            case 65...70 where hexadecimal: digit = UInt64(byte - 65 + 10)
            case 97...102 where hexadecimal: digit = UInt64(byte - 97 + 10)
            default: throw Failure.invalidData
            }
            let (product, multipliedOverflow) = result.multipliedReportingOverflow(by: radix)
            let (sum, addedOverflow) = product.addingReportingOverflow(digit)
            guard !multipliedOverflow && !addedOverflow else { throw Failure.invalidData }
            result = sum
        }
        return result
    }
}
