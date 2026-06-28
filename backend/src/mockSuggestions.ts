import { inferConversationState } from './conversationState.js';
import type { SuggestionRequest, SuggestionResponse } from './schemas.js';

export function createMockSuggestions(input: SuggestionRequest): SuggestionResponse {
  const lastMessage = input.messages.at(-1)?.texts.at(-1) ?? '';
  const kind = input.intent?.kind ?? 'initial';
  const draftText = input.draftText?.trim() ?? '';
  const activeSuggestions = input.activeSuggestions ?? [];
  const conversationState = inferConversationState(input);

  if (
    !draftText &&
    (conversationState.replyPosture === 'observe_or_light_reaction' ||
      conversationState.activeExchangeType === 'others_talking')
  ) {
    const bystanderPool = [
      { label: '리액션만', text: 'ㅋㅋㅋㅋ' },
      { label: '살짝 끼기', text: '뭐야 ㅋㅋ' },
      { label: '안 끼기', text: '걍 보고만 있어야겠다 ㅋㅋ' },
      { label: '관전', text: '구경만 해야겠다 ㅋㅋ' },
      { label: '짧게', text: '아니 ㅋㅋ' }
    ].sort(() => Math.random() - 0.5);

    return {
      suggestions: bystanderPool.slice(0, 3).map((suggestion, index) => ({
        id: `s${index + 1}`,
        ...suggestion
      }))
    };
  }

  if (kind === 'shorter') {
    if (activeSuggestions.length === 3) {
      return {
        suggestions: activeSuggestions.map((suggestion, index) => ({
          id: `s${index + 1}`,
          label: suggestion.label,
          text: suggestion.text.length > 12 ? suggestion.text.slice(0, 12) : suggestion.text
        }))
      };
    }

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
    if (activeSuggestions.length === 3) {
      return {
        suggestions: activeSuggestions.map((suggestion, index) => ({
          id: `s${index + 1}`,
          label: suggestion.label,
          text: `${suggestion.text} 괜찮으면 그렇게 하자`
        }))
      };
    }

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
    if (activeSuggestions.length === 3) {
      return {
        suggestions: activeSuggestions.map((suggestion, index) => ({
          id: `s${index + 1}`,
          label: suggestion.label,
          text: `${suggestion.text} ㅋㅋ`
        }))
      };
    }

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

    if (activeSuggestions.length === 3) {
      const instruction = input.intent?.instruction ?? '원하는 느낌';
      return {
        suggestions: activeSuggestions.map((suggestion, index) => ({
          id: `s${index + 1}`,
          label: suggestion.label,
          text: `${suggestion.text} (${instruction})`
        }))
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

  if (kind === 'refresh' || kind === 'regenerate') {
    const refreshPool = [
      { label: '다른 각도', text: '그건 또 뭔 흐름이야 ㅋㅋ' },
      { label: '받아치기', text: '잠깐만 이 대화 어디로 가는 중임' },
      { label: '가볍게', text: '오케이 일단 상황 파악부터 ㅋㅋ' },
      { label: '짧게', text: 'ㅋㅋ 뭐야' },
      { label: '흘리기', text: '난 일단 조용히 보고 있을게' },
      { label: '이어가기', text: '그럼 지금 뭐부터 하면 됨?' }
    ].sort(() => Math.random() - 0.5);

    return {
      suggestions: refreshPool.slice(0, 3).map((suggestion, index) => ({
        id: `s${index + 1}`,
        ...suggestion
      }))
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
