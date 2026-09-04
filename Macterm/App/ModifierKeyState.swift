import AppKit
import Observation

/// Publishes live modifier-key state to chrome that explains keyboard shortcuts.
@MainActor @Observable
final class ModifierKeyState {
    static let shared = ModifierKeyState()

    private(set) var isCommandPressed = false

    private init() {}

    /// Updates the Command-key state from one AppKit modifier-flags event.
    func updateModifierFlags(_ flags: NSEvent.ModifierFlags) {
        isCommandPressed = flags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.command)
    }

    /// Clears modifiers when the app resigns active and may miss key-up events.
    func resetModifierFlags() {
        isCommandPressed = false
    }
}
