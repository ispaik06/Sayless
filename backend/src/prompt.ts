import type { SuggestionRequest } from './schemas.js';

const MAX_CONTEXT_GROUPS = 20;

export function buildSuggestionPrompt(input: SuggestionRequest): string {
  const payload = {
    chatRoom: input.chatRoom ?? null,
    locale: input.locale ?? 'ko-KR',
    draftText: input.draftText ?? null,
    intent: input.intent ?? { kind: 'initial' },
    previousSuggestions: input.previousSuggestions?.slice(-18) ?? [],
    messages: input.messages.slice(-MAX_CONTEXT_GROUPS)
  };

  return [
    'Task: Act as a conversation judgment engine and reply recommender for Korean chat/DM contexts.',
    'Do not merely rewrite tone. First infer what the situation needs: whether to reply, accept, decline, joke, flirt, schedule, continue, end, soften, or avoid sounding too eager/stiff.',
    'Input is JSON. messages are recent visible chat groups in chronological order.',
    'role: me=the user, other=someone else, system=room event.',
    'texts is an ordered array of separate chat bubbles from the same speaker; preserve chatty rhythm instead of merging into one formal sentence.',
    'Use chatRoom/name/context to infer relationship. If it looks like close friends, labels and replies may be playful or absurd. If it looks distant/work-like, be polite and low-risk.',
    'Return exactly 3 distinct reply strategies.',
    'If intent.kind is initial, suggestion 1 label must be exactly "추천" and should be the best default reply matching my tone and the other person’s tone.',
    'If intent.kind is not initial, choose all 3 labels from the chat context and intent. Do not force "추천" for the first item unless it is truly the most natural strategy label.',
    'Labels must be short Korean strategy names chosen for this exact context, such as "장난스럽게", "플러팅", "정중하게", "선 긋기", "약속 잡기", "대화 이어가기", "헛소리", etc. Do not use the same labels every time.',
    'If intent.kind is regenerate, produce a fresh set and avoid repeating previousSuggestions.',
    'draftText is the current text already typed in the chat input. It may be null.',
    'For intent.kind shorter/softer/wittier/custom: if draftText is non-empty, treat draftText as the source reply to refine. Return 3 improved versions of that typed text, preserving the underlying intent and fitting the chat context.',
    'If draftText is non-empty and intent.kind is shorter, make the typed text shorter without changing the decision.',
    'If draftText is non-empty and intent.kind is softer, make the typed text warmer/less sharp without sounding forced.',
    'If draftText is non-empty and intent.kind is wittier, make the typed text more clever/playful without forcing jokes.',
    'If draftText is non-empty and intent.kind is custom, follow intent.instruction. If the instruction asks for alternatives, other directions, or different reply ideas, provide those rather than only rewriting draftText.',
    'For intent.kind shorter/softer/wittier/custom: if draftText is empty, generate new replies in that requested style from the chat context as before.',
    'Avoid explanations, numbering, quotes, AI/self references, emojis unless the chat naturally uses them, and anything that sounds like a corporate assistant.',
    'Output strict JSON only: {"suggestions":[{"id":"s1","label":"...","text":"..."},{"id":"s2","label":"...","text":"..."},{"id":"s3","label":"...","text":"..."}]}',
    JSON.stringify(payload)
  ].join('\n');
}
