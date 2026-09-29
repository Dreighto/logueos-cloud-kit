# Execution Validation (practice project)

Evidence for the skill's claims: a throwaway Vapor+Fluent+SQLite project built + tested on room
(Swift 6.3.3). Source: `~/dev/fluent-practice` (throwaway). 17/17 tests pass.  <!-- canon-lint: skip (historical practice repo) -->

## Fluent/Vapor Skill Validation — EXECUTION REPORT

Built a throwaway blog-domain project at `/home/dreighto/dev/fluent-practice` and proved every claim by real build + test runs. **All 17 tests pass, clean build under Swift 6 strict concurrency.**  <!-- canon-lint: skip (historical practice repo) -->

### Commands run + key output

```
$ swift build
Build complete! (0.27s)          # zero warnings/errors in App target

$ swift test
✔ Test run with 17 tests in 8 suites passed after 1.720 seconds.
```

Ran the full suite 3x back-to-back — 17/17 pass each time (confirmed stable, since one fix was timing-sensitive).

Versions resolved (from `Package.resolved`): vapor 4.122.0, fluent 4.13.0, fluent-kit 1.57.0, fluent-sqlite-driver (4.9+), fluent-postgres-driver 2.12.0, sqlite-nio 1.12.9, Swift 6.3.3.

### The 13 validation items

| #   | Item                                                           | Status       | Evidence (test)                                                                                                                       |
| --- | -------------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | App connects to DB (SQLite; PG compiled+documented)            | **VERIFIED** | `MigrationAndConnectionTests.connects`; PG `.postgres(url:)`/`.psql` branch in `configure.swift` compiles clean                       |
| 2   | Related models                                                 | **VERIFIED** | `RelationshipTests.relations`                                                                                                         |
| 3   | One-to-many (Author→Posts) + many-to-many (Post↔Tag)           | **VERIFIED** | `RelationshipTests.relations`                                                                                                         |
| 4   | Eager `.with` + NESTED (`author→posts→tags`) + self-ref mentor | **VERIFIED** | `RelationshipTests.eagerAndNested`, `.selfReference`                                                                                  |
| 5   | Pagination + `~~` filtering                                    | **VERIFIED** | `QueryFeatureTests.paginatedSearch` (total=5, pageCount=3)                                                                            |
| 6   | `db.transaction {}` that throws → rollback                     | **VERIFIED** | `IntegrityTests.transactionRollback` (0 rows survive)                                                                                 |
| 7   | UNIQUE + FK (bogus author_id throws; cascade; PRAGMA verified) | **VERIFIED** | `IntegrityTests` unique/FK/cascade/softDelete — `PRAGMA foreign_keys` reads `1`, enforcement confirmed                                |
| 8   | Migration apply + REVERT cleanly                               | **VERIFIED** | `MigrationAndConnectionTests.migrateThenRevert` (query throws after `autoRevert`)                                                     |
| 9   | Repository/service layer                                       | **VERIFIED** | `PostRepository` used by `paginatedSearch` + HTTP routes                                                                              |
| 10  | Unit + integration tests                                       | **VERIFIED** | unit (`createDTOStripsExtras`, raw SQL) + HTTP integration (`IntegrationTests`)                                                       |
| 11  | N+1 detection via query counting                               | **VERIFIED** | `PerformanceTests.nPlusOne`: naive=6, eager=2, counted BOTH by a swift-log `LogHandler` AND `app.fluent.history` — they agree exactly |
| 12  | Raw SQL via SQLKit (justified aggregate)                       | **VERIFIED** | `QueryFeatureTests.rawAggregate` (`GROUP BY author_id` COUNT)                                                                         |
| 13  | Flawed → corrected                                             | **VERIFIED** | N+1 naive-vs-eager + mass-assignment (`ForgedCreate` with extra `id` dropped by `CreatePostDTO`)                                      |

Nothing was left unverified or fabricated.

### Fluent 4.13 API gotchas discovered (gold for the skill)

1. **SQLite in-memory pooling** — confirmed by execution. fluent-sqlite-driver hardcodes `maxConnectionsPerEventLoop: 1` over the whole EventLoopGroup, and plain `:memory:` is private per connection → multi-event-loop app gives each loop its own empty DB ("no such table"). **Fixes used:** (a) per-test on-disk file at a unique temp path (whole suite — bulletproof), and (b) `Application.make(.testing, .shared(MultiThreadedEventLoopGroup(numberOfThreads: 1)))` to pin one connection (`InMemoryGotchaTests` proves `.sqlite(.memory)` then works).

2. **FK pragma** — fluent-sqlite-driver 4.9 **does** enable `PRAGMA foreign_keys=ON`. Verified two ways: read the pragma back (`=1`) and a bogus-author_id insert throws. So SQLite FK tests are meaningful here (don't assume they're off).

3. **Query counting — `app.fluent.history` exists.** The skill says "no built-in query-count API"; that's a miss. `app.fluent.history.start()/.queries.count/.clear()/.stop()` is a built-in recorder and matched the LogHandler count exactly (6 vs 2). **Its own gotcha:** `app.db` snapshots the history recorder at access time — a handle captured with `let db = app.db` _before_ `history.start()` records nothing. Must fetch `app.db` fresh after `start()`.

4. **Log-line counting mechanics** — FluentKit logs `"Running query"` at `.debug` per `DatabaseQuery`. A counting `LogHandler` works only if (a) bootstrapped once via `LoggingSystem.bootstrap` before any Logger, and (b) `app.logger.logLevel = .debug` (Vapor defaults higher, suppressing the lines). swift-log's current API wants `log(event:)` implemented, not the deprecated `log(level:…)`.

5. **In-memory tester first-request 404** (cost the most iterations) — the `app.testing()` (`.inMemory`) responder can return **404 for the app's very first HTTP request** to a freshly-configured app. Root cause: `app.routes` is a non-atomic get-or-create over `Application.storage` (`Routing/Application+Routes.swift`), and the responder rebuilds from `app.routes` on a DB event-loop thread — a fresh app that's never been "touched" resolves an empty Routes. It reproduces on **both** `.inMemory` and `.running(port:0)`. Any awaited DB round-trip immediately before the first request (which every real test naturally does) fixes it. Notably, touching state in the `withApp` helper _before_ the body did NOT reliably fix it — the warm-up must land right before `app.testing()`.

6. **API shapes that differed from a first guess:** `.postgres(url:)` is throwing → needs `try`. `@Siblings` array `attach([...])` has **no** `method:` overload (only single-model `attach(_:method:on:)`). `#expect(try await freeFunction() == x)` fails to propagate the throw for a standalone function call — hoist to a `let` first (method-chain forms like `X.query().count() == n` compile fine).

7. **Swift 6 strict concurrency:** every model is `final class …: Model, @unchecked Sendable` (matches the reference). The custom `LogHandler` needed `nonisolated(unsafe)` on its mutable `logLevel`/`metadata` and a `NIOLockedValueBox` counter to be Sendable-clean.

### Design notes

- Serialized the root `@Suite(.serialized)` because the harness mutates process globals (`SQLITE_FILE` env for the per-test DB file, and the query-counter). Each test still gets its own Application + unique on-disk SQLite file.
- `configure` maps `.testing`→SQLite (file if `SQLITE_FILE` set, else `:memory:`), `DATABASE_URL`→Postgres (compile-only), else on-disk file.

### Final file tree

```
fluent-practice/
├── Package.swift
├── Package.resolved
├── Sources/App/
│   ├── configure.swift          entrypoint.swift  routes.swift
│   ├── Models/         Author.swift  Post.swift  Tag.swift  PostTag.swift
│   ├── Migrations/     CreateAuthor  CreateTag  CreatePost  CreatePostTag
│   ├── DTOs/           PostDTOs.swift            (CreatePostDTO / PostDTO / HealthDTO)
│   ├── Services/       PostRepository.swift
│   └── Support/        QueryCountingLogHandler.swift
└── Tests/AppTests/
    ├── TestSupport.swift          (withApp helper, logging bootstrap, seed helpers)
    ├── MigrationAndConnectionTests.swift   RelationshipTests.swift
    ├── QueryFeatureTests.swift             IntegrityTests.swift
    ├── PerformanceTests.swift              IntegrationTests.swift
    └── InMemoryGotchaTests.swift
```

Project root is clean (stray dev `.sqlite` removed). No production code touched.

---

## Doc-Verification Pass (2026-07-11)

Separate from the execution-validation above, a 4-agent research fan-out re-checked every
`[inferred-from-research]` rule in the reference files against version-pinned primary sources
(official Vapor/Fluent docs, `api.vapor.codes` for the resolved tag, the vapor GitHub driver source,
and PostgreSQL/SQLite official docs). Anchor: Vapor 4.122, FluentKit 1.57.0, fluent-postgres-driver
2.12, fluent-sqlite-driver 4.9, PostgreSQL 12+, Swift 6.2/6.3.

**Outcome: 41 inferred rules checked → 36 confirmed and upgraded to `[verified-by-docs]`, 1 corrected,
4 kept inferred.**

| File             | Confirmed→upgraded | Kept inferred                                           | Corrected                                 |
| ---------------- | ------------------ | ------------------------------------------------------- | ----------------------------------------- |
| migrations.md    | 8                  | 0                                                       | 0                                         |
| performance.md   | 7                  | 0                                                       | 0                                         |
| testing.md       | 5                  | 1 (fixtures/factories advisory)                         | 1 (N+1: `app.fluent.history` is official) |
| architecture.md  | 4                  | 1 (domain-vs-persistence split)                         | 0                                         |
| drivers.md       | 4                  | 0                                                       | 0                                         |
| security.md      | 2                  | 2 (Idempotency-Key; pool-acquisition-timeout sub-claim) | 0                                         |
| transactions.md  | 3                  | 0                                                       | 0                                         |
| models.md        | 1                  | 0                                                       | 0                                         |
| queries.md       | 1                  | 0                                                       | 0                                         |
| relationships.md | 1                  | 0                                                       | 0                                         |

**Correction:** the testing N+1 rule (and the testing overview prose) previously claimed "there is no
official Fluent query-count API." FluentKit ships `app.fluent.history` with public
`start()`/`stop()`/`clear()`/`queries: [DatabaseQuery]` (verified in vapor/fluent `Fluent+History.swift`
and fluent-kit `QueryHistory.swift`). Both were rewritten around the official recorder.

**The 4 rules still `[inferred-from-research]`** are sound engineering with no version-pinned Vapor/
Fluent/PostgreSQL primary source, treat as "verify before relying": fixtures/factory advisory
(testing.md), the `Idempotency-Key` write-idempotency pattern (security.md), the connection-pool
acquisition-timeout Vapor API sub-claim (security.md, PG `statement_timeout` + 409 in that rule ARE
confirmed), and the domain-vs-persistence model split (architecture.md).

Method: read each reference file, extracted the inferred rules, verified each against primary sources
with per-rule verdicts (confirmed/refuted/uncertain) + citations; no execution against the practice
project in this pass (doc/source verification only).
