import { describe, expect, it } from 'vitest';
import { admitDictationText, languagePrimary, languagesForMode } from './dictation-language.js';

describe('dictation languages', () => {
  it('reads a primary subtag', () => {
    expect(languagePrimary('en-US')).toBe('en');
    expect(languagePrimary('EL_GR')).toBe('el');
  });

  it('auto allows English and Greek, and a pin allows only that one', () => {
    expect(languagesForMode('auto')).toEqual(['en', 'el']);
    expect(languagesForMode('en')).toEqual(['en']);
    expect(languagesForMode('el')).toEqual(['el']);
  });

  it('drops a detected language that is neither English nor Greek', () => {
    expect(admitDictationText('Guten Tag', 'de', 'auto')).toBe(false);
    expect(admitDictationText('Bonjour', 'fr', 'en')).toBe(false);
    expect(admitDictationText('Привет', 'ru', 'auto')).toBe(false);
  });

  it('keeps English and Greek when auto, and respects a pin', () => {
    expect(admitDictationText('Hello there', 'en', 'auto')).toBe(true);
    expect(admitDictationText('Γεια σου', 'el', 'auto')).toBe(true);
    expect(admitDictationText('Γεια σου', 'el', 'en')).toBe(false);
    expect(admitDictationText('Hello there', 'en', 'el')).toBe(false);
    expect(admitDictationText('Hello there', 'en-US', 'en')).toBe(true);
  });

  it('with no tag, drops other scripts and keeps Latin or Greek', () => {
    expect(admitDictationText('Hello', null, 'auto')).toBe(true);
    expect(admitDictationText('Γεια', null, 'auto')).toBe(true);
    expect(admitDictationText('こんにちは', null, 'auto')).toBe(false);
    expect(admitDictationText('Привет', null, 'en')).toBe(false);
    expect(admitDictationText('Γεια', null, 'en')).toBe(false);
    expect(admitDictationText('Hello', null, 'el')).toBe(false);
    expect(admitDictationText('Γεια', null, 'el')).toBe(true);
    expect(admitDictationText('42', null, 'en')).toBe(true);
  });
});
