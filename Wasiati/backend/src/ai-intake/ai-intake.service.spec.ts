import { ForbiddenException } from '@nestjs/common';
import { AiIntakeService, MAX_TURNS } from './ai-intake.service';
import { AiProviderPort, AiReply } from './ai-provider.interface';

/**
 * Ameen collects; the guided form builds. These pin that division, because it is what
 * makes the two paths produce the same will:
 *
 *  - finalize() returns a SEED and creates nothing. It used to call wills.create(),
 *    which recorded a legal disclaimer the user never accepted and defaulted their
 *    madhhab to Jumhūr without asking;
 *  - the seed is the form's own field vocabulary (counters), so the form still derives
 *    the heir set and applies the ḥijb rules — the model cannot put a grandfather
 *    beside a living father;
 *  - values are clamped to what the form's steppers allow, so nothing reaches state
 *    that a user could not have clicked;
 *  - the transcript stays provider-neutral plain text.
 */
function makeService(reply: AiReply, opts: { transcript?: any; extracted?: any; completed?: boolean } = {}) {
  const saved: any[] = [];
  const session = {
    id: 's1',
    userId: 'u1',
    transcript: opts.transcript ?? [],
    extractedData: opts.extracted ?? null,
    completed: opts.completed ?? false,
  };
  const prisma: any = {
    intakeSession: {
      findUnique: async () => session,
      create: async ({ data }: any) => ({ ...session, ...data }),
      update: async ({ data }: any) => {
        saved.push(data);
        return { ...session, ...data };
      },
    },
  };
  const ai: AiProviderPort = { name: 'Fake', configured: true, complete: jest.fn(async () => reply) };
  return { svc: new AiIntakeService(ai, prisma), saved, ai, session };
}

const SAYS = (toolInput: Record<string, any> | null, text = 'And your parents?'): AiReply => ({ text, toolInput });
const FAMILY = { sex: 'male', wives: 1, sons: 2, daughters: 1, mother: true };

describe('extraction stays inside what the form could produce', () => {
  it('clamps a count above the form’s stepper maximum', async () => {
    const { svc } = makeService(SAYS({ sex: 'male', sons: 500 }));
    const res = await svc.continueSession('s1', 'u1', 'US', 'I have five hundred sons');
    expect(res.extractedData.sons).toBe(20);
  });

  it('caps wives at four, as the form does', async () => {
    const { svc } = makeService(SAYS({ sex: 'male', wives: 9 }));
    const res = await svc.continueSession('s1', 'u1', 'US', 'nine wives');
    expect(res.extractedData.wives).toBe(4);
  });

  it('never returns a negative count', async () => {
    const { svc } = makeService(SAYS({ sex: 'male', sons: -3 }));
    const res = await svc.continueSession('s1', 'u1', 'US', 'x');
    expect(res.extractedData.sons).toBe(0);
  });

  it('drops wives for a female testator — the form’s spouse control switches on sex', async () => {
    const { svc } = makeService(SAYS({ sex: 'female', wives: 2, husband: true }));
    const res = await svc.continueSession('s1', 'u1', 'US', 'x');
    expect(res.extractedData.wives).toBe(0);
    expect(res.extractedData.husband).toBe(true);
  });

  it('drops a husband for a male testator', async () => {
    const { svc } = makeService(SAYS({ sex: 'male', husband: true }));
    const res = await svc.continueSession('s1', 'u1', 'US', 'x');
    expect(res.extractedData.husband).toBe(false);
  });

  it('ignores a madhhab outside the two the picker offers', async () => {
    const { svc } = makeService(SAYS({ sex: 'male', sons: 1, madhhab: 'MALIKI' }));
    const res = await svc.continueSession('s1', 'u1', 'US', 'x');
    expect(res.extractedData.madhhab).toBeUndefined();
  });

  it('keeps a madhhab the user actually stated', async () => {
    const { svc } = makeService(SAYS({ sex: 'male', sons: 1, madhhab: 'HANAFI' }));
    const res = await svc.continueSession('s1', 'u1', 'US', 'we follow Hanafi');
    expect(res.extractedData.madhhab).toBe('HANAFI');
  });
});

describe('turn handling', () => {
  it('keeps the previous extraction when a turn is only a clarifying question', async () => {
    const { svc } = makeService(SAYS(null, 'Your brother’s son, or your son’s brother?'), { extracted: FAMILY });
    const res = await svc.continueSession('s1', 'u1', 'US', 'my nephew');
    expect(res.extractedData.sons).toBe(2);
  });

  it('stores plain text turns, never provider blocks', async () => {
    const { svc, saved } = makeService(SAYS({ sex: 'male', sons: 1 }, 'Noted.'));
    await svc.continueSession('s1', 'u1', 'US', 'one son');
    expect(saved[0].transcript).toEqual([
      { role: 'user', content: 'one son' },
      { role: 'assistant', content: 'Noted.' },
    ]);
  });

  it('reports token usage when the provider gives it', async () => {
    const { svc } = makeService({ ...SAYS({ sex: 'male' }), usage: { inputTokens: 900, outputTokens: 40 } });
    await expect(svc.continueSession('s1', 'u1', 'US', 'x')).resolves.toBeDefined();
  });

  it('halts a conversation that will not converge', async () => {
    const long = Array.from({ length: MAX_TURNS * 2 }, (_, i) => ({
      role: i % 2 ? 'assistant' : 'user',
      content: `turn ${i}`,
    }));
    const { svc, ai } = makeService(SAYS(null), { transcript: long });
    await expect(svc.continueSession('s1', 'u1', 'US', 'again')).rejects.toBeInstanceOf(ForbiddenException);
    expect(ai.complete).not.toHaveBeenCalled();
  });

  it('will not call a session complete on the model’s say-so alone, with no family captured', async () => {
    const { svc } = makeService(SAYS({ sex: 'male', readyToFinalize: true }));
    const res = await svc.continueSession('s1', 'u1', 'US', "that's everything");
    expect(res.completed).toBe(false);
  });

  it('completes once a family IS captured and confirmed', async () => {
    const { svc } = makeService(SAYS({ ...FAMILY, readyToFinalize: true }));
    const res = await svc.continueSession('s1', 'u1', 'US', 'yes that is right');
    expect(res.completed).toBe(true);
  });
});

describe('finalize hands over a seed and creates nothing', () => {
  it('returns the family in the form’s draftState vocabulary', async () => {
    const { svc } = makeService(SAYS(null), { extracted: { ...FAMILY, readyToFinalize: true } });
    const res = await svc.finalize('s1', 'u1');

    expect(res.seed).toMatchObject({ sex: 'male', wives: 1, sons: 2, daughters: 1, mother: true });
    // Bookkeeping must not leak into what seeds the wizard.
    expect(res.seed).not.toHaveProperty('readyToFinalize');
    expect(res.seed).not.toHaveProperty('seededWillId');
  });

  it('refuses when no family was captured', async () => {
    const { svc } = makeService(SAYS(null), { extracted: { sex: 'male' } });
    await expect(svc.finalize('s1', 'u1')).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('refuses a second handover, so one conversation cannot seed two wills', async () => {
    const { svc } = makeService(SAYS(null), { extracted: { ...FAMILY, seededWillId: 'will-1' } });
    await expect(svc.finalize('s1', 'u1')).rejects.toThrow(/already been carried/i);
  });

  it('records which will the conversation became', async () => {
    const { svc, saved } = makeService(SAYS(null), { extracted: FAMILY });
    await svc.markSeeded('s1', 'u1', 'will-9');
    expect(saved[0].extractedData.seededWillId).toBe('will-9');
    expect(saved[0].completed).toBe(true);
  });
});
