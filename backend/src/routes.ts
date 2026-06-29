import type { FastifyInstance } from 'fastify';
import { ZodError } from 'zod';
import { requireAuth } from './auth.js';
import { config } from './config.js';
import { ensureUserForClerkId, getAccountStatus, recordAIUsageEvent } from './db/accounts.js';
import { createMockSuggestions } from './mockSuggestions.js';
import { InvalidAIResponseError, UnsafeSuggestionGuardError, createAISuggestionsWithUsage } from './openaiSuggestions.js';
import { SuggestionRequestSchema } from './schemas.js';

function elapsedMs(startedAt: bigint): number {
  return Number(process.hrtime.bigint() - startedAt) / 1_000_000;
}

function readSingleHeader(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function isAIConfigurationError(error: unknown): boolean {
  return error instanceof Error && /(?:OPENAI|GEMINI|GROQ|AI_PROVIDER|API key|API_KEY)/i.test(error.message);
}

function isAIRequestError(error: unknown): boolean {
  if (error instanceof InvalidAIResponseError) {
    return true;
  }

  if (!(error instanceof Error)) {
    return false;
  }

  const maybeOpenAIError = error as Error & {
    status?: number;
    code?: string;
    type?: string;
  };

  return Boolean(maybeOpenAIError.status || maybeOpenAIError.code || maybeOpenAIError.type);
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
    service: 'sayless-backend',
    provider: config.suggestionProvider,
    model: config.aiModel
  }));

  app.get('/auth/config', async (_request, reply) => {
    if (!config.clerkPublishableKey) {
      return reply.code(500).send({
        error: 'configuration_error',
        message: 'Clerk publishable key is not configured'
      });
    }

    return {
      clerkPublishableKey: config.clerkPublishableKey
    };
  });

  app.get('/me', async (request, reply) => {
    const auth = requireAuth(request, reply);
    if (!auth) {
      return reply;
    }

    return getAccountStatus(auth.clerkUserId);
  });

  app.post('/suggestions', async (request, reply) => {
    const startedAt = process.hrtime.bigint();

    try {
      const auth = requireAuth(request, reply);
      if (!auth) {
        return reply;
      }

      if (config.saylessClientKey) {
        const clientKey = readSingleHeader(request.headers['x-sayless-client-key']);

        if (clientKey !== config.saylessClientKey) {
          request.log.warn(
            {
              clientKeyPresent: Boolean(clientKey),
              elapsedMs: Math.round(elapsedMs(startedAt))
            },
            'suggestions unauthorized'
          );

          return reply.code(401).send({
            error: 'unauthorized',
            message: 'Invalid Sayless client key'
          });
        }
      }

      const input = SuggestionRequestSchema.parse(request.body);
      const user = await ensureUserForClerkId(auth.clerkUserId);
      const result =
        config.suggestionProvider !== 'mock'
          ? await createAISuggestionsWithUsage(input)
          : {
              suggestions: createMockSuggestions(input),
              usage: []
            };
      const usageTotals = aggregateUsage(result.usage);

      await recordAIUsageEvent({
        userId: user.id,
        provider: config.suggestionProvider,
        model: config.aiModel,
        inputTokens: usageTotals.inputTokens,
        outputTokens: usageTotals.outputTokens,
        totalTokens: usageTotals.totalTokens,
        latencyMs: usageTotals.latencyMs,
        metadata: {
          chatRoomPresent: Boolean(input.chatRoom),
          participantCount: input.chatRoom?.participantCount ?? null,
          draftTextPresent: Boolean(input.draftText),
          activeSuggestionsPresent: Boolean(input.activeSuggestions),
          intent: input.intent?.kind ?? 'initial',
          refreshIndex: input.intent?.refreshIndex ?? null,
          messageCount: input.messages.length,
          attempts: result.usage.map((item) => ({
            attempt: item.attempt,
            usagePresent: item.usagePresent,
            totalTokens: item.totalTokens,
            latencyMs: Math.round(item.latencyMs)
          }))
        }
      });

      request.log.info(
        {
          chatRoomPresent: Boolean(input.chatRoom),
          participantCount: input.chatRoom?.participantCount ?? null,
          draftTextPresent: Boolean(input.draftText),
          activeSuggestionsPresent: Boolean(input.activeSuggestions),
          intent: input.intent?.kind ?? 'initial',
          refreshIndex: input.intent?.refreshIndex ?? null,
          messageCount: input.messages.length,
          clerkUserId: auth.clerkUserId,
          provider: config.suggestionProvider,
          model: config.aiModel,
          inputTokens: usageTotals.inputTokens,
          outputTokens: usageTotals.outputTokens,
          totalTokens: usageTotals.totalTokens,
          elapsedMs: Math.round(elapsedMs(startedAt))
        },
        'suggestions generated'
      );

      return result.suggestions;
    } catch (error) {
      if (error instanceof ZodError) {
        request.log.warn(
          {
            issues: error.issues.map((issue) => ({
              path: issue.path.join('.'),
              message: issue.message
            })),
            elapsedMs: Math.round(elapsedMs(startedAt))
          },
          'suggestions invalid request'
        );

        return reply.code(400).send({
          error: 'invalid_request',
          details: error.issues.map((issue) => ({
            path: issue.path.join('.'),
            message: issue.message
          }))
        });
      }

      if (isAIConfigurationError(error)) {
        request.log.error(
          {
            error: loggableError(error),
            elapsedMs: Math.round(elapsedMs(startedAt))
          },
          'suggestions configuration error'
        );

        return reply.code(500).send({
          error: 'configuration_error',
          message: 'Suggestion service is not configured'
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
        isAIRequestError(error) ? 'suggestions ai request failed' : 'suggestions failed'
      );

      return reply.code(isAIRequestError(error) ? 502 : 500).send({
        error: isAIRequestError(error) ? 'ai_request_failed' : 'suggestions_failed',
        message: 'Suggestion generation failed'
      });
    }
  });
}

function aggregateUsage(
  usage: Array<{
    inputTokens: number;
    outputTokens: number;
    totalTokens: number;
    latencyMs: number;
  }>
) {
  return usage.reduce(
    (totals, item) => ({
      inputTokens: totals.inputTokens + item.inputTokens,
      outputTokens: totals.outputTokens + item.outputTokens,
      totalTokens: totals.totalTokens + item.totalTokens,
      latencyMs: totals.latencyMs + item.latencyMs
    }),
    {
      inputTokens: 0,
      outputTokens: 0,
      totalTokens: 0,
      latencyMs: 0
    }
  );
}
