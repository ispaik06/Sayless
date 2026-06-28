import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import Fastify from 'fastify';
import { assertOpenAIConfigured, config } from './config.js';
import { registerRoutes } from './routes.js';

async function buildServer() {
  assertOpenAIConfigured();

  const app = Fastify({
    logger: {
      level: config.nodeEnv === 'development' ? 'info' : 'warn',
      redact: ['req.headers.authorization', 'req.headers.x-sayless-client-key', 'OPENAI_API_KEY']
    },
    bodyLimit: 64 * 1024
  });

  await app.register(cors, {
    origin: false
  });

  await app.register(rateLimit, {
    max: 120,
    timeWindow: '1 minute'
  });

  await registerRoutes(app);

  return app;
}

async function main() {
  const app = await buildServer();

  await app.listen({
    host: config.host,
    port: config.port
  });

  app.log.info(
    {
      host: config.host,
      port: config.port,
      nodeEnv: config.nodeEnv,
      mode: config.suggestionMode
    },
    'sayless backend listening'
  );
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : 'unknown startup error';
  console.error(`[Sayless][Backend] startup failed: ${message}`);
  process.exit(1);
});
