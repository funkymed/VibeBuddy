import AppKit
import AVFoundation
import VibeBuddyKit

/// Do not build the synthesiser eagerly: `AVSpeechSynthesizer` allocates a
/// multi-megabyte audio engine on first use, and the preference is off by default.
@MainActor
final class VoiceAnnouncer {

    /// Two identical alerts inside this window are one announcement.
    static let debounce: TimeInterval = 4

    private var synthesiser: AVSpeechSynthesizer?
    private var lastSpokenAt: Date?
    private var lastText: String?

    func announce(_ text: String, locale: Locale, now: Date = Date()) {
        if let lastSpokenAt, let lastText, lastText == text,
           now.timeIntervalSince(lastSpokenAt) < Self.debounce { return }
        lastSpokenAt = now
        lastText = text

        let engine = synthesiser ?? AVSpeechSynthesizer()
        synthesiser = engine
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: locale.identifier)
        engine.speak(utterance)
    }
}

/// A tap on the trackpad. No hardware check needed: `NSHapticFeedbackManager`
/// resolves to a no-op performer without a Force Touch trackpad.
enum Haptics {
    @MainActor
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
