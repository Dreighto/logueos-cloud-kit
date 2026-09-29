## migrations

Fluent migrations are version-controlled schema/data changes implemented as types conforming to `Migration` (EventLoopFuture) or, in modern Swift 6.2/6.3 code, `AsyncMigration` (async/await), with `prepare(on:)` applying the change and `revert(on:)` undoing it. Migrations are registered via `app.migrations.add(_:to:)` in dependency order and applied with `swift run App migrate`; the schema DSL (`database.schema(_:).id().field(...).create()/.update()/.delete()`) is stringly-typed on purpose so old migrations stay valid as models evolve. The single highest-stakes fact: Fluent does NOT wrap a migration in a transaction, and each schema/query call commits independently, so a multi-statement migration that fails halfway leaves the DB partially migrated and NOT recorded as applied in `_fluent_migrations` — reruns then hit "column already exists". This is intentional (MySQL/Mongo lack transactional DDL), so the operational rule is one operation per migration. On large Postgres tables the naive `.field(..., .required)` emits `ALTER TABLE ... ADD COLUMN ... NOT NULL` which takes an ACCESS EXCLUSIVE lock and can rewrite the table; the safe path is expand-and-contract: add nullable column, backfill in keyset-paginated batches (separate data migration), add `CHECK (col IS NOT NULL) NOT VALID`, `VALIDATE CONSTRAINT`, then `SET NOT NULL` (instant on PG12+ given a validated check). `CREATE INDEX CONCURRENTLY` and `ALTER TYPE ... ADD VALUE` must run outside a transaction — safe from Fluent precisely because it doesn't wrap migrations, but you must NOT wrap them in `database.transaction {}`, and these require raw SQL via `database as? SQLDatabase`. Editing an already-shipped migration never re-runs it (Fluent keys off the migration name in `_fluent_migrations`, not code content) — always add a new migration. revert() cannot reconstitute dropped data, so destructive migrations are effectively one-way and need backups, not a trusted revert.

### Rules
- [verified-by-docs] Prefer `AsyncMigration` (async/await `prepare`/`revert`) over the EventLoopFuture `Migration` for new code; signatures are `func prepare(on database: any Database) async throws` in Swift 6 strict-concurrency projects. — _Docs show both; AsyncMigration is the modern form and the `any Database` existential is current for Fluent 4.13 / Swift 6._  (https://docs.vapor.codes/fluent/migration/)
- [verified-by-docs] Keep each migration to a SINGLE operation. Fluent does NOT wrap a migration's prepare() in a transaction, so a multi-step migration that fails midway leaves a partially-applied schema that is NOT recorded in _fluent_migrations, and the rerun fails on 'already exists'. — _Maintainer discussion: transactional migrations aren't imposed because not all backends support DDL-in-transaction; granularity is the mitigation._  (https://github.com/vapor/fluent-kit/issues/286)
- [verified-by-docs] Register migrations in dependency order via `app.migrations.add(MigrationA()); app.migrations.add(MigrationB())` — a migration that adds a foreign key must be registered AFTER the migration creating the referenced table. Use `to:` to target a non-default database. — _Order of registration is the only sequencing mechanism Fluent provides._  (https://docs.vapor.codes/fluent/migration/)
- [verified-by-docs] NEVER edit a migration that has already been applied in production and expect it to re-run. Fluent tracks applied migrations by NAME in `_fluent_migrations`; editing the code is invisible. Ship a NEW migration (e.g. AddEmailToUsers) instead. — _Runner only compares names present/absent in the table, never code content — the classic 'works locally on fresh DB, silently missing in prod' bug._  (https://github.com/vapor/fluent/issues/682)
- [verified-by-docs] Do NOT add a required column to a large existing Postgres table with `.field(name, type, .required)` under load — it emits ALTER TABLE ADD COLUMN NOT NULL taking an ACCESS EXCLUSIVE lock and can rewrite/scan the whole table, blocking all writes. — _Setting NOT NULL forces a full table scan under an exclusive lock; on millions of rows this is an outage._  (https://www.bytebase.com/reference/postgres/how-to/how-to-alter-large-table-postgres/)
- [verified-by-docs] Safe NOT NULL on a large table = 4 steps across migrations: (1) add column nullable, (2) backfill in batches, (3) `ADD CONSTRAINT ... CHECK (col IS NOT NULL) NOT VALID` then `VALIDATE CONSTRAINT`, (4) `ALTER COLUMN col SET NOT NULL` (instant on PG12+ given the validated CHECK), optionally drop the redundant CHECK. Steps 3-4 need raw SQL. — _NOT VALID registers the constraint without scanning; VALIDATE scans under a lock that allows concurrent reads/writes; SET NOT NULL then trusts the validated constraint._  (https://dev.to/mickelsamuel/adding-not-null-constraints-to-existing-postgresql-columns-safely-5fk9)
- [verified-by-docs] Use `CREATE INDEX CONCURRENTLY` for indexes on large/live tables (a plain index build blocks writes). Run it via raw SQL from a migration — it works only because Fluent doesn't wrap migrations in a transaction. Never place it inside `database.transaction { }`. Pair with `DROP INDEX CONCURRENTLY IF EXISTS` in revert(). — _Postgres forbids CONCURRENTLY inside a transaction block; wrapping it in Fluent's transaction API triggers a hard error._  (https://www.postgresql.org/docs/current/sql-createindex.html)
- [verified-by-docs] Cast the migration's database to SQLKit for anything Fluent's schema DSL can't express: `guard let sql = database as? SQLDatabase else { throw ... }; try await sql.raw("...").run()`. Works for req.db, app.db, and the Migration database. — _CHECK NOT VALID, VALIDATE CONSTRAINT, CONCURRENTLY, ALTER TYPE ADD VALUE all require raw SQL — the DSL has no cases for them._  (https://docs.vapor.codes/fluent/advanced/)
- [verified-by-docs] Backfill data as a SEPARATE migration/script, batched with keyset pagination (filter id > lastId, limit N), one transaction per batch, with a throttle between batches. Never a single unbounded UPDATE (long lock + table bloat) and never one giant transaction across all rows. — _Per-batch transactions cap lock duration and WAL/bloat; keyset pagination avoids OFFSET re-scans._  (https://fly.io/phoenix-files/backfilling-data/)
- [verified-by-docs] Treat destructive migrations (drop column/table) as one-way. revert() cannot reconstruct dropped data — rely on backups and application-level rollback, not on a trusted revert path. In expand-contract, defer all drops to the contract phase. — _revert() re-adds an empty column at best; the data is gone._  (https://github.com/vapor/fluent-kit/issues/286)
- [verified-by-docs] Disable --auto-migrate/app.autoMigrate() in production; run `swift run App migrate` explicitly as a pipeline step. Auto-migrate couples schema change to app boot and removes control over timing. --revert reverts the whole last BATCH, not one migration. — _Batch-granular revert + boot-coupled migration are both production hazards; explicit control is safer._  (https://docs.vapor.codes/fluent/migration/)
- [verified-by-docs] For enums that change often, prefer a String/Int column backed by a Swift `RawRepresentable & Codable` enum stored in `@Field` (or use `@Enum` + native type) — adding a Swift case then needs no DDL. Reserve native Postgres enums (database.enum builder) for stable value sets. — _Native enums require ALTER TYPE ADD VALUE (forward-only, no DROP VALUE); text/CHECK is far more migration-friendly._  (https://docs.vapor.codes/fluent/schema/)
- [verified-by-docs] `ALTER TYPE ... ADD VALUE` is forward-only and (historically) cannot run in a transaction — run it standalone via raw SQL; its revert is a no-op. Removing/renaming an enum value requires building a new type, converting columns, dropping the old type (expand-contract). — _Postgres has no ALTER TYPE DROP VALUE; treat additions as irreversible._  (https://www.postgresql.org/docs/current/sql-altertable.html)
- [verified-by-docs] Add foreign keys with `.references("table","id")` (field-level, create only) or `.foreignKey("col", references:"table","id", onDelete:.cascade)` (top-level, works in updates, nameable). Actions: .noAction(default)/.restrict/.cascade/.setNull/.setDefault. FK actions run in-DB and bypass Fluent middleware/soft-delete. — _onDelete .cascade silently deletes rows without firing model middleware — a data-safety surprise._  (https://docs.vapor.codes/fluent/schema/)
- [verified-by-docs] Set defaults and other unsupported column constraints via `.sql(...)`: `.field("active", .bool, .required, .sql(.default(true)))` or `.sql(.default(SQLFunction("now")))` for timestamps. The DSL has no dedicated default() modifier. — _Column defaults are only reachable through the SQLColumnConstraintAlgorithm escape hatch._  (https://docs.vapor.codes/fluent/schema/)
- [verified-by-docs] For unique constraints use `.unique(on: "email")` / multi-column `.unique(on:"first","last")`; give it an explicit `name:` and remove it with the matching `.deleteUnique(on:)` or `.deleteConstraint(name:)`. On big Postgres tables a unique constraint builds a blocking index — build the index CONCURRENTLY then attach, rather than .unique() directly. — _deleteConstraint(name:) is required to drop a named constraint; the blocking-index caveat is the production overlay._  (https://docs.vapor.codes/fluent/schema/)

### Snippets

**Minimal AsyncMigration (create + revert)** · Fluent 4.13 / Swift 6: prepare/revert take `any Database`. Older tutorials show `on database: Database` without `any` — update them. · https://docs.vapor.codes/fluent/schema/
```swift
struct UserMigration: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            .id()
            .field("name", .string, .required)
            .field("email", .string, .required)
            .unique(on: "email")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users").delete()
    }
}

// register (configure.swift)
app.migrations.add(UserMigration())
```

**Add column + foreign key in a schema UPDATE** · onDelete/onUpdate actions run in the DB and bypass Fluent model middleware + soft-delete. · https://docs.vapor.codes/fluent/schema/
```swift
struct AddStarToPlanet: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("planets")
            .field("star_id", .uuid, .required, .references("stars", "id", onDelete: .cascade))
            .update()
    }
    func revert(on database: any Database) async throws {
        try await database.schema("planets")
            .deleteField("star_id")
            .update()
    }
}
```

**Safe NOT NULL on a large Postgres table (raw SQL via SQLKit)** · Prereq: column already added nullable AND backfilled so no NULLs remain. I split into separate sql.raw() calls deliberately — postgres-nio's extended protocol rejects some multi-statement strings, and CONCURRENTLY-class statements must not share a transaction. lock_timeout can be set with its own sql.raw("SET lock_timeout='5s'") call. Exact form not shown in official docs — verify against your driver. · https://dev.to/mickelsamuel/adding-not-null-constraints-to-existing-postgresql-columns-safely-5fk9
```swift
import FluentSQL

struct EnforceEmailNotNull: AsyncMigration {
    func prepare(on database: any Database) async throws {
        guard let sql = database as? SQLDatabase else { throw Abort(.internalServerError) }
        // send as SEPARATE raw statements (postgres-nio uses the extended
        // query protocol; multiple statements in one string can fail)
        try await sql.raw("ALTER TABLE users ADD CONSTRAINT chk_email_nn CHECK (email IS NOT NULL) NOT VALID").run()
        try await sql.raw("ALTER TABLE users VALIDATE CONSTRAINT chk_email_nn").run()
        try await sql.raw("ALTER TABLE users ALTER COLUMN email SET NOT NULL").run()  // instant on PG12+
        try await sql.raw("ALTER TABLE users DROP CONSTRAINT chk_email_nn").run()
    }
    func revert(on database: any Database) async throws {
        guard let sql = database as? SQLDatabase else { throw Abort(.internalServerError) }
        try await sql.raw("ALTER TABLE users ALTER COLUMN email DROP NOT NULL").run()
    }
}
```

**CREATE INDEX CONCURRENTLY from a migration** · Works only because Fluent does NOT wrap migrations in a transaction. Do NOT put this inside database.transaction {}. Keep this migration index-only (no other DDL/backfill) so nothing forces a surrounding transaction. · https://www.postgresql.org/docs/current/sql-createindex.html
```swift
import FluentSQL

struct CreateTodoTitleIndex: AsyncMigration {
    func prepare(on database: any Database) async throws {
        guard let sql = database as? SQLDatabase else { throw Abort(.internalServerError) }
        try await sql.raw("CREATE INDEX CONCURRENTLY IF NOT EXISTS todo_title_idx ON todos (title)").run()
    }
    func revert(on database: any Database) async throws {
        guard let sql = database as? SQLDatabase else { throw Abort(.internalServerError) }
        try await sql.raw("DROP INDEX CONCURRENTLY IF EXISTS todo_title_idx").run()
    }
}
```

**Batched, keyset-paginated backfill (separate data migration)** · One transaction per batch caps lock duration and WAL bloat. Keep backfill OUT of the schema migration; run it as its own step and make it resumable. · https://fly.io/phoenix-files/backfilling-data/
```swift
struct BackfillOrderStatus: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let batchSize = 10_000
        var lastId: UUID? = nil
        while true {
            var q = Order.query(on: database).sort(\.$id, .ascending).limit(batchSize)
            if let last = lastId { q = q.filter(\.$id > last) }
            let batch = try await q.all()
            if batch.isEmpty { break }
            try await database.transaction { tx in
                for order in batch where order.status == nil {
                    order.status = order.shipped ? "shipped" : "pending"
                    try await order.save(on: tx)
                }
            }
            lastId = batch.last?.id
            try await Task.sleep(nanoseconds: 100_000_000) // throttle
        }
    }
    func revert(on database: any Database) async throws { /* best-effort / no-op */ }
}
```

**Native Postgres enum: create, read into a field, add value** · database.enum builder (create/read/update/deleteCase/delete) is the doc-blessed native-enum path. ALTER TYPE ADD VALUE is forward-only (no DROP VALUE) and must not run inside a transaction; its revert is a no-op. · https://docs.vapor.codes/fluent/schema/
```swift
// create the enum type
try await database.enum("planet_type")
    .case("smallRocky").case("gasGiant").case("dwarf")
    .create()

// use it as a column type
let planetType = try await database.enum("planet_type").read()
try await database.schema("planets")
    .field("type", planetType, .required)
    .update()

// add a value later (forward-only) — raw SQL, no transaction
guard let sql = database as? SQLDatabase else { throw Abort(.internalServerError) }
try await sql.raw("ALTER TYPE planet_type ADD VALUE 'iceGiant'").run()
```

### Failure modes
- **Migration fails midway; rerun errors with 'column already exists' / 'constraint already defined'.** → Keep migrations to one operation. To recover: manually drop the partially-created objects (or manually insert the _fluent_migrations row after finishing by hand), then continue. Split multi-step changes into separate migrations. (cause: Fluent does not wrap migrations in a transaction; earlier statements committed but the migration was never recorded in _fluent_migrations, so `migrate` retries the whole thing.)
- **New column added to an old migration works locally but is missing in production.** → Never edit shipped migrations. Add a new migration (e.g. AddXToY) that applies the delta. (cause: The migration name is already in _fluent_migrations in prod; Fluent compares names, not code, so the edited migration never re-runs. Local DB is fresh so it runs there.)
- **Production write outage / lock pile-up when a deploy adds a required column to a big table.** → Expand-contract: add nullable, backfill in batches, CHECK NOT VALID + VALIDATE, then SET NOT NULL. Set a small lock_timeout so the DDL fails fast instead of queuing. (cause: `.field(name, type, .required)` -> ALTER TABLE ADD COLUMN NOT NULL takes ACCESS EXCLUSIVE and scans/rewrites the table.)
- **`CREATE INDEX CONCURRENTLY cannot run inside a transaction block` error from a migration.** → Run CONCURRENTLY as a standalone sql.raw() outside any transaction, in a migration that does nothing else. Use DROP INDEX CONCURRENTLY IF EXISTS in revert. (cause: The CONCURRENTLY statement was placed inside `database.transaction { }`, or a multi-statement raw string got wrapped implicitly.)
- **Multi-statement `sql.raw("...; ...; ...")` block fails or behaves oddly against Postgres.** → Send each statement as its own sql.raw(...).run() call. Verify behavior against your driver version in staging before shipping. (cause: postgres-nio uses the extended query protocol which generally allows a single statement per query; concatenated statements (and CONCURRENTLY/ALTER TYPE among them) can error or share an unwanted transaction.)
- **Rolling back a migration that dropped a column doesn't bring the data back.** → Treat destructive migrations as one-way; take a backup / archive table before contract-phase drops. Do not rely on revert for data recovery. (cause: revert() can re-add the column definition but the data was permanently deleted by the DROP.)
- **onDelete: .cascade silently deleted related rows without firing model middleware or respecting soft-delete.** → Only use DB-level cascade when you accept it bypasses Fluent hooks; otherwise handle deletes in application code / model middleware. (cause: Foreign-key actions execute inside the database, bypassing Fluent entirely.)
- **Need to remove or rename a native Postgres enum value and there's no API for it.** → Expand-contract on the type: create a new enum type, convert columns to it, drop the old type — or switch the column to text + CHECK. Prefer text-backed enums for values that change. (cause: Postgres has no ALTER TYPE DROP VALUE; ALTER TYPE ADD VALUE is forward-only.)
- **`migrate --revert` undid more than the one migration expected.** → Understand batch granularity; apply high-risk migrations in their own `migrate` run so their batch is isolated, and prefer forward corrective migrations over revert in prod. (cause: Revert operates on the entire last BATCH (all migrations applied in one `migrate` invocation), in reverse order — not a single migration.)

### Version-sensitive
- `prepare(on:)/revert(on:) signature`: Fluent 4.13 + Swift 6 uses `func prepare(on database: any Database) async throws` (AsyncMigration). Pre-existential tutorials show `on database: Database`. The schema doc's Model-Coupling example still shows the non-`any` form — treat `any Database` as current.  (https://docs.vapor.codes/fluent/migration/)
- `_fluent_migrations tracking table`: Current table is `_fluent_migrations` (id UUID PK, name, batch, created_at, updated_at). Very old Fluent used a table named `fluent` with createdAt/updatedAt camelCase. Fluent keys off the `name` column, so editing an applied migration's code never re-runs it.  (https://github.com/vapor/fluent/issues/682)
- `Migration transaction wrapping`: Fluent intentionally does NOT wrap a migration in a transaction (backend DDL-transaction support varies). This is the reason CONCURRENTLY / ALTER TYPE ADD VALUE work from migrations, and the reason partial-failure leaves a dirty schema. Do not assume atomicity per migration.  (https://github.com/vapor/fluent-kit/issues/286)
- `ADD COLUMN with default on Postgres`: Since PG11, adding a column with a constant default is metadata-only (no rewrite). But SET NOT NULL still scans unless a validated CHECK exists; volatile defaults and type changes still rewrite. Don't assume 'add column default' is always cheap across the operation set.  (https://www.postgresql.org/docs/current/sql-altertable.html)
- `Enum storage: @Field RawRepresentable vs native database.enum`: Two distinct approaches. A Swift `String`-backed Codable enum in `@Field` stores raw text (no DDL to add a case). The native `database.enum(...)` builder creates a real PG enum type (ALTER TYPE needed to extend). `@Enum` property wrapper pairs with the native type. Pick text/CHECK for evolving sets.  (https://docs.vapor.codes/fluent/schema/)

### Open questions
- Context7 is NOT connected in this environment; per instructions I substituted Firecrawl scrapes of docs.vapor.codes and a Perplexity deep-research pass for production practice. Official API-reference pages (api.vapor.codes/fluentkit) were not scraped directly this pass.
- The multi-step raw-SQL NOT NULL / lock_timeout snippet and the single-vs-multi-statement behavior of sql.raw() against postgres-nio (extended query protocol) are inferred, not confirmed by an official doc for fluent-postgres-driver 2.12.x — should be verified by reading postgres-nio/SQLKit source or testing before treating the exact form as compile-and-run correct.
- Whether recent PostgreSQL (16/17) has relaxed the ALTER TYPE ADD VALUE-in-transaction restriction was not pinned to a specific version in official docs during this pass; treated conservatively as 'must run outside a transaction'.
- SQLKit's schema/index builder may expose CONCURRENTLY or NOT VALID options in newer versions; I fell back to raw SQL. Did not confirm whether a first-class builder method now exists in the FluentKit 4.13 / SQLKit release line — worth checking api.vapor.codes/sqlkit.
- Did not independently verify the exact current column set of _fluent_migrations against FluentKit 4.13 source; the schema (id/name/batch/created_at/updated_at) comes from a maintainer issue thread, not the API reference.

### Sources
- https://docs.vapor.codes/fluent/migration/
- https://docs.vapor.codes/fluent/schema/
- https://docs.vapor.codes/fluent/advanced/
- https://docs.vapor.codes/fluent/transaction/
- https://docs.vapor.codes/fluent/model/
- https://docs.vapor.codes/fluent/overview/
- https://api.vapor.codes/fluentkit/documentation/fluentkit
- https://github.com/vapor/fluent-kit/issues/286
- https://github.com/vapor/fluent/issues/682
- https://github.com/vapor/fluent/issues/480
- https://blog.vapor.codes/posts/adding-db-table-index/
- https://www.postgresql.org/docs/current/sql-altertable.html
- https://www.postgresql.org/docs/current/sql-createindex.html
- https://dev.to/mickelsamuel/adding-not-null-constraints-to-existing-postgresql-columns-safely-5fk9
- https://www.bytebase.com/reference/postgres/how-to/how-to-alter-large-table-postgres/
- https://fly.io/phoenix-files/backfilling-data/
- https://xata.io/blog/pgroll-expand-contract
