/// Right Command versus Left Command, and the Globe key left alone.
///
/// Keycode 54 is Right Command, 55 is Left Command. The device-dependent bits
/// (`NX_DEVICERCMDKEYMASK` 0x10, `NX_DEVICELCMDKEYMASK` 0x08) are what stay
/// accurate when both sides are held. Fn is keycode 63 and must produce an
/// exact `.pass`: no action, not consumed, flags not rewritten.

import Testing

@testable import HelperCore

@Suite("Hotkey recognition")
struct HotkeyRecognizerTests {
    private func rightCommand(down: Bool, extra: ModifierFlags = []) -> KeyboardEvent {
        var flags = extra
        if down {
            flags.insert(.command)
            flags.insert(.deviceRightCommand)
        }
        return KeyboardEvent(kind: .flagsChanged, keyCode: VirtualKey.rightCommand, flags: flags)
    }

    private func leftCommand(down: Bool, extra: ModifierFlags = []) -> KeyboardEvent {
        var flags = extra
        if down {
            flags.insert(.command)
            flags.insert(.deviceLeftCommand)
        }
        return KeyboardEvent(kind: .flagsChanged, keyCode: VirtualKey.leftCommand, flags: flags)
    }

    @Test("Right Command down then up is one ptt_down and one ptt_up, and is consumed")
    func pushToTalk() {
        let recognizer = HotkeyRecognizer()
        let down = recognizer.handle(rightCommand(down: true))
        #expect(down.actions == [.pttDown])
        // Consumed so Right Command is not also a ⌘ modifier. Left Command is
        // a different key and is not consumed.
        #expect(down.consumeEvent)
        #expect(recognizer.isPushToTalkHeld)

        let up = recognizer.handle(rightCommand(down: false))
        #expect(up.actions == [.pttUp])
        #expect(up.consumeEvent)
        #expect(recognizer.isPushToTalkHeld == false)
    }

    @Test("the non-coalesced rider does not hide a Right Command press")
    func nonCoalescedRider() {
        // Real events often carry kCGEventFlagMaskNonCoalesced (0x100) next to
        // the device bit. Measured right-command flags are `1<<20 | 0x110`.
        let recognizer = HotkeyRecognizer()
        let down = recognizer.handle(rightCommand(down: true, extra: [.nonCoalesced]))
        #expect(down.actions == [.pttDown])
    }

    @Test("Left Command is not push-to-talk and is not consumed")
    func leftCommandPassesThrough() {
        let recognizer = HotkeyRecognizer()
        let down = recognizer.handle(leftCommand(down: true))
        #expect(down == .pass)
        #expect(recognizer.isPushToTalkHeld == false)

        let up = recognizer.handle(leftCommand(down: false))
        #expect(up == .pass)
    }

    @Test("a flagsChanged that is neither Command key emits nothing")
    func otherModifiersDoNotFire() {
        let recognizer = HotkeyRecognizer()
        #expect(
            recognizer.handle(KeyboardEvent(kind: .flagsChanged, keyCode: 56, flags: [.shift]))
                == .pass
        )
        #expect(recognizer.handle(rightCommand(down: true)).actions == [.pttDown])
        // Shift pressed while Right Command is held keeps the command bits set
        // and must not repeat push-to-talk. The forwarded event loses the
        // right-command bits so Shift is not also ⌘-Shift.
        let shift = recognizer.handle(
            KeyboardEvent(
                kind: .flagsChanged,
                keyCode: 56,
                flags: [.command, .deviceRightCommand, .shift]
            )
        )
        #expect(shift.actions.isEmpty)
        #expect(shift.consumeEvent == false)
        #expect(shift.replacementFlags == [.shift])
    }

    @Test("Fn/Globe is never a hotkey and its event is never rewritten")
    func functionKeyPassesThrough() {
        let recognizer = HotkeyRecognizer()
        _ = recognizer.handle(rightCommand(down: true))
        // Even while Right Command is held, the Globe event is returned
        // untouched — including the command bits it happens to carry — so
        // input-source switching sees the original flagsChanged.
        let fn = KeyboardEvent(
            kind: .flagsChanged,
            keyCode: VirtualKey.function,
            flags: [.secondaryFn, .command, .deviceRightCommand]
        )
        #expect(recognizer.handle(fn) == .pass)
        #expect(
            recognizer.handle(
                KeyboardEvent(kind: .keyDown, keyCode: VirtualKey.function, flags: [.secondaryFn])
            ) == .pass
        )
        #expect(recognizer.isPushToTalkHeld)
    }

    @Test("an arrow key carrying the Fn bit is not a push-to-talk press")
    func arrowKeysDoNotFire() {
        // Apple keyboards set the SecondaryFn bit on the arrow keys, Home/End,
        // Page Up/Down and the function row *without* Fn being held.
        let recognizer = HotkeyRecognizer()
        let leftArrow = KeyboardEvent(kind: .keyDown, keyCode: 123, flags: [.secondaryFn])
        #expect(recognizer.handle(leftArrow) == .pass)
        #expect(recognizer.isPushToTalkHeld == false)
    }

    @Test("Right Command+Space emits toggle and is swallowed")
    func rightCommandSpaceToggle() {
        let recognizer = HotkeyRecognizer()
        _ = recognizer.handle(rightCommand(down: true))
        let space = recognizer.handle(
            KeyboardEvent(
                kind: .keyDown,
                keyCode: VirtualKey.space,
                flags: [.command, .deviceRightCommand]
            )
        )
        #expect(space.actions == [.toggle])
        // Swallowed, or hands-free mode also types a space into the target app.
        #expect(space.consumeEvent)
    }

    @Test("Left Command+Space is left alone")
    func leftCommandSpacePassesThrough() {
        // Left Command+Space is Spotlight. It must not toggle hands-free and
        // must not be swallowed.
        let recognizer = HotkeyRecognizer()
        _ = recognizer.handle(leftCommand(down: true))
        let space = recognizer.handle(
            KeyboardEvent(
                kind: .keyDown,
                keyCode: VirtualKey.space,
                flags: [.command, .deviceLeftCommand]
            )
        )
        #expect(space == .pass)
    }

    @Test("Space with both Command keys is left alone")
    func bothCommandKeysDoNotStealSpace() {
        let recognizer = HotkeyRecognizer()
        _ = recognizer.handle(leftCommand(down: true))
        _ = recognizer.handle(rightCommand(down: true, extra: [.deviceLeftCommand]))
        let space = recognizer.handle(
            KeyboardEvent(
                kind: .keyDown,
                keyCode: VirtualKey.space,
                flags: [.command, .deviceLeftCommand, .deviceRightCommand]
            )
        )
        // Not consumed and not a toggle — Left Command+Space still reaches the
        // system. Only the right-side bit is removed.
        #expect(space.actions.isEmpty)
        #expect(space.consumeEvent == false)
        #expect(space.replacementFlags == [.command, .deviceLeftCommand])
    }

    @Test("Space without Right Command is left alone")
    func plainSpacePassesThrough() {
        let recognizer = HotkeyRecognizer()
        #expect(
            recognizer.handle(KeyboardEvent(kind: .keyDown, keyCode: VirtualKey.space, flags: []))
                == .pass
        )
    }

    @Test("Fn+Space is not hands-free")
    func fnSpaceIsNotToggle() {
        let recognizer = HotkeyRecognizer()
        #expect(
            recognizer.handle(
                KeyboardEvent(kind: .flagsChanged, keyCode: VirtualKey.function, flags: [.secondaryFn])
            ) == .pass
        )
        #expect(
            recognizer.handle(
                KeyboardEvent(kind: .keyDown, keyCode: VirtualKey.space, flags: [.secondaryFn])
            ) == .pass
        )
    }

    @Test("holding Right Command+Space swallows the autorepeat but toggles once")
    func autorepeatToggles() {
        let recognizer = HotkeyRecognizer()
        _ = recognizer.handle(rightCommand(down: true))
        let first = recognizer.handle(
            KeyboardEvent(
                kind: .keyDown,
                keyCode: VirtualKey.space,
                flags: [.command, .deviceRightCommand]
            )
        )
        #expect(first.actions == [.toggle])
        for _ in 0..<5 {
            let repeated = recognizer.handle(
                KeyboardEvent(
                    kind: .keyDown,
                    keyCode: VirtualKey.space,
                    flags: [.command, .deviceRightCommand],
                    isAutorepeat: true
                )
            )
            #expect(repeated.actions.isEmpty)
            #expect(repeated.consumeEvent)
        }
    }

    @Test("the matching key-up is swallowed even if the modifier went first")
    func keyUpAfterModifierRelease() {
        let recognizer = HotkeyRecognizer()
        _ = recognizer.handle(rightCommand(down: true))
        _ = recognizer.handle(
            KeyboardEvent(
                kind: .keyDown,
                keyCode: VirtualKey.space,
                flags: [.command, .deviceRightCommand]
            )
        )
        _ = recognizer.handle(rightCommand(down: false))
        let up = recognizer.handle(KeyboardEvent(kind: .keyUp, keyCode: VirtualKey.space, flags: []))
        #expect(up.consumeEvent)
        #expect(up.actions.isEmpty)
    }

    @Test("an unmatched key-up is forwarded")
    func unmatchedKeyUpPassesThrough() {
        let recognizer = HotkeyRecognizer()
        #expect(
            recognizer.handle(KeyboardEvent(kind: .keyUp, keyCode: VirtualKey.space, flags: []))
                == .pass
        )
    }

    @Test("Ctrl+Cmd+V emits retry_insert and is swallowed")
    func retryInsert() {
        let recognizer = HotkeyRecognizer()
        let decision = recognizer.handle(
            KeyboardEvent(
                kind: .keyDown,
                keyCode: VirtualKey.v,
                flags: [.control, .command, .deviceLeftCommand]
            )
        )
        #expect(decision.actions == [.retryInsert])
        #expect(decision.consumeEvent)
    }

    @Test(
        "near misses on the retry chord are forwarded",
        arguments: [
            ModifierFlags([.command, .deviceLeftCommand]),
            ModifierFlags([.control]),
            ModifierFlags([.control, .command, .shift]),
            ModifierFlags([.control, .command, .option]),
            ModifierFlags([]),
        ]
    )
    func retryChordIsExact(flags: ModifierFlags) {
        let recognizer = HotkeyRecognizer()
        let decision = recognizer.handle(
            KeyboardEvent(kind: .keyDown, keyCode: VirtualKey.v, flags: flags)
        )
        #expect(decision == .pass)
    }

    @Test("Caps Lock and the Fn bit do not break the retry chord")
    func retryChordIgnoresRiders() {
        let recognizer = HotkeyRecognizer()
        let decision = recognizer.handle(
            KeyboardEvent(
                kind: .keyDown,
                keyCode: VirtualKey.v,
                flags: [.control, .command, .capsLock, .secondaryFn, .numericPad, .deviceLeftCommand]
            )
        )
        #expect(decision.actions == [.retryInsert])
    }

    @Test("a letter held with Right Command is forwarded without the command bit")
    func rightCommandDoesNotChord() {
        let recognizer = HotkeyRecognizer()
        _ = recognizer.handle(rightCommand(down: true, extra: [.nonCoalesced]))
        let c = recognizer.handle(
            KeyboardEvent(
                kind: .keyDown,
                keyCode: 8,
                flags: [.command, .deviceRightCommand, .nonCoalesced]
            )
        )
        #expect(c.actions.isEmpty)
        #expect(c.consumeEvent == false)
        #expect(c.replacementFlags == [.nonCoalesced])
    }

    @Test("a synthetic ⌘V with no device bit keeps Command while Right Command is held")
    func syntheticPasteKeepsCommand() {
        // Paste posts Left Command (keycode 55) and V with exactly `.maskCommand`
        // and no device-side bit. Stripping that would turn paste into the
        // letter v whenever a follow-up hold overlaps an insertion.
        let recognizer = HotkeyRecognizer()
        _ = recognizer.handle(rightCommand(down: true))
        let commandDown = recognizer.handle(
            KeyboardEvent(kind: .flagsChanged, keyCode: VirtualKey.leftCommand, flags: [.command])
        )
        #expect(commandDown == .pass)
        let v = recognizer.handle(
            KeyboardEvent(kind: .keyDown, keyCode: VirtualKey.v, flags: [.command])
        )
        #expect(v == .pass)
    }

    @Test("a letter held with Left Command keeps its command bit")
    func leftCommandStillChords() {
        let recognizer = HotkeyRecognizer()
        _ = recognizer.handle(leftCommand(down: true))
        let c = recognizer.handle(
            KeyboardEvent(kind: .keyDown, keyCode: 8, flags: [.command, .deviceLeftCommand])
        )
        #expect(c == .pass)
    }

    @Test("Left Command still chords while Right Command is the dictation key")
    func leftCommandChordsDuringDictation() {
        let recognizer = HotkeyRecognizer()
        _ = recognizer.handle(rightCommand(down: true))
        let left = recognizer.handle(
            KeyboardEvent(
                kind: .flagsChanged,
                keyCode: VirtualKey.leftCommand,
                flags: [.command, .deviceLeftCommand, .deviceRightCommand]
            )
        )
        #expect(left.actions.isEmpty)
        #expect(left.consumeEvent == false)
        // The right-side bit is stripped. Left Command and the generic
        // command bit stay, so the shortcut still works.
        #expect(left.replacementFlags == [.command, .deviceLeftCommand])

        let c = recognizer.handle(
            KeyboardEvent(
                kind: .keyDown,
                keyCode: 8,
                flags: [.command, .deviceLeftCommand, .deviceRightCommand]
            )
        )
        #expect(c.consumeEvent == false)
        #expect(c.replacementFlags == [.command, .deviceLeftCommand])
    }

    @Test("releasing Right Command while Left stays down still emits ptt_up")
    func releaseRightWhileLeftHeld() {
        let recognizer = HotkeyRecognizer()
        #expect(recognizer.handle(leftCommand(down: true)).actions.isEmpty)
        #expect(
            recognizer.handle(rightCommand(down: true, extra: [.deviceLeftCommand])).actions
                == [.pttDown]
        )
        let up = recognizer.handle(
            KeyboardEvent(
                kind: .flagsChanged,
                keyCode: VirtualKey.rightCommand,
                flags: [.command, .deviceLeftCommand]
            )
        )
        #expect(up.actions == [.pttUp])
        #expect(up.consumeEvent)
        #expect(recognizer.isPushToTalkHeld == false)
    }

    @Test("keycode alone distinguishes the sides when device bits are absent")
    func keycodeFallbackWithoutDeviceBits() {
        let recognizer = HotkeyRecognizer()
        let right = recognizer.handle(
            KeyboardEvent(kind: .flagsChanged, keyCode: VirtualKey.rightCommand, flags: [.command])
        )
        #expect(right.actions == [.pttDown])
        let left = HotkeyRecognizer().handle(
            KeyboardEvent(kind: .flagsChanged, keyCode: VirtualKey.leftCommand, flags: [.command])
        )
        #expect(left.actions.isEmpty)
        #expect(left.consumeEvent == false)
    }

    @Test("Right Command+Space during a hold still reports ptt_down, toggle, ptt_up")
    func toggleDuringHoldReportsVerbatim() {
        let recognizer = HotkeyRecognizer()
        var actions: [HotkeyAction] = []
        actions += recognizer.handle(rightCommand(down: true)).actions
        actions += recognizer.handle(
            KeyboardEvent(
                kind: .keyDown,
                keyCode: VirtualKey.space,
                flags: [.command, .deviceRightCommand]
            )
        ).actions
        actions += recognizer.handle(
            KeyboardEvent(
                kind: .keyUp,
                keyCode: VirtualKey.space,
                flags: [.command, .deviceRightCommand]
            )
        ).actions
        actions += recognizer.handle(rightCommand(down: false)).actions
        #expect(actions == [.pttDown, .toggle, .pttUp])
    }

    @Test("a repeated flagsChanged for a held Right Command does not emit again")
    func repeatFlagsChangedIsSilent() {
        let recognizer = HotkeyRecognizer()
        #expect(recognizer.handle(rightCommand(down: true)).actions == [.pttDown])
        let again = recognizer.handle(rightCommand(down: true))
        #expect(again.actions.isEmpty)
        #expect(again.consumeEvent)
    }

    @Test("reset clears a stuck Right Command so the next press is seen")
    func resetClearsLatch() {
        let recognizer = HotkeyRecognizer()
        #expect(recognizer.handle(rightCommand(down: true)).actions == [.pttDown])
        recognizer.reset()
        #expect(recognizer.isPushToTalkHeld == false)
        #expect(recognizer.handle(rightCommand(down: true)).actions == [.pttDown])
    }

    @Test("reset clears a pending swallowed key-up")
    func resetClearsSwallowedKeys() {
        let recognizer = HotkeyRecognizer()
        _ = recognizer.handle(rightCommand(down: true))
        _ = recognizer.handle(
            KeyboardEvent(
                kind: .keyDown,
                keyCode: VirtualKey.space,
                flags: [.command, .deviceRightCommand]
            )
        )
        recognizer.reset()
        #expect(
            recognizer.handle(KeyboardEvent(kind: .keyUp, keyCode: VirtualKey.space, flags: []))
                == .pass
        )
    }

    @Test("the ModifierFlags raw values match CGEventFlags and the command keycodes")
    func flagRawValues() {
        #expect(ModifierFlags.capsLock.rawValue == 0x0001_0000)
        #expect(ModifierFlags.shift.rawValue == 0x0002_0000)
        #expect(ModifierFlags.control.rawValue == 0x0004_0000)
        #expect(ModifierFlags.option.rawValue == 0x0008_0000)
        #expect(ModifierFlags.command.rawValue == 0x0010_0000)
        #expect(ModifierFlags.numericPad.rawValue == 0x0020_0000)
        #expect(ModifierFlags.help.rawValue == 0x0040_0000)
        #expect(ModifierFlags.secondaryFn.rawValue == 0x0080_0000)
        // NX_DEVICELCMDKEYMASK / NX_DEVICERCMDKEYMASK.
        #expect(ModifierFlags.deviceLeftCommand.rawValue == 0x0000_0008)
        #expect(ModifierFlags.deviceRightCommand.rawValue == 0x0000_0010)
        #expect(ModifierFlags.nonCoalesced.rawValue == 0x0000_0100)
        #expect(VirtualKey.space == 49)
        #expect(VirtualKey.v == 9)
        #expect(VirtualKey.rightCommand == 54)
        #expect(VirtualKey.leftCommand == 55)
        #expect(VirtualKey.function == 63)
    }
}
