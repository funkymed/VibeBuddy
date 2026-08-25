import SwiftUI

/// How full something is, as a colour: green, yellow, orange, red. One table for every
/// gauge in the app. There were two — the footer's consumption meter warmed at
/// 25/50/75 %, the per-session context ring stayed grey until 70 % — so a session at 60
/// % looked idle next to a week at 25 % that was already yellow.
enum QuotaScale {
    /// - Parameter fraction: 0…1.
    static func colour(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.25: return .green
        case ..<0.50: return .yellow
        case ..<0.75: return .orange
        default:      return .red
        }
    }

    /// The shade for a gauge with nothing to show yet.
    static let unknown = PanelInk.disabled
}
