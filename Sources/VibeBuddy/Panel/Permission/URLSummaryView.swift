import SwiftUI
import VibeBuddyKit

/// One line of target text.
struct URLSummaryView: View {
    let target: String
    let l10n: Strings

    var body: some View {
        if let host = Self.host(of: target) {
            addressed(host)
        } else {
            plain
        }
    }

    private func addressed(_ host: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l10n.permissionDomain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PanelInk.tertiary)
                .tracking(0.8)

            Text(host)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(PanelInk.primary)
                // Deliberately not `.textSelection(.enabled)`: it installs an
                // I-beam that wins over everything the panel puts on the pointer, so
                // the hand flickered on every button and row.
                .lineLimit(1)
                .truncationMode(.middle)

            if let rest = Self.rest(of: target, host: host) {
                Text(rest)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PanelInk.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A file path or a search query: nothing to promote, so nothing is.
    private var plain: some View {
        Text(target)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(PanelInk.primary)
            .lineLimit(3)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The host, when the target is an address at all.
    static func host(of target: String) -> String? {
        let text = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("/") else { return nil }

        if let host = URLComponents(string: text)?.host, !host.isEmpty { return host }

        let head = text.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard head.contains("."), !head.contains(" ") else { return nil }
        return String(head)
    }

    /// Everything the host does not cover, kept in the order it was written so the user
    /// reads the real URL and not a reconstruction of it.
    static func rest(of target: String, host: String) -> String? {
        let text = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = text.range(of: host) else { return nil }
        let tail = text[range.upperBound...]
        return tail.isEmpty || tail == "/" ? nil : String(tail)
    }
}
