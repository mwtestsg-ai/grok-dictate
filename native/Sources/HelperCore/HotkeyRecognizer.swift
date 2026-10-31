/// Turns raw keyboard events into protocol `hotkey` actions.
///
/// Pure and CoreGraphics-free so the whole matrix is unit-testable without a
/// windowserver, an event tap or an Accessibility grant. This file is where
/// "hold Right Command" actually lives.
///
/// Right Command is not the same key as Left Command.
///
///   * Keycode on `.flagsChanged` says which physical key moved.
///     `kVK_RightCommand` is 54 (0x36) — the unlisted slot between Escape
///     (0x35) and `kVK_Command` (0x37, Left Command, 55). Chromium, Karabiner
///     and a measured event (`golang/go#32131`, flags `1<<20 | 0x110`) all
///     agree.
///   * Device-dependent bits in `CGEvent.flags` say which side is down even
///     when the other side is also held. `NX_DEVICERCMDKEYMASK` is 0x10,
///     `NX_DEVICELCMDKEYMASK` is 0x08 (IOKit `IOLLEvent.h`). The generic
///     `kCGEventFlagMaskCommand` bit is set for either side and is not enough.
///
/// Fn / Globe is keycode 63 (`kVK_Function`) plus `kCGEventFlagMaskSecondaryFn`.
/// It is never a hotkey. The recogniser returns `.pass` for it with no flag
/// rewrite, and the event tap returns that original event before any other
/// decision, so macOS input-source switching still sees the Globe key.
///
/// Right Command's own `.flagsChanged` is consumed. Leaving it in the stream
/// would start dictation and also fire ⌘-shortcuts. Left Command is a
/// different keycode and is never consumed. Fn is never consumed either:
/// swallowing `.flagsChanged` for keycode 63 is what breaks "Press 🌐 key to
/// change input source".

import Foundation

/// Mirrors the `CGEventFlags` bits this helper cares about. Redeclared rather
/// than imported so `HelperCore` stays free of CoreGraphics; the executable
/// target maps one to the other, and a test asserts the raw values match.
public struct ModifierFlags: OptionSet, Sendable, Equatable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let capsLock = ModifierFlags(rawValue: 0x0001_0000)
    public static let shift = ModifierFlags(rawValue: 0x0002_0000)
    public static let control = ModifierFlags(rawValue: 0x0004_0000)
    public static let option = ModifierFlags(rawValue: 0x0008_0000)
    public static let command = ModifierFlags(rawValue: 0x0010_0000)
    public static let numericPad = ModifierFlags(rawValue: 0x0020_0000)
    public static let help = ModifierFlags(rawValue: 0x0040_0000)
    public static let secondaryFn = ModifierFlags(rawValue: 0x0080_0000)

    /// `NX_DEVICELCMDKEYMASK`. Set only while the left Command key is down.
    public static let deviceLeftCommand = ModifierFlags(rawValue: 0x0000_0008)
    /// `NX_DEVICERCMDKEYMASK`. Set only while the right Command key is down.
    public static let deviceRightCommand = ModifierFlags(rawValue: 0x0000_0010)
    /// `kCGEventFlagMaskNonCoalesced`. Rides along on real events; not a key.
    public static let nonCoalesced = ModifierFlags(rawValue: 0x0000_0100)

    /// The four modifiers a chord may specify. Caps Lock, the numeric-pad bit,
    /// Fn and the device-dependent side bits are excluded on purpose: they ride
    /// along on ordinary keystrokes and would make an exact-match chord test
    /// fail at random.
    public static let chordMask: ModifierFlags = [.shift, .control, .option, .command]
}

/// Virtual key codes. **Positional, not layout-dependent.**
/// On the user's QWERTZ layout V sits in the same physical position as on
/// QWERTY, so a hardcoded code is correct here; assumption 10.6 and §5.5
/// record that layout resolution is deliberately out of scope for a
/// single-user v1. On Dvorak this code would be the wrong physical key.
public enum VirtualKey {
    public static let space = 49  // kVK_Space
    public static let v = 9  // kVK_ANSI_V
    /// Right Command. See the file comment for why this is 54 and not 55.
    public static let rightCommand = 54  // 0x36
    /// Left Command. `kVK_Command`.
    public static let leftCommand = 55  // 0x37
    /// Globe / Fn. `kVK_Function`. Never a dictation key.
    public static let function = 63  // 0x3F
}

public struct KeyboardEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case flagsChanged
        case keyDown
        case keyUp
    }

    public let kind: Kind
    public let keyCode: Int
    public let flags: ModifierFlags
    public let isAutorepeat: Bool
    public let timestampMs: Int

    public init(
        kind: Kind,
        keyCode: Int,
        flags: ModifierFlags,
        isAutorepeat: Bool = false,
        timestampMs: Int = 0
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.flags = flags
        self.isAutorepeat = isAutorepeat
        self.timestampMs = timestampMs
    }
}

public struct RecognizerDecision: Sendable, Equatable {
    public let actions: [HotkeyAction]
    /// `true` → the tap callback returns `nil` and the event never reaches the
    /// focused application.
    public let consumeEvent: Bool
    /// When set, the tap forwards the event with these flags instead of the
    /// originals. Used to take Right Command out of a chord so it cannot also
    /// be a shortcut. `nil` means the original event is forwarded untouched —
    /// required for the Globe/Fn key.
    public let replacementFlags: ModifierFlags?

    public static let pass = RecognizerDecision(
        actions: [],
        consumeEvent: false,
        replacementFlags: nil
    )

    public init(
        actions: [HotkeyAction],
        consumeEvent: Bool,
        replacementFlags: ModifierFlags? = nil
    ) {
        self.actions = actions
        self.consumeEvent = consumeEvent
        self.replacementFlags = replacementFlags
    }
}

public final class HotkeyRecognizer {
    public private(set) var configuration: HotkeyConfiguration
    private var rightCommandIsDown = false
    private var leftCommandIsDown = false
    /// Key codes whose `keyDown` this recogniser swallowed, so the matching
    /// `keyUp` is swallowed too. Needed because the user routinely lets go of
    /// the modifier first: releasing Right Command before Space means the
    /// Space `keyUp` arrives without the right-command bit, and forwarding it
    /// would hand the focused app a key-up with no key-down.
    private var swallowedKeyDowns = Set<Int>()

    public init(configuration: HotkeyConfiguration = .default) {
        self.configuration = configuration
    }

    public func setConfiguration(_ configuration: HotkeyConfiguration) {
        self.configuration = configuration
    }

    /// Forget every latch. Called when the tap is rebuilt, because events that
    /// happened while the tap was down were never seen: without this, a Right
    /// Command released during the gap leaves the latch stuck and the next
    /// press emits nothing.
    public func reset() {
        rightCommandIsDown = false
        leftCommandIsDown = false
        swallowedKeyDowns.removeAll()
    }

    public var isPushToTalkHeld: Bool { rightCommandIsDown }

    public func handle(_ event: KeyboardEvent) -> RecognizerDecision {
        // Globe / Fn, before any latch update or flag rewrite. Input-source
        // switching reads this event as the keyboard produced it.
        if event.keyCode == VirtualKey.function {
            return .pass
        }

        switch event.kind {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        }
    }

    private func handleFlagsChanged(_ event: KeyboardEvent) -> RecognizerDecision {
        if event.keyCode == VirtualKey.leftCommand {
            leftCommandIsDown = leftCommandPressed(event.flags)
            return forward(event)
        }

        if event.keyCode == VirtualKey.rightCommand {
            let isDown = rightCommandPressed(event.flags)
            let changed = isDown != rightCommandIsDown
            rightCommandIsDown = isDown
            // Always consumed when this key is the dictation key, including a
            // flagsChanged that did not move the latch. Forwarding it would
            // publish Right Command as the ⌘ modifier. No action is emitted
            // unless the side actually went down or up.
            if configuration.ptt == .rightCmd {
                return RecognizerDecision(
                    actions: changed ? [isDown ? .pttDown : .pttUp] : [],
                    consumeEvent: true
                )
            }
            return forward(event)
        }

        return forward(event)
    }

    private func handleKeyDown(_ event: KeyboardEvent) -> RecognizerDecision {
        if configuration.toggle == .rightCmdSpace, isRightCommandSpace(event) {
            swallowedKeyDowns.insert(event.keyCode)
            // Autorepeat still gets swallowed — otherwise holding the chord
            // sprays spaces into the target app — but it emits nothing, or one
            // long press would flip hands-free mode dozens of times.
            return RecognizerDecision(
                actions: event.isAutorepeat ? [] : [.toggle],
                consumeEvent: true
            )
        }

        if configuration.retry == .ctrlCmdV,
            event.keyCode == VirtualKey.v,
            event.flags.intersection(.chordMask) == [.control, .command]
        {
            swallowedKeyDowns.insert(event.keyCode)
            return RecognizerDecision(
                actions: event.isAutorepeat ? [] : [.retryInsert],
                consumeEvent: true
            )
        }

        return forward(event)
    }

    private func handleKeyUp(_ event: KeyboardEvent) -> RecognizerDecision {
        guard swallowedKeyDowns.contains(event.keyCode) else { return forward(event) }
        swallowedKeyDowns.remove(event.keyCode)
        return RecognizerDecision(actions: [], consumeEvent: true)
    }

    /// Right Command is down on this flagsChanged. The device bit wins. The
    /// generic command bit is only a fallback for a keyboard that omits side
    /// bits, and only when Left Command is not already explaining that bit.
    private func rightCommandPressed(_ flags: ModifierFlags) -> Bool {
        if flags.contains(.deviceRightCommand) { return true }
        if flags.contains(.deviceLeftCommand) { return false }
        if leftCommandIsDown { return false }
        return flags.contains(.command)
    }

    /// Left Command is down. Same device-bit rule. A flagsChanged with only
    /// the generic command bit while Right Command is already held is not
    /// treated as Left: that shape is also how a synthetic ⌘V is posted, and
    /// it must not latch the shortcut side for the rest of the session.
    private func leftCommandPressed(_ flags: ModifierFlags) -> Bool {
        if flags.contains(.deviceLeftCommand) { return true }
        if flags.contains(.deviceRightCommand) { return false }
        if rightCommandIsDown { return leftCommandIsDown }
        return flags.contains(.command)
    }

    /// Space is the hands-free chord only for Right Command alone.
    /// Left Command+Space stays Spotlight (and any other left-side shortcut).
    private func isRightCommandSpace(_ event: KeyboardEvent) -> Bool {
        guard event.keyCode == VirtualKey.space else { return false }
        // Left Command on the event itself: Spotlight and every other
        // left-side chord, including Left+Right together.
        if event.flags.contains(.deviceLeftCommand) { return false }
        if event.flags.contains(.deviceRightCommand) { return true }
        // No right-side bit. A latched Left Command means this Space belongs
        // to a left-side shortcut. Otherwise trust the Right Command latch,
        // which covers a keyboard that never sends device bits.
        if leftCommandIsDown { return false }
        return rightCommandIsDown
    }

    private func forward(_ event: KeyboardEvent) -> RecognizerDecision {
        RecognizerDecision(
            actions: [],
            consumeEvent: false,
            replacementFlags: strippedRightCommand(on: event)
        )
    }

    /// While Right Command is physically held, drop its side bit — and the
    /// generic command bit, when Left Command is not also down — so a letter
    /// typed during dictation is not a shortcut. Events that do not carry the
    /// right-side bit are left alone: a Left Command chord, and the helper's
    /// own synthetic ⌘V (posted with `.maskCommand` and no device bit), must
    /// keep their command flag.
    private func strippedRightCommand(on event: KeyboardEvent) -> ModifierFlags? {
        guard rightCommandIsDown else { return nil }
        guard event.flags.contains(.deviceRightCommand) else { return nil }
        var raw = event.flags.rawValue & ~ModifierFlags.deviceRightCommand.rawValue
        let leftHeld = event.flags.contains(.deviceLeftCommand) || leftCommandIsDown
        if !leftHeld {
            raw &= ~ModifierFlags.command.rawValue
        }
        let stripped = ModifierFlags(rawValue: raw)
        return stripped == event.flags ? nil : stripped
    }
}
