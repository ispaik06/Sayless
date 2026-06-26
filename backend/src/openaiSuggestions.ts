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

export async function createOpenAISuggestions(input: SuggestionRequest): Promise<SuggestionResponse> {
  const completion = await getOpenAIClient().chat.completions.create({
    model: config.openaiModel,
    temperature: 0.85,
    max_tokens: 360,
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

  return SuggestionResponseSchema.parse(JSON.parse(content));
}
