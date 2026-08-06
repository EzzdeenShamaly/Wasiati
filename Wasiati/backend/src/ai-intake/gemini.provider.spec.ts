import { ServiceUnavailableException } from '@nestjs/common';
import { GeminiAiProvider } from './providers/gemini.provider';
import { UnconfiguredAiProvider } from './providers/unconfigured-ai.provider';
import { AiToolSpec } from './ai-provider.interface';

/**
 * The Gemini adapter is the only place that knows Google's wire format, so this is
 * where that translation gets pinned: `assistant` → `model`, the system prompt as
 * `system_instruction`, the tool as a `function_declarations` entry, and
 * `functionCall.args` read back as the extraction.
 *
 * There was no test of any kind over this module before — which is how the previous
 * provider's broken turn loop (an assistant tool call replayed with no matching
 * tool result, rejected on the second turn) survived unnoticed.
 */
const TOOL: AiToolSpec = {
  name: 'record_will_intake_data',
  description: 'Records the extraction.',
  parameters: {
    type: 'object',
    properties: { readyToFinalize: { type: 'boolean' } },
  },
};

function makeProvider(key = 'test-key', responder?: (body: any) => any) {
  const config: any = {
    get: (k: string) =>
      k === 'GEMINI_API_KEY' ? key : k === 'GEMINI_MODEL' ? 'gemini-2.5-flash' : undefined,
  };
  const calls: { url: string; body: any; headers: any }[] = [];
  global.fetch = jest.fn(async (url: any, init: any) => {
    const body = JSON.parse(init.body);
    calls.push({ url: String(url), body, headers: init.headers });
    const payload = responder
      ? responder(body)
      : { candidates: [{ content: { parts: [{ text: 'Hello, who are your heirs?' }] } }] };
    if (payload.__status) {
      return { ok: false, status: payload.__status, text: async () => 'upstream detail' } as any;
    }
    return { ok: true, status: 200, json: async () => payload } as any;
  }) as any;
  return { provider: new GeminiAiProvider(config), calls };
}

afterEach(() => {
  jest.restoreAllMocks();
});

describe('GeminiAiProvider', () => {
  it('maps an assistant turn to Gemini’s "model" role', async () => {
    const { provider, calls } = makeProvider();
    await provider.complete({
      system: 'sys',
      turns: [
        { role: 'user', text: 'I have two sons' },
        { role: 'assistant', text: 'Noted. Their names?' },
      ],
      tool: TOOL,
    });
    expect(calls[0].body.contents).toEqual([
      { role: 'user', parts: [{ text: 'I have two sons' }] },
      { role: 'model', parts: [{ text: 'Noted. Their names?' }] },
    ]);
  });

  it('sends the system prompt as system_instruction, not as a turn', async () => {
    const { provider, calls } = makeProvider();
    await provider.complete({ system: 'You are Wasiati’s assistant.', turns: [], tool: TOOL });
    expect(calls[0].body.system_instruction).toEqual({ parts: [{ text: 'You are Wasiati’s assistant.' }] });
    expect(JSON.stringify(calls[0].body.contents)).not.toContain('You are Wasiati');
  });

  it('opens an empty conversation with a synthetic user turn', async () => {
    const { provider, calls } = makeProvider();
    await provider.complete({ system: 'sys', turns: [], tool: TOOL });
    expect(calls[0].body.contents).toEqual([{ role: 'user', parts: [{ text: 'Hi' }] }]);
  });

  it('declares the tool as a function_declaration', async () => {
    const { provider, calls } = makeProvider();
    await provider.complete({ system: 'sys', turns: [], tool: TOOL });
    const decl = calls[0].body.tools[0].function_declarations[0];
    expect(decl.name).toBe('record_will_intake_data');
    expect(decl.parameters.properties.readyToFinalize).toEqual({ type: 'boolean' });
  });

  it('authenticates with the x-goog-api-key header', async () => {
    const { provider, calls } = makeProvider('secret-key');
    await provider.complete({ system: 'sys', turns: [], tool: TOOL });
    expect(calls[0].headers['x-goog-api-key']).toBe('secret-key');
    expect(calls[0].url).toContain('gemini-2.5-flash:generateContent');
  });

  it('reads functionCall.args as the extraction', async () => {
    const { provider } = makeProvider('k', () => ({
      candidates: [
        {
          content: {
            parts: [
              { text: 'Got it.' },
              { functionCall: { name: 'record_will_intake_data', args: { readyToFinalize: true } } },
            ],
          },
        },
      ],
    }));
    const reply = await provider.complete({ system: 'sys', turns: [], tool: TOOL });
    expect(reply.text).toBe('Got it.');
    expect(reply.toolInput).toEqual({ readyToFinalize: true });
  });

  it('never accepts a call to some other function as the extraction', async () => {
    // A hallucinated foreign function must not leak into toolInput — and with no
    // prose either, the turn produced nothing a user could see, so it now surfaces
    // as a retryable failure instead of resolving into an empty reply.
    const { provider } = makeProvider('k', () => ({
      candidates: [{ content: { parts: [{ functionCall: { name: 'something_else', args: { x: 1 } } }] } }] ,
    }));
    await expect(provider.complete({ system: 'sys', turns: [], tool: TOOL })).rejects.toThrow(/could not answer/i);
  });

  it('returns toolInput null when the model only spoke', async () => {
    const { provider } = makeProvider();
    const reply = await provider.complete({ system: 'sys', turns: [], tool: TOOL });
    expect(reply.toolInput).toBeNull();
    expect(reply.text).toContain('heirs');
  });

  it('calls a rate limit BUSY, not "not configured" — the app shows different copy for each', async () => {
    const { provider } = makeProvider('k', () => ({ __status: 429 }));
    await expect(provider.complete({ system: 'sys', turns: [], tool: TOOL })).rejects.toThrow(/busy/i);
  });

  it('treats a provider 500 as transient too', async () => {
    const { provider } = makeProvider('k', () => ({ __status: 503 }));
    await expect(provider.complete({ system: 'sys', turns: [], tool: TOOL })).rejects.toThrow(/busy/i);
  });

  it('surfaces a 400 as a real provider error, since retrying will not help', async () => {
    const { provider } = makeProvider('k', () => ({ __status: 400 }));
    await expect(provider.complete({ system: 'sys', turns: [], tool: TOOL })).rejects.toThrow(/AI provider error \(400\)/);
  });

  it('reports unconfigured when no key is set, and never calls out', async () => {
    const { provider, calls } = makeProvider('');
    expect(provider.configured).toBe(false);
    await expect(provider.complete({ system: 'sys', turns: [], tool: TOOL })).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(calls).toHaveLength(0);
  });

  it('disables thinking — billed as output and able to eat the whole token budget', async () => {
    const { provider, calls } = makeProvider();
    await provider.complete({ system: 'sys', turns: [], tool: TOOL });
    expect(calls[0].body.generationConfig.thinkingConfig).toEqual({ thinkingBudget: 0 });
  });

  it('treats an empty candidate as a failed turn, never an empty reply', async () => {
    // The MAX_TOKENS shape: thinking/args consumed the budget, no text, no call.
    const { provider } = makeProvider('k', () => ({
      candidates: [{ content: { parts: [] }, finishReason: 'MAX_TOKENS' }],
    }));
    await expect(provider.complete({ system: 'sys', turns: [], tool: TOOL })).rejects.toThrow(/ran out of room/i);
  });

  it('a tool-call-only turn is a valid answer (no prose required)', async () => {
    const { provider } = makeProvider('k', () => ({
      candidates: [
        { content: { parts: [{ functionCall: { name: 'record_will_intake_data', args: { readyToFinalize: false } } }] } },
      ],
    }));
    const reply = await provider.complete({ system: 'sys', turns: [], tool: TOOL });
    expect(reply.toolInput).toEqual({ readyToFinalize: false });
    expect(reply.text).toBe('');
  });
});

describe('UnconfiguredAiProvider', () => {
  it('refuses cleanly so the app can fall back to the guided form', async () => {
    const p = new UnconfiguredAiProvider();
    expect(p.configured).toBe(false);
    await expect(p.complete({ system: 's', turns: [], tool: TOOL })).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });
});
