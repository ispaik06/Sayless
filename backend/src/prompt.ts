import type { SuggestionRequest } from './schemas.js';

const MAX_CONTEXT_GROUPS = 20;

export function buildSuggestionPrompt(input: SuggestionRequest): string {
  const payload = {
    chatRoom: input.chatRoom ?? null,
    locale: input.locale ?? 'ko-KR',
    messages: input.messages.slice(-MAX_CONTEXT_GROUPS)
  };

  return [
    'Task: Write 3 short, natural KakaoTalk reply suggestions.',
    'Input is JSON. messages are recent visible chat groups in chronological order.',
    'role: me=the user, other=someone else, system=room event.',
    'texts is an ordered array of separate chat bubbles from the same speaker; do not merge their tone into one formal sentence.',
    'Match the input locale and casualness. Avoid explanations, numbering, quotes, and AI/self references.',
    'Output strict JSON only: {"suggestions":[{"id":"s1","text":"..."},{"id":"s2","text":"..."},{"id":"s3","text":"..."}]}',
    JSON.stringify(payload)
  ].join('\n');
}
