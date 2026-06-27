import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  inferConversationState,
  validateSuggestionsForConversationState,
  type ConversationState
} from './conversationState.js';
import type { SuggestionRequest, SuggestionResponse } from './schemas.js';

const chargerBystanderInput: SuggestionRequest = {
  chatRoom: {
    title: 'BoB',
    participantCount: 7
  },
  messages: [
    { role: 'other', name: '최도휘', texts: ['그리고 나 니집에', '8핀 충전기 놓고옴'] },
    { role: 'other', name: '이재엽', texts: ['아', '그거', '니거였노?', '잘쓰고있었는데 ㅋㅋ'] },
    { role: 'other', name: '최도휘', texts: ['ㅋㅋ'] }
  ]
};

function responseWithText(text: string): SuggestionResponse {
  return {
    suggestions: [
      { id: 's1', label: '테스트', text },
      { id: 's2', label: '리액션만', text: 'ㅋㅋㅋㅋ' },
      { id: 's3', label: '안 끼기', text: '걍 보고만 있어야겠다 ㅋㅋ' }
    ]
  };
}

describe('inferConversationState', () => {
  it('detects a group chat where other people are talking and the user is a bystander', () => {
    const state = inferConversationState(chargerBystanderInput);

    assert.equal(state.roomKind, 'group');
    assert.equal(state.hasRecentMeMessage, false);
    assert.deepEqual(state.recentOtherSpeakers, ['최도휘', '이재엽']);
    assert.equal(state.lastSpeakerRole, 'other');
    assert.equal(state.lastSpeakerName, '최도휘');
    assert.equal(state.activeExchangeType, 'others_talking');
    assert.equal(state.replyPosture, 'observe_or_light_reaction');
  });
});

describe('validateSuggestionsForConversationState', () => {
  const state: ConversationState = inferConversationState(chargerBystanderInput);

  it('rejects replies that pretend the user owns or permitted the charger', () => {
    const unsafeTexts = ['내 거 맞음', '걍 써도 됨', '내가 놓고 갔나봄', '아 그거 내꺼였네', '응 맞아'];

    for (const text of unsafeTexts) {
      const result = validateSuggestionsForConversationState(responseWithText(text), state);
      assert.equal(result.ok, false, text);
    }
  });

  it('allows low-intrusion bystander reactions', () => {
    const allowedResponse: SuggestionResponse = {
      suggestions: [
        { id: 's1', label: '리액션만', text: 'ㅋㅋㅋㅋ' },
        { id: 's2', label: '살짝 끼기', text: '뭐야 ㅋㅋ' },
        { id: 's3', label: '안 끼기', text: '걍 보고만 있어야겠다 ㅋㅋ' }
      ]
    };

    const result = validateSuggestionsForConversationState(allowedResponse, state);
    assert.equal(result.ok, true);
  });

  it('allows staying-silent style comments', () => {
    const allowedResponse: SuggestionResponse = {
      suggestions: [
        { id: 's1', label: '구경', text: '구경만 해야겠다 ㅋㅋ' },
        { id: 's2', label: '리액션만', text: 'ㅋㅋㅋㅋ' },
        { id: 's3', label: '살짝', text: '뭐야 ㅋㅋ' }
      ]
    };

    const result = validateSuggestionsForConversationState(allowedResponse, state);
    assert.equal(result.ok, true);
  });

  it('rejects suggestions that are too similar to previous suggestions', () => {
    const result = validateSuggestionsForConversationState(
      responseWithText('뭐야ㅋㅋ'),
      state,
      {
        ...chargerBystanderInput,
        previousSuggestions: [{ label: '살짝', text: '뭐야 ㅋㅋ' }]
      }
    );

    assert.equal(result.ok, false);
  });

  it('rejects duplicate suggestions inside the new response', () => {
    const result = validateSuggestionsForConversationState(
      {
        suggestions: [
          { id: 's1', label: '리액션', text: '뭐야 ㅋㅋ' },
          { id: 's2', label: '살짝', text: '뭐야ㅋㅋ' },
          { id: 's3', label: '관전', text: '걍 보고만 있어야겠다 ㅋㅋ' }
        ]
      },
      state,
      chargerBystanderInput
    );

    assert.equal(result.ok, false);
  });
});
