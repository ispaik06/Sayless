import { createClient } from '@libsql/client/web';
import { drizzle } from 'drizzle-orm/libsql';
import type { AppConfig } from '../config.js';
import * as schema from './schema.js';

export function createDb(config: AppConfig) {
  const client = createClient({
    url: config.tursoDatabaseUrl,
    authToken: config.tursoAuthToken
  });

  return drizzle(client, { schema });
}

export type Database = ReturnType<typeof createDb>;
