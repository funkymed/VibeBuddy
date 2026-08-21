import Foundation

/// JSON that remembers the order its keys were written in.
///
/// `JSONSerialization` decodes an object into a `Dictionary`, which has no
/// order. Re-serialising it therefore shuffles the file — `.sortedKeys` makes
/// that shuffle *stable* rather than making it stop, which is why D6 forbids it
/// and why this type exists instead.
///
/// The user's `~/.claude/settings.json` is eleven kilobytes of hand-edited
/// settings with `$schema` deliberately first. Anything that reorders it on
/// every launch is a bug, however valid the JSON it produces.
///
/// Numbers keep their original text: re-encoding `1.0` as `1`, or losing a
/// digit of a large integer, is the same class of damage in a smaller place.
/// See RFC-006, risk R1 and decision D6.
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

    // MARK: - Reading an object

    public var objectPairs: [(key: String, value: OrderedJSON)]? {
        if case let .object(pairs) = self { return pairs }
        return nil
    }

    public subscript(key: String) -> OrderedJSON? {
        objectPairs?.first { $0.key == key }?.value
    }

    /// Sets or replaces `key`, **in place** when it already exists. A key that
    /// moves to the end of the file on every write is the reordering this type
    /// exists to prevent, one key at a time.
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
