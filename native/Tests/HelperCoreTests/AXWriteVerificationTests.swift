/// The AX tier reports success only when the caret proves it.
///
/// Everything reachable without a real application on a real screen is here.
/// What is *not* coverable headlessly, and must be run by a human against Arc,
/// Notes and TextEdit, is the input to these functions: whether a given
/// application exposes `kAXSelectedTextRange` at all and what it does to it
/// during a write. `--probe-ax` prints exactly the three values these tests take
/// as arguments, which is the point of extending it.

import Testing

@testable import HelperCore

@Suite("AX write verification")
struct AXWriteVerificationTests {
    private let n = 8  // the marker `--probe-ax` writes, in UTF-16 units

    private func isUnverifiable(_ verdict: AXWriteVerdict) -> Bool {
        if case .unverifiable = verdict { return true }
        return false
    }

    // MARK: - Landed

    @Test("a caret that advanced by exactly the number of units written landed")
    func exactAdvance() {
        let verdict = AXWriteVerification.verdict(
            before: AXSelectedRange(location: 12, length: 0),
            after: AXSelectedRange(location: 20, length: 0),
            insertedUTF16Count: n
        )
        #expect(verdict == .landed(caretAdvancedBy: 8))
        #expect(AXWriteVerification.trustsWrite(verdict))
    }

    @Test("replacing a selection collapses it and advances from its start")
    func replacedSelection() {
        // Setting kAXSelectedText with a selection active is a replace, which is
        // dictation's semantics when the user has highlighted something. The
        // caret ends N units past where the selection *started*.
        let verdict = AXWriteVerification.verdict(
            before: AXSelectedRange(location: 12, length: 5),
            after: AXSelectedRange(location: 20, length: 0),
            insertedUTF16Count: n
        )
        #expect(verdict == .landed(caretAdvancedBy: 8))
    }

    @Test("an advance that is not exactly N still counts as landed")
    func inexactAdvance() {
        // Not every accessibility implementation counts these ranges in UTF-16.
        // WebKit works in character positions, so an emoji written as a
        // surrogate pair can advance the caret by one; a target with text
        // substitution on can store something a different length from what was
        // written. Any forward movement is proof a write happened — insisting on
        // exactly N would decline the AX tier in Safari for a smart quote.
        for advance in [1, 3, 7, 9, 40] {
            let verdict = AXWriteVerification.verdict(
                before: AXSelectedRange(location: 100, length: 0),
                after: AXSelectedRange(location: 100 + advance, length: 0),
                insertedUTF16Count: n
            )
            #expect(verdict == .landed(caretAdvancedBy: advance))
            #expect(AXWriteVerification.trustsWrite(verdict))
        }
    }

    @Test("a write into an empty field at the origin landed")
    func fromTheOrigin() {
        let verdict = AXWriteVerification.verdict(
            before: AXSelectedRange(location: 0, length: 0),
            after: AXSelectedRange(location: 8, length: 0),
            insertedUTF16Count: n
        )
        #expect(AXWriteVerification.trustsWrite(verdict))
    }

    // MARK: - Did not land — the Arc case

    @Test("an unchanged range is a discarded write, whatever the AXError said")
    func unchangedRange() {
        // This is the bug: Arc's web content reports kAXSelectedTextAttribute as
        // settable, returns kAXErrorSuccess, and inserts nothing. 13.8 s of
        // speech, an 11 ms round trip, a green pill and no text
        // (`AXWriteVerification`'s header quotes the log).
        let verdict = AXWriteVerification.verdict(
            before: AXSelectedRange(location: 12, length: 0),
            after: AXSelectedRange(location: 12, length: 0),
            insertedUTF16Count: n
        )
        #expect(verdict.isDiscardedWrite)
        #expect(AXWriteVerification.trustsWrite(verdict) == false)
        #expect(verdict.evidence.contains("{12, 0}"))
        #expect(verdict.evidence.contains("8"))
    }

    @Test("a surviving selection with an unchanged range is also a discarded write")
    func unchangedSelection() {
        // A real replace would have collapsed the selection to length 0. Both
        // numbers identical means nothing happened at all.
        let verdict = AXWriteVerification.verdict(
            before: AXSelectedRange(location: 3, length: 11),
            after: AXSelectedRange(location: 3, length: 11),
            insertedUTF16Count: n
        )
        #expect(verdict.isDiscardedWrite)
        #expect(AXWriteVerification.trustsWrite(verdict) == false)
    }

    // MARK: - Cannot verify

    @Test("an unreadable range before the write cannot be verified")
    func unreadableBefore() {
        // `AXInserter` reads this one *before* writing precisely so it can
        // decline here without anything having been inserted — which is what
        // keeps the fall-through to Unicode from duplicating text.
        let verdict = AXWriteVerification.verdict(
            before: nil,
            after: AXSelectedRange(location: 20, length: 0),
            insertedUTF16Count: n
        )
        #expect(isUnverifiable(verdict))
        #expect(verdict.evidence.contains("before"))
        #expect(AXWriteVerification.trustsWrite(verdict) == false)
    }

    @Test("an unreadable range after the write cannot be verified")
    func unreadableAfter() {
        let verdict = AXWriteVerification.verdict(
            before: AXSelectedRange(location: 12, length: 0),
            after: nil,
            insertedUTF16Count: n
        )
        #expect(isUnverifiable(verdict))
        #expect(verdict.evidence.contains("after"))
        #expect(AXWriteVerification.trustsWrite(verdict) == false)
    }

    @Test("a caret that moved backwards proves nothing")
    func caretWentBackwards() {
        let verdict = AXWriteVerification.verdict(
            before: AXSelectedRange(location: 12, length: 0),
            after: AXSelectedRange(location: 4, length: 0),
            insertedUTF16Count: n
        )
        #expect(isUnverifiable(verdict))
        #expect(AXWriteVerification.trustsWrite(verdict) == false)
    }

    @Test("a selection that collapsed without the caret moving proves nothing")
    func collapsedWithoutAdvancing() {
        // Consistent with the selection having been deleted and nothing put in
        // its place, and consistent with an app that reports ranges its own way.
        // Neither is evidence that this text went in.
        let verdict = AXWriteVerification.verdict(
            before: AXSelectedRange(location: 12, length: 5),
            after: AXSelectedRange(location: 12, length: 0),
            insertedUTF16Count: n
        )
        #expect(isUnverifiable(verdict))
        #expect(AXWriteVerification.trustsWrite(verdict) == false)
    }

    @Test("a selection left behind by the write proves nothing")
    func selectionSurvives() {
        let verdict = AXWriteVerification.verdict(
            before: AXSelectedRange(location: 12, length: 0),
            after: AXSelectedRange(location: 20, length: 4),
            insertedUTF16Count: n
        )
        #expect(isUnverifiable(verdict))
        #expect(AXWriteVerification.trustsWrite(verdict) == false)
    }

    @Test("writing nothing is unverifiable rather than landed")
    func emptyWrite() {
        // Unreachable through the ladder, which refuses empty text before any
        // tier runs. Asserted so that a verifier which quietly passes on a
        // degenerate input fails here rather than in the field.
        let verdict = AXWriteVerification.verdict(
            before: AXSelectedRange(location: 12, length: 0),
            after: AXSelectedRange(location: 12, length: 0),
            insertedUTF16Count: 0
        )
        #expect(isUnverifiable(verdict))
        #expect(AXWriteVerification.trustsWrite(verdict) == false)
    }

    // MARK: - The policy itself

    @Test("only a verified landing is trusted")
    func policy() {
        // The asymmetry, stated once as an executable assertion: a false decline
        // costs one Unicode injection (156-166 ms measured, phase-2-report.md §4
        // HT-3, against 32-50 ms for AX) and the user sees their text. A missed
        // lie costs the user their words behind a green "Inserted" pill.
        #expect(AXWriteVerification.trustsWrite(.landed(caretAdvancedBy: 1)))
        #expect(AXWriteVerification.trustsWrite(.didNotLand(evidence: "…")) == false)
        #expect(AXWriteVerification.trustsWrite(.unverifiable(evidence: "…")) == false)
    }

    @Test("every verdict carries evidence a human can read")
    func evidenceIsAlwaysPresent() {
        // The reason string ends up in a helper `log` frame and, when Unicode
        // also fails, in the `insert_result` the user is shown
        // (IMPLEMENTATION-PLAN.md §4: "STT failed" is a defect).
        let verdicts: [AXWriteVerdict] = [
            .landed(caretAdvancedBy: 3),
            .didNotLand(evidence: "the selected range is still {1, 0}"),
            .unverifiable(evidence: "the selected range could not be read"),
        ]
        for verdict in verdicts {
            #expect(verdict.evidence.isEmpty == false)
        }
    }

    @Test("a range prints the way AX tools print a CFRange")
    func rangeDescription() {
        #expect("\(AXSelectedRange(location: 12, length: 3))" == "{12, 3}")
    }
}

/// Telegram inserts and returns `kAXErrorFailure`. Arc returns success and
/// inserts nothing. The caret decides; the error code does not.
@Suite("AX post-write action")
struct AXPostWriteActionTests {
    private let landed = AXWriteVerification.verdict(
        before: AXSelectedRange(location: 0, length: 0),
        after: AXSelectedRange(location: 60, length: 0),
        insertedUTF16Count: 60
    )
    private let discarded = AXWriteVerification.verdict(
        before: AXSelectedRange(location: 12, length: 0),
        after: AXSelectedRange(location: 12, length: 0),
        insertedUTF16Count: 60
    )
    private let unverifiable = AXWriteVerification.verdict(
        before: AXSelectedRange(location: 12, length: 0),
        after: nil,
        insertedUTF16Count: 60
    )

    @Test("a caret that moved is accepted even when the AX call returned an error")
    func errorWithMovedCaretSkipsUnicode() {
        // Telegram, 2026-10-31: one hotkey, one final transcript, text_len=60.
        // Setting kAXSelectedTextAttribute returned kAXErrorFailure (-25200)
        // with settable=true, and the message was in the field. The ladder
        // then posted one Unicode chunk of those same 60 units.
        let action = AXWriteVerification.postWriteAction(
            writeReturnedSuccess: false,
            verdict: landed
        )
        #expect(action == .accept(despiteError: true))
    }

    @Test("a failed write whose caret did not move still falls through")
    func errorWithUnchangedCaretFallsThrough() {
        let action = AXWriteVerification.postWriteAction(
            writeReturnedSuccess: false,
            verdict: discarded
        )
        #expect(action == .fallThrough)
    }

    @Test("a failed write with an unreadable caret falls through unless the character count grew")
    func errorWithUnreadableCaret() {
        let unread = AXWriteVerification.postWriteAction(
            writeReturnedSuccess: false,
            verdict: unverifiable
        )
        #expect(unread == .fallThrough)

        // The range can stay stale while the field grows. Any increase is
        // enough — the same rule as an inexact caret advance.
        let grew = AXWriteVerification.postWriteAction(
            writeReturnedSuccess: false,
            verdict: discarded,
            characterCountBefore: 10,
            characterCountAfter: 70
        )
        #expect(grew == .accept(despiteError: true))

        let grewByOne = AXWriteVerification.postWriteAction(
            writeReturnedSuccess: false,
            verdict: unverifiable,
            characterCountBefore: 10,
            characterCountAfter: 11
        )
        #expect(grewByOne == .accept(despiteError: true))
    }

    @Test("a character count that did not grow does not invent a landing")
    func countDidNotGrow() {
        for (before, after) in [(10, 10), (10, 9), (0, 0)] {
            let action = AXWriteVerification.postWriteAction(
                writeReturnedSuccess: false,
                verdict: discarded,
                characterCountBefore: before,
                characterCountAfter: after
            )
            #expect(action == .fallThrough)
        }
        let missing = AXWriteVerification.postWriteAction(
            writeReturnedSuccess: false,
            verdict: discarded,
            characterCountBefore: nil,
            characterCountAfter: 70
        )
        #expect(missing == .fallThrough)
    }

    @Test("a successful write whose caret moved is accepted, and one whose caret did not still falls through")
    func successFollowsTheCaret() {
        // The second expectation is the Arc path and the Telegram sessions
        // that returned success, left the caret unmoved, and were recovered by
        // Unicode without a duplicate. A character-count increase must not
        // close that path: the count is only evidence after an error return.
        #expect(
            AXWriteVerification.postWriteAction(writeReturnedSuccess: true, verdict: landed)
                == .accept(despiteError: false)
        )
        #expect(
            AXWriteVerification.postWriteAction(
                writeReturnedSuccess: true,
                verdict: discarded,
                characterCountBefore: 10,
                characterCountAfter: 70
            ) == .fallThrough
        )
        #expect(
            AXWriteVerification.postWriteAction(writeReturnedSuccess: true, verdict: unverifiable)
                == .fallThrough
        )
    }
}
