import Foundation

/// A version as this app compares them: numbers, most significant first.
///
/// String comparison is the trap here — `"1.0.10" < "1.0.9"` is true letter by letter,
/// which would hide every tenth release. The same mistake the perfcheck verdict made
/// with its budgets before 2026-08-20.
public struct ReleaseVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    /// As many components as the tag carried, so `1.1` and `1.1.0` still compare equal.
    public let components: [Int]

    public init(components: [Int]) {
        self.components = components
    }

    /// Accepts what GitHub tags actually look like: `v1.0.2`, `1.0.2`, `1.0.2-beta.1`.
    /// The pre-release suffix is dropped rather than ordered — this app has never
    /// shipped one, and inventing an ordering for something that does not exist is how
    /// a comparison quietly gets it wrong later.
    public init?(_ text: String) {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("v") || body.hasPrefix("V") { body.removeFirst() }
        if let dash = body.firstIndex(of: "-") { body = String(body[body.startIndex..<dash]) }
        if let plus = body.firstIndex(of: "+") { body = String(body[body.startIndex..<plus]) }

        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            numbers.append(value)
        }
        components = numbers
    }

    public static func < (a: ReleaseVersion, b: ReleaseVersion) -> Bool {
        // Missing components read as zero, so `1.1` and `1.1.0` are the same version.
        let count = max(a.components.count, b.components.count)
        for index in 0..<count {
            let left = index < a.components.count ? a.components[index] : 0
            let right = index < b.components.count ? b.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (a: ReleaseVersion, b: ReleaseVersion) -> Bool {
        !(a < b) && !(b < a)
    }

    public var description: String { components.map(String.init).joined(separator: ".") }
}
