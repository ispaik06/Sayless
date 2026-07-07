import { createClerkClient } from '@clerk/backend';
import type { AppConfig } from './config.js';

export type AuthenticatedUser = {
  clerkUserId: string;
  sessionId: string | null;
};

export async function authenticateRequest(request: Request, config: AppConfig): Promise<AuthenticatedUser | null> {
  if (!config.clerkSecretKey) {
    throw new Error('CLERK_SECRET_KEY is required');
  }

  const clerk = createClerkClient({
    secretKey: config.clerkSecretKey,
    publishableKey: config.clerkPublishableKey
  });
  const requestState = await clerk.authenticateRequest(request, {
    acceptsToken: 'session_token'
  });
  const auth = requestState.toAuth();

  if (!auth?.userId) {
    return null;
  }

  return {
    clerkUserId: auth.userId,
    sessionId: auth.sessionId
  };
}

export async function hashIdentifier(value: string): Promise<string> {
  const input = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', input);
  return Array.from(new Uint8Array(digest))
    .slice(0, 8)
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}
