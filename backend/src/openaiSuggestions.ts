import OpenAI from 'openai';
import { config } from './config.js';
import { buildSuggestionPrompt } from './prompt.js';
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
    case 'regenerate':
    case 'wittier':
      return 0.9;
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

function usesReasoningChatParameters(model: string): boolean {
  return /^gpt-5(?:\.|-|$)/.test(model) || /^o\d/.test(model);
}

export async function createOpenAISuggestions(input: SuggestionRequest): Promise<SuggestionResponse> {
  const usesReasoningParameters = usesReasoningChatParameters(config.openaiModel);
  const completion = await getOpenAIClient().chat.completions.create({
    model: config.openaiModel,
    ...(usesReasoningParameters
      ? {
          max_completion_tokens: 1200
        }
      : {
          temperature: temperatureForIntent(input.intent?.kind),
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
        content: buildSuggestionPrompt(input)
      }
    ],
    response_format: {
      type: 'json_object'
    }
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
