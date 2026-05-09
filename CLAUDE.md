# Taskade Tower — Codebase Guide

## Project Overview

Taskade Tower is a Node.js/Express proxy and integration server that exposes a unified REST API for several third-party services: Taskade, Google Docs, Gemini AI, Cloudflare, Hugging Face, GitLab, and Notion. It is hosted on Replit and tunnelled externally via Cloudflare Tunnel (domain: `oneseco.com`).

## Repository Structure

```
Taskade-Tower/
├── index.js                  # Main Express app — all routes live here
├── google-docs-service.js    # Google Docs + Drive SDK wrapper
├── gemini-service.js         # Google Gemini AI (generative AI) wrapper
├── cloudflare-service.js     # Cloudflare API wrapper
├── huggingface-service.js    # Hugging Face Inference API wrapper
├── gitlab-service.js         # GitLab API wrapper (@gitbeaker/node)
├── notion-service.js         # Notion OAuth + REST API wrapper
├── package.json              # Dependencies (Express, axios, SDKs)
├── .env.example              # Template for required environment variables
├── .gitignore                # Standard Node ignores + .env + .cloudflared/*.json
├── .replit                   # Replit config — entry: index.js, port 3000
├── replit.nix                # Nix channel config for Replit
├── setup-tunnel.sh           # Helper script to configure Cloudflare Tunnel locally
├── .cloudflared/config.yml   # Cloudflare Tunnel ingress config (oneseco.com → localhost:3000)
├── *-test.html               # Browser-based test UIs for each service
├── test-client.html          # Main test UI (Taskade endpoints)
├── docs-embed-example.html   # Google Docs embed demo
└── attached_assets/          # Static assets (images, exported HTML)
```

## Running the Server

```bash
npm install          # install dependencies
node index.js        # start on port 3000 (default)
```

The Replit run button executes `node index.js`. There is no build step and no test suite.

## Environment Variables

Copy `.env.example` to `.env` and fill in values. **Never commit `.env`.**

| Variable | Required by | Notes |
|---|---|---|
| `TASKADE_API_KEY` | Taskade routes | `x-api-key` header to Taskade v1 API |
| `NOTION_OAUTH_CLIENT_ID` | Notion routes | Pre-filled: `21510b32-d6d2-43a0-821a-adc88f938680` |
| `NOTION_OAUTH_CLIENT_SECRET` | Notion routes | Must be set |
| `NOTION_REDIRECT_URI` | Notion OAuth | Default: `https://oneseco.com` |
| `GOOGLE_SERVICE_ACCOUNT_EMAIL` | Google Docs | Service account email |
| `GOOGLE_PRIVATE_KEY` | Google Docs | PEM key with `\n` escaping |
| `GEMINI_API_KEY` | Gemini routes | Google AI Studio key |
| `CLOUDFLARE_API_KEY` | Cloudflare routes | Global API key |
| `CLOUDFLARE_EMAIL` | Cloudflare routes | Account email |
| `HUGGINGFACE_API_KEY` | HuggingFace routes | HF Access Token |
| `GITLAB_API_KEY` | GitLab routes | Personal Access Token |
| `GITLAB_HOST` | GitLab routes | Default: `https://gitlab.com` |

Services whose keys are absent are gracefully degraded — they log a warning at startup and return HTTP 503 on any request.

## Architecture

### Service Initialization Pattern

Each service module is instantiated at startup inside a `try/catch`. If the required env vars are missing the error is caught, the service variable is left `undefined`, and every route for that service checks for it and returns 503 immediately. This keeps the entire server running even if individual integrations are not configured.

```js
let geminiService;
try {
  geminiService = new GeminiService();
} catch (error) {
  console.warn('Gemini service not initialized:', error.message);
}
```

### Authentication Middleware

Taskade endpoints use the `authenticateRequest` middleware defined in `index.js`. It reads `TASKADE_API_KEY` from `process.env`, attaches it to `req.apiKey`, and returns 401 if absent. All other service endpoints handle their own credentials internally.

### Response Shape Convention

All routes return JSON. Success responses always include `"success": true` plus a named payload key. Error responses return `{ "error": "<message>" }` with an appropriate HTTP status code.

## API Route Groups

### Taskade (`/taskade-tower/*`)
All routes require `TASKADE_API_KEY` via `authenticateRequest`.

| Method | Path | Description |
|---|---|---|
| GET | `/taskade-tower/health` | Health check |
| GET | `/taskade-tower/agents` | List agents |
| POST | `/taskade-tower/agents` | Create agent |
| GET | `/taskade-tower/agents/:id` | Get agent |
| PUT | `/taskade-tower/agents/:id` | Update agent |
| DELETE | `/taskade-tower/agents/:id` | Delete agent |
| POST | `/taskade-tower/agents/:id/execute` | Execute agent |

### Google Docs (`/google-docs/*`)
Requires Google service account credentials in env.

| Method | Path | Description |
|---|---|---|
| POST | `/google-docs/create` | Create document |
| GET | `/google-docs/:documentId` | Read document |
| POST | `/google-docs/:documentId/insert` | Insert text at beginning |
| POST | `/google-docs/:documentId/append` | Append text at end |
| POST | `/google-docs/:documentId/replace` | Replace text |
| POST | `/google-docs/:documentId/update` | Custom batchUpdate |

### Gemini AI (`/gemini/*`)
Requires `GEMINI_API_KEY`. Uses `gemini-pro` model.

| Method | Path | Description |
|---|---|---|
| POST | `/gemini/generate` | Generate text from prompt |
| POST | `/gemini/analyze` | Analyze text (`summary`/`sentiment`/`keywords`/`improve`) |
| POST | `/gemini/generate-document` | Generate content, optionally write to Google Doc |
| POST | `/gemini/enhance-document/:documentId` | Enhance existing Google Doc content |
| GET | `/gemini/analyze-document/:documentId` | Analyze Google Doc content |

### Cloudflare (`/cloudflare/*`)
Requires `CLOUDFLARE_API_KEY` and `CLOUDFLARE_EMAIL`.

| Method | Path | Description |
|---|---|---|
| GET | `/cloudflare/zones` | List zones |
| GET | `/cloudflare/zones/:zoneId` | Get zone |
| GET/POST | `/cloudflare/zones/:zoneId/dns` | DNS records |
| PUT/DELETE | `/cloudflare/zones/:zoneId/dns/:recordId` | Modify DNS record |
| POST | `/cloudflare/zones/:zoneId/purge-cache` | Purge cache |
| GET | `/cloudflare/zones/:zoneId/analytics` | Zone analytics |
| GET/PUT | `/cloudflare/zones/:zoneId/security` | Security settings |
| PUT | `/cloudflare/zones/:zoneId/security-level` | Set security level |
| GET/PUT | `/cloudflare/zones/:zoneId/ssl` | SSL settings |

### Hugging Face (`/huggingface/*`)
Requires `HUGGINGFACE_API_KEY`. All routes accept optional `model` to override defaults.

| Method | Path | Default model |
|---|---|---|
| POST | `/huggingface/text-generation` | `gpt2` |
| POST | `/huggingface/text-classification` | `cardiffnlp/twitter-roberta-base-sentiment-latest` |
| POST | `/huggingface/question-answering` | `deepset/roberta-base-squad2` |
| POST | `/huggingface/summarization` | `facebook/bart-large-cnn` |
| POST | `/huggingface/entity-recognition` | `dbmdz/bert-large-cased-finetuned-conll03-english` |
| POST | `/huggingface/translation` | `Helsinki-NLP/opus-mt-en-fr` |
| POST | `/huggingface/embeddings` | `sentence-transformers/all-MiniLM-L6-v2` |
| POST | `/huggingface/fill-mask` | `bert-base-uncased` |
| POST | `/huggingface/image-classification` | `google/vit-base-patch16-224` |
| POST | `/huggingface/object-detection` | `facebook/detr-resnet-50` |
| POST | `/huggingface/text-to-image` | `runwayml/stable-diffusion-v1-5` |

### GitLab (`/gitlab/*`)
Requires `GITLAB_API_KEY`. Uses `@gitbeaker/node`.

| Method | Path | Description |
|---|---|---|
| GET | `/gitlab/user` | Current user |
| GET/POST | `/gitlab/projects` | List/create projects |
| GET | `/gitlab/projects/:id` | Get project |
| GET/POST | `/gitlab/projects/:id/branches` | Branches |
| GET | `/gitlab/projects/:id/commits` | Commits (filterable by `ref_name`, `since`, `until`, `path`) |
| GET | `/gitlab/projects/:id/commits/:sha` | Single commit |
| GET/POST | `/gitlab/projects/:id/issues` | Issues |
| PUT | `/gitlab/projects/:id/issues/:iid` | Update issue |
| GET/POST | `/gitlab/projects/:id/merge_requests` | Merge requests |
| GET/POST | `/gitlab/projects/:id/pipelines` | Pipelines |
| GET/POST | `/gitlab/projects/:id/members` | Project members |
| GET/POST/DELETE | `/gitlab/projects/:id/repository/files` | Repository file ops |
| GET | `/gitlab/projects/:id/statistics` | Project stats |

### Notion (`/notion/*`)
Uses OAuth 2.0 flow. Tokens are stored in-memory (lost on restart — see Known Limitations).

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/notion/auth` | — | Redirect to Notion OAuth |
| GET | `/notion/callback` | — | Exchange code for token |
| POST | `/notion/search` | `access_token` in body | Search pages/databases |
| GET | `/notion/pages/:pageId` | `access_token` header | Get page |
| PATCH | `/notion/pages/:pageId` | `access_token` header | Update page |
| DELETE | `/notion/pages/:pageId` | `access_token` header | Archive page |
| POST | `/notion/pages` | `access_token` in body | Create page |
| GET | `/notion/blocks/:blockId/children` | `access_token` header | Get block children |
| PATCH | `/notion/blocks/:blockId/children` | `access_token` header | Append blocks |
| GET | `/notion/databases/:databaseId` | `access_token` header | Get database |
| POST | `/notion/databases/:databaseId/query` | `access_token` in body | Query database |
| GET | `/notion/users` | `access_token` header | List workspace users |

## Test Interfaces

Each service has a corresponding HTML file served by the server:

| URL | File |
|---|---|
| `/test` | `test-client.html` (Taskade) |
| `/google-docs-test` | `google-docs-test.html` |
| `/gemini-test` | `gemini-test.html` |
| `/cloudflare-test` | `cloudflare-test.html` |
| `/huggingface-test` | `huggingface-test.html` |
| `/gitlab-test` | `gitlab-test.html` |
| `/notion-test` | `notion-test.html` |

These are self-contained browser UIs that make `fetch()` calls to the local API. They are development tools only, not a production UI.

## Deployment

### Replit
- Entry point: `node index.js`
- Port: `3000` (binds `0.0.0.0`)
- Deployment target: Cloud Run (see `.replit`)
- Object storage bucket configured via `@replit/object-storage`

### Cloudflare Tunnel (local Mac development)
The tunnel exposes the local server at `oneseco.com`:

```bash
bash setup-tunnel.sh   # one-time: install cloudflared + create tunnel
cloudflared tunnel run taskade-tower   # run the tunnel
```

Config is in `.cloudflared/config.yml`. Tunnel credential JSON files are gitignored.

## Known Limitations

1. **Notion tokens are in-memory only** — `NotionService.tokens` resets on every server restart. A persistent store (database, KV) is needed for production.
2. **No test suite** — `npm test` exits with an error. All testing is manual via the HTML test UIs.
3. **`google-docs-service.js` defines `createDocument` twice** — the second definition (lines 152–164) overwrites the first. The first version also sets public permissions via Drive; the second does not.
4. **No rate limiting or request validation middleware** — endpoints trust body shape and rely on downstream APIs to reject bad input.
5. **`gemini-pro` model** — `GeminiService` hardcodes `gemini-pro`. Newer model IDs may be needed as Google deprecates older ones.

## Adding a New Service

1. Create `<name>-service.js` exporting a class with methods.
2. `require()` it at the top of `index.js`.
3. Instantiate it in a `try/catch` block following the existing pattern.
4. Add routes grouped by prefix, checking `if (!<service>) return res.status(503).json(...)` at the top of each handler.
5. Add any new env vars to `.env.example`.
6. Create `<name>-test.html` and a corresponding `GET /<name>-test` route.
