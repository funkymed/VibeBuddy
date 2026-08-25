import Foundation

/// JSON that remembers the order its keys were written in.
public indirect enum OrderedJSON: Equatable, Sendable {
    case object([(key: String, value: OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    /// The literal as written, never parsed into a `Double`.
    case number(String)
    case bool(Bool)
    case null

    public static func == (a: OrderedJSON, b: OrderedJSON) -> Bool {
        switch (a, b) {
        case let (.object(x), .object(y)):
            return x.count == y.count
                && zip(x, y).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case let (.array(x), .array(y)):   return x == y
        case let (.string(x), .string(y)): return x == y
        case let (.number(x), .number(y)): return x == y
        case let (.bool(x), .bool(y)):     return x == y
        case (.null, .null):               return true
        default:                           return false
        }
    }

    public var objectPairs: [(key: String, value: OrderedJSON)]? {
        if case let .object(pairs) = self { return pairs }
        return nil
    }

    public subscript(key: String) -> OrderedJSON? {
        objectPairs?.first { $0.key == key }?.value
    }

    /// Sets or replaces `key`, in place when it already exists.
    public func setting(_ key: String, to value: OrderedJSON?) -> OrderedJSON {
        var pairs = objectPairs ?? []
        let index = pairs.firstIndex { $0.key == key }
        switch (index, value) {
        case let (i?, v?): pairs[i] = (key, v)
        case let (i?, nil): pairs.remove(at: i)
        case let (nil, v?): pairs.append((key, v))
        case (nil, nil): break
        }
        return .object(pairs)
    }
}
