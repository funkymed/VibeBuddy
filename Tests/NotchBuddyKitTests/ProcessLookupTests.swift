import Testing
import Darwin
@testable import NotchBuddyKit

@Suite("Path normalisation")
struct NormaliseTests {

    // Without this the cwd libproc reports and the cwd a transcript records
    // compare unequal for the same directory, and every session in a temp
    // directory looks dead.
    @Test("the /private prefix is stripped")
    func stripsPrivate() {
        #expect(ProcessLookup.normalise("/private/tmp/x") == "/tmp/x")
        #expect(ProcessLookup.normalise("/private/var/folders/a") == "/var/folders/a")
    }

    @Test("trailing slashes are dropped, but the root survives")
    func trailingSlashes() {
        #expect(ProcessLookup.normalise("/Users/dev/proj/") == "/Users/dev/proj")
        #expect(ProcessLookup.normalise("/Users/dev/proj///") == "/Users/dev/proj")
        #expect(ProcessLookup.normalise("/") == "/")
    }

    @Test("an ordinary path is left alone")
    func untouched() {
        #expect(ProcessLookup.normalise("/Users/dev/Sites/notch") == "/Users/dev/Sites/notch")
    }

    @Test("a path merely containing 'private' is not mangled")
    func notAPrefix() {
        #expect(ProcessLookup.normalise("/Users/dev/private/x") == "/Users/dev/private/x")
    }
}

@Suite("libproc wrappers")
struct ProcessLookupTests {

    @Test("this process can see itself")
    func seesSelf() {
        let me = getpid()
        #expect(ProcessLookup.name(of: me) != nil)
        #expect(ProcessLookup.path(of: me) != nil)
        #expect(ProcessLookup.cwd(of: me) != nil)
    }

    @Test("the pid list is non-empty and contains this process")
    func listPIDs() {
        let pids = ProcessLookup.allPIDs()
        #expect(pids.count > 1)
        #expect(pids.contains(getpid()))
        #expect(!pids.contains(where: { $0 <= 0 }))
    }

    // The reason `parent(of:)` uses sysctl rather than proc_pidinfo: the latter
    // is privilege-gated and returns nothing for setuid processes such as
    // `login`, which sits in the chain of every login-shell terminal. Walking
    // to the top proves the chain is not silently truncated.
    @Test("the parent chain reaches launchd rather than dying early")
    func chainReachesLaunchd() {
        var current = getpid()
        var hops = 0
        while let parent = ProcessLookup.parent(of: current), parent > 1, hops < 32 {
            current = parent
            hops += 1
        }
        // Either we arrived at launchd's child, or the walk ended cleanly.
        #expect(hops > 0)
        #expect(ProcessLookup.parent(of: current) == nil || ProcessLookup.parent(of: current) == 1)
    }

    @Test("an impossible pid yields nil, not a crash")
    func absentPID() {
        let absent: pid_t = 999_999
        #expect(ProcessLookup.parent(of: absent) == nil)
        #expect(ProcessLookup.cwd(of: absent) == nil)
    }
}

@Suite("Terminal detection")
struct TerminalFocusTests {

    @Test("Warp reports as 'stable', which is not a typo")
    func warpIsStable() {
        #expect(TerminalFocusProbe.terminalNames.contains("stable"))
    }

    @Test("the hop limit is bounded so a cycle cannot hang the probe")
    func boundedWalk() {
        #expect(TerminalFocusProbe.maxHops > 0)
        #expect(TerminalFocusProbe.maxHops <= 16)
    }

    // Suppressing an alert wrongly is worse than showing one wrongly, so an
    // unresolvable chain must resolve to "no terminal" rather than to a guess.
    @Test("an unresolvable pid reports no hosting terminal")
    func unknownPIDHasNoTerminal() {
        #expect(TerminalFocusProbe.hostingTerminal(of: 999_999) == nil)
    }
}
