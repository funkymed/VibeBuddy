import Foundation

/// Whether the permission panel shows, hides, or does not know yet.
///
/// **Three states, because two booleans could not say "not yet".** The reference
/// carried `permissionSuppressed` and `permissionChecked` side by side
/// (`NotchContentView.swift:154-162`). The pair existed for one reason: a request
/// arrives, the panel draws, and a frame later the frontmost-terminal check comes
/// back and hides it again — a flash the user reads as a glitch. The second flag
/// held the panel back until the first had an answer.
///
/// Two flags also spell a fourth combination nobody meant — suppressed but not
/// yet checked — and every reader has to decide what that means. One enum spells
/// the three real states and cannot spell the fourth. RFC-007, T4.
public enum PermissionPresentation: Sendable, Equatable {

    /// Nothing to ask, or the suppression checks decided not to ask here — the
    /// user's terminal is already in front, or the rule was granted long ago.
    case hidden

    /// A request is in hand and its suppression checks have not answered yet.
    /// Draw nothing. This state lasts a frame or two; it exists so the panel
    /// never appears only to withdraw.
    case checking

    /// Ask.
    case shown

    public var isVisible: Bool { self == .shown }
}
