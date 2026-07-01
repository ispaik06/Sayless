import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { buildSuggestionPrompt } from './prompt.js';
import type { SuggestionRequest } from './schemas.js';

const baseRefreshInput: SuggestionRequest = {
  chatRoom: {
    title: 'BoB',
    participantCount: 7
  },
  messages: [
    { role: 'other', name: '최도휘', texts: ['그리고 나 니집에', '8핀 충전기 놓고옴'] },
    { role: 'other', name: '이재엽', texts: ['아', '그거', '니거였노?', '잘쓰고있었는데 ㅋㅋ'] },
    { role: 'other', name: '최도휘', texts: ['ㅋㅋ'] }
  ],
  previousSuggestions: [
    { label: '리액션만', text: 'ㅋㅋㅋㅋ' },
    { label: '살짝 끼기', text: '뭐야 ㅋㅋ' },
    { label: '안 끼기', text: '걍 보고만 있어야겠다 ㅋㅋ' }
  ],
  intent: {
    kind: 'refresh',
    refreshIndex: 2
  }
};

describe('refresh novelty prompt', () => {
  it('adds refresh novelty instructions and keeps brainstorming internal', () => {
    const prompt = buildSuggestionPrompt(baseRefreshInput, {
      novelty: {
        level: 'high',
        avoidSemanticDuplicates: true,
        avoidSameTone: true,
        avoidSameSentenceShape: true,
        avoidSameSocialMove: true,
        randomizationHint: 'avoid sounding like an assistant'
      }
    });

    assert.match(prompt, /This is a refresh request/u);
    assert.match(prompt, /refreshIndex: 2/u);
    assert.match(prompt, /previousSuggestions/u);
    assert.match(prompt, /Do not reuse the same tone, sentence shape, joke pattern, ending, or social move/u);
    assert.match(prompt, /Do not produce semantic duplicates of previousSuggestions/u);
    assert.match(prompt, /Internally brainstorm 8-12 possible replies/u);
    assert.match(prompt, /do not output the brainstorm/u);
    assert.match(prompt, /Return only the best 3 final replies/u);
    assert.match(prompt, /Do not follow a fixed template like safe\/funny\/short/u);
    assert.match(prompt, /Do not include brainstorming/u);
  });

  it('does not contain good reply sentence examples that anchor output', () => {
    const prompt = buildSuggestionPrompt({
      ...baseRefreshInput,
      previousSuggestions: [],
      intent: {
        kind: 'initial'
      }
    });

    assert.doesNotMatch(prompt, /Good examples/u);
    assert.doesNotMatch(prompt, /Good bystander replies/u);
    assert.doesNotMatch(prompt, /"ㅋㅋㅋㅋ"/u);
    assert.doesNotMatch(prompt, /"뭐야 ㅋㅋ"/u);
    assert.doesNotMatch(prompt, /"걍 보고만 있어야겠다 ㅋㅋ"/u);
  });
});

describe('reply language policy', () => {
  it('instructs the model to answer English chats in English', () => {
    const prompt = buildSuggestionPrompt({
      chatRoom: {
        title: 'Alex',
        participantCount: 2
      },
      locale: 'auto',
      messages: [
        { role: 'other', name: 'Alex', texts: ['Hey, are you still coming tonight?'] },
        { role: 'me', texts: ['Yeah, just running a bit late'] },
        { role: 'other', name: 'Alex', texts: ['No worries, want me to save you a seat?'] }
      ],
      intent: {
        kind: 'initial'
      }
    });

    assert.match(prompt, /If the recent conversation is mostly or entirely English, generate natural English replies and English labels/u);
    assert.match(prompt, /Do not default to Korean/u);
    assert.match(prompt, /"locale": "auto"/u);
  });
});

describe('refresh slot allocation', () => {
  it('does not hard-code deterministic refresh slots', () => {
    const checkedFiles = ['src/prompt.ts', 'src/openaiSuggestions.ts', 'src/routes.ts'];
    const source = checkedFiles.map((path) => readFileSync(path, 'utf8')).join('\n');

    assert.doesNotMatch(source, /slot\s*1\s*=\s*["'](?:무난|장난|짧게)/u);
    assert.doesNotMatch(source, /slot1\s*=\s*["'](?:무난|장난|짧게)/u);
    assert.doesNotMatch(source, /suggestions\[0\]\.label\s*=\s*["']추천/u);
    assert.doesNotMatch(source, /suggestions\[1\]\.label\s*=\s*["']장난/u);
    assert.doesNotMatch(source, /suggestions\[2\]\.label\s*=\s*["']짧게/u);
  });
});
