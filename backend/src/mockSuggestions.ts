import type { SuggestionRequest, SuggestionResponse } from './schemas.js';

export function createMockSuggestions(input: SuggestionRequest): SuggestionResponse {
  const lastMessage = input.messages.at(-1)?.texts.at(-1) ?? '';
  const kind = input.intent?.kind ?? 'initial';
  const draftText = input.draftText?.trim() ?? '';

  if (kind === 'shorter') {
    if (draftText) {
      return {
        suggestions: [
          { id: 's1', label: '짧게 다듬기', text: draftText.length > 12 ? draftText.slice(0, 12) : draftText },
          { id: 's2', label: '툭 보내기', text: draftText.replace(/[.!?。！？]+$/u, '') },
          { id: 's3', label: '한마디', text: draftText.split(/\s+/u).slice(0, 4).join(' ') || draftText }
        ]
      };
    }

    return {
      suggestions: [
        { id: 's1', label: '한마디', text: '좋아' },
        { id: 's2', label: '짧게', text: 'ㅇㅋ' },
        { id: 's3', label: '가볍게', text: '그럼 ㄱㄱ' }
      ]
    };
  }

  if (kind === 'softer') {
    if (draftText) {
      return {
        suggestions: [
          { id: 's1', label: '부드럽게', text: `${draftText} 괜찮으면 그렇게 하자` },
          { id: 's2', label: '덜 딱딱하게', text: `${draftText} 편하게 생각해도 돼` },
          { id: 's3', label: '조심스럽게', text: `나는 ${draftText} 쪽도 괜찮아` }
        ]
      };
    }

    return {
      suggestions: [
        { id: 's1', label: '천천히', text: '응 좋아. 편한 시간에 맞춰보자' },
        { id: 's2', label: '부드럽게', text: '괜찮아, 천천히 정해도 돼' },
        { id: 's3', label: '다정하게', text: '나는 좋아. 너 편한 쪽으로 하자' }
      ]
    };
  }

  if (kind === 'wittier') {
    if (draftText) {
      return {
        suggestions: [
          { id: 's1', label: '센스있게', text: `${draftText} ㅋㅋ 이 정도면 꽤 괜찮지` },
          { id: 's2', label: '장난 섞어서', text: `${draftText} 나 지금 말 잘한 듯` },
          { id: 's3', label: '가볍게', text: `${draftText} 아무튼 결론은 이거임` }
        ]
      };
    }

    return {
      suggestions: [
        { id: 's1', label: '센스있게', text: '좋아 ㅋㅋ 어디로 출동하면 됨?' },
        { id: 's2', label: '장난', text: '나 지금 약간 추진력 생김' },
        { id: 's3', label: '헛소리', text: '오케이 나의 일정표가 방금 박수침' }
      ]
    };
  }

  if (kind === 'custom') {
    if (draftText) {
      const instruction = input.intent?.instruction ?? '원하는 느낌';
      return {
        suggestions: [
          { id: 's1', label: '요청 반영', text: `${draftText} (${instruction})` },
          { id: 's2', label: '다른 방향', text: `다르게 가면 ${draftText}` },
          { id: 's3', label: '대안', text: `${instruction} 느낌으로는 이렇게도 가능해` }
        ]
      };
    }

    return {
      suggestions: [
        { id: 's1', label: '요청 톤', text: '좋아. 그 느낌으로 말해볼게' },
        { id: 's2', label: '요청 반영', text: input.intent?.instruction ?? '원하는 느낌으로 다시 써볼게' },
        { id: 's3', label: '다른 버전', text: '조금 다르게 가면 이렇게도 가능해' }
      ]
    };
  }

  if (kind === 'regenerate') {
    return {
      suggestions: [
        { id: 's1', label: '다른 각도', text: '그럼 이렇게 해보자' },
        { id: 's2', label: '가볍게', text: '오케이 그걸로 가자 ㅋㅋ' },
        { id: 's3', label: '정리해서', text: '좋아. 그럼 시간만 맞추면 되겠다' }
      ]
    };
  }

  if (lastMessage.includes('?') || lastMessage.includes('？')) {
    return {
      suggestions: [
        { id: 's1', label: '추천', text: '응 맞아' },
        { id: 's2', label: '가볍게', text: '아마 그럴듯?' },
        { id: 's3', label: '확인 후 답장', text: '잠깐만 확인해볼게' }
      ]
    };
  }

  return {
    suggestions: [
      { id: 's1', label: '추천', text: 'ㅋㅋㅋㅋ' },
      { id: 's2', label: '대화 이어가기', text: '오 좋다' },
      { id: 's3', label: '약속 잡기', text: '그럼 그렇게 하자' }
    ]
  };
}
