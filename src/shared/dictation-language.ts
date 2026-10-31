/**
 * English and Greek are the only languages this build will insert.
 *
 * xAI's streaming STT socket takes one optional `language` code. The current
 * docs describe it as a bias ("leans toward that language when the audio is
 * ambiguous"), not an allowlist, and there is no multi-language parameter.
 * Spike 3 measured the same thing: English audio sent with `language=de` came
 * back `"language":"en"`. Greek (`el`) is in the published catalog.
 *
 * `auto` therefore omits `language`, so the server can hear either English or
 * Greek. Pinning one code would bias the other away. Whatever comes back is
 * still filtered here: a detected language other than `en` or `el` is not
 * inserted. With no language tag, text in any script besides Latin and Greek
 * is dropped too. Untagged Latin text can still be German or French — the
 * server's `language` field is the signal that catches those, and this build
 * does not invent a second recogniser.
 */

import type { LanguageMode } from '@contracts/config.js';

export const DICTATION_LANGUAGES = ['en', 'el'] as const;
export type DictationLanguage = (typeof DICTATION_LANGUAGES)[number];

/** Primary subtag: `en-US` and `el_GR` are `en` and `el`. */
export function languagePrimary(code: string): string {
  const primary = code.trim().toLowerCase().split(/[-_]/)[0];
  return primary ?? '';
}

export function isDictationLanguage(code: string | null | undefined): code is DictationLanguage {
  if (code === null || code === undefined || code.length === 0) return false;
  return (DICTATION_LANGUAGES as readonly string[]).includes(languagePrimary(code));
}

/** Languages a mode is willing to insert. `auto` is both. */
export function languagesForMode(mode: LanguageMode): readonly DictationLanguage[] {
  if (mode === 'en') return ['en'];
  if (mode === 'el') return ['el'];
  return DICTATION_LANGUAGES;
}

/**
 * A letter that is neither Latin nor Greek. Digits and punctuation are not
 * letters, so "42" and "OK." stay admissible when the server sent no tag.
 */
const FOREIGN_LETTER = new RegExp(
  String.raw`\p{Letter}(?<!\p{Script=Latin})(?<!\p{Script=Greek})`,
  'u',
);

function hasForeignScript(text: string): boolean {
  return FOREIGN_LETTER.test(text);
}

function hasGreekLetter(text: string): boolean {
  return /\p{Script=Greek}/u.test(text);
}

function hasLatinLetter(text: string): boolean {
  return /\p{Script=Latin}/u.test(text);
}

/**
 * Whether this text may be shown or inserted.
 *
 * A language tag from the server is decisive. No tag falls back to script:
 * English mode keeps Latin, Greek mode keeps Greek, auto keeps either, and
 * every other script is refused in all three.
 */
export function admitDictationText(
  text: string,
  detected: string | null,
  mode: LanguageMode,
): boolean {
  if (text.trim().length === 0) return false;
  const allowed = languagesForMode(mode);

  if (detected !== null && detected.length > 0) {
    const primary = languagePrimary(detected);
    return (allowed as readonly string[]).includes(primary);
  }

  if (hasForeignScript(text)) return false;
  if (mode === 'el') return hasGreekLetter(text);
  if (mode === 'en') return hasLatinLetter(text) || !hasGreekLetter(text);
  return true;
}
