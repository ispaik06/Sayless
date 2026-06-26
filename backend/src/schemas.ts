import { z } from 'zod';

export const ChatMessageGroupSchema = z.object({
  role: z.enum(['me', 'other', 'system']),
  name: z.string().trim().min(1).max(80).optional(),
  texts: z.array(z.string().trim().min(1).max(800)).min(1).max(8)
});

export const SuggestionRequestSchema = z.object({
  chatRoom: z.string().trim().max(120).optional(),
  locale: z.string().trim().max(20).optional(),
  draftText: z.string().trim().max(1000).optional(),
  messages: z.array(ChatMessageGroupSchema).min(1).max(24),
  intent: z
    .object({
      kind: z.enum(['initial', 'regenerate', 'shorter', 'softer', 'wittier', 'custom']),
      instruction: z.string().trim().min(1).max(500).optional()
    })
    .optional(),
  previousSuggestions: z
    .array(
      z.object({
        label: z.string().trim().min(1).max(24),
        text: z.string().trim().min(1).max(240)
      })
    )
    .max(24)
    .optional()
});

export const ReplySuggestionSchema = z.object({
  id: z.string().trim().min(1).max(24),
  label: z.string().trim().min(1).max(24),
  text: z.string().trim().min(1).max(240)
});

export const SuggestionResponseSchema = z.object({
  suggestions: z.array(ReplySuggestionSchema).length(3)
});

export type ChatMessageGroup = z.infer<typeof ChatMessageGroupSchema>;
export type ReplySuggestion = z.infer<typeof ReplySuggestionSchema>;
export type SuggestionRequest = z.infer<typeof SuggestionRequestSchema>;
export type SuggestionResponse = z.infer<typeof SuggestionResponseSchema>;
