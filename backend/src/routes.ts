import type { FastifyInstance } from 'fastify';
import { ZodError } from 'zod';
import { config } from './config.js';
import { createMockSuggestions } from './mockSuggestions.js';
import { UnsafeSuggestionGuardError, createOpenAISuggestions } from './openaiSuggestions.js';
import { SuggestionRequestSchema } from './schemas.js';

function elapsedMs(startedAt: bigint): number {
  return Number(process.hrtime.bigint() - startedAt) / 1_000_000;
}

function loggableError(error: unknown): Record<string, unknown> {
  if (!(error instanceof Error)) {
    return {
      message: 'unknown error',
      valueType: typeof error
    };
  }

  const maybeOpenAIError = error as Error & {
    status?: number;
    code?: string;
    type?: string;
    param?: string;
  };

  return {
    name: error.name,
    message: error.message,
    status: maybeOpenAIError.status,
    code: maybeOpenAIError.code,
    type: maybeOpenAIError.type,
    param: maybeOpenAIError.param,
    stack: process.env.NODE_ENV === 'development' ? error.stack : undefined
  };
}

export async function registerRoutes(app: FastifyInstance): Promise<void> {
  app.get('/health', async () => ({
    ok: true,
    mode: config.suggestionMode
  }));

  app.post('/suggestions', async (request, reply) => {
    const startedAt = process.hrtime.bigint();

    try {
      const input = SuggestionRequestSchema.parse(request.body);
      const result =
        config.suggestionMode === 'openai'
          ? await createOpenAISuggestions(input)
          : createMockSuggestions(input);

      request.log.info(
        {
          chatRoomPresent: Boolean(input.chatRoom),
          participantCount: input.chatRoom?.participantCount ?? null,
          draftTextPresent: Boolean(input.draftText),
          activeSuggestionsPresent: Boolean(input.activeSuggestions),
          intent: input.intent?.kind ?? 'initial',
          refreshIndex: input.intent?.refreshIndex ?? null,
          messageCount: input.messages.length,
          mode: config.suggestionMode,
          elapsedMs: Math.round(elapsedMs(startedAt))
        },
        'suggestions generated'
      );

      return result;
    } catch (error) {
      if (error instanceof ZodError) {
        return reply.code(400).send({
          error: 'invalid_request',
          details: error.issues.map((issue) => ({
            path: issue.path.join('.'),
            message: issue.message
          }))
        });
      }

      if (error instanceof UnsafeSuggestionGuardError) {
        return reply.code(422).send({
          error: 'unsafe_suggestions',
          message: '추천 생성 실패: 대화 당사자 판단이 불확실합니다'
        });
      }

      request.log.error(
        {
          error: loggableError(error),
          elapsedMs: Math.round(elapsedMs(startedAt))
        },
        'suggestions failed'
      );

      return reply.code(500).send({
        error: 'suggestions_failed'
      });
    }
  });
}
