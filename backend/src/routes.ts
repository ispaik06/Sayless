import { ZodError } from 'zod';
import { authenticateRequest, hashIdentifier, type AuthenticatedUser } from './auth.js';
import type { AppConfig } from './config.js';
import type { Database } from './db/client.js';
import { ensureUserForClerkId, getAccountStatus, recordAIUsageEvent } from './db/accounts.js';
import { DownloadReleaseError, fetchLatestDmgAsset } from './downloadRelease.js';
import { createMockSuggestions } from './mockSuggestions.js';
import { InvalidAIResponseError, UnsafeSuggestionGuardError, createAISuggestionsWithUsage } from './openaiSuggestions.js';
import { SuggestionRequestSchema } from './schemas.js';

type RouteContext = {
  config: AppConfig;
  db: Database;
  request: Request;
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization,Content-Type',
  'Access-Control-Max-Age': '86400'
};

function elapsedMs(startedAt: number): number {
  return performance.now() - startedAt;
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

function loggableError(error: unknown, config: AppConfig): Record<string, unknown> {
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
    stack: config.nodeEnv === 'development' ? error.stack : undefined
  };
}

function json(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...corsHeaders,
      ...init.headers
    }
  });
}

function redirect(location: string): Response {
  return new Response(null, {
    status: 302,
    headers: {
      ...corsHeaders,
      'Cache-Control': 'no-store',
      Location: location
    }
  });
}

function notFound(): Response {
  return json(
    {
      error: 'not_found',
      message: 'Route not found'
    },
    { status: 404 }
  );
}

function methodNotAllowed(): Response {
  return json(
    {
      error: 'method_not_allowed',
      message: 'Method not allowed'
    },
    { status: 405 }
  );
}

export async function handleRequest(context: RouteContext): Promise<Response> {
  const { request } = context;
  const url = new URL(request.url);

  if (request.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: corsHeaders
    });
  }

  if (url.pathname === '/health') {
    return request.method === 'GET' ? handleHealth(context) : methodNotAllowed();
  }

  if (url.pathname === '/download') {
    return request.method === 'GET' ? handleDownload(context) : methodNotAllowed();
  }

  if (url.pathname === '/auth/config') {
    return request.method === 'GET' ? handleAuthConfig(context) : methodNotAllowed();
  }

  if (url.pathname === '/me') {
    return request.method === 'GET' ? handleMe(context) : methodNotAllowed();
  }

  if (url.pathname === '/suggestions') {
    return request.method === 'POST' ? handleSuggestions(context) : methodNotAllowed();
  }

  return notFound();
}

type AuthResult =
  | {
      auth: AuthenticatedUser;
    }
  | {
      response: Response;
    };

async function requireAuth(context: RouteContext): Promise<AuthResult> {
  const auth = await authenticateRequest(context.request, context.config);
  if (!auth) {
    return {
      response: json(
        {
          error: 'unauthorized',
          message: 'Authentication required'
        },
        { status: 401 }
      )
    };
  }

  return {
    auth
  };
}

function handleHealth({ config }: RouteContext): Response {
  return json({
    ok: true,
    service: 'sayless-backend',
    provider: config.suggestionProvider,
    model: config.aiModel
  });
}

async function handleDownload({ config }: RouteContext): Promise<Response> {
  try {
    const { tagName, asset } = await fetchLatestDmgAsset({
      owner: config.githubReleaseOwner,
      repo: config.githubReleaseRepo,
      token: config.githubToken
    });

    console.info(
      JSON.stringify({
        event: 'download_redirect',
        repo: `${config.githubReleaseOwner}/${config.githubReleaseRepo}`,
        tagName,
        assetName: asset.name
      })
    );

    return redirect(asset.browser_download_url);
  } catch (error) {
    if (error instanceof DownloadReleaseError) {
      console.warn(
        JSON.stringify({
          event: 'download_redirect_failed',
          code: error.code,
          statusCode: error.statusCode,
          message: error.message
        })
      );

      return json(
        {
          error: error.code,
          message: error.message
        },
        { status: error.statusCode }
      );
    }

    console.error(
      JSON.stringify({
        event: 'download_redirect_failed',
        error: loggableError(error, config)
      })
    );

    return json(
      {
        error: 'download_redirect_failed',
        message: 'Could not resolve latest Sayless DMG download'
      },
      { status: 502 }
    );
  }
}

function handleAuthConfig({ config }: RouteContext): Response {
  if (!config.clerkPublishableKey) {
    return json(
      {
        error: 'configuration_error',
        message: 'Clerk publishable key is not configured'
      },
      { status: 500 }
    );
  }

  return json({
    clerkPublishableKey: config.clerkPublishableKey
  });
}

async function handleMe(context: RouteContext): Promise<Response> {
  const authResult = await requireAuth(context);
  if ('response' in authResult) {
    return authResult.response;
  }

  const accountStatus = await getAccountStatus(context.db, authResult.auth.clerkUserId);

  return json({
    ...accountStatus,
    limits: {
      dailySuggestions: context.config.freeDailySuggestionLimit,
      weeklySuggestions: context.config.freeWeeklySuggestionLimit
    }
  });
}

async function handleSuggestions(context: RouteContext): Promise<Response> {
  const startedAt = performance.now();
  const { config, db, request } = context;

  try {
    const authResult = await requireAuth(context);
    if ('response' in authResult) {
      return authResult.response;
    }

    const input = SuggestionRequestSchema.parse(await request.json());
    const userHash = await hashIdentifier(authResult.auth.clerkUserId);
    const user = await ensureUserForClerkId(db, authResult.auth.clerkUserId);
    const accountStatus = await getAccountStatus(db, authResult.auth.clerkUserId);
    const exceededLimit = freeUsageLimitExceeded(config, accountStatus.usage);

    if (accountStatus.plan === 'free' && exceededLimit) {
      console.warn(
        JSON.stringify({
          event: 'suggestions_usage_limit_exceeded',
          userHash,
          scope: exceededLimit.scope,
          usageRequests: exceededLimit.requests,
          freeSuggestionLimit: exceededLimit.limit,
          elapsedMs: Math.round(elapsedMs(startedAt))
        })
      );

      return json(
        {
          error: 'usage_limit_exceeded',
          message: exceededLimit.message,
          plan: accountStatus.plan,
          scope: exceededLimit.scope,
          usage: accountStatus.usage,
          limit: exceededLimit.limit
        },
        { status: 402 }
      );
    }

    const result =
      config.suggestionProvider !== 'mock'
        ? await createAISuggestionsWithUsage(config, input)
        : {
            suggestions: createMockSuggestions(input),
            usage: []
          };
    const usageTotals = aggregateUsage(result.usage);

    await recordAIUsageEvent(db, {
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

    console.info(
      JSON.stringify({
        event: 'suggestions_generated',
        chatRoomPresent: Boolean(input.chatRoom),
        participantCount: input.chatRoom?.participantCount ?? null,
        draftTextPresent: Boolean(input.draftText),
        activeSuggestionsPresent: Boolean(input.activeSuggestions),
        intent: input.intent?.kind ?? 'initial',
        refreshIndex: input.intent?.refreshIndex ?? null,
        messageCount: input.messages.length,
        userHash,
        provider: config.suggestionProvider,
        model: config.aiModel,
        plan: accountStatus.plan,
        freeDailySuggestionLimit: config.freeDailySuggestionLimit,
        freeWeeklySuggestionLimit: config.freeWeeklySuggestionLimit,
        inputTokens: usageTotals.inputTokens,
        outputTokens: usageTotals.outputTokens,
        totalTokens: usageTotals.totalTokens,
        elapsedMs: Math.round(elapsedMs(startedAt))
      })
    );

    return json(result.suggestions);
  } catch (error) {
    if (error instanceof ZodError || error instanceof SyntaxError) {
      const details =
        error instanceof ZodError
          ? error.issues.map((issue) => ({
              path: issue.path.join('.'),
              message: issue.message
            }))
          : undefined;

      console.warn(
        JSON.stringify({
          event: 'suggestions_invalid_request',
          details,
          elapsedMs: Math.round(elapsedMs(startedAt))
        })
      );

      return json(
        {
          error: 'invalid_request',
          message: 'Suggestion request was too large or malformed',
          details
        },
        { status: 400 }
      );
    }

    if (isAIConfigurationError(error)) {
      console.error(
        JSON.stringify({
          event: 'suggestions_configuration_error',
          error: loggableError(error, config),
          elapsedMs: Math.round(elapsedMs(startedAt))
        })
      );

      return json(
        {
          error: 'configuration_error',
          message: 'Suggestion service is not configured'
        },
        { status: 500 }
      );
    }

    if (error instanceof UnsafeSuggestionGuardError) {
      return json(
        {
          error: 'unsafe_suggestions',
          message: '추천 생성 실패: 대화 당사자 판단이 불확실합니다'
        },
        { status: 422 }
      );
    }

    console.error(
      JSON.stringify({
        event: isAIRequestError(error) ? 'suggestions_ai_request_failed' : 'suggestions_failed',
        error: loggableError(error, config),
        elapsedMs: Math.round(elapsedMs(startedAt))
      })
    );

    return json(
      {
        error: isAIRequestError(error) ? 'ai_request_failed' : 'suggestions_failed',
        message: 'Suggestion generation failed'
      },
      { status: isAIRequestError(error) ? 502 : 500 }
    );
  }
}

function freeUsageLimitExceeded(config: AppConfig, usage: AccountUsageSummary): FreeUsageLimitExceeded | null {
  if (usage.daily.requests >= config.freeDailySuggestionLimit) {
    return {
      scope: 'daily',
      requests: usage.daily.requests,
      limit: config.freeDailySuggestionLimit,
      message: `Free plan daily limit reached (${config.freeDailySuggestionLimit} suggestions today).`
    };
  }

  if (usage.weekly.requests >= config.freeWeeklySuggestionLimit) {
    return {
      scope: 'weekly',
      requests: usage.weekly.requests,
      limit: config.freeWeeklySuggestionLimit,
      message: `Free plan weekly limit reached (${config.freeWeeklySuggestionLimit} suggestions this week).`
    };
  }

  return null;
}

type AccountUsageSummary = {
  daily: {
    requests: number;
  };
  weekly: {
    requests: number;
  };
};

type FreeUsageLimitExceeded = {
  scope: 'daily' | 'weekly';
  requests: number;
  limit: number;
  message: string;
};

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
