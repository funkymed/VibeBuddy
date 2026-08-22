import Foundation
import VibeHookProtocol

/// How a chosen answer to `AskUserQuestion` gets back to the model.
///
/// **The hook has no channel for an answer.** It may allow a tool or deny it,
/// and nothing else (RFC-007 §1, and §4 records that allowing plus an
/// out-of-band reply was looked for and does not exist). So the answer travels
/// as a **deny whose reason is phrased as the answer**: the model reads a deny
/// reason as the tool's result and carries on with it.
///
/// This lives in the Kit rather than beside the view that offers the options,
/// because the view is not what sends it — the panel's owner is, and the two
/// drifted apart exactly once already: `AskQuestionView` documented the hijack
/// while `NotchPanel` sent the bare option text, so the model received
/// « Deux curseurs séparés » as a *refusal reason* and had every reason to try
/// something else. One function, in the one place both sides can reach.
///
/// Anyone who "fixes" this into an `allow` breaks every question the user
/// answers from the notch.
public enum QuestionAnswer {

    /// The message a chosen option is sent back as.
    ///
    /// English on purpose: the model reads this string, the user never sees it,
    /// so it stays out of `Strings` and does not follow the UI language.
    public static func denyMessage(for option: String) -> String {
        "The user chose: \"\(option)\". "
            + "This is the answer to your question, not a refusal — continue with it."
    }

    /// The decision to hand the queue for a chosen option.
    public static func decision(for option: String) -> HookDecision {
        .deny(message: denyMessage(for: option))
    }
}
