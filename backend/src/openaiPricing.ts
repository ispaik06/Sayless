export type OpenAIModelPricing = {
  inputPerMillionUsd: number;
  cachedInputPerMillionUsd: number;
  outputPerMillionUsd: number;
  source: string;
  lastChecked: string;
  note: string;
};

export type OpenAITokenUsageSummary = {
  inputTokens: number;
  cachedInputTokens: number;
  uncachedInputTokens: number;
  outputTokens: number;
  totalTokens: number;
  cacheHitRatio: number | null;
};

export type OpenAICostEstimate = {
  estimatedCostUsd: number | null;
  pricing: OpenAIModelPricing | null;
};

export const OPENAI_MODEL_PRICING: Record<string, OpenAIModelPricing> = {
  'gpt-5.4': {
    inputPerMillionUsd: 2.5,
    cachedInputPerMillionUsd: 0.25,
    outputPerMillionUsd: 15,
    source: 'User-provided pricing in Sayless task',
    lastChecked: '2026-06-27',
    note: 'Estimated-cost config only. OpenAI pricing can change; update this file when it does.'
  },
  'gpt-5.4-mini': {
    inputPerMillionUsd: 0.75,
    cachedInputPerMillionUsd: 0.075,
    outputPerMillionUsd: 4.5,
    source: 'User-provided pricing in Sayless task',
    lastChecked: '2026-06-27',
    note: 'Estimated-cost config only. OpenAI pricing can change; update this file when it does.'
  },
  'gpt-5.4-nano': {
    inputPerMillionUsd: 0.2,
    cachedInputPerMillionUsd: 0.02,
    outputPerMillionUsd: 1.25,
    source: 'User-provided pricing in Sayless task',
    lastChecked: '2026-06-27',
    note: 'Estimated-cost config only. OpenAI pricing can change; update this file when it does.'
  }
};

export function pricingForModel(model: string): OpenAIModelPricing | null {
  return OPENAI_MODEL_PRICING[model] ?? null;
}

export function estimateOpenAICostUsd(model: string, usage: OpenAITokenUsageSummary): OpenAICostEstimate {
  const pricing = pricingForModel(model);
  if (!pricing) {
    return {
      estimatedCostUsd: null,
      pricing: null
    };
  }

  const estimatedCostUsd =
    (usage.uncachedInputTokens / 1_000_000) * pricing.inputPerMillionUsd +
    (usage.cachedInputTokens / 1_000_000) * pricing.cachedInputPerMillionUsd +
    (usage.outputTokens / 1_000_000) * pricing.outputPerMillionUsd;

  return {
    estimatedCostUsd,
    pricing
  };
}
