import Foundation

public extension OrderedJSON {
    enum ParseError: Error, Equatable {
        case unexpectedEnd
        case unexpected(byte: UInt8, at: Int)
        case badEscape(at: Int)
        case trailingData(at: Int)
    }

    static func parse(_ data: Data) throws -> OrderedJSON {
        var parser = Parser(bytes: Array(data))
        let value = try parser.value()
        parser.skipSpace()
        guard parser.index == parser.bytes.count else {
            throw ParseError.trailingData(at: parser.index)
        }
        return value
    }

    /// Two-space indent, one key per line, in the order the object holds them.
    func encoded(indent: Int = 0) -> String {
        let pad = String(repeating: " ", count: indent)
        let inner = String(repeating: " ", count: indent + 2)
        switch self {
        case let .object(pairs):
            guard !pairs.isEmpty else { return "{}" }
            let body = pairs
                .map { "\(inner)\(OrderedJSON.quote($0.key)): \($0.value.encoded(indent: indent + 2))" }
                .joined(separator: ",\n")
            return "{\n\(body)\n\(pad)}"
        case let .array(items):
            guard !items.isEmpty else { return "[]" }
            let body = items
                .map { "\(inner)\($0.encoded(indent: indent + 2))" }
                .joined(separator: ",\n")
            return "[\n\(body)\n\(pad)]"
        case let .string(text):  return OrderedJSON.quote(text)
        case let .number(text):  return text
        case let .bool(flag):    return flag ? "true" : "false"
        case .null:              return "null"
        }
    }

    static func quote(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

private struct Parser {
    let bytes: [UInt8]
    var index = 0

    mutating func skipSpace() {
        while index < bytes.count,
              bytes[index] == 0x20 || bytes[index] == 0x09
                || bytes[index] == 0x0A || bytes[index] == 0x0D {
            index += 1
        }
    }

    mutating func value() throws -> OrderedJSON {
        skipSpace()
        guard index < bytes.count else { throw OrderedJSON.ParseError.unexpectedEnd }
        switch bytes[index] {
        case 0x7B: return try object()
        case 0x5B: return try array()
        case 0x22: return .string(try string())
        case 0x74: try literal("true");  return .bool(true)
        case 0x66: try literal("false"); return .bool(false)
        case 0x6E: try literal("null");  return .null
        default:   return .number(try number())
        }
    }

    mutating func literal(_ text: String) throws {
        for byte in text.utf8 {
            guard index < bytes.count, bytes[index] == byte else {
                throw OrderedJSON.ParseError.unexpected(byte: bytes[min(index, bytes.count - 1)], at: index)
            }
            index += 1
        }
    }

    mutating func object() throws -> OrderedJSON {
        index += 1  // {
        var pairs: [(key: String, value: OrderedJSON)] = []
        skipSpace()
        if index < bytes.count, bytes[index] == 0x7D { index += 1; return .object(pairs) }
        while true {
            skipSpace()
            let key = try string()
            skipSpace()
            guard index < bytes.count, bytes[index] == 0x3A else {
                throw OrderedJSON.ParseError.unexpected(byte: bytes[min(index, bytes.count - 1)], at: index)
            }
            index += 1
            pairs.append((key, try value()))
            skipSpace()
            guard index < bytes.count else { throw OrderedJSON.ParseError.unexpectedEnd }
            if bytes[index] == 0x2C { index += 1; continue }
            if bytes[index] == 0x7D { index += 1; return .object(pairs) }
            throw OrderedJSON.ParseError.unexpected(byte: bytes[index], at: index)
        }
    }

    mutating func array() throws -> OrderedJSON {
        index += 1  // [
        var items: [OrderedJSON] = []
        skipSpace()
        if index < bytes.count, bytes[index] == 0x5D { index += 1; return .array(items) }
        while true {
            items.append(try value())
            skipSpace()
            guard index < bytes.count else { throw OrderedJSON.ParseError.unexpectedEnd }
            if bytes[index] == 0x2C { index += 1; continue }
            if bytes[index] == 0x5D { index += 1; return .array(items) }
            throw OrderedJSON.ParseError.unexpected(byte: bytes[index], at: index)
        }
    }

    mutating func string() throws -> String {
        guard index < bytes.count, bytes[index] == 0x22 else {
            throw OrderedJSON.ParseError.unexpected(byte: bytes[min(index, bytes.count - 1)], at: index)
        }
        index += 1
        var out = [UInt8]()
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x22 { index += 1; return String(decoding: out, as: UTF8.self) }
            if byte == 0x5C {
                index += 1
                guard index < bytes.count else { throw OrderedJSON.ParseError.unexpectedEnd }
                switch bytes[index] {
                case 0x22: out.append(0x22)
                case 0x5C: out.append(0x5C)
                case 0x2F: out.append(0x2F)
                case 0x62: out.append(0x08)
                case 0x66: out.append(0x0C)
                case 0x6E: out.append(0x0A)
                case 0x72: out.append(0x0D)
                case 0x74: out.append(0x09)
                case 0x75:
                    // Decoded through Foundation rather than by hand: surrogate pairs
                    // are the part everyone gets wrong.
                    let start = index - 1
                    var length = 6
                    if start + 12 <= bytes.count, bytes[start + 6] == 0x5C, bytes[start + 7] == 0x75 {
                        length = 12
                    }
                    let escape = String(decoding: bytes[start..<(start + length)], as: UTF8.self)
                    guard let decoded = try? JSONSerialization.jsonObject(
                        with: Data(("\"" + escape + "\"").utf8),
                        options: [.fragmentsAllowed]) as? String
                    else { throw OrderedJSON.ParseError.badEscape(at: start) }
                    out.append(contentsOf: Array(decoded.utf8))
                    index = start + length
                    continue
                default: throw OrderedJSON.ParseError.badEscape(at: index)
                }
                index += 1
                continue
            }
            out.append(byte)
            index += 1
        }
        throw OrderedJSON.ParseError.unexpectedEnd
    }

    mutating func number() throws -> String {
        let start = index
        while index < bytes.count {
            let byte = bytes[index]
            let isNumber = (byte >= 0x30 && byte <= 0x39)
                || byte == 0x2D || byte == 0x2B || byte == 0x2E
                || byte == 0x65 || byte == 0x45
            if !isNumber { break }
            index += 1
        }
        guard index > start else {
            throw OrderedJSON.ParseError.unexpected(byte: bytes[min(start, bytes.count - 1)], at: start)
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }
}
