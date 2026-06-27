import OpenAI from 'openai';
import { config } from './config.js';
import { buildNoveltyPayload, buildSuggestionPrompt, type NoveltyPayload } from './prompt.js';
import { logOpenAIUsage } from './openaiUsage.js';
import {
  inferConversationState,
  validateSuggestionsForConversationState,
  type ConversationState,
  type SuggestionGuardResult
} from './conversationState.js';
import { SuggestionResponseSchema, type SuggestionRequest, type SuggestionResponse } from './schemas.js';

let client: OpenAI | undefined;

function getOpenAIClient(): OpenAI {
  if (!config.openaiApiKey) {
    throw new Error('OPENAI_API_KEY is not configured');
  }

  client ??= new OpenAI({
    apiKey: config.openaiApiKey
  });

  return client;
}

function temperatureForIntent(kind?: string): number {
  switch (kind) {
    case 'refresh':
    case 'regenerate':
      return 0.95;
    case 'wittier':
      return 0.85;
    case 'custom':
      return 0.75;
    case 'shorter':
    case 'softer':
      return 0.55;
    case 'initial':
    default:
      return 0.65;
  }
}

function topPForIntent(kind?: string): number {
  return kind === 'refresh' || kind === 'regenerate' ? 0.95 : 0.9;
}

function frequencyPenaltyForIntent(kind?: string): number {
  return kind === 'refresh' || kind === 'regenerate' ? 0.3 : 0;
}

function presencePenaltyForIntent(kind?: string): number {
  return kind === 'refresh' || kind === 'regenerate' ? 0.35 : 0;
}

function usesReasoningChatParameters(model: string): boolean {
  return /^gpt-5(?:\.|-|$)/.test(model) || /^o\d/.test(model);
}

export class UnsafeSuggestionGuardError extends Error {
  constructor(readonly guardResult: Exclude<SuggestionGuardResult, { ok: true }>) {
    super('OpenAI suggestions failed safety/novelty guard');
    this.name = 'UnsafeSuggestionGuardError';
  }
}

export async function createOpenAISuggestions(input: SuggestionRequest): Promise<SuggestionResponse> {
  const conversationState = inferConversationState(input);
  const novelty = buildNoveltyPayload(input);
  const firstResult = await requestOpenAISuggestions(input, conversationState, novelty, undefined, 'initial');
  const firstGuard = validateSuggestionsForConversationState(firstResult, conversationState, input);

  if (firstGuard.ok) {
    return firstResult;
  }

  const retryResult = await requestOpenAISuggestions(
    input,
    conversationState,
    novelty,
    buildGuardRetryInstruction(firstGuard),
    'retry'
  );
  const retryGuard = validateSuggestionsForConversationState(retryResult, conversationState, input);

  if (retryGuard.ok) {
    return retryResult;
  }

  throw new UnsafeSuggestionGuardError(retryGuard);
}

async function requestOpenAISuggestions(
  input: SuggestionRequest,
  conversationState: ConversationState,
  novelty: NoveltyPayload | null,
  additionalInstruction?: string,
  attempt: 'initial' | 'retry' = 'initial'
): Promise<SuggestionResponse> {
  const usesReasoningParameters = usesReasoningChatParameters(config.openaiModel);
  const startedAt = performance.now();
  const completion = await getOpenAIClient().chat.completions.create({
    model: config.openaiModel,
    ...(usesReasoningParameters
      ? {
          max_completion_tokens: 1200
        }
      : {
          temperature: temperatureForIntent(input.intent?.kind),
          top_p: topPForIntent(input.intent?.kind),
          frequency_penalty: frequencyPenaltyForIntent(input.intent?.kind),
          presence_penalty: presencePenaltyForIntent(input.intent?.kind),
          max_tokens: 360
        }),
    messages: [
      {
        role: 'system',
        content:
          'You are Sayless, a Korean chat reply judgment and recommendation engine. Return only valid JSON matching the requested schema.'
      },
      {
        role: 'user',
        content: buildSuggestionPrompt(input, {
          conversationState,
          novelty,
          additionalInstruction
        })
      }
    ],
    response_format: {
      type: 'json_object'
    }
  });
  const latencyMs = performance.now() - startedAt;
  logOpenAIUsage({
    model: config.openaiModel,
    usage: completion.usage,
    latencyMs,
    attempt
  });

  const content = completion.choices[0]?.message.content;
  if (!content) {
    throw new Error('OpenAI response was empty');
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'unknown JSON parse error';
    throw new Error(`OpenAI response was not valid JSON: ${message}`);
  }

  const result = SuggestionResponseSchema.safeParse(parsed);
  if (!result.success) {
    throw new Error(
      `OpenAI response schema mismatch: ${result.error.issues
        .map((issue) => `${issue.path.join('.') || '<root>'}: ${issue.message}`)
        .join('; ')}`
    );
  }

  return result.data;
}

function buildGuardRetryInstruction(guardResult: Exclude<SuggestionGuardResult, { ok: true }>): string {
  return `The previous response was rejected by the safety/novelty guard.
Rejected text: "${guardResult.suggestion.text}"
Matched previous/sibling text: "${guardResult.matchedSuggestion?.text ?? ''}"
Reason: ${guardResult.reason}
Return exactly 3 valid suggestions that pass both safety and novelty checks.
If the conversation state says the user is a bystander, use only low-intrusion reactions or silence-like comments.
Do not include ownership, permission, confirmation, responsibility, memory, action, or "me too" claims.
Do not repeat previousSuggestions semantically, tonally, structurally, or socially.
Avoid: "내 거", "내꺼", "내가", "나도", "써도 됨", "응 맞아", "맞음".`;
}
