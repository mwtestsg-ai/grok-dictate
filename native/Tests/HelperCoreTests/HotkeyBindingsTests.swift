import Testing

@testable import HelperCore

@Suite("Hotkey bindings")
struct HotkeyBindingsTests {
    @Test("the canonical spellings parse")
    func canonicalSpellings() {
        #expect(HotkeyBinding.parse("rightcmd") == .rightCmd)
        #expect(HotkeyBinding.parse("rightcmd+space") == .rightCmdSpace)
        #expect(HotkeyBinding.parse("ctrl+cmd+v") == .ctrlCmdV)
    }

    @Test("case and token order are tolerated")
    func tolerantParsing() {
        #expect(HotkeyBinding.parse("RightCmd+Space") == .rightCmdSpace)
        #expect(HotkeyBinding.parse("cmd+ctrl+v") == .ctrlCmdV)
        #expect(HotkeyBinding.parse(" ctrl + cmd + v ") == .ctrlCmdV)
    }

    @Test(
        "the old Fn bindings and anything else are rejected",
        arguments: [
            "",
            "  ",
            "f13",
            "fn",
            "fn+space",
            "cmd+v",
            "ctrl+v",
            "fn+f5",
            "option+space",
            "ctrl+cmd+shift+v",
            "cmd",
            "right+cmd",
        ]
    )
    func rejectsUnknown(raw: String) {
        #expect(HotkeyBinding.parse(raw) == nil)
    }

    @Test("the defaults match contracts/config.ts")
    func defaults() {
        #expect(HotkeyConfiguration.default.ptt == .rightCmd)
        #expect(HotkeyConfiguration.default.toggle == .rightCmdSpace)
        #expect(HotkeyConfiguration.default.retry == .ctrlCmdV)
    }

    @Test("a valid set_hotkeys applies with no warnings")
    func applyValid() {
        var configuration = HotkeyConfiguration.default
        let warnings = configuration.apply(
            ptt: "rightcmd",
            toggle: "rightcmd+space",
            retry: "ctrl+cmd+v"
        )
        #expect(warnings.isEmpty)
        #expect(configuration == .default)
    }

    @Test("an unrecognised binding warns and keeps the previous value")
    func applyInvalidKeepsPrevious() {
        var configuration = HotkeyConfiguration.default
        let warnings = configuration.apply(ptt: "f13", toggle: "rightcmd+space", retry: "ctrl+cmd+v")
        #expect(warnings.count == 1)
        #expect(warnings[0].contains("f13"))
        #expect(warnings[0].contains("rightcmd"))
        #expect(configuration.ptt == .rightCmd)
    }

    @Test("a saved fn binding is refused rather than armed")
    func legacyFnIsRefused() {
        var configuration = HotkeyConfiguration.default
        let warnings = configuration.apply(ptt: "fn", toggle: "fn+space", retry: "ctrl+cmd+v")
        #expect(warnings.count == 2)
        #expect(configuration.ptt == .rightCmd)
        #expect(configuration.toggle == .rightCmdSpace)
    }

    @Test("one bad slot does not discard the other two")
    func slotsAreIndependent() {
        var configuration = HotkeyConfiguration.default
        let warnings = configuration.apply(ptt: "nonsense", toggle: "rubbish", retry: "ctrl+cmd+v")
        #expect(warnings.count == 2)
        #expect(configuration == .default)
    }

    @Test("a binding valid for another slot is still refused")
    func slotMismatch() {
        var configuration = HotkeyConfiguration.default
        let warnings = configuration.apply(
            ptt: "rightcmd+space",
            toggle: "rightcmd+space",
            retry: "ctrl+cmd+v"
        )
        #expect(warnings.count == 1)
        #expect(configuration.ptt == .rightCmd)
    }
}
