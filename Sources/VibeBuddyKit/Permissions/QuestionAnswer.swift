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

    /// Several questions, or several picks: every question is named with its answer,
    /// so the model never has to guess which pick belongs where.
    public static func denyMessage(for picks: QuestionPicks) -> String {
        if picks.count == 1, let only = picks.first, only.options.count == 1 {
            return denyMessage(for: only.options[0])
        }
        let lines = picks.map { pick in
            "- \"\(pick.question)\" → "
                + pick.options.map { "\"\($0)\"" }.joined(separator: ", ")
        }
        return "The user answered:\n" + lines.joined(separator: "\n")
            + "\nThese are the answers to your questions, not a refusal — continue with them."
    }

    public static func decision(for picks: QuestionPicks) -> HookDecision {
        .deny(message: denyMessage(for: picks))
    }

    /// The real answer when the original input is known: that input with `answers`
    /// added, which `AskUserQuestion` returns as the user's own answer — no error in
    /// the terminal, no failed turn. `picks` is one entry per question, in order.
    /// Falls back to the deny when the input is missing or not an object.
    public static func decision(for picks: QuestionPicks, input: Data?) -> HookDecision {
        guard let input,
              var object = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
              let questions = object["questions"] as? [[String: Any]]
        else { return decision(for: picks.filter { !$0.options.isEmpty }) }

        var answers: [String: String] = [:]
        for (index, question) in questions.enumerated() where index < picks.count {
            let chosen = picks[index].options
            guard !chosen.isEmpty else { continue }
            // Keyed on the text Claude wrote, not on the panel's truncated copy.
            let text = question["question"] as? String ?? picks[index].question
            // Several picks are one string, joined as Claude Code joins them itself.
            answers[text] = chosen.joined(separator: ", ")
        }
        object["answers"] = answers
        guard let data = try? JSONSerialization.data(withJSONObject: object)
        else { return decision(for: picks.filter { !$0.options.isEmpty }) }
        return .allowUpdating(input: data)
    }
}
