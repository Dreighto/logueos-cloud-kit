# Fluent/Vapor Skill — Mastery Report

Authored 2026-07-09. Deliverable for "become the project's Swift Fluent specialist + produce a
reusable skill." This file is the authoring record; the loadable skill is `SKILL.md`.

## 1. What was produced

- **`SKILL.md`** (~360 lines / ~3.2k words) — the operational skill: activation, versions,
  project-detection, mental model, per-area rules (models, relationships, queries, migrations,
  transactions, testing, performance, security, architecture, drivers), a failure-pattern table, a
  stale→current version table, canonical examples, a completion checklist, and a refresh policy.
- **`references/`** (12 files, ~1.9k lines) — depth per topic with cited sources + confidence tags:
  models, relationships, queries, migrations, transactions, testing, performance, security,
  architecture, drivers, version-sensitive, plus `sources.md` (73 URLs) and `validation.md` (the
  execution report). `SKILL.md` tells the agent which reference to open when.
- **Practice project** — `~/dev/fluent-practice` (throwaway), a Vapor+Fluent+SQLite blog domain.  <!-- canon-lint: skip (historical practice repo, deleted after mastery) -->

## 2. Method

Parallel research fan-out (Firecrawl + Perplexity + WebFetch on docs.vapor.codes, api.vapor.codes,
and the vapor/* GitHub source) across 11 topic clusters, then a hands-on practice project that
built + tested every claim, then reconciliation where execution disagreed with the docs.
**Context7 was NOT connected in this environment** — substituted direct official-doc scraping and,
for the highest-stakes areas (transactions, drivers), reading the FluentKit/SQLKit/sqlite-kit
**source** directly.

## 3. Evidence separation (per the task's requirement)

- **Verified by execution** (practice project, 17/17 tests, clean Swift 6.3.3 build): model + all
  relationship kinds incl. self-ref, eager + nested eager load, pagination + `~~` filter,
  transaction rollback, UNIQUE + FK enforcement (SQLite `PRAGMA foreign_keys` = 1), migration
  apply+revert, repository layer, N+1 detection, raw-SQL aggregate, mass-assignment defense.
- **Verified by source** (read the repo source): transaction internals (bare `BEGIN`, no savepoints,
  READ COMMITTED), SQLKit upsert/`.for(.update)`, Postgres/SQLite driver config + TLS.
- **Verified by docs**: the bulk of model/relationship/query/migration/testing API rules
  (docs.vapor.codes), tagged `[verified-by-docs]` in the references.
- **Inferred from research**: production practices (expand-contract migrations, keyset pagination,
  RLS, idempotency) — tagged `[inferred-from-research]`; treat as "verify before relying."

## 4. Execution corrected the research (why the practice project mattered)

1. **`app.fluent.history` is a built-in query recorder.** Research (docs) claimed "no built-in
   query-count API"; execution found `app.fluent.history.start()/.queries.count/.clear()/.stop()`
   and it matched a custom LogHandler exactly (naive 6 vs eager 2). Skill corrected. Gotcha: capture
   `app.db` _after_ `history.start()` (it snapshots the recorder).
2. **`.sqlite(.memory)` is per-connection on the resolved versions.** One research agent read
   sqlite-kit source claiming a shared temp-file mapping (no gotcha); the practice project **hit
   "no such table"** and fixed it with a unique temp-file DB / single-thread EventLoopGroup. Skill
   reflects the execution truth and flags the discrepancy.
3. **SQLite FK enforcement is ON by default** (confirmed both by source and by execution: pragma
   reads 1, bogus FK throws) — so SQLite FK tests are meaningful.
4. Minor API corrections from execution: `.postgres(url:)` throws (needs `try`); `@Siblings`
   array `attach([...])` has no `method:` overload; a fresh app's first `app.testing()` request can
   404 (warm up with a DB round-trip first); custom `LogHandler` needs `nonisolated(unsafe)` +
   `NIOLockedValueBox` under Swift 6.

## 5. Commands run + results (practice project)

```
$ swift build      # → Build complete! (0.27s), zero warnings/errors in App target
$ swift test       # → Test run with 17 tests in 8 suites passed after 1.720s (3× stable)
```

Resolved versions: vapor 4.122.0, fluent 4.13.0, fluent-kit 1.57.0, fluent-postgres-driver 2.12.0,
fluent-sqlite-driver 4.9+, sqlite-nio 1.12.9, Swift 6.3.3. Full item-by-item table + gotchas in
`references/validation.md`.

## 6. Known gaps / unresolved

- **Postgres was not executed** — the practice suite ran on SQLite (hermetic, no server needed); the
  Postgres `configure` branch compiles but PG-specific behavior (native ENUM, ILIKE, JSONB, isolation
  levels, real pool contention) is doc/source-verified, not execution-verified here. Run a Dockerized
  PG suite to close this.
- docs.vapor.codes is **unversioned** — exact signatures for the 4.13.x tag were cross-checked
  against api.vapor.codes / GitHub source where it mattered, but not exhaustively.
- The `.memory` source-vs-execution discrepancy (item 4.2) suggests a sqlite-kit version nuance worth
  a definitive check against the exact resolved tag.
- Some production patterns (RLS tenant isolation across pooled connections, exact SQLKit onConflict
  builder spelling) remain `inferred` — verify before relying.

## 7. Refresh recommendation

Re-verify when `Package.resolved` shows a **FluentKit** major/minor bump (concurrency/Sendable
behavior tracks it, not the Fluent 4.13 number), a **driver** major bump (Postgres/SQLite config
APIs shift), a **Swift** major, or **Vapor 5** (removes EventLoopFuture, changes lifecycle). To
refresh: re-run the research fan-out, re-run the practice project against the new versions, and
update the version anchor + version-sensitive table. Full policy in `SKILL.md` → "Refreshing this
skill."
