import Foundation
import Observation

/// Which alerts are allowed to interrupt, and how they are rendered. A change
/// here can only silence what RFC-012's state machine produced, never alter it.
@MainActor
@Observable
public final class NotificationPrefs {

    public enum Keys {
        public static let onFinished = "vibebuddy.alerts.finished"
        public static let onFailed = "vibebuddy.alerts.failed"
        public static let onNeedsAttention = "vibebuddy.alerts.needsAttention"
        public static let voice = "vibebuddy.alerts.voice"
        public static let haptics = "vibebuddy.alerts.haptics"
        public static let quietWhenFrontmost = "vibebuddy.alerts.quietWhenFrontmost"
    }

    @ObservationIgnored private let store: PreferencesStore

    public var onFinished: Bool { didSet { store.set(onFinished, forKey: Keys.onFinished) } }
    public var onFailed: Bool { didSet { store.set(onFailed, forKey: Keys.onFailed) } }
    public var onNeedsAttention: Bool {
        didSet { store.set(onNeedsAttention, forKey: Keys.onNeedsAttention) }
    }

    /// Speak the alert. Off by default and instantiated lazily on the other
    /// side: `AVSpeechSynthesizer` allocates several megabytes of audio engine.
    public var voice: Bool { didSet { store.set(voice, forKey: Keys.voice) } }
    public var haptics: Bool { didSet { store.set(haptics, forKey: Keys.haptics) } }

    /// Stay silent when the terminal the alert is about is already in front.
    public var quietWhenFrontmost: Bool {
        didSet { store.set(quietWhenFrontmost, forKey: Keys.quietWhenFrontmost) }
    }

    public init(store: PreferencesStore) {
        self.store = store
        onFinished = store.bool(Keys.onFinished, default: true)
        onFailed = store.bool(Keys.onFailed, default: true)
        onNeedsAttention = store.bool(Keys.onNeedsAttention, default: true)
        voice = store.bool(Keys.voice, default: false)
        haptics = store.bool(Keys.haptics, default: false)
        quietWhenFrontmost = store.bool(Keys.quietWhenFrontmost, default: true)
    }

    public func allows(_ kind: SessionAlert.Kind) -> Bool {
        switch kind {
        case .finished: return onFinished
        case .failed: return onFailed
        case .needsAttention: return onNeedsAttention
        }
    }
}
