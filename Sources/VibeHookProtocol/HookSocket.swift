import Darwin
import Foundation

/// The `AF_UNIX` plumbing both sides share.
public enum HookSocket {
    /// Longest a `sun_path` can be.
    public static let pathLimit = 103

    public enum Failure: Error, Equatable {
        case pathTooLong
        case cannotCreate(Int32)
        case cannotConnect(Int32)
        case cannotBind(Int32)
        case timedOut
        case closed
    }

    static func address(_ path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8)
        guard bytes.count <= pathLimit else { throw Failure.pathTooLong }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
        }
        return addr
    }

    /// Runs `body` with the address laid out the way `connect`/`bind` want it.
    static func withAddress<T>(
        _ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
    ) throws -> T {
        var addr = try address(path)
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        return try withUnsafePointer(to: &addr) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, size)
            }
        }
    }

    /// Writing to a socket whose peer has gone raises `SIGPIPE`, and the default
    /// disposition kills the process.
    public static func silencePipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    public static func connect(to path: String, timeout: TimeInterval) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.cannotCreate(errno) }
        silencePipe(fd)
        do {
            try withAddress(path) { pointer, size in
                guard Darwin.connect(fd, pointer, size) == 0 else {
                    throw Failure.cannotConnect(errno)
                }
            }
        } catch {
            close(fd)
            throw error
        }
        // Bounded on purpose: a wedged app must not hold Claude Code for ever.
        var window = timeval(
            tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1e6))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &window, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    /// Binds a fresh listening socket, private to this user.
    public static func listen(at path: String, backlog: Int32 = 16) throws -> Int32 {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.cannotCreate(errno) }
        silencePipe(fd)
        do {
            try withAddress(path) { pointer, size in
                guard Darwin.bind(fd, pointer, size) == 0 else {
                    throw Failure.cannotBind(errno)
                }
            }
            guard Darwin.listen(fd, backlog) == 0 else { throw Failure.cannotBind(errno) }
            chmod(path, 0o600)
        } catch {
            close(fd)
            throw error
        }
        return fd
    }

    /// The PID on the other end.
    public static func peerPID(_ fd: Int32) -> pid_t? {
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0
        else { return nil }
        return pid
    }

    /// Bounds how long a `recv` on this descriptor may block.
    public static func setReadTimeout(_ fd: Int32, seconds: TimeInterval) {
        var window = timeval(tv_sec: Int(seconds),
                             tv_usec: Int32((seconds - Double(Int(seconds))) * 1e6))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &window,
                   socklen_t(MemoryLayout<timeval>.size))
    }

    public static func write(_ data: Data, to fd: Int32) -> Bool {
        var sent = 0
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            while sent < data.count {
                let n = send(fd, base + sent, data.count - sent, 0)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    /// Reads until the first newline.
    public static func readLine(from fd: Int32, limit: Int = 1 << 20) -> Data? {
        var line = Data()
        var byte: UInt8 = 0
        while line.count < limit {
            let n = recv(fd, &byte, 1, 0)
            if n == 0 { return nil }            // peer hung up
            if n < 0 {
                if errno == EINTR { continue }
                return nil                      // timeout, or a real error
            }
            if byte == 0x0A { return line }
            line.append(byte)
        }
        return nil
    }

    /// Whether the peer has gone away, without consuming anything.
    public static func peerHungUp(_ fd: Int32) -> Bool {
        var byte: UInt8 = 0
        return recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT) == 0
    }
}
