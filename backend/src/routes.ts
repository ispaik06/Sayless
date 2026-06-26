import type { FastifyInstance } from 'fastify';
import { ZodError } from 'zod';
import { config } from './config.js';
import { createMockSuggestions } from './mockSuggestions.js';
import { createOpenAISuggestions } from './openaiSuggestions.js';
import { SuggestionRequestSchema } from './schemas.js';

function elapsedMs(startedAt: bigint): number {
  return Number(process.hrtime.bigint() - startedAt) / 1_000_000;
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

      request.log.error(
        {
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
