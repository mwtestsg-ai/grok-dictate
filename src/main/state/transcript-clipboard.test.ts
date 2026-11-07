import { describe, expect, it } from 'vitest';
import { transcriptForClipboard } from './transcript-clipboard.js';

describe('transcript left on the clipboard', () => {
  it('keeps the transcript after a successful insert when the setting is on', () => {
    expect(transcriptForClipboard(true, true, 'Hello')).toBe('Hello');
  });

  it('leaves the clipboard alone when the insert failed or the setting is off', () => {
    expect(transcriptForClipboard(false, true, 'Hello')).toBeNull();
    expect(transcriptForClipboard(true, false, 'Hello')).toBeNull();
    expect(transcriptForClipboard(true, true, '')).toBeNull();
    expect(transcriptForClipboard(true, true, null)).toBeNull();
  });
});
