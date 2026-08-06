/**
 * The seam between Ameen and whichever model actually answers.
 *
 * The rest of the codebase already works this way — `PaymentProviderPort`,
 * `IdentityProviderPort`, `StorageProviderPort` — and AI was the one integration
 * that never got a port: the Anthropic URL, its auth headers, its request body and
 * its content-block response shape were spread through `AiIntakeService`, and the
 * provider's wire format was even persisted into `IntakeSession.transcript`. That
 * is exactly the coupling the payments port exists to avoid.
 *
 * Everything crossing this boundary is provider-NEUTRAL:
 *
 *  - a turn is `{role, text}`, never a provider's block/part structure, so the
 *    stored transcript survives a provider change and the app keeps rendering it;
 *  - the tool is described in plain JSON Schema, which each adapter translates
 *    into its own dialect (`input_schema` for Anthropic, `function_declarations`
 *    for Gemini);
 *  - the reply is `{text, toolInput}`, so the caller never sees content blocks.
 *
 * A consequence worth stating: because turns carry text only, an adapter never
 * replays a previous tool call back to the model. That is deliberate. The old code
 * pushed the assistant's `tool_use` block into the transcript and then sent the next
 * user turn with no matching `tool_result`, which the Messages API rejects — the
 * intake would break on the second turn. Re-deriving the extraction each turn (the
 * system prompt asks for it cumulatively) is both simpler and provider-portable.
 */

/** One conversational turn, in the only shape this service stores or replays. */
export interface AiTurn {
  role: 'user' | 'assistant';
  text: string;
}

/** A tool the model may call, described in provider-neutral JSON Schema. */
export interface AiToolSpec {
  name: string;
  description: string;
  /** JSON Schema for the tool's arguments (an object schema). */
  parameters: Record<string, any>;
}

export interface AiCompletionRequest {
  system: string;
  turns: AiTurn[];
  tool: AiToolSpec;
  maxOutputTokens?: number;
}

/** Token counts for one call, when the provider reports them. */
export interface AiUsage {
  inputTokens: number;
  outputTokens: number;
}

/** What the caller gets back: prose for the user, plus the tool arguments if called. */
export interface AiReply {
  text: string;
  /** The tool's arguments when the model called it this turn, else null. */
  toolInput: Record<string, any> | null;
  /** Present when the provider reported token usage — the only spend signal we get. */
  usage?: AiUsage;
}

export interface AiProviderPort {
  /** For logs and diagnostics, e.g. 'Gemini'. */
  readonly name: string;
  /** False when no API key is configured — the caller turns this into a clean 503. */
  readonly configured: boolean;
  complete(req: AiCompletionRequest): Promise<AiReply>;
}

/** DI token, mirroring PAYMENT_PROVIDER / IDENTITY_PROVIDER / STORAGE_PROVIDER. */
export const AI_PROVIDER = Symbol('AI_PROVIDER');
