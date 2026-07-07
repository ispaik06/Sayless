export type SuggestionProvider = 'mock' | 'openai' | 'gemini' | 'groq';

export type Env = {
  AI_PROVIDER?: string;
  SUGGESTION_MODE?: string;
  AI_MODEL?: string;
  OPENAI_MODEL?: string;
  AI_BASE_URL?: string;
  OPENAI_API_KEY?: string;
  GEMINI_API_KEY?: string;
  GROQ_API_KEY?: string;
  NODE_ENV?: string;
  CLERK_SECRET_KEY?: string;
  CLERK_PUBLISHABLE_KEY?: string;
  NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY?: string;
  TURSO_DATABASE_URL?: string;
  TURSO_AUTH_TOKEN?: string;
  FREE_DAILY_SUGGESTION_LIMIT?: string;
  FREE_WEEKLY_SUGGESTION_LIMIT?: string;
  GITHUB_RELEASE_OWNER?: string;
  GITHUB_RELEASE_REPO?: string;
  GITHUB_TOKEN?: string;
  GH_TOKEN?: string;
};

export type AppConfig = ReturnType<typeof createConfig>;

function readNumber(env: Env, name: keyof Env, fallback: number): number {
  const raw = env[name];
  if (!raw) {
    return fallback;
  }

  const value = Number.parseInt(raw, 10);
  return Number.isFinite(value) ? value : fallback;
}

function readSuggestionProvider(env: Env): SuggestionProvider {
  const provider = env.AI_PROVIDER?.toLowerCase();
  if (isSuggestionProvider(provider)) {
    return provider;
  }

  if (env.SUGGESTION_MODE) {
    const mode = env.SUGGESTION_MODE.toLowerCase();
    return isSuggestionProvider(mode) ? mode : 'mock';
  }

  if (env.GEMINI_API_KEY) {
    return 'gemini';
  }

  if (env.GROQ_API_KEY) {
    return 'groq';
  }

  return env.OPENAI_API_KEY ? 'openai' : 'mock';
}

function isSuggestionProvider(value: string | undefined): value is SuggestionProvider {
  return value === 'mock' || value === 'openai' || value === 'gemini' || value === 'groq';
}

function defaultModelForProvider(provider: SuggestionProvider): string {
  switch (provider) {
    case 'gemini':
      return 'gemini-3.5-flash';
    case 'groq':
      return 'llama-3.3-70b-versatile';
    case 'openai':
      return 'gpt-4o-mini';
    case 'mock':
      return 'mock';
  }
}

function defaultBaseUrlForProvider(provider: SuggestionProvider): string | undefined {
  switch (provider) {
    case 'gemini':
      return 'https://generativelanguage.googleapis.com/v1beta/openai/';
    case 'groq':
      return 'https://api.groq.com/openai/v1';
    case 'openai':
    case 'mock':
      return undefined;
  }
}

function apiKeyForProvider(env: Env, provider: SuggestionProvider): string | undefined {
  switch (provider) {
    case 'gemini':
      return env.GEMINI_API_KEY;
    case 'groq':
      return env.GROQ_API_KEY;
    case 'openai':
      return env.OPENAI_API_KEY;
    case 'mock':
      return undefined;
  }
}

export function createConfig(env: Env) {
  const suggestionProvider = readSuggestionProvider(env);

  return {
    nodeEnv: env.NODE_ENV ?? 'production',
    suggestionProvider,
    aiModel: env.AI_MODEL ?? env.OPENAI_MODEL ?? defaultModelForProvider(suggestionProvider),
    aiBaseUrl: env.AI_BASE_URL ?? defaultBaseUrlForProvider(suggestionProvider),
    aiApiKey: apiKeyForProvider(env, suggestionProvider),
    openaiApiKey: env.OPENAI_API_KEY,
    geminiApiKey: env.GEMINI_API_KEY,
    groqApiKey: env.GROQ_API_KEY,
    clerkSecretKey: env.CLERK_SECRET_KEY,
    clerkPublishableKey: env.CLERK_PUBLISHABLE_KEY ?? env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY,
    tursoDatabaseUrl: env.TURSO_DATABASE_URL ?? '',
    tursoAuthToken: env.TURSO_AUTH_TOKEN,
    freeDailySuggestionLimit: readNumber(env, 'FREE_DAILY_SUGGESTION_LIMIT', 100),
    freeWeeklySuggestionLimit: readNumber(env, 'FREE_WEEKLY_SUGGESTION_LIMIT', 500),
    githubReleaseOwner: env.GITHUB_RELEASE_OWNER ?? 'ispaik06',
    githubReleaseRepo: env.GITHUB_RELEASE_REPO ?? 'Sayless',
    githubToken: env.GITHUB_TOKEN ?? env.GH_TOKEN
  } as const;
}

export function assertAIConfigured(config: AppConfig): void {
  if (config.suggestionProvider !== 'mock' && !config.aiApiKey) {
    throw new Error(`AI_PROVIDER=${config.suggestionProvider} requires ${apiKeyNameForProvider(config.suggestionProvider)}`);
  }

  if (!config.clerkSecretKey) {
    throw new Error('CLERK_SECRET_KEY is required');
  }

  if (!config.tursoDatabaseUrl) {
    throw new Error('TURSO_DATABASE_URL is required');
  }

  if (!config.tursoAuthToken) {
    throw new Error('TURSO_AUTH_TOKEN is required');
  }
}

function apiKeyNameForProvider(provider: SuggestionProvider): string {
  switch (provider) {
    case 'gemini':
      return 'GEMINI_API_KEY';
    case 'groq':
      return 'GROQ_API_KEY';
    case 'openai':
      return 'OPENAI_API_KEY';
    case 'mock':
      return 'no API key';
  }
}
