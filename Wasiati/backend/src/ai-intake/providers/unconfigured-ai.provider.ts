import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { AiCompletionRequest, AiProviderPort, AiReply } from '../ai-provider.interface';

/**
 * The adapter used when no AI key is set: refuses with a clean 503 rather than
 * pretending. Same shape as `UnconfiguredStorageProvider` / `UnconfiguredIdentityProvider`
 * — the alternative is a half-wired call that fails somewhere less obvious.
 *
 * The app already has a screen for this: a 503 on `/ai-intake/start` renders the
 * "AI intake isn't switched on for this server yet" view with a link to the manual
 * form, so the feature degrades to the guided flow rather than to an error.
 */
@Injectable()
export class UnconfiguredAiProvider implements AiProviderPort {
  readonly name = 'Unconfigured';
  readonly configured = false;

  async complete(_req: AiCompletionRequest): Promise<AiReply> {
    throw new ServiceUnavailableException('AI intake is not configured on this server (missing GEMINI_API_KEY).');
  }
}
