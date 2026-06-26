import type { SuggestionRequest, SuggestionResponse } from './schemas.js';

export function createMockSuggestions(input: SuggestionRequest): SuggestionResponse {
  const lastMessage = input.messages.at(-1)?.texts.at(-1) ?? '';

  if (lastMessage.includes('?') || lastMessage.includes('？')) {
    return {
      suggestions: [
        { id: 's1', text: '응 맞아' },
        { id: 's2', text: '아마 그럴듯?' },
        { id: 's3', text: '잠깐만 확인해볼게' }
      ]
    };
  }

  return {
    suggestions: [
      { id: 's1', text: 'ㅋㅋㅋㅋ' },
      { id: 's2', text: '오 좋다' },
      { id: 's3', text: '그럼 그렇게 하자' }
    ]
  };
}
