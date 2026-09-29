---
name: fluent-vapor
description: >-
  Use when working with Swift Fluent — the Vapor ORM — or server-side Swift persistence:
  defining `Model`s, migrations, `@Field`/`@Parent`/`@Children`/`@Siblings` relationships,
  the query builder, transactions, FluentPostgresDriver / FluentSQLiteDriver, connection
  pooling, or testing Fluent-backed apps. Activates on Vapor/Fluent/FluentKit database work.
---

# Fluent + Vapor (server-side Swift persistence)

Operational skill for building and reviewing Fluent-backed Vapor apps. This file carries the
**rules**; open a `references/<topic>.md` file for depth, cited sources, and long examples.
Fluent is part of the Swift + Vapor + FluentKit ecosystem, not a standalone language.

## Activate when a task involves

Vapor · Fluent · FluentKit · FluentPostgresDriver · FluentSQLiteDriver · `Model` · `Migration` /
`AsyncMigration` · `@ID`/`@Field`/`@OptionalField`/`@Timestamp`/`@Enum`/`@Group` · `@Parent`/
`@OptionalParent`/`@Children`/`@Siblings` · `.query(on:)` / `.filter` / `.with` / `.paginate` ·
`database.schema(...)` · `db.transaction` · Swift server-side persistence / a Postgres or SQLite
schema behind Vapor. For pure SwiftUI/iOS work use `swift-vapor-swiftui-professional` instead.

## Versions (anchor — verify before quoting APIs)

Swift 6.2/6.3 strict concurrency · Vapor 4.122 · Fluent 4.13 (the thin Vapor integration) ·
**FluentKit** (core ORM; Sendable requirement since 1.48 — **execution-validated here against
fluent-kit 1.57.0 / vapor 4.122 / Swift 6.3.3**, see `references/validation.md`; concurrency tracks
_this_ number, check `Package.resolved`) · fluent-postgres-driver 2.12 · fluent-sqlite-driver 4.9 · SQLKit/FluentSQL for
raw. EventLoopFuture APIs still ship (removed only in Vapor 5) but **async/await is the current
surface** — write that. Research date 2026-07-09; refresh policy at the bottom.

## Project-detection checklist

- `Package.swift` depends on `vapor/fluent` + a `fluent-*-driver`; targets import `Fluent`.
- Models are `final class X: Model` under `Sources/App/Models/`; migrations conform to
  `AsyncMigration` under `Migrations/`; `configure.swift` calls `app.databases.use(...)` +
  `app.migrations.add(...)`.
- `Package.resolved` pins the real FluentKit + driver versions — read it, don't assume.
- A `sully-vapor`-style repo on this machine (`~/dev/sully-vapor`) is a compiling Fluent 4.13 +
  Postgres reference for current idioms.

## Core mental model

1. A **Model** is a `final class` = one table. Property wrappers map Swift props to columns by
   **string key** (deliberately not keypaths, so migrations can reference dropped columns).
2. **Migrations are the schema's source of truth**, applied by name and irreversible in practice —
   the model class only describes what the app reads _today_.
3. Models are **reference types** and collide with Swift 6 `Sendable`; keep them **ephemeral and
   per-request**, and cross every concurrency/API boundary with a value-type `Codable & Sendable`
   **DTO**. Never hand a live model to an actor, `Task.detached`, or a queue payload.
4. The query builder is **parameterized by default** (safe); raw SQL via SQLKit is the only
   injection surface.
5. `req.db` inside routes (event-loop-affine); `app.db` in jobs/commands/background work.

---

## Model & schema rules → `references/models.md`

- Three hard requirements: `static let schema`, one `@ID`, and an empty `init() {}`.
- **Every model is `final class X: Model, @unchecked Sendable`** — this is Vapor's _official_
  guidance under Swift 6, not a hack (property wrappers synthesize mutable `_x` storage the
  compiler can't prove Sendable). Apply it to `Fields`, `ModelAlias`, and pivots too.
- Default id: `@ID(key: .id) var id: UUID?` (portable, auto-generated). Use
  `@ID(custom: "id", generatedBy: .database) var id: Int?` only for auto-increment ints.
- `@Field(key:)` = required column; `@OptionalField(key:)` = nullable. Keys are snake_case
  strings; property names camelCase. A non-optional `@Field` over a NULL column throws at decode.
- `@Timestamp(key:, on: .create/.update/.delete)` as `Date?`. `.delete` = **soft delete**: normal
  queries hide rows, `.withDeleted()` includes, `.restore(on:)` undeletes, `delete(force: true)`
  hard-deletes. Match storage format to column type (`.iso8601`→`.string`, `.unix`→`.double`).
- Enums: native `@Enum` needs a `database.enum(...).create()` migration and `ALTER TYPE ADD VALUE`
  (forward-only) to extend — **prefer a `.string`-backed `Codable` enum in `@Field`** for
  value sets that change (adding a case then needs no DDL).
- **DTOs, not models, on the wire** — decode a create/update DTO and map Model→response DTO;
  never `req.content.decode(User.self)` (mass-assignment) or return the model (leaks columns).
- Community idiom: a nested `enum FieldKeys { static let x: FieldKey = "x" }` referenced by both
  model and migration kills stringly-typed drift (official docs still show inline strings).

## Relationship rules → `references/relationships.md`

| Relation          | Wrapper                                                | FK / storage                         |
| ----------------- | ------------------------------------------------------ | ------------------------------------ |
| to-one (required) | `@Parent(key: "star_id") var star: Star`               | FK column on this model              |
| to-one (nullable) | `@OptionalParent(key:) var star: Star?`                | nullable FK, drop `.required`        |
| one-to-many       | `@Children(for: \.$star) var planets: [Planet]`        | none (FK on child)                   |
| one-to-one        | `@OptionalChild(for: \.$planet)`                       | none; add `.unique(on:)` on child FK |
| many-to-many      | `@Siblings(through: Pivot.self, from: \.$a, to: \.$b)` | pivot model w/ two `@Parent`         |
| self-reference    | same-model `@OptionalParent` + `@Children`             | FK to own table                      |

- Set a parent by id, never by object: `model.$star.id = other.id`.
- A pivot is any Model with two `@Parent`s; add `.unique(on: "a_id", "b_id")` to block dup links;
  manage with `$tags.attach(tag, method: .ifNotExists, on:)` / `.detach(...)`.
- **Eager-load to kill N+1**: `.with(\.$star)` adds exactly one query regardless of row count;
  nest via `.with(\.$star) { $0.with(\.$galaxy) }`. Works only on `.all()` / `.first()`.
- Accessing an unloaded relation **traps** — eager-load, or lazy `try await model.$star.get(on:)`,
  or guard `model.$star.value != nil`.
- `.join(Other.self, on:)` is separate — for filtering/sorting on related columns in one query;
  read with `model.joined(Other.self)`; alias repeated joins with `ModelAlias`.
- `@Parent` JSON-encodes as `{"star":{"id":…}}` — always cross the wire with a DTO carrying a flat
  `Star.IDValue`.

## Query-building rules → `references/queries.md`

- Key-path projections `\.$field`, not plain keypaths. Operators: `==` `!=` `<` `>`; subset `~~`
  (IN) / `!~`; string `=~` (prefix) `~=` (suffix) `~~` (contains).
- Chained `.filter` are **AND**; OR needs `.group(.or) { $0.filter(...).filter(...) }`.
- Terminators (execute now): `.all()`, `.first()`, `.count()/.sum/.average/.min/.max`, `.all(\.$f)`.
- Pagination: `.paginate(for: req)` / `.paginate(PageRequest(page:per:))` → `Page` (LIMIT/OFFSET +
  a COUNT). For big/hot tables prefer **keyset**: `.filter(\.$id > cursor).sort(\.$id).limit(per)`.
- Bulk ops in one statement: `.set(\.$f, to:).filter(...).update()` and `.filter(...).delete()` —
  both **bypass model middleware/lifecycle hooks**.
- Field selection `.field(\.$id).field(\.$name)`; `.unique()` = DISTINCT; `.chunk(max:)` streams
  large reads to bound memory.
- See generated SQL: `app.logger.logLevel = .debug` (abstracted) or `.trace` (raw SQL w/ binds,
  noisy, dev-only). Count queries with the built-in **`app.fluent.history`** recorder (see Testing).

## Migration safety rules → `references/migrations.md` ⚠️ highest-stakes

- `struct X: AsyncMigration { func prepare(on database: any Database) async throws … func revert … }`.
  Register in **dependency order** (`app.migrations.add(...)`): referenced table before its FK.
- **Fluent does NOT wrap a migration in a transaction.** A multi-step migration that fails halfway
  leaves a dirty schema NOT recorded in `_fluent_migrations` → rerun hits "already exists".
  **Rule: one operation per migration.**
- **Never edit a migration already applied in prod** — Fluent tracks by _name_, not code, so the
  edit never re-runs (works on a fresh local DB, silently missing in prod). Ship a new migration.
- **`revert()` cannot restore dropped data** — destructive migrations are one-way; back up first,
  defer drops to a later "contract" migration.
- **Large-table NOT NULL** = expand-and-contract, never `.field(name, type, .required)` on a live
  big table (ACCESS EXCLUSIVE lock + table rewrite): (1) add nullable, (2) backfill in keyset
  batches (separate data migration, one tx per batch, throttle), (3) `CHECK … NOT VALID` +
  `VALIDATE CONSTRAINT`, (4) `SET NOT NULL` (instant on PG12+). Steps 3-4 need raw SQL.
- `CREATE INDEX CONCURRENTLY` / `ALTER TYPE ADD VALUE` **must NOT be inside `db.transaction {}`** —
  they work from a migration precisely because Fluent doesn't wrap it; keep that migration
  single-purpose. FK: `.references("t","id", onDelete: .cascade)` — DB-level, **bypasses Fluent
  middleware + soft-delete**. Column default: `.sql(.default(true))` (no native DSL modifier).
- Prod: disable `autoMigrate()`; run `swift run App migrate` explicitly. `migrate --revert` reverts
  the whole last **batch**, not one migration.

## Transaction rules → `references/transactions.md`

- `try await req.db.transaction { db in … }` — commits on return, **rolls back on any throw**.
- **Run every query on the closure's `db`, not the outer `req.db`** — else it executes outside the
  transaction and won't roll back (the #1 transaction bug).
- **No savepoints / nested transactions** — a nested `.transaction` just reuses the same connection
  (no-op wrapper), so an inner throw rolls back the whole outer unit. Postgres aborts the entire
  transaction on any statement error.
- Bare `BEGIN` = the DB default isolation (Postgres READ COMMITTED); Fluent has no isolation param.
  For higher, run `SET TRANSACTION ISOLATION LEVEL …` as the first statement via the
  `db as? SQLDatabase` cast, and retry on serialization failures.
- **Constraints are the final integrity layer.** A transaction alone doesn't stop concurrent
  check-then-insert races — pair it with a `.unique(on:)` constraint. Upsert + locking live in
  SQLKit, not Fluent's builder: `.ignoringConflicts(with:)` / `.onConflict(with:) { $0.set(excludedValueOf:) }`,
  and `.for(.update)` (Postgres only — emits nothing on SQLite). Optimistic concurrency = a
  `version` column + conditional `UPDATE … WHERE version = :expected` with `.returning(...).all()`
  (Fluent's `.update()` returns Void and hides the row count).

## Testing expectations → `references/testing.md`

- **VaporTesting + Swift Testing** (`import VaporTesting` + `Testing`, `@Suite`/`@Test`, `#expect`,
  `app.testing().test(...)`), not XCTVapor/`app.testable()`. Add `.product(name:"VaporTesting",
package:"vapor")` to the test target.
- App-per-test: `Application.make(.testing)` → `configure` → `autoMigrate()` → test →
  `autoRevert()` → `asyncShutdown()`, reverting + shutting down on the throw path too (leaking the
  Application crashes later tests with a thread-allocation precondition). Wrap in a
  `withAppIncludingDB` helper.
- Hermetic DB via env split in `configure`: `if app.environment == .testing {
app.databases.use(.sqlite(.memory), as: .sqlite) }`. App-per-test with in-memory SQLite runs in
  parallel; a **shared** DB suite needs the `.serialized` trait.
- **SQLite in-memory (execution-verified)**: on the resolved versions `.sqlite(.memory)` gave "no such
  table" — the SQLite pool is 1-per-event-loop and `:memory:` is private per connection, so a
  multi-event-loop app hands each loop an empty DB. Fix: a **unique temp-file DB per test**
  (bulletproof) or pin a single-thread `EventLoopGroup`. (Some sqlite-kit source maps `.memory` to a
  shared temp file; that was NOT the observed behavior — verify for your version.)
- Test migrations round-trip by calling `prepare` then `revert` directly and asserting a query
  throws after revert. Test constraints with `await #expect(throws: Error.self) { try await … }`.
  **SQLite enforces FKs by default now** (`enableForeignKeys: true` → `PRAGMA foreign_keys=ON` per
  connection); keep a deliberate FK-violation test to confirm your version/config.
- **N+1 query counting**: FluentKit has a built-in recorder — `app.fluent.history.start()`, run the
  route, read `app.fluent.history.queries.count`, then `.clear()`/`.stop()`. Capture `app.db` **after**
  `history.start()` (it snapshots the recorder at access). A `.debug` `LogHandler` counting FluentKit's
  "Running query" lines is an equivalent cross-check (both matched: naive 6 vs eager 2). Assert eager
  `.with()` ≪ naive-loop count. A freshly-configured app's _first_ `app.testing()` request can 404 —
  do an awaited DB round-trip just before it.
- Run a parallel **Postgres** suite for what SQLite can't emulate (JSONB, arrays, real uuid, ILIKE,
  partial indexes, PG isolation).

## Performance checklist → `references/performance.md`

- Pool total = `maxConnectionsPerEventLoop × eventLoops`, kept under Postgres `max_connections`.
  **The PG driver default is 1** — raise it under load; `connectionPoolTimeout` default `.seconds(10)`.
- Kill N+1 with eager `.with` (+ nested). **Index FK columns** — Postgres does _not_ auto-index
  them — plus `.filter`/`.sort` columns; add composite/partial indexes via raw `CREATE INDEX`.
- Bulk insert with array `create(on:)` (one multi-row INSERT), chunk ~1000; bulk update with
  `.filter().set().update()`. Keyset pagination for deep/large tables. `.chunk(max:)` for big reads.
- Cache hot reads behind Vapor's `Cache` (`app.caches.use(.memory)` / redis) to relieve the pool.

## Security checklist → `references/security.md`

- **DTO in, DTO out** — the primary defense against mass-assignment and hash/field leakage.
- Raw SQL: `\(bind:)` (values) and `\(ident:)` (identifiers) only — never bare `\(value)`.
  `\(raw:)` is deprecated; `\(unsafeRaw:)` is static-SQL-only. `.filter(.sql(raw:))` / `.custom`
  bypass binding — keep them static. Prefer the structured builder.
- Credentials from `Environment.get`/`DATABASE_URL`, never hardcoded/logged. **TLS `.require` in
  prod** (docs' `.disable` is dev-only).
- Validate with `Validatable` (`try DTO.validate(content: req)` before decode).
- Multi-tenant: derive `tenant_id` from auth (never the body); centralize the filter in a
  repository; add Postgres RLS as a backstop. Duplicate writes: unique constraint + transaction/
  upsert + idempotency key; map unique-violation → HTTP 409.

## Architecture & concurrency → `references/architecture.md`

- Keep Fluent models in the persistence layer; return/pass **DTOs**. `req.db` in routes, `app.db`
  in jobs/commands. Queue payloads are `Codable & Sendable` carrying an **ID** — re-fetch inside
  the job, never embed a live model.
- Repository/service layer and domain-vs-persistence split are optional Vapor patterns — adopt when
  the app grows or needs mock-based tests; skip for small CRUD.
- Multiple DBs: distinct `DatabaseID`s, `app.databases.default(to:)`, `Model.query(on: req.db(.id))`.

---

## Drivers: Postgres / SQLite → `references/drivers.md`

Same Model/query/migration code; swap the factory in `configure`. Source-verified facts:

- **Postgres** (`fluent-postgres-driver` 2.12): `SQLPostgresConfiguration(hostname:…:tls:)` or
  `init(url:)` for `DATABASE_URL`; TLS `.disable`/`.prefer`/`.require` — cert **and** hostname
  verification is always enforced once TLS negotiates (no "require but skip verify" from a URL). Real
  pool (`maxConnectionsPerEventLoop`, default 1). Choose for production / concurrent writers.
- **SQLite** (`fluent-sqlite-driver` 4.9): `.sqlite(.file(…))` or `.sqlite(.memory)`. FKs **on by
  default**; `maxConnectionsPerEventLoop` is **ignored** (pinned to 1); single-writer (contention
  _hangs_ via the busy handler — use WAL or move to Postgres). `.memory` behaved as **private per
  connection** in testing (→ "no such table" across event loops; pool is 1/event-loop) — use a unique
  temp-file DB or a single-thread ELG for tests. `.memory(identifier:)` names a shared in-memory DB.
- Abstraction leaks: native `@Enum` (PG `CREATE TYPE` vs SQLite `TEXT`), `ILIKE` (PG-only), JSON/JSONB
  vs TEXT, timestamp typing, raw SQL. Keep JSON as TEXT + client-generated UUID ids for parity.
- **Deprecated**: `PostgresConfiguration` (use `SQLPostgresConfiguration`); Fluent-3
  `enableReferences(on:)`/`enableForeignKeys(on:)` (now the `SQLiteConfiguration.enableForeignKeys` flag).

## Common failure patterns (fast lookup)

| Symptom                                        | Cause                                                 | Fix                                                        |
| ---------------------------------------------- | ----------------------------------------------------- | ---------------------------------------------------------- |
| "Stored property `_id` … is mutable" (Swift 6) | property-wrapper storage                              | `, @unchecked Sendable` on the class                       |
| N identical SELECTs, latency ∝ rows            | relation access in a loop                             | `.with(\.$rel)` eager load                                 |
| Trap reading `model.rel.name`                  | relation never loaded                                 | eager/lazy-load or guard `$rel.value`                      |
| Client sets `isAdmin`/`balance` and it saves   | decoded body into the Model                           | decode a DTO; set privileged fields server-side            |
| Migration rerun: "already exists"              | multi-step migration failed halfway (no tx)           | one op per migration; clean up + re-run                    |
| New column missing in prod only                | edited an applied migration                           | ship a new migration (tracked by name)                     |
| Prod write outage adding a column              | `.required` on a big table                            | expand-and-contract                                        |
| `CONCURRENTLY cannot run in a transaction`     | inside `db.transaction{}`                             | run as standalone raw SQL, single-purpose migration        |
| Tx changes commit despite throw                | queries on `req.db` not closure `db`                  | use the closure's `db`                                     |
| "no such table" in tests                       | forgot autoMigrate (`.memory` now shares a temp file) | `autoMigrate()` before querying                            |
| FK not enforced on SQLite                      | `enableForeignKeys:false` / raw SQLiteNIO             | keep the default (`true` → PRAGMA on)                      |
| Pool-timeout hangs under load                  | `maxConnectionsPerEventLoop` = 1                      | raise it (under `max_connections`)                         |
| App deadlocks on boot/shutdown                 | sync `Application(env)`/`.wait()`                     | `Application.make` + `asyncShutdown`; `await future.get()` |

## Version-sensitive APIs (stale → current)

| Stale                                        | Current                                                             |
| -------------------------------------------- | ------------------------------------------------------------------- |
| `Application(env)` + `app.shutdown()`        | `try await Application.make(env)` + `try await app.asyncShutdown()` |
| `Migration` (`-> EventLoopFuture`)           | `AsyncMigration` (`async throws`, `on database: any Database`)      |
| `.all().map { }` chains                      | `try await …all()` / `.first()` / `.paginate(for:)`                 |
| `XCTVapor` / `app.testable()` / `XCTAssert*` | `VaporTesting` / `app.testing()` / `#expect`                        |
| `ModelMiddleware`                            | `AsyncModelMiddleware`                                              |
| `PostgresConfiguration` / bare host init     | `SQLPostgresConfiguration`                                          |
| `\(raw:)`                                    | `\(unsafeRaw:)` (static only) / `\(bind:)` for values               |
| models without `@unchecked Sendable`         | required since FluentKit 1.48 under Swift 6                         |
| new AsyncKit code                            | soft-deprecated (async-kit 1.19) — don't add                        |

Never `.wait()` on an event-loop thread (pool deadlock) — bridge a future with `try await future.get()`.

## Canonical examples

```swift
// Model (Swift 6, soft-delete, FieldKeys)
final class Post: Model, @unchecked Sendable {
    static let schema = "posts"
    @ID(key: .id) var id: UUID?
    @Field(key: "title") var title: String
    @Parent(key: "author_id") var author: Author
    @Siblings(through: PostTag.self, from: \.$post, to: \.$tag) var tags: [Tag]
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?   // soft delete
    init() {}
    init(id: UUID? = nil, title: String, authorID: Author.IDValue) {
        self.id = id; self.title = title; self.$author.id = authorID
    }
}

// Migration (reversible, FK + unique)
struct CreatePost: AsyncMigration {
    func prepare(on db: any Database) async throws {
        try await db.schema("posts").id()
            .field("title", .string, .required)
            .field("author_id", .uuid, .required, .references("authors", "id", onDelete: .cascade))
            .field("created_at", .datetime).field("deleted_at", .datetime)
            .create()
    }
    func revert(on db: any Database) async throws { try await db.schema("posts").delete() }
}

// Eager load (no N+1) + DTO out
let posts = try await Post.query(on: req.db).with(\.$author).with(\.$tags).all()
return posts.map { PostDTO($0) }   // never return the model

// Transaction (use the closure's db; constraint is the real guard)
try await req.db.transaction { db in
    guard try await Account.query(on: db).filter(\.$id == id).first() != nil else {
        throw Abort(.notFound)
    }
    try await Ledger(accountID: id, delta: amount).create(on: db)
}
```

## Completion & verification checklist

Before claiming a Fluent change is done:

- [ ] `swift build` clean under Swift 6 strict concurrency (models `@unchecked Sendable`).
- [ ] Migration **applies AND reverts** cleanly (test both, or `autoMigrate`/`autoRevert`).
- [ ] Every new/edited migration is a **new** migration (never edited a shipped one); one op each.
- [ ] Reads use eager `.with` where a relation is touched in a loop (query-count checked).
- [ ] Request bodies decode into DTOs; responses map Model→DTO (no model on the wire).
- [ ] Transactions run on the closure's `db`; uniqueness enforced by a **constraint**, not just code.
- [ ] Tests pass on SQLite; FK enforcement verified; Postgres-specific behavior covered if used.
- [ ] Prod migrations run explicitly (not `autoMigrate`); large-table changes are expand-contract.
- [ ] Credentials from env; TLS `.require` in prod; no secrets logged.
- [ ] Name the check you ran — never mark verified on a hunch.

## References (official)

- Fluent docs: https://docs.vapor.codes/fluent/ (model, relations, query, schema, migration,
  transaction, advanced) · Testing: https://docs.vapor.codes/advanced/testing/
- API ref: https://api.vapor.codes/ (fluentkit, sqlkit, fluentpostgresdriver)
- **Swift 6 + Fluent Sendable**: https://blog.vapor.codes/posts/fluent-models-and-sendable/
- Source of truth: github.com/vapor/{fluent-kit, fluent-postgres-driver, fluent-sqlite-driver, sql-kit}
- Full cited source list: `references/sources.md`. Per-topic depth + confidence tags + failure
  modes: the matching `references/<topic>.md`.

## When to open a reference file

Load `SKILL.md` for every Fluent task. Open a `references/<topic>.md` only when you need depth:
`migrations.md` before any production/large-table migration (mandatory — highest stakes),
`relationships.md` for a new relation graph, `testing.md` when standing up a test target,
`drivers.md` for driver/pool/SQLite-memory config, `security.md` for auth/multi-tenant/raw SQL,
`performance.md` for pooling/N+1/pagination tuning. Don't load every reference at once.

## Refreshing this skill

Re-verify when `Package.resolved` shows a **FluentKit major/minor bump** (concurrency + Sendable
behavior tracks FluentKit, not the Fluent 4.13 number), a **driver major bump**
(fluent-postgres/sqlite config APIs shift), a **Swift major** (6→7), or Vapor 5 (removes
EventLoopFuture, changes lifecycle). To refresh: re-run the research fan-out against the live
docs.vapor.codes + api.vapor.codes + the vapor GitHub tags, re-run the practice project against the
new versions, and update the version anchor + version-sensitive table above. Docs.vapor.codes is
unversioned — always cross-check exact signatures against `api.vapor.codes` for the resolved tag.
Evidence policy: claims here are doc-verified or execution-verified (practice project); items marked
inferred in the references were not confirmed against a version-pinned API page — treat those as
"verify before relying." Context7 was unavailable at authoring time; official docs were scraped
directly instead.

**Doc-verification pass (2026-07-11):** a 4-agent fan-out re-checked all 41 `[inferred-from-research]`
rules across the reference files against version-pinned primary sources (official Vapor/Fluent docs,
api.vapor.codes for the resolved tag, the vapor GitHub driver source, and PostgreSQL/SQLite docs).
Result: 36 upgraded to `[verified-by-docs]`, 1 factual error corrected (the N+1 rule wrongly said
"no official query-count API" — FluentKit ships `app.fluent.history`; fixed in testing.md rule + prose),
and 4 kept `[inferred-from-research]` because no version-pinned primary source confirms them (they are
sound engineering, not doc-backed): the fixtures/factories advisory (testing.md), the Idempotency-Key
pattern and the pool-acquisition-timeout sub-claim (security.md), and the domain-vs-persistence model
split (architecture.md). `[verified-by-docs]` in the references now means "confirmed against a primary
source (docs, driver source, or PostgreSQL/SQLite docs)" as of this pass. See `references/validation.md`.
