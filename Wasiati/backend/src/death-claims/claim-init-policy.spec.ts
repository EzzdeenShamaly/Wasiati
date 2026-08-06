import { ClaimInitPolicy, ClaimRole } from '@prisma/client';
import { DeathClaimsService, WillParties } from './death-claims.service';

/**
 * Spec §6: "claim initiation policy — trustee only / heirs with documents / both."
 *
 * The testator chooses who is allowed to report their death. Before this, ANY
 * witness or trustee attached to the will could start a claim regardless of the
 * stored preference.
 *
 * HEIRS_WITH_DOCUMENTS used to resolve to `role === 'WITNESS'` — not because the policy
 * was about witnesses, but because no heir roster existed to match against, so witnesses
 * stood in for heirs. `will.heirContacts` exists now, so the policy means what it says.
 * Witnesses stay eligible: they were the only people the policy ever admitted, and
 * dropping them would lock out every will already relying on it.
 */
describe('claim initiation policy', () => {
  const allows = DeathClaimsService.policyAllows;

  it('TRUSTEE_ONLY: only the trustee', () => {
    expect(allows(ClaimInitPolicy.TRUSTEE_ONLY, ClaimRole.TRUSTEE)).toBe(true);
    expect(allows(ClaimInitPolicy.TRUSTEE_ONLY, ClaimRole.WITNESS)).toBe(false);
    expect(allows(ClaimInitPolicy.TRUSTEE_ONLY, ClaimRole.HEIR)).toBe(false);
  });

  it('HEIRS_WITH_DOCUMENTS: an heir OR a witness, never the trustee', () => {
    expect(allows(ClaimInitPolicy.HEIRS_WITH_DOCUMENTS, ClaimRole.HEIR)).toBe(true);
    expect(allows(ClaimInitPolicy.HEIRS_WITH_DOCUMENTS, ClaimRole.WITNESS)).toBe(true);
    expect(allows(ClaimInitPolicy.HEIRS_WITH_DOCUMENTS, ClaimRole.TRUSTEE)).toBe(false);
  });

  it('BOTH: any of the three', () => {
    expect(allows(ClaimInitPolicy.BOTH, ClaimRole.TRUSTEE)).toBe(true);
    expect(allows(ClaimInitPolicy.BOTH, ClaimRole.WITNESS)).toBe(true);
    expect(allows(ClaimInitPolicy.BOTH, ClaimRole.HEIR)).toBe(true);
  });

  it('covers every policy — adding one must fail to compile, not silently allow', () => {
    // If a new ClaimInitPolicy member appears, the switch in policyAllows loses its
    // exhaustiveness and TypeScript flags it. This test pins the current set.
    expect(Object.values(ClaimInitPolicy).sort()).toEqual(['BOTH', 'HEIRS_WITH_DOCUMENTS', 'TRUSTEE_ONLY']);
  });

  it('covers every role, so a new ClaimRole cannot be silently admitted', () => {
    expect(Object.values(ClaimRole).sort()).toEqual(['HEIR', 'TRUSTEE', 'WITNESS']);
  });
});

/**
 * `authorizedParties` replaces `authorizedRole`, which returned at most ONE role and
 * searched only witnesses and trustees, on phone alone. The heir roster — documented as
 * existing "so the will can be released to each at claim time" — was read by nothing.
 */
describe('DeathClaimsService.authorizedParties', () => {
  const will = (policy: ClaimInitPolicy): WillParties => ({
    witnesses: [{ id: 'w1', phone: '+966555000111', email: 'witness@x.com' }],
    trustees: [{ id: 't1', phone: '+966555000222', email: 'trustee@x.com' }],
    heirContacts: [
      { id: 'h1', phone: '+966555000333', email: 'heir@x.com' },
      { id: 'h2', phone: null, email: 'emailonly@x.com' },
    ],
    owner: { claimInitPolicy: policy },
  });

  describe('finds each kind of party', () => {
    it('matches a witness', () => {
      const [p] = DeathClaimsService.authorizedParties(will(ClaimInitPolicy.BOTH), '+966555000111');
      expect(p).toMatchObject({ role: ClaimRole.WITNESS, partyId: 'w1' });
    });

    it('matches a trustee', () => {
      const [p] = DeathClaimsService.authorizedParties(will(ClaimInitPolicy.BOTH), '+966555000222');
      expect(p).toMatchObject({ role: ClaimRole.TRUSTEE, partyId: 't1' });
    });

    // The whole point of the change: the heir roster is finally read.
    it('matches an HEIR from will.heirContacts', () => {
      const [p] = DeathClaimsService.authorizedParties(will(ClaimInitPolicy.BOTH), '+966555000333');
      expect(p).toMatchObject({ role: ClaimRole.HEIR, partyId: 'h1' });
    });
  });

  describe('matches on phone AND email', () => {
    it('matches an heir by email when only an email is on file', () => {
      const [p] = DeathClaimsService.authorizedParties(will(ClaimInitPolicy.BOTH), 'emailonly@x.com');
      expect(p).toMatchObject({ role: ClaimRole.HEIR, partyId: 'h2' });
    });

    it('matches email case-insensitively', () => {
      const [p] = DeathClaimsService.authorizedParties(will(ClaimInitPolicy.BOTH), '  HEIR@X.COM ');
      expect(p).toMatchObject({ partyId: 'h1' });
    });

    // The regression that made the old lookup unusable, now at the party level.
    it('matches a national-format phone against the international one on file', () => {
      const [p] = DeathClaimsService.authorizedParties(will(ClaimInitPolicy.BOTH), '0555000333');
      expect(p).toMatchObject({ role: ClaimRole.HEIR, partyId: 'h1' });
    });
  });

  describe('heir authorisation under each policy', () => {
    it('HEIRS_WITH_DOCUMENTS admits the heir', () => {
      const parties = DeathClaimsService.authorizedParties(
        will(ClaimInitPolicy.HEIRS_WITH_DOCUMENTS),
        '+966555000333',
      );
      expect(parties.map((p) => p.role)).toEqual([ClaimRole.HEIR]);
    });

    it('HEIRS_WITH_DOCUMENTS admits the witness too', () => {
      const parties = DeathClaimsService.authorizedParties(
        will(ClaimInitPolicy.HEIRS_WITH_DOCUMENTS),
        '+966555000111',
      );
      expect(parties.map((p) => p.role)).toEqual([ClaimRole.WITNESS]);
    });

    it('HEIRS_WITH_DOCUMENTS excludes the trustee', () => {
      expect(
        DeathClaimsService.authorizedParties(will(ClaimInitPolicy.HEIRS_WITH_DOCUMENTS), '+966555000222'),
      ).toEqual([]);
    });

    it('TRUSTEE_ONLY excludes the heir', () => {
      expect(DeathClaimsService.authorizedParties(will(ClaimInitPolicy.TRUSTEE_ONLY), '+966555000333')).toEqual([]);
    });

    it('TRUSTEE_ONLY excludes the witness', () => {
      expect(DeathClaimsService.authorizedParties(will(ClaimInitPolicy.TRUSTEE_ONLY), '+966555000111')).toEqual([]);
    });

    it('TRUSTEE_ONLY admits the trustee', () => {
      const parties = DeathClaimsService.authorizedParties(will(ClaimInitPolicy.TRUSTEE_ONLY), '+966555000222');
      expect(parties.map((p) => p.role)).toEqual([ClaimRole.TRUSTEE]);
    });

    it('BOTH admits every role', () => {
      for (const [contact, role] of [
        ['+966555000111', ClaimRole.WITNESS],
        ['+966555000222', ClaimRole.TRUSTEE],
        ['+966555000333', ClaimRole.HEIR],
      ] as const) {
        expect(DeathClaimsService.authorizedParties(will(ClaimInitPolicy.BOTH), contact).map((p) => p.role)).toEqual([
          role,
        ]);
      }
    });
  });

  describe('rejects what it should', () => {
    it('returns nothing for a stranger', () => {
      expect(DeathClaimsService.authorizedParties(will(ClaimInitPolicy.BOTH), '+15550001111')).toEqual([]);
      expect(DeathClaimsService.authorizedParties(will(ClaimInitPolicy.BOTH), 'stranger@x.com')).toEqual([]);
    });

    it('returns nothing for an empty contact, rather than matching a blank field', () => {
      expect(DeathClaimsService.authorizedParties(will(ClaimInitPolicy.BOTH), '')).toEqual([]);
      expect(DeathClaimsService.authorizedParties(will(ClaimInitPolicy.BOTH), '   ')).toEqual([]);
    });

    // A null phone on an heir row must not match a caller who supplied nothing useful.
    it('does not let a null field on the roster match anything', () => {
      const w = will(ClaimInitPolicy.BOTH);
      const parties = DeathClaimsService.authorizedParties(w, 'nobody@x.com');
      expect(parties).toEqual([]);
    });
  });

  // One person can be both a witness and an heir. The claim path should see both, not
  // silently pick one — the old single-role return could drop the eligible one and
  // reject a person the policy admits.
  it('returns EVERY role a contact holds, not just the first', () => {
    const w = will(ClaimInitPolicy.BOTH);
    w.heirContacts.push({ id: 'h3', phone: '+966555000111', email: null }); // same phone as w1
    const parties = DeathClaimsService.authorizedParties(w, '+966555000111');
    expect(parties.map((p) => p.role).sort()).toEqual([ClaimRole.HEIR, ClaimRole.WITNESS]);
  });
});
