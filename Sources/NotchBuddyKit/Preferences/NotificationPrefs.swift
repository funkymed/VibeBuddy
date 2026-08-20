import Foundation
import Observation

/// Which alerts are allowed to interrupt, and how they are rendered.
///
/// RFC-012 owns *what happened*; this owns *whether to say it*. The split is why
/// a preference change can never alter the state machine's reading of a
/// transcript — it can only silence what that reading produced.
@MainActor
@Observable
public final class NotificationPrefs {

    public enum Keys {
        public static let onFinished = "notchbuddy.alerts.finished"
        public static let onFailed = "notchbuddy.alerts.failed"
        public static let onNeedsAttention = "notchbuddy.alerts.needsAttention"
        public static let voice = "notchbuddy.alerts.voice"
        public static let haptics = "notchbuddy.alerts.haptics"
        public static let quietWhenFrontmost = "notchbuddy.alerts.quietWhenFrontmost"
    }

    @ObservationIgnored private let store: PreferencesStore

    public var onFinished: Bool { didSet { store.set(onFinished, forKey: Keys.onFinished) } }
    public var onFailed: Bool { didSet { store.set(onFailed, forKey: Keys.onFailed) } }
    /// The agent asked a question and is stopped until it is answered.
    public var onNeedsAttention: Bool {
        didSet { store.set(onNeedsAttention, forKey: Keys.onNeedsAttention) }
    }

    /// Speak the alert. Off by default, and lazily instantiated on the other
    /// side: `AVSpeechSynthesizer` allocates an audio engine of several
    /// megabytes the first time it is used.
    public var voice: Bool { didSet { store.set(voice, forKey: Keys.voice) } }
    public var haptics: Bool { didSet { store.set(haptics, forKey: Keys.haptics) } }

    /// Stay silent when the terminal the alert is about is already in front.
    ///
    /// Was hard-coded. It is the suppression that matters most, and also the one
    /// someone might reasonably disagree with — on a second display the
    /// "frontmost" terminal can be a screen away.
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

    /// Whether this kind of alert may be shown at all.
    public func allows(_ kind: SessionAlert.Kind) -> Bool {
        switch kind {
        case .finished: return onFinished
        case .failed: return onFailed
        case .needsAttention: return onNeedsAttention
        }
    }
}
