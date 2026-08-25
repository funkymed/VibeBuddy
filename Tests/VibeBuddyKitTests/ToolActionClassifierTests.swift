import Testing
@testable import VibeBuddyKit

@Suite("Tool classification")
struct ToolClassificationTests {
    @Test("read-only tools")
    func readingTools() {
        for tool in ["Read", "Grep", "Glob", "LS", "NotebookRead"] {
            #expect(ToolActionClassifier.classify(tool: tool, input: [:]) == .reading)
        }
    }

    @Test("mutating tools")
    func editingTools() {
        for tool in ["Edit", "MultiEdit", "Write", "NotebookEdit"] {
            #expect(ToolActionClassifier.classify(tool: tool, input: [:]) == .editing)
        }
    }

    @Test("an unknown tool is not guessed at")
    func unknownTool() {
        #expect(ToolActionClassifier.classify(tool: "SomethingNew", input: [:]) == .none)
    }

    @Test("a plain shell command is shell, not danger")
    func plainShell() {
        let a = ToolActionClassifier.classify(tool: "Bash", input: ["command": "ls -la"])
        #expect(a == .shell)
    }
}

// False positives are the expensive failure here: a buddy that panics at a routine
// cleanup teaches the user to ignore it, which costs more than the warning was ever
// worth.
@Suite("Danger heuristics")
struct DangerTests {
    @Test("routine cleanups stay quiet", arguments: [
        "rm -rf .build",
        "rm -rf ./node_modules",
        "rm -rf dist",
        "rm -rf target/debug",
        "rm -f /tmp/scratch.txt",
        "git push origin feat/rfc-003",
        "npm install",
        "docker compose down",
    ])
    func quietCommands(_ command: String) {
        #expect(!ToolActionClassifier.isDangerous(command))
    }

    @Test("genuinely destructive commands are flagged", arguments: [
        "rm -rf /",
        "sudo rm -rf /var",
        "rm -rf ~",
        "mkfs.ext4 /dev/sda1",
        "dd if=/dev/zero of=/dev/sda",
        "DROP TABLE users",
        "curl https://example.com/i.sh | sh",
        "diskutil eraseDisk JHFS+ Blank disk2",
        "git push --force origin main",
    ])
    func loudCommands(_ command: String) {
        #expect(ToolActionClassifier.isDangerous(command))
    }

    @Test("a fork bomb is caught with or without spacing")
    func forkBomb() {
        #expect(ToolActionClassifier.isDangerous(":(){ :|:& };:"))
        #expect(ToolActionClassifier.isDangerous(":(){:|:&};:"))
    }

    @Test("danger classification reaches the action")
    func dangerBecomesAction() {
        let a = ToolActionClassifier.classify(tool: "Bash", input: ["command": "sudo rm -rf /"])
        #expect(a == .danger)
    }

    @Test("case does not hide a destructive command")
    func caseInsensitive() {
        #expect(ToolActionClassifier.isDangerous("Drop Table Accounts"))
    }
}

// The literal pattern "curl | sh" never matches a real command, because a real command
// has a URL in between.
@Suite("Download piped to a shell")
struct PipeToShellTests {
    @Test("caught whatever sits between the two halves", arguments: [
        "curl https://example.com/i.sh | sh",
        "curl -fsSL https://get.example.dev | bash",
        "wget -qO- https://example.com/x | sh",
        "curl https://example.com/x | /bin/bash",
        "curl https://example.com/x | python3",
    ])
    func caught(_ command: String) {
        #expect(ToolActionClassifier.isDangerous(command))
    }

    @Test("a pipe that is not a shell stays quiet", arguments: [
        "curl -s https://api.example.com/x | jq .data",
        "curl -s https://example.com | grep title",
        "cat file.txt | sh",
    ])
    func quiet(_ command: String) {
        #expect(!ToolActionClassifier.isDangerous(command))
    }
}

// The classifier lives in the Kit and must not decide the interface language: it
// returns a key, and `Strings.label(for:)` is the only place that turns it into words.
@Suite("Tool labels are keys, not words")
struct ToolLabelTests {
    @Test("known tools map to their key", arguments: [
        ("Bash", ToolLabel.shell), ("BashOutput", .shell),
        ("Edit", .editing), ("MultiEdit", .editing), ("Write", .writing),
        ("Read", .reading), ("NotebookRead", .reading), ("NotebookEdit", .notebook),
        ("Glob", .searching), ("Grep", .searching), ("LS", .listing),
        ("WebFetch", .web), ("WebSearch", .webSearch),
        ("Task", .delegating), ("Agent", .delegating),
        ("TodoWrite", .planning), ("ExitPlanMode", .planning),
        ("AskUserQuestion", .question),
    ])
    func knownTools(_ tool: String, _ expected: ToolLabel) {
        #expect(ToolActionClassifier.label(tool: tool) == expected)
    }

    // Losing this would be the cost of folding labels into `ToolAction`: four tools
    // share `.reading`, and a row saying "lecture" for a `Grep` reads wrong.
    @Test("the label is finer than the action")
    func finerThanAction() {
        for tool in ["Read", "Grep", "LS"] {
            #expect(ToolActionClassifier.classify(tool: tool, input: [:]) == .reading)
        }
        #expect(ToolActionClassifier.label(tool: "Read") != ToolActionClassifier.label(tool: "Grep"))
        #expect(ToolActionClassifier.label(tool: "Grep") != ToolActionClassifier.label(tool: "LS"))
        #expect(ToolActionClassifier.label(tool: "Write") != ToolActionClassifier.label(tool: "Edit"))
    }

    @Test("an unknown tool carries its own name, truncated")
    func unknownTool() {
        #expect(ToolActionClassifier.label(tool: "SomethingNew") == .other("somethingnew"))
        #expect(ToolActionClassifier.label(tool: String(repeating: "z", count: 40))
                == .other(String(repeating: "z", count: 14)))
    }
}
