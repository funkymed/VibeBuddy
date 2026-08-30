import Foundation
import Darwin

/// Thin wrappers over `libproc`: macOS has no `/proc`, so these are the only way to
/// enumerate processes and read their name, path and cwd.
public enum ProcessLookup {
    /// Retried once: the count can grow between sizing and filling, and a short read
    /// drops.
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
    public static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let r = buffer.withUnsafeMutableBufferPointer {
            proc_name(pid, $0.baseAddress, UInt32(MAXPATHLEN))
        }
        if r > 0 {
            let name = Self.string(from: buffer)
            if !name.isEmpty { return name }
        }
        return sysctlName(of: pid)
    }

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

    public static func path(of pid: pid_t) -> String? {
        let capacity = Int(MAXPATHLEN) * 4
        var buffer = [CChar](repeating: 0, count: capacity)
        let r = buffer.withUnsafeMutableBufferPointer {
            proc_pidpath(pid, $0.baseAddress, UInt32(capacity))
        }
        guard r > 0 else { return nil }
        return Self.string(from: buffer)
    }

    /// `String(cString:)` is deprecated: it walks past the end without a terminator.
    static func string(from buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Do not use `proc_pidinfo(PROC_PIDTBSDINFO)`: it fails without privileges.
    public static func parent(of pid: pid_t) -> pid_t? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }

    /// Controlling terminal, as `/dev/ttys004` — the only identity an emulator and the
    /// kernel agree on: titles lie, two tabs share a cwd, but one tab owns a given pty.
    public static func tty(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0
        else { return nil }
        let device = info.kp_eproc.e_tdev
        // `NODEV` is -1, and a process without a terminal reports it.
        guard device != -1, let name = devname(device, S_IFCHR) else { return nil }
        let short = String(cString: name)
        return short.isEmpty ? nil : "/dev/" + short
    }

    /// Working directory, via `PROC_PIDVNODEPATHINFO`.
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

    /// Strip `/private` and trailing slashes: otherwise `libproc`'s cwd and the
    /// transcript's compare unequal (`/private/tmp/x` vs `/tmp/x`) and look dead.
    public static func normalise(_ path: String) -> String {
        var s = path
        if s.hasPrefix("/private/") { s = String(s.dropFirst(8)) }
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Live agent processes, grouped by normalised cwd.
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
            let path = path(of: pid)?.lowercased()
            // The desktop app is called Claude too. Measured 2026-08-30:
            // `/Applications/Claude.app/Contents/MacOS/Claude` matched on its name and
            // was counted as an agent running in `/`, which is its cwd. It is a chat
            // window, not a coding agent, and it owns no transcript.
            if let path, path.contains("/claude.app/") { return false }
            if name(of: pid)?.lowercased() == "claude" { return true }
            guard let path else { return false }
            return path.contains("/claude/versions/")
                || path.hasSuffix("/claude")
                || path.hasSuffix("/bin/claude")
        }
    }
}
