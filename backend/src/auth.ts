import { getAuth } from '@clerk/fastify';
import type { FastifyReply, FastifyRequest } from 'fastify';

export type AuthenticatedUser = {
  clerkUserId: string;
  sessionId: string | null;
};

export function requireAuth(request: FastifyRequest, reply: FastifyReply): AuthenticatedUser | undefined {
  const auth = getAuth(request);

  if (!auth.userId) {
    void reply.code(401).send({
      error: 'unauthorized',
      message: 'Authentication required'
    });

    return undefined;
  }

  return {
    clerkUserId: auth.userId,
    sessionId: auth.sessionId
  };
}
