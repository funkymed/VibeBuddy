import Foundation

/// One question of an `AskUserQuestion` call.
public struct AskedQuestion: Sendable, Equatable {
    public let prompt: String
    /// The short chip Claude Code shows above the question (« Périmètre »).
    public let header: String?
    /// The labels, which are also what goes back as the answer.
    public let options: [String]
    /// Aligned with `options`: the line under each label, and the monospace mock-up
    /// shown beside it in the terminal. Nil where Claude gave none.
    public let details: [String?]
    public let previews: [String?]
    /// Several options may be picked, and the answer carries all of them.
    public let multiSelect: Bool

    public init(prompt: String, header: String? = nil, options: [String],
                details: [String?] = [], previews: [String?] = [],
                multiSelect: Bool = false) {
        self.prompt = prompt
        self.header = header
        self.options = options
        // Padded to the options, so an index into one is an index into all three.
        self.details = (details + Array(repeating: nil, count: options.count)).prefix(options.count).map { $0 }
        self.previews = (previews + Array(repeating: nil, count: options.count)).prefix(options.count).map { $0 }
        self.multiSelect = multiSelect
    }

    public var hasPreviews: Bool { previews.contains { $0 != nil } }
}

/// Each question with what was picked for it, in the order they were asked.
public typealias QuestionPicks = [(question: String, options: [String])]

extension Array where Element == AskedQuestion {
    /// One click answers: a single question, one pick. Anything else needs a send
    /// button, or the first click would answer questions nobody has read.
    public var answersOnClick: Bool {
        count == 1 && !(first?.multiSelect ?? false)
    }
}

/// What is ticked, question by question. Held by the permission panel so the send
/// button can sit in the decision bar, beside the other two ways out.
public struct QuestionSelection: Equatable, Sendable {
    /// Question index → picked option indices.
    public private(set) var picked: [Int: Set<Int>] = [:]

    public init() {}

    public func isOn(_ choice: Int, at index: Int) -> Bool {
        picked[index, default: []].contains(choice)
    }

    /// A checkbox for several, a radio for one.
    public mutating func toggle(_ choice: Int, of question: AskedQuestion, at index: Int) {
        var set = picked[index, default: []]
        if question.multiSelect {
            if set.remove(choice) == nil { set.insert(choice) }
        } else {
            set = [choice]
        }
        picked[index] = set
    }

    /// Every question with options has a pick: a partial answer is one the model would
    /// have to guess the rest of.
    public func isComplete(_ questions: [AskedQuestion]) -> Bool {
        questions.indices.allSatisfy { index in
            questions[index].options.isEmpty || !picked[index, default: []].isEmpty
        }
    }

    /// One entry per question, aligned by index with the input Claude sent.
    public func picks(_ questions: [AskedQuestion]) -> QuestionPicks {
        questions.indices.map { index in
            let question = questions[index]
            let options = picked[index, default: []].sorted()
                .filter { $0 < question.options.count }
                .map { question.options[$0] }
            return (question.prompt, options)
        }
    }
}
