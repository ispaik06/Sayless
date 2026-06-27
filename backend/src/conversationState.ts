import type { ReplySuggestion, SuggestionRequest, SuggestionResponse } from './schemas.js';

export type RoomKind = 'dm' | 'group' | 'unknown';

export type ActiveExchangeType =
  | 'dm_direct'
  | 'group_direct_to_me'
  | 'group_open'
  | 'others_talking'
  | 'unclear';

export type ReplyPosture =
  | 'answer'
  | 'light_answer'
  | 'react_only'
  | 'observe_or_light_reaction'
  | 'do_not_assume';

export type ConversationState = {
  participantCount: number | null;
  roomKind: RoomKind;
  hasRecentMeMessage: boolean;
  recentOtherSpeakers: string[];
  lastSpeakerRole: 'me' | 'other' | 'system' | null;
  lastSpeakerName: string | null;
  activeExchangeType: ActiveExchangeType;
  replyPosture: ReplyPosture;
};

type FlatMessage = {
  role: 'me' | 'other' | 'system';
  name: string | null;
  text: string;
};

type SuggestionText = {
  label: string;
  text: string;
};

type GuardFailure = {
  ok: false;
  reason: string;
  suggestion: ReplySuggestion;
  matchedSuggestion?: SuggestionText;
  pattern?: string;
};

export type SuggestionGuardResult =
  | {
      ok: true;
    }
  | GuardFailure;

type UnsafePattern = {
  pattern: RegExp;
  description: string;
};

const BYSTANDER_UNSAFE_PATTERNS: UnsafePattern[] = [
  { pattern: /내\s*거/u, description: 'claims user ownership' },
  { pattern: /내꺼/u, description: 'claims user ownership' },
  { pattern: /내\s*꺼/u, description: 'claims user ownership' },
  { pattern: /내\s*충전기/u, description: 'claims user ownership of the charger' },
  { pattern: /내\s*집/u, description: 'claims user private context' },
  {
    pattern: /내가\s*(?:놓고|두고|할|해|했|가져|갖고|가지고|쓸|쓰|챙|보내|갈|사|살|냈|낼|맡|확인|찾|알아)/u,
    description: 'claims user action or responsibility'
  },
  { pattern: /내\s*가/u, description: 'speaks as an involved first-person party' },
  { pattern: /나도/u, description: 'claims user participation or agreement' },
  { pattern: /써도\s*됨/u, description: 'grants permission as if the user is responsible' },
  { pattern: /써라/u, description: 'grants permission as if the user is responsible' },
  { pattern: /(?:^|[\s"'“”‘’([{<])맞음(?:$|[\s"'“”‘’.,!?)}\]>ㅋㅋㅋ])/u, description: 'confirms as a party' },
  { pattern: /응\s*맞/u, description: 'confirms as a party' }
];

export function inferRoomKind(participantCount?: number | null): RoomKind {
  if (participantCount === 2) {
    return 'dm';
  }

  if (participantCount && participantCount >= 3) {
    return 'group';
  }

  return 'unknown';
}

export function inferConversationState(input: SuggestionRequest): ConversationState {
  const participantCount = input.chatRoom?.participantCount ?? null;
  const roomKind = inferRoomKind(participantCount);
  const flatMessages = flattenMessages(input);
  const recentNonSystemMessages = flatMessages.filter((message) => message.role !== 'system').slice(-6);
  const lastRelevantMessage = recentNonSystemMessages.at(-1) ?? flatMessages.at(-1) ?? null;
  const hasRecentMeMessage = recentNonSystemMessages.some((message) => message.role === 'me');
  const recentOtherSpeakers = uniqueNames(
    recentNonSystemMessages
      .filter((message) => message.role === 'other')
      .map((message) => message.name)
  );

  const baseState = {
    participantCount,
    roomKind,
    hasRecentMeMessage,
    recentOtherSpeakers,
    lastSpeakerRole: lastRelevantMessage?.role ?? null,
    lastSpeakerName: lastRelevantMessage?.name ?? null
  };

  if (roomKind === 'dm') {
    return {
      ...baseState,
      activeExchangeType: 'dm_direct',
      replyPosture: 'answer'
    };
  }

  if (
    roomKind === 'group' &&
    !hasRecentMeMessage &&
    recentOtherSpeakers.length >= 2 &&
    lastRelevantMessage?.role === 'other'
  ) {
    return {
      ...baseState,
      activeExchangeType: 'others_talking',
      replyPosture: 'observe_or_light_reaction'
    };
  }

  if (roomKind === 'group' && hasRecentMeMessage && lastRelevantMessage?.role === 'other') {
    return {
      ...baseState,
      activeExchangeType: 'group_direct_to_me',
      replyPosture: 'answer'
    };
  }

  if (roomKind === 'group' && lastRelevantMessage?.role === 'other') {
    return {
      ...baseState,
      activeExchangeType: 'group_open',
      replyPosture: 'light_answer'
    };
  }

  return {
    ...baseState,
    activeExchangeType: 'unclear',
    replyPosture: 'do_not_assume'
  };
}

export function validateSuggestionsForConversationState(
  response: SuggestionResponse,
  state: ConversationState,
  input?: SuggestionRequest
): SuggestionGuardResult {
  if (state.replyPosture !== 'observe_or_light_reaction' && state.activeExchangeType !== 'others_talking') {
    return validateSuggestionNovelty(response, input);
  }

  for (const suggestion of response.suggestions) {
    const text = suggestion.text.trim();
    const unsafePattern = BYSTANDER_UNSAFE_PATTERNS.find(({ pattern }) => pattern.test(text));

    if (unsafePattern) {
      return {
        ok: false,
        reason: unsafePattern.description,
        suggestion,
        pattern: unsafePattern.pattern.source
      };
    }
  }

  const noveltyResult = validateSuggestionNovelty(response, input);
  if (!noveltyResult.ok) {
    return noveltyResult;
  }

  return {
    ok: true
  };
}

function validateSuggestionNovelty(response: SuggestionResponse, input?: SuggestionRequest): SuggestionGuardResult {
  const suggestions = response.suggestions;

  for (let i = 0; i < suggestions.length; i += 1) {
    for (let j = i + 1; j < suggestions.length; j += 1) {
      const left = suggestions[i];
      const right = suggestions[j];

      if (areSuggestionTextsTooSimilar(left.text, right.text)) {
        return {
          ok: false,
          reason: 'new suggestions are too similar to each other',
          suggestion: right,
          matchedSuggestion: left
        };
      }
    }
  }

  const previousSuggestions = input?.previousSuggestions ?? [];
  for (const suggestion of suggestions) {
    const matchedSuggestion = previousSuggestions.find((previousSuggestion) =>
      areSuggestionTextsTooSimilar(suggestion.text, previousSuggestion.text)
    );

    if (matchedSuggestion) {
      return {
        ok: false,
        reason: 'new suggestion is too similar to a previous suggestion',
        suggestion,
        matchedSuggestion
      };
    }
  }

  return {
    ok: true
  };
}

function areSuggestionTextsTooSimilar(left: string, right: string): boolean {
  const normalizedLeft = normalizeSuggestionText(left);
  const normalizedRight = normalizeSuggestionText(right);

  if (!normalizedLeft || !normalizedRight) {
    return false;
  }

  if (normalizedLeft === normalizedRight) {
    return true;
  }

  const minLength = Math.min(normalizedLeft.length, normalizedRight.length);
  if (
    minLength >= 6 &&
    (normalizedLeft.includes(normalizedRight) || normalizedRight.includes(normalizedLeft))
  ) {
    return true;
  }

  if (minLength >= 8 && characterBigramSimilarity(normalizedLeft, normalizedRight) >= 0.82) {
    return true;
  }

  return false;
}

function normalizeSuggestionText(text: string): string {
  return text
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[ㅋㅎ]{2,}/gu, (match) => match[0] ?? '')
    .replace(/[\p{P}\p{S}\s]/gu, '')
    .trim();
}

function characterBigramSimilarity(left: string, right: string): number {
  const leftBigrams = characterBigrams(left);
  const rightBigrams = characterBigrams(right);

  if (leftBigrams.size === 0 || rightBigrams.size === 0) {
    return 0;
  }

  let intersectionSize = 0;
  for (const bigram of leftBigrams) {
    if (rightBigrams.has(bigram)) {
      intersectionSize += 1;
    }
  }

  const unionSize = new Set([...leftBigrams, ...rightBigrams]).size;
  return unionSize === 0 ? 0 : intersectionSize / unionSize;
}

function characterBigrams(text: string): Set<string> {
  const bigrams = new Set<string>();

  for (let index = 0; index < text.length - 1; index += 1) {
    bigrams.add(text.slice(index, index + 2));
  }

  return bigrams;
}

function flattenMessages(input: SuggestionRequest): FlatMessage[] {
  return input.messages.flatMap((group) =>
    group.texts.map((text) => ({
      role: group.role,
      name: group.name?.trim() || null,
      text
    }))
  );
}

function uniqueNames(names: Array<string | null>): string[] {
  const seen = new Set<string>();
  const result: string[] = [];

  for (const name of names) {
    if (!name || seen.has(name)) {
      continue;
    }

    seen.add(name);
    result.push(name);
  }

  return result;
}
