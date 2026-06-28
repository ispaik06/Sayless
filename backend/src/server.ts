import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance } from 'fastify';
import { assertAIConfigured, config } from './config.js';
import { registerRoutes } from './routes.js';

async function buildServer() {
  assertAIConfigured();

  const app = Fastify({
    logger: {
      level: config.nodeEnv === 'development' ? 'info' : 'warn',
      redact: [
        'req.headers.authorization',
        'req.headers.x-sayless-client-key',
        'OPENAI_API_KEY',
        'GEMINI_API_KEY',
        'GROQ_API_KEY'
      ]
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

function installShutdownHandlers(app: FastifyInstance) {
  let isShuttingDown = false;

  async function shutdown(signal: NodeJS.Signals) {
    if (isShuttingDown) {
      return;
    }

    isShuttingDown = true;

    console.log(
      JSON.stringify({
        event: 'sayless_backend_shutdown_started',
        signal
      })
    );

    const forceExit = setTimeout(() => {
      console.error(
        JSON.stringify({
          event: 'sayless_backend_shutdown_forced',
          signal
        })
      );
      process.exit(1);
    }, 8000);
    forceExit.unref();

    try {
      await app.close();
      clearTimeout(forceExit);
      console.log(
        JSON.stringify({
          event: 'sayless_backend_shutdown_complete',
          signal
        })
      );
      process.exit(0);
    } catch (error) {
      clearTimeout(forceExit);
      const message = error instanceof Error ? error.message : 'unknown shutdown error';
      console.error(
        JSON.stringify({
          event: 'sayless_backend_shutdown_failed',
          signal,
          message
        })
      );
      process.exit(1);
    }
  }

  process.once('SIGTERM', () => {
    void shutdown('SIGTERM');
  });

  process.once('SIGINT', () => {
    void shutdown('SIGINT');
  });
}

async function main() {
  const app = await buildServer();

  await app.listen({
    host: config.host,
    port: config.port
  });

  console.log(
    JSON.stringify({
      event: 'sayless_backend_listening',
      host: config.host,
      port: config.port,
      nodeEnv: config.nodeEnv,
      provider: config.suggestionProvider,
      model: config.aiModel
    })
  );

  installShutdownHandlers(app);

  app.log.info(
    {
      host: config.host,
      port: config.port,
      nodeEnv: config.nodeEnv,
      provider: config.suggestionProvider,
      model: config.aiModel
    },
    'sayless backend listening'
  );
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : 'unknown startup error';
  console.error(`[Sayless][Backend] startup failed: ${message}`);
  process.exit(1);
});
