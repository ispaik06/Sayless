import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { config } from '../config.js';
import * as schema from './schema.js';

const client = createClient({
  url: config.tursoDatabaseUrl,
  authToken: config.tursoAuthToken
});

export const db = drizzle(client, { schema });
