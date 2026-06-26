import { z } from 'zod';

export const ChatMessageGroupSchema = z.object({
  role: z.enum(['me', 'other', 'system']),
  name: z.string().trim().min(1).max(80).optional(),
  texts: z.array(z.string().trim().min(1).max(800)).min(1).max(8)
});

export const SuggestionRequestSchema = z.object({
  chatRoom: z.string().trim().max(120).optional(),
  locale: z.string().trim().max(20).optional(),
  messages: z.array(ChatMessageGroupSchema).min(1).max(24)
});

export const ReplySuggestionSchema = z.object({
  id: z.string().trim().min(1).max(24),
  text: z.string().trim().min(1).max(240)
});

export const SuggestionResponseSchema = z.object({
  suggestions: z.array(ReplySuggestionSchema).length(3)
});

export type ChatMessageGroup = z.infer<typeof ChatMessageGroupSchema>;
export type ReplySuggestion = z.infer<typeof ReplySuggestionSchema>;
export type SuggestionRequest = z.infer<typeof SuggestionRequestSchema>;
export type SuggestionResponse = z.infer<typeof SuggestionResponseSchema>;
