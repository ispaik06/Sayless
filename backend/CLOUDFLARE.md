# Cloudflare Workers Deployment

> Deprecated: Sayless backend hosting is no longer supported by this project.
> This file is retained only as a reference for forks that want to run their own backend.

## Worker Settings

Cloudflare dashboard path:

1. Workers & Pages
2. Create
3. Worker
4. Import a repository
5. Select this repository

Use these build settings:

```text
Root directory: backend
Build command: npm install
Deploy command: npm run deploy
```

The Worker entrypoint is configured in `wrangler.toml`:

```text
main = "src/worker.ts"
compatibility_flags = ["nodejs_compat"]
```

## Variables

Set these as plain variables unless you need to hide them:

```text
AI_PROVIDER=gemini
AI_MODEL=gemini-3.5-flash
NODE_ENV=production
FREE_DAILY_SUGGESTION_LIMIT=100
FREE_WEEKLY_SUGGESTION_LIMIT=500
GITHUB_RELEASE_OWNER=ispaik06
GITHUB_RELEASE_REPO=Sayless
```

Set these as encrypted secrets:

```text
CLERK_SECRET_KEY
CLERK_PUBLISHABLE_KEY
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
GEMINI_API_KEY
OPENAI_API_KEY
GROQ_API_KEY
GITHUB_TOKEN
```

Only one AI provider key is required. If `AI_PROVIDER=gemini`, set `GEMINI_API_KEY`.

## Custom Domain

After the first successful deploy:

1. Open the Worker in Cloudflare.
2. Go to Settings.
3. Open Domains & Routes.
4. Add a route or custom domain for your fork, for example `api.your-domain.example`.
5. Update the macOS app backend URL to the deployed Worker URL or custom domain.

## Smoke Test

Open:

```text
https://<your-worker-subdomain>.workers.dev/health
```

Expected response:

```json
{
  "ok": true,
  "service": "sayless-backend",
  "provider": "gemini",
  "model": "gemini-3.5-flash"
}
```
