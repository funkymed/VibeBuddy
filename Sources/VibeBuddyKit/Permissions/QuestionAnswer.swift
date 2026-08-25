import Foundation
import VibeHookProtocol

/// How a chosen answer to `AskUserQuestion` gets back to the model.
public enum QuestionAnswer {
    /// The message a chosen option is sent back as.
    public static func denyMessage(for option: String) -> String {
        "The user chose: \"\(option)\". "
            + "This is the answer to your question, not a refusal — continue with it."
    }

    /// The decision to hand the queue for a chosen option.
    public static func decision(for option: String) -> HookDecision {
        .deny(message: denyMessage(for: option))
    }
}
