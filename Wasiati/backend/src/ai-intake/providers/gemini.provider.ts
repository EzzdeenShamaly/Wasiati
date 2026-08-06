import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  AiCompletionRequest,
  AiProviderPort,
  AiReply,
  AiToolSpec,
} from '../ai-provider.interface';

/** Google's Generative Language REST surface. Overridable for tests/proxies. */
const DEFAULT_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta';
const DEFAULT_MODEL = 'gemini-2.5-flash';
/** A model call should not outlive the app's own 20s client receive timeout by much. */
const REQUEST_TIMEOUT_MS = 30_000;

/**
 * Ameen on Gemini (owner, 24 Jul 2026: Claude's API was too expensive for this
 * feature's volume). Raw `fetch` rather than the SDK, matching how every other
 * outbound integration in this codebase is written.
 *
 * Three shape differences from the Anthropic path this replaced, all absorbed here
 * so nothing above the port has to know:
 *
 *  - the assistant role is called `model`, not `assistant`;
 *  - the system prompt is its own `system_instruction`, not a top-level string;
 *  - a tool is a `function_declarations` entry and its arguments come back as
 *    `functionCall.args` (already an object — unlike OpenAI, no JSON string to parse).
 */
@Injectable()
export class GeminiAiProvider implements AiProviderPort {
  readonly name = 'Gemini';

  constructor(private config: ConfigService) {}

  private get apiKey(): string {
    return this.config.get<string>('GEMINI_API_KEY') ?? '';
  }

  get configured(): boolean {
    return this.apiKey.length > 0;
  }

  private get model(): string {
    return this.config.get<string>('GEMINI_MODEL') || DEFAULT_MODEL;
  }

  private get baseUrl(): string {
    return (this.config.get<string>('GEMINI_BASE_URL') || DEFAULT_BASE_URL).replace(/\/+$/, '');
  }

  /**
   * Gemini's `parameters` is an OpenAPI-3 subset. The tool schema this app uses —
   * object/array/string/number/boolean with `enum`, `items` and `required` — is
   * inside that subset, so it passes through as-is. `$schema`/`additionalProperties`
   * would not be, hence the strip.
   */
  private toFunctionDeclaration(tool: AiToolSpec) {
    const { $schema, additionalProperties, ...parameters } = tool.parameters as any;
    return { name: tool.name, description: tool.description, parameters };
  }

  async complete(req: AiCompletionRequest): Promise<AiReply> {
    if (!this.configured) {
      throw new ServiceUnavailableException('AI intake is not configured on this server (missing GEMINI_API_KEY).');
    }

    // An empty conversation still needs an opening user turn to answer.
    const turns = req.turns.length ? req.turns : [{ role: 'user' as const, text: 'Hi' }];
    const body = {
      system_instruction: { parts: [{ text: req.system }] },
      contents: turns.map((t) => ({
        role: t.role === 'assistant' ? 'model' : 'user',
        parts: [{ text: t.text }],
      })),
      tools: [{ function_declarations: [this.toFunctionDeclaration(req.tool)] }],
      // AUTO, not ANY. Forcing the call every turn would be the obvious reading of
      // "enforce structured output", but it also forbids the model from asking a
      // clarifying question without inventing values to report — and this intake needs
      // clarifying questions ("your brother's son, or your son's brother?"). So the
      // call stays optional and the caller keeps the previous extraction on a turn that
      // is only prose. The values themselves are constrained by the declaration, and
      // clamped again server-side, which is where enforcement actually belongs.
      tool_config: { function_calling_config: { mode: 'AUTO' } },
      generationConfig: {
        maxOutputTokens: req.maxOutputTokens ?? 1024,
        // gemini-2.5-flash THINKS by default, thinking tokens are billed as output
        // AND count against maxOutputTokens. Left on, a complex turn can spend the
        // whole budget reasoning and return a candidate with no text at all
        // (finishReason MAX_TOKENS) — Ameen answering with silence — while roughly
        // doubling output spend. This intake is enum extraction with a fixed tool;
        // it does not need chain-of-thought.
        thinkingConfig: { thinkingBudget: 0 },
      },
    };

    // The old code had no timeout at all, so a hung provider held the request open
    // until something upstream gave up.
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), REQUEST_TIMEOUT_MS);

    let data: any;
    try {
      const res = await fetch(`${this.baseUrl}/models/${this.model}:generateContent`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': this.apiKey },
        body: JSON.stringify(body),
        signal: abort.signal,
      });
      if (!res.ok) {
        const detail = await res.text().catch(() => '');
        // 429/503 from the provider is transient and worth saying so; the caller
        // maps a plain 503 to "not configured", which would be the wrong story.
        const transient = res.status === 429 || res.status >= 500;
        throw new ServiceUnavailableException(
          transient
            ? 'Ameen is busy right now. Please try again in a moment.'
            : `AI provider error (${res.status}). ${detail.slice(0, 200)}`,
        );
      }
      data = await res.json();
    } catch (err) {
      if (err instanceof ServiceUnavailableException) throw err;
      if ((err as any)?.name === 'AbortError') {
        throw new ServiceUnavailableException('Ameen took too long to answer. Please try again.');
      }
      throw new ServiceUnavailableException('Could not reach the AI provider. Please try again.');
    } finally {
      clearTimeout(timer);
    }

    const candidate = data?.candidates?.[0];
    const parts: any[] = candidate?.content?.parts ?? [];
    const text = parts
      .filter((p) => typeof p?.text === 'string')
      .map((p) => p.text)
      .join('\n')
      .trim();
    const call = parts.find((p) => p?.functionCall)?.functionCall;
    const toolInput =
      call && call.name === req.tool.name && call.args && typeof call.args === 'object'
        ? (call.args as Record<string, any>)
        : null;

    // A turn that produced NEITHER prose NOR a tool call is a failed generation, not
    // an answer — the classic case is MAX_TOKENS eating the whole budget (which the
    // thinkingBudget above mostly prevents, but a runaway function-call arg can still
    // hit it). Silently returning '' here made Ameen reply with an empty bubble;
    // surfacing it as transient lets the user simply try again.
    if (!text && !toolInput) {
      throw new ServiceUnavailableException(
        candidate?.finishReason === 'MAX_TOKENS'
          ? 'Ameen ran out of room for that answer. Please try again.'
          : 'Ameen could not answer that. Please try again.',
      );
    }

    // Gemini reports this on every response. It is the only spend signal the feature
    // has, and it used to be thrown away.
    const u = data?.usageMetadata;
    const usage =
      u && typeof u.promptTokenCount === 'number'
        ? { inputTokens: u.promptTokenCount, outputTokens: u.candidatesTokenCount ?? 0 }
        : undefined;

    return { text, toolInput, ...(usage ? { usage } : {}) };
  }
}
