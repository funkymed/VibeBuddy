import Foundation
import Darwin
import os

/// Self-measurement of the numbers RFC-001 puts a budget on.
///
/// Read from inside the process via `task_info`: no `sudo`, no subprocess — a
/// probe that spawned `ps` would be measuring what it added. The governing
/// metric is idle wakeups, not CPU: 0.4 % CPU at 70 wakeups/s drains a battery
/// and trips no percentage-based threshold.
public struct PerfSample: Sendable, Equatable {
    public let residentBytes: UInt64
    /// Physical footprint, bytes — what macOS charges the process and shows as
    /// "Memory". On Apple Silicon it diverges from RSS enough to matter.
    public let footprintBytes: UInt64
    public let cpuSeconds: Double
    public let interruptWakeups: UInt64
    /// Cumulative wakeups that happened while the system was otherwise idle.
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
