import 'dotenv/config';

export type SuggestionMode = 'mock' | 'openai';

function readNumber(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) {
    return fallback;
  }

  const value = Number.parseInt(raw, 10);
  return Number.isFinite(value) ? value : fallback;
}

function readSuggestionMode(): SuggestionMode {
  if (process.env.SUGGESTION_MODE) {
    return process.env.SUGGESTION_MODE === 'openai' ? 'openai' : 'mock';
  }

  return process.env.OPENAI_API_KEY ? 'openai' : 'mock';
}

export const config = {
  host: '0.0.0.0',
  port: readNumber('PORT', 3000),
  nodeEnv: process.env.NODE_ENV ?? 'development',
  suggestionMode: readSuggestionMode(),
  openaiModel: process.env.OPENAI_MODEL ?? 'gpt-4o-mini',
  openaiApiKey: process.env.OPENAI_API_KEY,
  saylessClientKey: process.env.SAYLESS_CLIENT_KEY
} as const;

export function assertOpenAIConfigured(): void {
  if (config.suggestionMode === 'openai' && !config.openaiApiKey) {
    throw new Error('SUGGESTION_MODE=openai requires OPENAI_API_KEY');
  }
}
