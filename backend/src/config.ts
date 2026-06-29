import 'dotenv/config';

export type SuggestionProvider = 'mock' | 'openai' | 'gemini' | 'groq';

function readNumber(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) {
    return fallback;
  }

  const value = Number.parseInt(raw, 10);
  return Number.isFinite(value) ? value : fallback;
}

function readSuggestionProvider(): SuggestionProvider {
  const provider = process.env.AI_PROVIDER?.toLowerCase();
  if (isSuggestionProvider(provider)) {
    return provider;
  }

  if (process.env.SUGGESTION_MODE) {
    const mode = process.env.SUGGESTION_MODE.toLowerCase();
    return isSuggestionProvider(mode) ? mode : 'mock';
  }

  if (process.env.GEMINI_API_KEY) {
    return 'gemini';
  }

  if (process.env.GROQ_API_KEY) {
    return 'groq';
  }

  return process.env.OPENAI_API_KEY ? 'openai' : 'mock';
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

function apiKeyForProvider(provider: SuggestionProvider): string | undefined {
  switch (provider) {
    case 'gemini':
      return process.env.GEMINI_API_KEY;
    case 'groq':
      return process.env.GROQ_API_KEY;
    case 'openai':
      return process.env.OPENAI_API_KEY;
    case 'mock':
      return undefined;
  }
}

const suggestionProvider = readSuggestionProvider();

export const config = {
  host: '0.0.0.0',
  port: readNumber('PORT', 3000),
  nodeEnv: process.env.NODE_ENV ?? 'development',
  suggestionProvider,
  aiModel: process.env.AI_MODEL ?? process.env.OPENAI_MODEL ?? defaultModelForProvider(suggestionProvider),
  aiBaseUrl: process.env.AI_BASE_URL ?? defaultBaseUrlForProvider(suggestionProvider),
  aiApiKey: apiKeyForProvider(suggestionProvider),
  openaiApiKey: process.env.OPENAI_API_KEY,
  geminiApiKey: process.env.GEMINI_API_KEY,
  groqApiKey: process.env.GROQ_API_KEY,
  saylessClientKey: process.env.SAYLESS_CLIENT_KEY,
  clerkSecretKey: process.env.CLERK_SECRET_KEY,
  tursoDatabaseUrl: process.env.TURSO_DATABASE_URL ?? '',
  tursoAuthToken: process.env.TURSO_AUTH_TOKEN
} as const;

export function assertAIConfigured(): void {
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
