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

    /// Set while `reload()` re-reads the store, so no `didSet` writes back the
    /// keys a reset has just removed.
    @ObservationIgnored private var isReloading = false

    public var onFinished: Bool = true { didSet { persist(onFinished, Keys.onFinished) } }
    public var onFailed: Bool = true { didSet { persist(onFailed, Keys.onFailed) } }
    public var onNeedsAttention: Bool = true {
        didSet { persist(onNeedsAttention, Keys.onNeedsAttention) }
    }

    /// Speak the alert. Off by default and instantiated lazily on the other
    /// side: `AVSpeechSynthesizer` allocates several megabytes of audio engine.
    public var voice: Bool = false { didSet { persist(voice, Keys.voice) } }
    public var haptics: Bool = false { didSet { persist(haptics, Keys.haptics) } }

    /// Stay silent when the terminal the alert is about is already in front.
    public var quietWhenFrontmost: Bool = true {
        didSet { persist(quietWhenFrontmost, Keys.quietWhenFrontmost) }
    }

    public init(store: PreferencesStore) {
        self.store = store
        reload()
    }

    /// Re-read the store in place; see `AppearancePrefs.reload()`.
    public func reload() {
        isReloading = true
        defer { isReloading = false }
        onFinished = store.bool(Keys.onFinished, default: true)
        onFailed = store.bool(Keys.onFailed, default: true)
        onNeedsAttention = store.bool(Keys.onNeedsAttention, default: true)
        voice = store.bool(Keys.voice, default: false)
        haptics = store.bool(Keys.haptics, default: false)
        quietWhenFrontmost = store.bool(Keys.quietWhenFrontmost, default: true)
    }

    private func persist(_ value: Any, _ key: String) {
        guard !isReloading else { return }
        store.set(value, forKey: key)
    }

    public func allows(_ kind: SessionAlert.Kind) -> Bool {
        switch kind {
        case .finished: return onFinished
        case .failed: return onFailed
        case .needsAttention: return onNeedsAttention
        }
    }
}
