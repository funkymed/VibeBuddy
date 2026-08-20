import Foundation
import Darwin
import os

/// Self-measurement of the numbers RFC-001 puts a budget on.
///
/// Everything here is read from inside the process via `task_info`, which means
/// no `sudo`, no `powermetrics`, and — importantly — no subprocess. A probe that
/// spawned `ps` to measure itself would be measuring the thing it added.
///
/// The governing metric is **idle wakeups**, not CPU percentage. A process
/// sitting at 0.4 % CPU while waking 70 times a second drains a battery and
/// trips no percentage-based threshold anywhere.
public struct PerfSample: Sendable, Equatable {
    /// Resident set size, bytes.
    public let residentBytes: UInt64
    /// Physical footprint, bytes. This is what macOS actually charges the
    /// process, and what Activity Monitor shows as "Memory". On Apple Silicon it
    /// diverges from RSS enough to matter.
    public let footprintBytes: UInt64
    /// Cumulative CPU time, seconds (user + system).
    public let cpuSeconds: Double
    /// Cumulative wakeups charged to this task since launch.
    public let interruptWakeups: UInt64
    /// Cumulative wakeups that happened while the system was otherwise idle —
    /// the expensive kind, and the one the budget is written against.
    public let idleWakeups: UInt64
    public let uptime: TimeInterval

    public var residentMB: Double { Double(residentBytes) / 1_048_576 }
    public var footprintMB: Double { Double(footprintBytes) / 1_048_576 }
}

public enum PerfProbe {

    public static let log = Logger(subsystem: "fr.funkylab.vibebuddy", category: "perf")

    private static let launchedAt = Date()

    public static func sample() -> PerfSample {
        let basic = machBasicInfo()
        let power = machPowerInfo()
        return PerfSample(
            residentBytes: basic?.resident_size ?? 0,
            footprintBytes: physFootprint(),
            cpuSeconds: power.map {
                Double($0.total_user + $0.total_system) / 1_000_000_000
            } ?? 0,
            interruptWakeups: UInt64(power?.task_interrupt_wakeups ?? 0),
            idleWakeups: UInt64(power?.task_platform_idle_wakeups ?? 0),
            uptime: Date().timeIntervalSince(launchedAt)
        )
    }

    /// One CSV row. Header is emitted by `csvHeader`.
    public static func csvRow(_ s: PerfSample, label: String) -> String {
        String(
            format: "%@,%.1f,%.2f,%.2f,%.3f,%llu,%llu",
            label, s.uptime, s.residentMB, s.footprintMB,
            s.cpuSeconds, s.interruptWakeups, s.idleWakeups
        )
    }

    public static let csvHeader = "label,uptime_s,rss_mb,footprint_mb,cpu_s,wakeups,idle_wakeups"

    // MARK: - mach plumbing

    private static func machBasicInfo() -> mach_task_basic_info? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), raw, &count)
            }
        }
        return kr == KERN_SUCCESS ? info : nil
    }

    private static func machPowerInfo() -> task_power_info? {
        var info = task_power_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_power_info>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO), raw, &count)
            }
        }
        return kr == KERN_SUCCESS ? info : nil
    }

    /// `phys_footprint` lives in `task_vm_info`, not in the basic info struct.
    private static func physFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), raw, &count)
            }
        }
        return kr == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }
}
