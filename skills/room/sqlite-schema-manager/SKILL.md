---
name: sqlite-schema-manager
description: Apply schema discipline whenever creating, altering, or querying tables in logueos_memory.db (or any project SQLite database). Use BEFORE adding a column to an existing table, BEFORE writing a new `addChatMessage`-style helper, BEFORE emitting an observation that may contain operator data, or whenever the operator reports "the migration didn't take", "the DB has stale rows", "the column is missing on older installs", "API key leaked into a log". Do NOT use for read-only queries (just use the `sqlite` MCP) or for `card_catalog.db` (project-miru constraint — never write).
---

# SQLite Schema Manager

LogueOS persists operator state in `logueos_memory.db` (at the path in `serverConfig.memoryDbPath`). It holds chat history, thread metadata, web push subscriptions, token usage, and the Tier 0/1 observation pool. Schema changes ripple immediately to live operator sessions, so every change must be additive, idempotent, and reversible. This skill exists because we've shipped schema regressions that broke older DB files multiple times.

## The non-negotiables

### 1. Migrations are idempotent or they don't ship

Every table-creation path uses `CREATE TABLE IF NOT EXISTS`. Every column-addition uses `ALTER TABLE ADD COLUMN` wrapped in the duplicate-column swallow:

```ts
try {
  db.exec(
    `ALTER TABLE chat_thread_state ADD COLUMN provider_override TEXT NULL`,
  );
} catch (e) {
  if (!(e instanceof Error && /duplicate column/i.test(e.message))) throw e;
}
```

Why: workers / dev machines / the operator's laptop all carry DBs at different schema versions. A migration that errors on "already exists" stops everything from initializing.

### 2. Never drop columns

SQLite's `ALTER TABLE DROP COLUMN` exists but it's a footgun — it doesn't rewrite the table file, just hides the column from the schema. Real removal requires the table-rename-copy-rename pattern, which is high-risk on a live DB. Instead: leave the column, stop reading it, set it to nullable if it wasn't. Future-you can do the rewrite during a planned downtime if it ever matters.

### 3. Never modify schema inside a request handler

Schema changes go in the table-ensure helper that runs on first DB connection (per process). Not in `POST /api/foo` handlers. A schema change during a request can wedge other concurrent requests with locked-table errors.

### 4. Always back up before write-heavy operations

Operator's authorized `card_catalog.db` writes per memory `feedback_db_writes_allowed`, but the protocol is:

```bash
cp ~/dev/.../card_catalog.db ~/dev/.../card_catalog.db.bak.$(date +%Y%m%d-%H%M%S)
```

Then run the write. Then surface the diff in the commit. Same for `logueos_memory.db` if doing bulk changes.

### 5. The append-only JSONL invariant (HARD RULE)

Twelve files in `data/` (per kernel CLAUDE.md) are strictly append-only:

```
data/cc_completion_log.jsonl       data/routing_history.jsonl
data/pending_callbacks.jsonl       data/dispatch_dlq.jsonl
data/cc_heartbeat_log.jsonl        data/vp_ops_supervision.jsonl
data/drift_scanner_log.jsonl       data/agent_decisions.jsonl
data/github_resource_ledger.jsonl  data/usage_anomalies.jsonl
data/salvage_reports.jsonl         data/hermes_predictions.jsonl
```

Never edit, truncate, sort, deduplicate, or read-modify-write. Only `fs.appendFileSync` or shell `>>`. Use the helper scripts (`tools/emit/emit_completion.py`, `tools/emit/emit_heartbeat.py`) — do not hand-roll the append.

## The schemas to know

### chat_messages (oldest, most fields)

The chat history table. Append-only via `addChatMessage()`. Indexed by `thread_id`. Each row carries a `sender` ('operator' | 'agy' | 'cc' | 'system' | 'hermes'), `message` text, optional `trace_id` / `ticket_id` / `interactive_action`, and `timestamp`.

### chat_thread_meta

Per-thread metadata: `title`, `pinned`, `archived`, `summary`, `remember_flag`, `last_activity_at`. Created lazily on first message in a thread. Cascade-deleted by `deleteThread()`.

### chat_thread_state

Per-thread router state: `current_tier`, `operator_override`, `provider_override`, `last_model_used`. Operator overrides take precedence over the classifier's current_tier.

### chat_drafts

Per-thread draft text (the 300ms-debounced composer auto-save target). Single row per thread_id; UPSERT pattern.

### chat_uploads

Image-upload provenance: `id`, `filename`, `mime`, `size`, `target_repo`, `uploaded_at`. Written by `/api/chat/uploads`.

### web_push_subscriptions (when PWA push is fully shipped)

Endpoint, p256dh + auth keys, last-seen timestamp, dead-flag (set to true after a 410 Gone from the push provider — see `pwa-push-dispatcher`).

### chat_token_usage

Rolling daily per-provider counts: `date`, `provider`, `tokens_used`. UPSERT keyed by `(date, provider)`.

## The env-redaction scanner (mandatory on Tier 0 emissions)

Before writing an observation row to `data/logueos_memory.db` (via `tools/emit/emit_observation.py` or its helpers), scan the `body` text for env-var values that match known sensitive patterns:

```python
# in tools/emit/emit_observation.py or wherever observations are persisted
SENSITIVE_ENV_KEYS = [
  'ANTHROPIC_API_KEY', 'OPENAI_API_KEY', 'GEMINI_API_KEY', 'GOOGLE_API_KEY',
  'MIRU_ROUTING_KEY', 'LOGUEOS_MCP_URL_SECRET', 'W4_LISTENER_HMAC_SECRET',
  'GH_TOKEN', 'GITHUB_TOKEN_READ', 'GITHUB_TOKEN_WRITE', 'LINEAR_API_KEY',
  'ASSEMBLY_AI_API_KEY', 'ELEVENLABS_API_KEY', 'PERPLEXITY_API_KEY',
  'FIRECRAWL_API_KEY', 'JUSTTCG_API_KEY', 'CURSOR_API_KEY', 'CONTINUE_API_KEY',
  'CLAUDE_CODE_OAUTH_TOKEN',
]

def redact(body: str) -> str:
  for k in SENSITIVE_ENV_KEYS:
    val = os.environ.get(k, '')
    if val and len(val) > 10 and val in body:
      body = body.replace(val, f'<{k}_REDACTED>')
  return body
```

Why: Tier 0 emissions flow into the team memory pool, which is shared across workers AND sometimes excerpted in reports. A leaked API key in an observation body has no boundary.

## Verification

Before shipping a DB schema change:

1. Run the migration locally on the live DB (after the backup). `nvidia-smi` style check — show row counts before/after.
2. Use the `sqlite` MCP to verify the new column appears with the right type + nullability: `read_query: PRAGMA table_info(chat_thread_state)`.
3. Smoke a code path that USES the new column — read AND write — before declaring done.
4. For data migrations (re-keying, reformatting), run on a COPY first, diff the result against the original, then apply to the live.

## Related

- `proxy-auth-gatekeeper` — auth model for the routes that touch these tables
- `pwa-push-dispatcher` — companion for the web_push_subscriptions table
- [[reference-canonical-env]] — the .env file is the source of truth for env vars referenced here
- [[feedback-api-key-handling]] — never echo API key values, even in error logs
