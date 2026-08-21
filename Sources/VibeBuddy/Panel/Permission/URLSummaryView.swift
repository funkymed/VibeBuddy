import SwiftUI
import VibeBuddyKit

/// One line of target text.
///
/// Three asks come down to the same thing to show: a URL to fetch, a search
/// query, and a path being read. They share a view rather than a name — hence
/// `target` rather than `url`.
///
/// **The host is the decision.** Allowing a fetch grants a domain, not a
/// string: the rest of the URL changes on the next call and the domain does
/// not. So the host is drawn large and the path behind it, rather than one flat
/// line where `evil.example.com` hides in the middle of a query.
// RFC-007 T5
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

    // MARK: - With a host

    private func addressed(_ host: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l10n.permissionDomain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PanelInk.tertiary)
                .tracking(0.8)

            Text(host)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(PanelInk.primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            if let rest = Self.rest(of: target, host: host) {
                Text(rest)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PanelInk.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Without one

    /// A file path or a search query: nothing to promote, so nothing is. Cut
    /// from the head, because the tail is what names a file.
    private var plain: some View {
        Text(target)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(PanelInk.primary)
            .textSelection(.enabled)
            .lineLimit(3)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Reading the target

    /// The host, when the target is an address at all.
    ///
    /// `URLComponents` finds nothing without a scheme, and a `WebFetch` argument
    /// arrives written by hand often enough (`example.com/doc`) that the
    /// scheme-less form is worth a second pass. A leading `/` rules it out: that
    /// is a path, and this app never fetches one.
    static func host(of target: String) -> String? {
        let text = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("/") else { return nil }

        if let host = URLComponents(string: text)?.host, !host.isEmpty { return host }

        let head = text.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard head.contains("."), !head.contains(" ") else { return nil }
        return String(head)
    }

    /// Everything the host does not cover, kept in the order it was written so
    /// the user reads the real URL and not a reconstruction of it.
    static func rest(of target: String, host: String) -> String? {
        let text = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = text.range(of: host) else { return nil }
        let tail = text[range.upperBound...]
        return tail.isEmpty || tail == "/" ? nil : String(tail)
    }
}
