import { relations, sql } from 'drizzle-orm';
import { index, integer, sqliteTable, text, uniqueIndex } from 'drizzle-orm/sqlite-core';

export const users = sqliteTable(
  'users',
  {
    id: text('id').primaryKey(),
    clerkUserId: text('clerk_user_id').notNull(),
    stripeCustomerId: text('stripe_customer_id'),
    createdAt: integer('created_at', { mode: 'timestamp_ms' })
      .notNull()
      .default(sql`(unixepoch('subsec') * 1000)`),
    updatedAt: integer('updated_at', { mode: 'timestamp_ms' })
      .notNull()
      .default(sql`(unixepoch('subsec') * 1000)`)
  },
  (table) => [
    uniqueIndex('users_clerk_user_id_idx').on(table.clerkUserId),
    uniqueIndex('users_stripe_customer_id_idx').on(table.stripeCustomerId)
  ]
);

export const subscriptions = sqliteTable(
  'subscriptions',
  {
    id: text('id').primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    stripeSubscriptionId: text('stripe_subscription_id').notNull(),
    stripePriceId: text('stripe_price_id'),
    status: text('status').notNull(),
    currentPeriodEnd: integer('current_period_end', { mode: 'timestamp_ms' }),
    cancelAtPeriodEnd: integer('cancel_at_period_end', { mode: 'boolean' }).notNull().default(false),
    createdAt: integer('created_at', { mode: 'timestamp_ms' })
      .notNull()
      .default(sql`(unixepoch('subsec') * 1000)`),
    updatedAt: integer('updated_at', { mode: 'timestamp_ms' })
      .notNull()
      .default(sql`(unixepoch('subsec') * 1000)`)
  },
  (table) => [
    index('subscriptions_user_id_idx').on(table.userId),
    uniqueIndex('subscriptions_stripe_subscription_id_idx').on(table.stripeSubscriptionId)
  ]
);

export const usageEvents = sqliteTable(
  'usage_events',
  {
    id: text('id').primaryKey(),
    userId: text('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    eventType: text('event_type').notNull(),
    provider: text('provider'),
    model: text('model'),
    quantity: integer('quantity').notNull().default(1),
    inputTokens: integer('input_tokens').notNull().default(0),
    outputTokens: integer('output_tokens').notNull().default(0),
    totalTokens: integer('total_tokens').notNull().default(0),
    latencyMs: integer('latency_ms'),
    metadataJson: text('metadata_json'),
    createdAt: integer('created_at', { mode: 'timestamp_ms' })
      .notNull()
      .default(sql`(unixepoch('subsec') * 1000)`)
  },
  (table) => [
    index('usage_events_user_id_idx').on(table.userId),
    index('usage_events_created_at_idx').on(table.createdAt)
  ]
);

export const usersRelations = relations(users, ({ many }) => ({
  subscriptions: many(subscriptions),
  usageEvents: many(usageEvents)
}));

export const subscriptionsRelations = relations(subscriptions, ({ one }) => ({
  user: one(users, {
    fields: [subscriptions.userId],
    references: [users.id]
  })
}));

export const usageEventsRelations = relations(usageEvents, ({ one }) => ({
  user: one(users, {
    fields: [usageEvents.userId],
    references: [users.id]
  })
}));
