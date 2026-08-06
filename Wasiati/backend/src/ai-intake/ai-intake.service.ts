import { Inject, Injectable, ForbiddenException, Logger, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { AI_PROVIDER, AiProviderPort, AiTurn } from './ai-provider.interface';
import { INTAKE_TOOL, IntakeSeed, hasAnyHeir, normalizeSeed } from './intake-schema';

/**
 * Ameen — the conversational way into the will.
 *
 * What Ameen is FOR: letting someone describe their family in their own words instead
 * of working a form. What it is NOT for: building a will. It collects, the wizard
 * builds. `finalize()` hands the wizard a seed and stops; it creates nothing.
 *
 * That division is the whole design, and it is what keeps the two paths honest:
 *
 *  - the will is created by the FORM, through the same endpoint a typed user hits, so
 *    the disclaimer is accepted by the user, the madhhab is their choice, and every
 *    DTO validator runs. Ameen previously called `wills.create()` directly and so
 *    recorded a legal disclaimer nobody had agreed to;
 *  - the heir set is derived by the FORM from counters, so the ḥijb rules (no
 *    grandfather beside a living father) are applied once, in the place that already
 *    knows them;
 *  - anything Ameen captures is something a user could have clicked, because the
 *    extraction target IS the form's own field vocabulary (see intake-schema.ts).
 *
 * Voice input is on the client (native OS speech-to-text); by the time text arrives
 * here it is plain text, dictated or typed alike. Which model answers is behind
 * `AiProviderPort` — Gemini today.
 */

/**
 * A conversation that has not converged by here is looping, and every turn re-sends
 * the whole transcript, so cost grows with the square of the turn count. The wizard is
 * always one tap away, which makes stopping cheap.
 */
export const MAX_TURNS = 30;

@Injectable()
export class AiIntakeService {
  private readonly logger = new Logger(AiIntakeService.name);

  constructor(
    @Inject(AI_PROVIDER) private ai: AiProviderPort,
    private prisma: PrismaService,
  ) {}

  private systemPrompt(region: string) {
    return [
      "You are Ameen, Wasiati's intake assistant. You are gathering the facts a Sharia will needs, in a warm, plain conversation — one question at a time, never a form read aloud.",
      'Your ONLY job is to establish who in the family is living: the testator (male or female), spouse, sons, daughters, parents, and — only if relevant — grandparents, siblings, uncles and cousins. Ask for COUNTS, not names; names are collected later in the app.',
      'Call record_will_intake_data on every turn with the complete running picture, not just the newest detail. If someone corrects themselves, send the corrected totals.',
      'When a family member is mentioned ambiguously, ask a short clarifying question before recording — "your brother\'s son" and "your son\'s brother" are different people with different shares.',
      `The user is in ${region}. Keep the conversation to the family; if they ask about assets, funeral wishes or anything else, tell them the app will walk them through it after this step, and return to the question you asked.`,
      'You do not give legal or religious rulings, and you never state what someone will inherit — the app computes the shares. If asked, say that plainly and move on.',
      'When the family picture is complete, read it back in one short summary and ask them to confirm. Only once they confirm, set readyToFinalize to true.',
    ].join(' ');
  }

  async startSession(userId: string, region: string) {
    const session = await this.prisma.intakeSession.create({ data: { userId, transcript: [] } });
    return this.sendTurn(session.id, userId, region, null);
  }

  async continueSession(sessionId: string, userId: string, region: string, userMessage: string) {
    return this.sendTurn(sessionId, userId, region, userMessage);
  }

  /** Loads a session and confirms it belongs to the caller (NotFound otherwise). */
  private async loadOwned(sessionId: string, userId: string) {
    const session = await this.prisma.intakeSession.findUnique({ where: { id: sessionId } });
    if (!session || session.userId !== userId) throw new NotFoundException('Intake session not found.');
    return session;
  }

  /**
   * Reads a stored transcript into neutral turns. Tolerant of older rows that held a
   * provider's content-block array, so a resumed conversation never throws.
   */
  private toTurns(stored: unknown): AiTurn[] {
    if (!Array.isArray(stored)) return [];
    const turns: AiTurn[] = [];
    for (const entry of stored) {
      if (!entry || typeof entry !== 'object') continue;
      const { role, content } = entry as { role?: unknown; content?: unknown };
      const text =
        typeof content === 'string'
          ? content
          : Array.isArray(content)
            ? content
                .filter((b: any) => b?.type === 'text' && typeof b.text === 'string')
                .map((b: any) => b.text)
                .join('\n')
            : '';
      if (!text.trim()) continue;
      turns.push({ role: role === 'assistant' ? 'assistant' : 'user', text });
    }
    return turns;
  }

  private async sendTurn(sessionId: string, userId: string, region: string, userMessage: string | null) {
    const session = await this.loadOwned(sessionId, userId);
    if (session.completed) throw new ForbiddenException('This intake session is already complete.');

    const turns = this.toTurns(session.transcript);
    // Circuit breaker. Without one, a conversation that never converges bills for a
    // transcript that grows every turn, and the user has no signal that it is stuck.
    if (turns.length >= MAX_TURNS * 2) {
      throw new ForbiddenException(
        'This conversation has gone on longer than expected. Continue in the guided form — everything captured so far is kept.',
      );
    }
    if (userMessage) turns.push({ role: 'user', text: userMessage });

    const reply = await this.ai.complete({
      system: this.systemPrompt(region),
      turns,
      tool: INTAKE_TOOL,
      maxOutputTokens: 512, // replies are a sentence or two; the cap is a cost bound
    });

    if (reply.usage) {
      // The only record of what Ameen costs. Gemini returns this on every response and
      // it was previously discarded, so the feature had no observable spend at all.
      this.logger.log(
        `intake ${sessionId} turn ${Math.ceil(turns.length / 2)} — in ${reply.usage.inputTokens} / out ${reply.usage.outputTokens} tokens`,
      );
    }

    // Persisted as {role, content: plain string} — provider-neutral, and the shape the
    // app's resume view already reads.
    const transcript = [...turns, { role: 'assistant' as const, text: reply.text }].map((t) => ({
      role: t.role,
      content: t.text,
    }));

    const prior = (session.extractedData as unknown as IntakeSeed) ?? undefined;
    // No tool call this turn (a clarifying question, say) keeps what we already had.
    const seed = reply.toolInput ? normalizeSeed(reply.toolInput, prior) : (prior ?? normalizeSeed(null));
    // The model saying "done" is a suggestion, not proof: refuse to call a session
    // complete while it holds no heir at all.
    const completed = !!seed.readyToFinalize && hasAnyHeir(seed);

    await this.prisma.intakeSession.update({
      where: { id: sessionId },
      data: { transcript, extractedData: seed as any, completed },
    });

    return { sessionId, reply: reply.text, extractedData: seed, completed };
  }

  async getSession(sessionId: string, userId: string) {
    return this.loadOwned(sessionId, userId);
  }

  /**
   * Hands the conversation to the guided form. Creates NOTHING.
   *
   * Returns the captured family as the `draftState` vocabulary the wizard restores
   * from, so the client can open the form pre-filled on step 1. The user then sees
   * every value, can change any of it, chooses their madhhab, accepts the disclaimer
   * and continues through witnesses, assets and review exactly as a typed user does —
   * and the will is created by the form's own save, not by us.
   *
   * Marked `seededWillId` once handed over so one conversation cannot seed two wills.
   */
  async finalize(sessionId: string, userId: string) {
    const session = await this.loadOwned(sessionId, userId);
    const seed = (session.extractedData as unknown as IntakeSeed) ?? normalizeSeed(null);

    if (seed.seededWillId) {
      throw new ForbiddenException('This conversation has already been carried into a will.');
    }
    if (!hasAnyHeir(seed)) {
      throw new ForbiddenException(
        'No family members were captured yet — keep talking to Ameen, or start the guided form directly.',
      );
    }

    await this.prisma.intakeSession.update({
      where: { id: sessionId },
      data: { completed: true },
    });

    // Re-normalized on the way out: this is the value that seeds the form, so it is
    // clamped at the boundary rather than trusted from storage.
    const { readyToFinalize, seededWillId, ...draft } = normalizeSeed(seed as any, seed);
    return { sessionId, seed: draft };
  }

  /** Records which will a seeded conversation became, once the form has saved it. */
  async markSeeded(sessionId: string, userId: string, willId: string) {
    const session = await this.loadOwned(sessionId, userId);
    const seed = (session.extractedData as unknown as IntakeSeed) ?? normalizeSeed(null);
    await this.prisma.intakeSession.update({
      where: { id: sessionId },
      data: { extractedData: { ...seed, seededWillId: willId } as any, completed: true },
    });
    return { ok: true };
  }
}
