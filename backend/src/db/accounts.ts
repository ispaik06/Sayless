import { and, desc, eq, gte, sql } from 'drizzle-orm';
import { randomUUID } from 'node:crypto';
import { db } from './client.js';
import { subscriptions, usageEvents, users } from './schema.js';

export type AIUsageEventInput = {
  userId: string;
  provider: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  latencyMs: number | null;
  metadata?: Record<string, unknown>;
};

const activeSubscriptionStatuses = new Set(['active', 'trialing']);

export async function ensureUserForClerkId(clerkUserId: string) {
  const existing = await db.query.users.findFirst({
    where: eq(users.clerkUserId, clerkUserId)
  });

  if (existing) {
    return existing;
  }

  const id = randomUUID();
  await db.insert(users).values({
    id,
    clerkUserId
  }).onConflictDoNothing({
    target: users.clerkUserId
  });

  const created = await db.query.users.findFirst({
    where: eq(users.clerkUserId, clerkUserId)
  });

  if (!created) {
    throw new Error('Failed to create user');
  }

  return created;
}

export async function getAccountStatus(clerkUserId: string) {
  const user = await ensureUserForClerkId(clerkUserId);
  const subscription = await db.query.subscriptions.findFirst({
    where: eq(subscriptions.userId, user.id),
    orderBy: desc(subscriptions.updatedAt)
  });
  const usage = await getMonthlyUsage(user.id);
  const plan = subscription && activeSubscriptionStatuses.has(subscription.status) ? 'pro' : 'free';

  return {
    user: {
      id: user.id,
      clerkUserId: user.clerkUserId,
      stripeCustomerId: user.stripeCustomerId
    },
    plan,
    subscription: subscription
      ? {
          status: subscription.status,
          stripePriceId: subscription.stripePriceId,
          currentPeriodEnd: subscription.currentPeriodEnd?.toISOString() ?? null,
          cancelAtPeriodEnd: subscription.cancelAtPeriodEnd
        }
      : null,
    usage
  };
}

export async function recordAIUsageEvent(input: AIUsageEventInput): Promise<void> {
  await db.insert(usageEvents).values({
    id: randomUUID(),
    userId: input.userId,
    eventType: 'suggestions.generated',
    provider: input.provider,
    model: input.model,
    quantity: 1,
    inputTokens: Math.max(0, Math.floor(input.inputTokens)),
    outputTokens: Math.max(0, Math.floor(input.outputTokens)),
    totalTokens: Math.max(0, Math.floor(input.totalTokens)),
    latencyMs: input.latencyMs === null ? null : Math.max(0, Math.round(input.latencyMs)),
    metadataJson: input.metadata ? JSON.stringify(input.metadata) : null
  });
}

async function getMonthlyUsage(userId: string) {
  const since = startOfMonth();
  const rows = await db
    .select({
      requests: sql<number>`coalesce(sum(${usageEvents.quantity}), 0)`,
      inputTokens: sql<number>`coalesce(sum(${usageEvents.inputTokens}), 0)`,
      outputTokens: sql<number>`coalesce(sum(${usageEvents.outputTokens}), 0)`,
      totalTokens: sql<number>`coalesce(sum(${usageEvents.totalTokens}), 0)`
    })
    .from(usageEvents)
    .where(and(eq(usageEvents.userId, userId), gte(usageEvents.createdAt, since)));

  const usage = rows[0];

  return {
    periodStart: since.toISOString(),
    requests: Number(usage?.requests ?? 0),
    inputTokens: Number(usage?.inputTokens ?? 0),
    outputTokens: Number(usage?.outputTokens ?? 0),
    totalTokens: Number(usage?.totalTokens ?? 0)
  };
}

function startOfMonth(): Date {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
}
