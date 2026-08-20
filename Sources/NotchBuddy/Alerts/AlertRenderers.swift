import AppKit
import AVFoundation
import NotchBuddyKit

/// Speaks an alert, and only builds a speech engine if it ever has to.
///
/// The reference implementation holds a `static let shared` created at launch
/// (`VoiceAnnouncer.swift:10`). `AVSpeechSynthesizer` allocates an audio engine
/// of several megabytes on first use, and the preference is off by default — so
/// that instance is pure cost for almost everyone. Here the synthesiser is built
/// on the first announcement and never before.
@MainActor
final class VoiceAnnouncer {

    /// Two identical alerts inside this window are one announcement. Speech is
    /// the slowest possible way to say the same thing twice.
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

/// A tap on the trackpad when something happens.
///
/// Does nothing on hardware without a Force Touch trackpad, which is correct and
/// needs no check: `NSHapticFeedbackManager` already resolves to a no-op
/// performer there.
enum Haptics {
    @MainActor
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
