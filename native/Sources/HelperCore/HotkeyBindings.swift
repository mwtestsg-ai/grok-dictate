/// The three hotkey slots and the strings the app is allowed to put in them.
///
/// Contract §3, `set_hotkeys`: values are lower-case, `+`-separated tokens. This
/// build recognises exactly `rightcmd`, `rightcmd+space` and `ctrl+cmd+v`. An
/// unrecognised binding — including the old `fn` / `fn+space` — is reported via
/// `log` at `warn` and the previous binding kept, never silently ignored. The
/// app migrates a saved `fn` config before it sends `set_hotkeys`; the helper
/// still refuses `fn` so a stale sender cannot arm the Globe key.

import Foundation

public enum HotkeyBinding: Sendable, Equatable {
    /// Push-to-talk: Right Command alone, observed through `.flagsChanged`
    /// on keycode `kVK_RightCommand` (54). Left Command is a different key.
    case rightCmd
    /// Hands-free toggle: Space while Right Command is held and Left Command
    /// is not. Same three-frame gesture the state machine already implements
    /// for the old Fn+Space chord.
    case rightCmdSpace
    /// Re-run the insertion ladder against `lastTranscript`.
    case ctrlCmdV

    public var canonical: String {
        switch self {
        case .rightCmd: "rightcmd"
        case .rightCmdSpace: "rightcmd+space"
        case .ctrlCmdV: "ctrl+cmd+v"
        }
    }

    /// Token-set comparison rather than string equality, so `cmd+ctrl+v` is
    /// accepted as well as `ctrl+cmd+v`.
    public static func parse(_ raw: String) -> HotkeyBinding? {
        let tokens = Set(
            raw.lowercased()
                .split(separator: "+")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        switch tokens {
        case ["rightcmd"]: return .rightCmd
        case ["rightcmd", "space"]: return .rightCmdSpace
        case ["ctrl", "cmd", "v"]: return .ctrlCmdV
        default: return nil
        }
    }
}

public struct HotkeyConfiguration: Sendable, Equatable {
    public var ptt: HotkeyBinding
    public var toggle: HotkeyBinding
    public var retry: HotkeyBinding

    /// The defaults from `contracts/config.ts`. The helper starts with these
    /// armed, so Right Command works before the app's first `set_hotkeys`.
    public static let `default` = HotkeyConfiguration(
        ptt: .rightCmd,
        toggle: .rightCmdSpace,
        retry: .ctrlCmdV
    )

    public init(ptt: HotkeyBinding, toggle: HotkeyBinding, retry: HotkeyBinding) {
        self.ptt = ptt
        self.toggle = toggle
        self.retry = retry
    }

    /// Apply a `set_hotkeys` command. Each slot is validated independently, so
    /// one bad value does not discard two good ones.
    ///
    /// A hold and a chord are not interchangeable — `ptt` has to be something
    /// whose press and release are both observable, which among the three is
    /// only `rightcmd` — so a slot/binding mismatch is rejected with the same
    /// "kept the previous value" rule as an unparseable string.
    public mutating func apply(ptt: String, toggle: String, retry: String) -> [String] {
        var warnings: [String] = []
        assign(raw: ptt, slot: "ptt", accepting: .rightCmd, into: &self.ptt, warnings: &warnings)
        assign(
            raw: toggle,
            slot: "toggle",
            accepting: .rightCmdSpace,
            into: &self.toggle,
            warnings: &warnings
        )
        assign(raw: retry, slot: "retry", accepting: .ctrlCmdV, into: &self.retry, warnings: &warnings)
        return warnings
    }

    private func assign(
        raw: String,
        slot: String,
        accepting accepted: HotkeyBinding,
        into target: inout HotkeyBinding,
        warnings: inout [String]
    ) {
        guard let parsed = HotkeyBinding.parse(raw) else {
            warnings.append(
                "ignoring unrecognised \(slot) hotkey \"\(raw)\"; keeping \"\(target.canonical)\". "
                    + "v1 supports only \"\(accepted.canonical)\" for \(slot)."
            )
            return
        }
        guard parsed == accepted else {
            warnings.append(
                "ignoring \(slot) hotkey \"\(raw)\"; keeping \"\(target.canonical)\". "
                    + "v1 supports only \"\(accepted.canonical)\" for \(slot)."
            )
            return
        }
        target = parsed
    }
}
