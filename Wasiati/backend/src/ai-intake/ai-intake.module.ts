import { Logger, Module } from '@nestjs/common';
import { AiIntakeService } from './ai-intake.service';
import { AiIntakeController } from './ai-intake.controller';
import { AI_PROVIDER } from './ai-provider.interface';
import { GeminiAiProvider } from './providers/gemini.provider';
import { UnconfiguredAiProvider } from './providers/unconfigured-ai.provider';

// No WillsModule / AssetsModule any more: Ameen collects, the guided form builds.
// This module can no longer create a will even by accident, which is the point.
@Module({
  imports: [],
  controllers: [AiIntakeController],
  providers: [
    AiIntakeService,
    GeminiAiProvider,
    UnconfiguredAiProvider,
    {
      provide: AI_PROVIDER,
      inject: [GeminiAiProvider, UnconfiguredAiProvider],
      // Gemini when a key is configured; otherwise the adapter that refuses with a
      // clean 503 — never one that pretends to answer. Same shape as the storage
      // and identity providers, and it logs which one is live so a misconfigured
      // deploy is visible at boot rather than at the first user's first message.
      useFactory: (gemini: GeminiAiProvider, unconfigured: UnconfiguredAiProvider) => {
        if (gemini.configured) {
          Logger.log('Ameen AI: Gemini', 'AiIntakeModule');
          return gemini;
        }
        Logger.warn(
          'Ameen AI: NOT CONFIGURED — /ai-intake returns 503 and the app falls back to the guided form. Set GEMINI_API_KEY.',
          'AiIntakeModule',
        );
        return unconfigured;
      },
    },
  ],
  exports: [AiIntakeService],
})
export class AiIntakeModule {}
