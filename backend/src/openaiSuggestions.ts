import OpenAI from 'openai';
import type { ChatCompletionCreateParamsNonStreaming } from 'openai/resources/chat/completions';
import { config } from './config.js';
import { buildNoveltyPayload, buildSuggestionPrompt, type NoveltyPayload } from './prompt.js';
import { logAIUsage } from './openaiUsage.js';
import {
  inferConversationState,
  validateSuggestionsForConversationState,
  type ConversationState,
  type SuggestionGuardResult
} from './conversationState.js';
import { SuggestionResponseSchema, type SuggestionRequest, type SuggestionResponse } from './schemas.js';

let client: OpenAI | undefined;

function getAIClient(): OpenAI {
  if (!config.aiApiKey) {
    throw new Error(`AI_PROVIDER=${config.suggestionProvider} is not configured with an API key`);
  }

  client ??= new OpenAI({
    apiKey: config.aiApiKey,
    baseURL: config.aiBaseUrl
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

function supportsStrictJsonResponseFormat(): boolean {
  return config.suggestionProvider === 'openai' || config.suggestionProvider === 'groq';
}

export class UnsafeSuggestionGuardError extends Error {
  constructor(readonly guardResult: Exclude<SuggestionGuardResult, { ok: true }>) {
    super('AI suggestions failed safety/novelty guard');
    this.name = 'UnsafeSuggestionGuardError';
  }
}

export class InvalidAIResponseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidAIResponseError';
  }
}

export async function createAISuggestions(input: SuggestionRequest): Promise<SuggestionResponse> {
  const conversationState = inferConversationState(input);
  const novelty = buildNoveltyPayload(input);
  const firstResult = await requestAISuggestions(input, conversationState, novelty, undefined, 'initial');
  const firstGuard = validateSuggestionsForConversationState(firstResult, conversationState, input);

  if (firstGuard.ok) {
    return firstResult;
  }

  const retryResult = await requestAISuggestions(
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

async function requestAISuggestions(
  input: SuggestionRequest,
  conversationState: ConversationState,
  novelty: NoveltyPayload | null,
  additionalInstruction?: string,
  attempt: 'initial' | 'retry' = 'initial'
): Promise<SuggestionResponse> {
  const usesReasoningParameters = config.suggestionProvider === 'openai' && usesReasoningChatParameters(config.aiModel);
  const startedAt = performance.now();
  const params: ChatCompletionCreateParamsNonStreaming = {
    model: config.aiModel,
    ...(usesReasoningParameters
      ? {
          max_completion_tokens: 1200
        }
      : {
          temperature: temperatureForIntent(input.intent?.kind),
          top_p: topPForIntent(input.intent?.kind),
          ...(config.suggestionProvider === 'openai'
            ? {
                frequency_penalty: frequencyPenaltyForIntent(input.intent?.kind),
                presence_penalty: presencePenaltyForIntent(input.intent?.kind)
              }
            : {}),
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
          additionalInstruction: [
            additionalInstruction,
            config.suggestionProvider === 'gemini'
              ? 'Return raw JSON only. Do not wrap the JSON in markdown code fences.'
              : null
          ]
            .filter((line): line is string => Boolean(line))
            .join('\n')
        })
      }
    ]
  };

  if (supportsStrictJsonResponseFormat()) {
    params.response_format = {
      type: 'json_object'
    };
  }

  const completion = await getAIClient().chat.completions.create(params);
  const latencyMs = performance.now() - startedAt;
  logAIUsage({
    provider: config.suggestionProvider,
    model: config.aiModel,
    usage: completion.usage,
    latencyMs,
    attempt
  });

  const content = normalizeMessageContent(completion.choices[0]?.message.content);
  if (!content) {
    throw new Error('AI response was empty');
  }

  const parsed = parseAIJson(content);

  const result = SuggestionResponseSchema.safeParse(parsed);
  if (!result.success) {
    throw new InvalidAIResponseError(
      `AI response schema mismatch: ${result.error.issues
        .map((issue) => `${issue.path.join('.') || '<root>'}: ${issue.message}`)
        .join('; ')}`
    );
  }

  return result.data;
}

function normalizeMessageContent(content: unknown): string {
  if (typeof content === 'string') {
    return content;
  }

  if (Array.isArray(content)) {
    return content
      .map((part) => {
        if (typeof part === 'string') {
          return part;
        }

        if (part && typeof part === 'object' && 'text' in part) {
          const text = (part as { text?: unknown }).text;
          return typeof text === 'string' ? text : '';
        }

        return '';
      })
      .join('');
  }

  return '';
}

function parseAIJson(content: string): unknown {
  const candidates = [
    content,
    stripMarkdownJsonFence(content),
    extractFirstJsonObject(content)
  ].filter((candidate): candidate is string => Boolean(candidate?.trim()));

  let lastMessage = 'unknown JSON parse error';
  for (const candidate of candidates) {
    try {
      return JSON.parse(candidate);
    } catch (error) {
      lastMessage = error instanceof Error ? error.message : lastMessage;
    }
  }

  throw new InvalidAIResponseError(`AI response was not valid JSON: ${lastMessage}`);
}

function stripMarkdownJsonFence(content: string): string {
  const trimmed = content.trim();
  const fenced = /^```(?:json)?\s*([\s\S]*?)\s*```$/i.exec(trimmed);
  return fenced?.[1]?.trim() ?? trimmed;
}

function extractFirstJsonObject(content: string): string | null {
  const start = content.indexOf('{');
  if (start === -1) {
    return null;
  }

  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let index = start; index < content.length; index += 1) {
    const character = content[index];

    if (escaped) {
      escaped = false;
      continue;
    }

    if (character === '\\') {
      escaped = true;
      continue;
    }

    if (character === '"') {
      inString = !inString;
      continue;
    }

    if (inString) {
      continue;
    }

    if (character === '{') {
      depth += 1;
    } else if (character === '}') {
      depth -= 1;
      if (depth === 0) {
        return content.slice(start, index + 1);
      }
    }
  }

  return null;
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
