import { WitnessesService } from './witnesses.service';

/**
 * A witness signature only completes when the legal name they verify matches the
 * name the testator recorded (spec §6). The match is forgiving about case, spacing
 * and diacritics — but never about identity.
 */
describe('witness ID name-match', () => {
  const n = WitnessesService.normalizeName;

  it('matches despite case and extra whitespace', () => {
    expect(n('Khalid  Al-Rashid ')).toBe(n('khalid al-rashid'));
  });

  it('matches Arabic names regardless of harakat (diacritics)', () => {
    expect(n('خَالِد')).toBe(n('خالد'));
  });

  it('does NOT match a different person', () => {
    expect(n('Khalid Al-Rashid')).not.toBe(n('Omar Al-Rashid'));
  });

  it('does not collapse distinct names to empty', () => {
    expect(n('Fatima')).not.toBe('');
    expect(n('Fatima')).not.toBe(n('Zainab'));
  });
});
