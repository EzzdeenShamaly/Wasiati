import { DataRetentionService } from './data-retention.service';

/**
 * The reminder milestone picker must fire each of 30/7/3 exactly once, always the
 * most-urgent unsent one, and never re-fire a milestone already sent.
 */
describe('DataRetentionService.pickDueReminder', () => {
  const pick = DataRetentionService.pickDueReminder;

  it('sends nothing before the first milestone', () => {
    expect(pick(45, [])).toBeNull();
    expect(pick(31, [])).toBeNull();
  });

  it('fires 30 at ~30 days, then not again', () => {
    expect(pick(30, [])).toBe(30);
    expect(pick(29, ['30'])).toBeNull();
  });

  it('fires 7 at ~a week, then 3 near the end', () => {
    expect(pick(7, ['30'])).toBe(7);
    expect(pick(3, ['30', '7'])).toBe(3);
    expect(pick(1, ['30', '7', '3'])).toBeNull();
  });

  it('picks the MOST urgent unsent milestone if runs were missed', () => {
    // First time we see the account is at 5 days remaining, nothing sent yet.
    expect(pick(5, [])).toBe(7); // 30 and 7 both passed; 7 is the tighter one
  });

  it('never re-sends once every passed milestone is marked', () => {
    // The sweep marks ALL passed milestones each run, so at day 2 the set is full.
    expect(pick(3, ['30', '7', '3'])).toBeNull();
    expect(pick(2, ['30', '7', '3'])).toBeNull();
  });
});
