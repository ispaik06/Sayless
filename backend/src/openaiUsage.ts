import { estimateOpenAICostUsd, type OpenAITokenUsageSummary } from './openaiPricing.js';

type OpenAIUsageLike = {
  input_tokens?: number;
  prompt_tokens?: number;
  output_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
  input_tokens_details?: {
    cached_tokens?: number;
  };
  prompt_tokens_details?: {
    cached_tokens?: number;
  };
};

export type ParsedOpenAIUsage = OpenAITokenUsageSummary & {
  usagePresent: boolean;
};

export function parseOpenAIUsage(usage: unknown): ParsedOpenAIUsage {
  if (!usage || typeof usage !== 'object') {
    return emptyUsage(false);
  }

  const raw = usage as OpenAIUsageLike;
  const inputTokens = nonNegativeInteger(raw.input_tokens ?? raw.prompt_tokens);
  const outputTokens = nonNegativeInteger(raw.output_tokens ?? raw.completion_tokens);
  const totalTokens = nonNegativeInteger(raw.total_tokens) || inputTokens + outputTokens;
  const cachedInputTokens = Math.min(
    inputTokens,
    nonNegativeInteger(raw.input_tokens_details?.cached_tokens ?? raw.prompt_tokens_details?.cached_tokens)
  );
  const uncachedInputTokens = Math.max(0, inputTokens - cachedInputTokens);

  return {
    usagePresent: true,
    inputTokens,
    cachedInputTokens,
    uncachedInputTokens,
    outputTokens,
    totalTokens,
    cacheHitRatio: inputTokens > 0 ? cachedInputTokens / inputTokens : null
  };
}

export function logAIUsage(params: {
  provider: string;
  model: string;
  usage: unknown;
  latencyMs: number;
  attempt: 'initial' | 'retry';
}): void {
  try {
    const usage = parseOpenAIUsage(params.usage);
    const cost = usage.usagePresent ? estimateOpenAICostUsd(params.model, usage) : null;

    console.log(
      JSON.stringify({
        event: 'ai_usage',
        provider: params.provider,
        model: params.model,
        attempt: params.attempt,
        inputTokens: usage.inputTokens,
        cachedInputTokens: usage.cachedInputTokens,
        uncachedInputTokens: usage.uncachedInputTokens,
        outputTokens: usage.outputTokens,
        totalTokens: usage.totalTokens,
        cacheHitRatio: usage.cacheHitRatio,
        estimatedCostUsd: cost?.estimatedCostUsd ?? null,
        pricingSource: cost?.pricing?.source ?? null,
        pricingLastChecked: cost?.pricing?.lastChecked ?? null,
        latencyMs: Math.round(params.latencyMs),
        usagePresent: usage.usagePresent
      })
    );
  } catch {
    // Usage logging must never break reply generation.
  }
}

function emptyUsage(usagePresent: boolean): ParsedOpenAIUsage {
  return {
    usagePresent,
    inputTokens: 0,
    cachedInputTokens: 0,
    uncachedInputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
    cacheHitRatio: null
  };
}

function nonNegativeInteger(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
}
