/**
 * The transcript that should be left on the system clipboard after an insert.
 *
 * Called only once the helper has reported the insert, so it runs after the
 * paste tier has published its promise. That tier later calls
 * `clearContents()` only if the pasteboard's change count is still the one
 * from publish. A copy in between changes the count and the clear leaves the
 * board alone; a copy after the clear is the last write. Either order ends
 * with this string, not with an empty board.
 *
 * The paste promise is marked so clipboard managers skip it. This copy is a
 * plain string, which is what those managers record.
 */
export function transcriptForClipboard(
  inserted: boolean,
  enabled: boolean,
  text: string | null,
): string | null {
  if (!inserted || !enabled) return null;
  if (text === null || text.length === 0) return null;
  return text;
}
