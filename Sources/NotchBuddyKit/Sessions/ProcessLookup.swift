import Foundation
import Darwin

/// Thin wrappers over `libproc`.
///
/// macOS has no `/proc`, so these are the only way to enumerate processes and
/// read their name, path and working directory. Adapted from Notch-Pilot
/// (MIT) — the most directly reusable piece of that project.
public enum ProcessLookup {

    /// Every process visible to the current user.
    ///
    /// Sized generously and retried once: the count can grow between asking how
    /// much room is needed and filling the buffer, and a short read would
    /// silently drop the processes that did not fit.
    public static func allPIDs() -> [pid_t] {
        var capacity = 4096
        for _ in 0..<2 {
            var buffer = [pid_t](repeating: 0, count: capacity)
            let bytes = buffer.withUnsafeMutableBufferPointer { buf in
                proc_listpids(UInt32(PROC_ALL_PIDS), 0, buf.baseAddress,
                              Int32(capacity * MemoryLayout<pid_t>.size))
            }
            guard bytes > 0 else { return [] }
            let count = Int(bytes) / MemoryLayout<pid_t>.size
            if count < capacity { return Array(buffer.prefix(count)).filter { $0 > 0 } }
            capacity *= 2
        }
        return []
    }

    /// `p_comm`, the 16-character accounting name.
    ///
    /// Falls back to `sysctl` for the same reason `parent(of:)` uses it:
    /// `proc_name` is privilege-gated and returns nothing for setuid processes
    /// such as `login`, which sits in the chain of every login-shell terminal.
    public static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let r = buffer.withUnsafeMutableBufferPointer {
            proc_name(pid, $0.baseAddress, UInt32(MAXPATHLEN))
        }
        if r > 0 {
            let name = String(cString: buffer)
            if !name.isEmpty { return name }
        }
        return sysctlName(of: pid)
    }

    /// Accounting name from the kernel's process table, readable for any pid.
    static func sysctlName(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0
        else { return nil }
        return withUnsafePointer(to: &info.kp_proc.p_comm) { tuple in
            tuple.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) {
                let name = String(cString: $0)
                return name.isEmpty ? nil : name
            }
        }
    }

    /// Full path of the backing executable.
    public static func path(of pid: pid_t) -> String? {
        let capacity = Int(MAXPATHLEN) * 4
        var buffer = [CChar](repeating: 0, count: capacity)
        let r = buffer.withUnsafeMutableBufferPointer {
            proc_pidpath(pid, $0.baseAddress, UInt32(capacity))
        }
        guard r > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Parent pid, via `sysctl` rather than `proc_pidinfo`.
    ///
    /// `proc_pidinfo(PROC_PIDTBSDINFO)` is the obvious call and it is the wrong
    /// one: it fails on processes we lack privileges for. That is not an edge
    /// case here — every iTerm2 session started through a login shell has a
    /// setuid-root `login` in its chain, so the walk from an agent up to its
    /// terminal stops two hops short, every time.
    ///
    /// Measured on this machine: the chain is
    /// `claude → zsh → login → iTerm2 Application → iTerm2`, and `proc_pidinfo`
    /// returns nothing for `login`. `sysctl(KERN_PROC_PID)` reads the same field
    /// from the kernel's process table and is not privilege-gated — it is what
    /// `ps` itself uses.
    ///
    /// The reference implementation walks the chain with `proc_pidinfo`, so it
    /// carries this blind spot.
    public static func parent(of pid: pid_t) -> pid_t? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }

    /// Working directory, via `PROC_PIDVNODEPATHINFO`.
    ///
    /// This is the load-bearing call. A transcript with a fresh timestamp proves
    /// nothing about liveness — a session that exited cleanly leaves one behind
    /// for as long as anyone cares to look. The working directory of a running
    /// process is the only thing that cannot lie.
    public static func cwd(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, $0, size)
        }
        guard r > 0 else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { tuple in
            tuple.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                let s = String(cString: $0)
                return s.isEmpty ? nil : s
            }
        }
    }

    /// Strip `/private` and trailing slashes.
    ///
    /// Without this the cwd reported by `libproc` and the one written in a
    /// transcript compare unequal for the same directory — `/private/tmp/x`
    /// against `/tmp/x` — and every session in a temp directory looks dead.
    public static func normalise(_ path: String) -> String {
        var s = path
        if s.hasPrefix("/private/") { s = String(s.dropFirst(8)) }
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Live agent processes, grouped by normalised working directory.
    ///
    /// Matching is by executable name *or* path: Claude Code installs versioned
    /// binaries under `…/claude/versions/…`, so the accounting name alone misses
    /// them. Matching `node` — as the reference's terminal jumper does — is
    /// deliberately avoided: it catches every unrelated Node process in the same
    /// directory.
    public static func agentPIDs(provider: AgentProvider = .claudeCode) -> [String: [pid_t]] {
        var result: [String: [pid_t]] = [:]
        for pid in allPIDs() {
            guard matches(pid: pid, provider: provider) else { continue }
            guard let cwd = cwd(of: pid), !cwd.isEmpty else { continue }
            result[normalise(cwd), default: []].append(pid)
        }
        return result
    }

    static func matches(pid: pid_t, provider: AgentProvider) -> Bool {
        switch provider {
        case .claudeCode:
            if name(of: pid)?.lowercased() == "claude" { return true }
            guard let path = path(of: pid)?.lowercased() else { return false }
            return path.contains("/claude/versions/")
                || path.hasSuffix("/claude")
                || path.hasSuffix("/bin/claude")
        }
    }
}
