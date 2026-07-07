import { assertAIConfigured, createConfig, type Env } from './config.js';
import { createDb } from './db/client.js';
import { handleRequest } from './routes.js';

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const config = createConfig(env);
      assertAIConfigured(config);
      const db = createDb(config);

      return await handleRequest({
        config,
        db,
        request
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'unknown worker error';

      console.error(
        JSON.stringify({
          event: 'sayless_worker_error',
          message
        })
      );

      return new Response(
        JSON.stringify({
          error: 'configuration_error',
          message: 'Backend is not configured'
        }),
        {
          status: 500,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'Access-Control-Allow-Origin': '*'
          }
        }
      );
    }
  }
};
