## drivers-postgres-sqlite

Fluent 4.13 (FluentKit) exposes a driver-agnostic `Model`/query/migration layer; you swap the backend in `configure(_:)` by registering a different `DatabaseConfigurationFactory` with `app.databases.use(_:as:)` under a `DatabaseID` (`.psql` from FluentPostgresDriver, `.sqlite` from FluentSQLiteDriver). Postgres (fluent-postgres-driver 2.12.x) is configured with `SQLPostgresConfiguration` — either explicit `hostname/port/username/password/database/tls:` or `init(url:)` for `DATABASE_URL` — with TLS modes `.disable` / `.prefer(...)` / `.require(...)` and a real per-event-loop connection pool (`maxConnectionsPerEventLoop`). SQLite (fluent-sqlite-driver 4.9.x) uses `.sqlite(.file("db.sqlite"))` or `.sqlite(.memory)`; two current-version facts overturn old advice: `maxConnectionsPerEventLoop` is **ignored** (hard-pinned to 1) and foreign-key enforcement is **on by default** (`SQLiteConfiguration.enableForeignKeys` defaults to `true`, issuing `PRAGMA foreign_keys = ON` per connection). The infamous in-memory "no such table" multi-connection gotcha is now worked around inside sqlite-kit: `.memory` is backed by a single shared per-process temp file (because `SQLITE_OMIT_SHARED_CACHE` is compiled in), so all pooled connections see the same schema. The abstraction leaks at native ENUMs (Postgres `CREATE TYPE` vs SQLite `TEXT`), `ILIKE` (Postgres-only), JSON/JSONB vs TEXT, timestamp typing, and any raw SQL. Pick SQLite for tests/embedded/single-writer state, Postgres for production and concurrent writers.

### Rules
- [verified-by-docs] Register a driver with `app.databases.use(<factory>, as: <DatabaseID>)` where the ID is `.psql` or `.sqlite` — same Model/migration code runs on either backend (https://docs.vapor.codes/fluent/overview/).
- [verified-by-source] Postgres explicit config is `SQLPostgresConfiguration(hostname:port:username:password:database:tls:)`; port defaults to `SQLPostgresConfiguration.ianaPortNumber` (5432) — used via `.postgres(configuration:as:.psql)` (https://github.com/vapor/postgres-kit/blob/main/Sources/PostgresKit/SQLPostgresConfiguration.swift).
- [verified-by-source] `SQLPostgresConfiguration(url:)` throws and parses `postgres://user:pass@host:port/db?tlsmode=disable|prefer|require` (aliases `sslmode`/`ssl`/`tls`, `postgres+uds://` for sockets) — so `try app.databases.use(.postgres(url: env), as: .psql)` for `DATABASE_URL` (https://github.com/vapor/postgres-kit/blob/main/Sources/PostgresKit/SQLPostgresConfiguration.swift).
- [verified-by-source] TLS is `PostgresConnection.Configuration.TLS`: `.disable`, `.prefer(try .init(configuration: .makeClientConfiguration()))`, `.require(try .init(configuration: .makeClientConfiguration()))`; URL default is `prefer` for TCP, `disable` for UDS (https://github.com/vapor/postgres-kit/blob/main/Sources/PostgresKit/SQLPostgresConfiguration.swift).
- [verified-by-source] Whenever TLS actually negotiates, full cert verification (chain + hostname) is *always* enforced — you cannot get "require but skip verification" from a URL; build the `TLSConfiguration` manually if you must (https://github.com/vapor/postgres-kit/blob/main/Sources/PostgresKit/SQLPostgresConfiguration.swift).
- [verified-by-source] Postgres pool size is real: `.postgres(configuration:maxConnectionsPerEventLoop:connectionPoolTimeout:sqlLogLevel:)`, default `maxConnectionsPerEventLoop: 1`, plus optional idle-connection pruning (`pruneInterval`) (https://github.com/vapor/fluent-postgres-driver/blob/main/Sources/FluentPostgresDriver/FluentPostgresConfiguration.swift).
- [verified-by-source] SQLite `maxConnectionsPerEventLoop` is accepted for source-compat but **ignored** — the pool is hard-coded to 1 per event loop because ">1 only adds thread contention, never parallelism" (https://github.com/vapor/fluent-sqlite-driver/blob/main/Sources/FluentSQLiteDriver/FluentSQLiteConfiguration.swift).
- [verified-by-source] SQLite foreign-key enforcement is **on by default**: `SQLiteConfiguration(storage:enableForeignKeys:)` defaults `enableForeignKeys` to `true`, and `SQLiteConnectionSource.makeConnection` runs `PRAGMA foreign_keys = ON` on every new connection — no manual step needed (https://github.com/vapor/sqlite-kit/blob/main/Sources/SQLiteKit/SQLiteConfiguration.swift, https://github.com/vapor/sqlite-kit/blob/main/Sources/SQLiteKit/SQLiteConnectionSource.swift).
- [verified-by-source] `.sqlite(.memory)` is NOT a raw `:memory:` DB: sqlite-kit maps it to a shared temp file `…/sqlite-kit_memorydb-<pid>-<uuid>.sqlite3` so all pooled connections share one database — the classic multi-connection "no such table" is already worked around (https://github.com/vapor/sqlite-kit/blob/main/Sources/SQLiteKit/SQLiteConnectionSource.swift).
- [verified-by-source] Raw SQLiteNIO `.memory` (`:memory:`) is genuinely per-connection and un-shareable (`SQLITE_OMIT_SHARED_CACHE` is compiled in) — only the sqlite-kit/Fluent layer fakes sharing via temp files; drop to raw sqlite-nio and the old gotcha returns (https://github.com/vapor/sqlite-nio/blob/main/Sources/SQLiteNIO/SQLiteConnection.swift).
- [verified-by-source] Each `.sqlite(.memory)` / `SQLiteConfiguration.memory` gets a fresh random UUID identifier → a distinct DB; to share one in-memory DB across configs in a process use `SQLiteConfiguration(storage: .memory(identifier: "shared"))` (https://github.com/vapor/sqlite-kit/blob/main/Sources/SQLiteKit/SQLiteConfiguration.swift).
- [verified-by-docs] For in-memory/test DBs, run migrations before use via `--auto-migrate` or `app.autoMigrate()` since nothing persists between runs (https://docs.vapor.codes/fluent/overview/).
- [verified-by-docs] `@Enum` maps to a native database enum where supported (Postgres `ENUM` type via `CREATE TYPE`); on SQLite it degrades to a `TEXT` column with enum validity enforced only in Swift, not the DB (https://docs.vapor.codes/fluent/model/).
- [verified-by-docs] Foreign-key `ON DELETE`/`ON UPDATE` actions run in the database, bypassing Fluent middleware and soft-delete — behavior is identical in intent on both drivers but only fires on SQLite because FK enforcement is enabled by default now (https://docs.vapor.codes/fluent/schema/).
- [verified-by-docs] Case-insensitive search: Postgres has `ILIKE` (a Postgres-only extension) and case-sensitive `LIKE`; SQLite has only `LIKE` (case-insensitive for ASCII by default, toggled by `PRAGMA case_sensitive_like`) — portable code should avoid raw `ILIKE` and normalize with `lower()` or contains-filters (https://sqlite.org/forum/info/e2d1cd8e30a218e6).
- [verified-by-docs] JSON: Postgres has native `json`/`jsonb` (Codable structs stored via the `.json`/custom field type, indexable with GIN); SQLite has no JSON type and stores JSON as `TEXT`/`BLOB` — keep JSON as `TEXT` on both if you need cross-driver parity (https://docs.vapor.codes/fluent/model/, https://sqlite.org/foreignkeys.html).
- [verified-by-docs] ID generation: Postgres uses `INSERT … RETURNING` to hydrate `@ID` in one round-trip; SQLite relies on connection-local `last_insert_rowid()` for autoincrement ids — client-generated `UUID` ids sidestep this difference on both (https://github.com/vapor/sqlite-nio/blob/main/Sources/SQLiteNIO/SQLiteConnection.swift).
- [verified-by-docs] `@Timestamp(format:)` defaults to efficient per-DB datetime encoding; Postgres backs it with native `timestamp`/`timestamptz`, SQLite with `TEXT`/`REAL` — use `.iso8601` or `.unix` for byte-identical cross-driver storage (https://docs.vapor.codes/fluent/model/).
- [verified-by-docs] SQLite is single-writer with file locking (a `busy_handler` is installed that retries indefinitely, so contention shows up as a *hang*, not an error); Postgres MVCC handles concurrent writers — choose Postgres for any multi-writer or multi-instance deployment (https://github.com/vapor/sqlite-nio/blob/main/Sources/SQLiteNIO/SQLiteConnection.swift).

### Snippets
```swift
// ===== Postgres — configure(_:) (fluent-postgres-driver 2.12.x) =====
import Fluent
import FluentPostgresDriver
import Vapor

public func configure(_ app: Application) async throws {
    // A) explicit fields — SQLPostgresConfiguration(hostname:port:username:password:database:tls:)
    let pg = SQLPostgresConfiguration(
        hostname: Environment.get("DATABASE_HOST") ?? "localhost",
        port: Environment.get("DATABASE_PORT").flatMap(Int.init)
            ?? SQLPostgresConfiguration.ianaPortNumber,           // 5432
        username: Environment.get("DATABASE_USERNAME") ?? "vapor",
        password: Environment.get("DATABASE_PASSWORD") ?? "vapor",
        database: Environment.get("DATABASE_NAME") ?? "vapor",
        tls: .prefer(try .init(configuration: .makeClientConfiguration()))
        //   .disable                                             // no TLS
        //   .require(try .init(configuration: .makeClientConfiguration())) // enforce TLS
    )
    app.databases.use(
        .postgres(configuration: pg, maxConnectionsPerEventLoop: 2),
        as: .psql
    )

    // B) from DATABASE_URL — init(url:) throws; ?tlsmode=disable|prefer|require
    // try app.databases.use(.postgres(url: Environment.get("DATABASE_URL")!), as: .psql)
}
```
```swift
// ===== SQLite — configure(_:) (fluent-sqlite-driver 4.9.x) =====
import Fluent
import FluentSQLiteDriver
import Vapor

public func configure(_ app: Application) async throws {
    // File-backed: single-instance / embedded / small persistent state.
    // Foreign keys are enforced by default (PRAGMA foreign_keys = ON per connection).
    app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)

    // In-memory: tests / scratch (see test snippet below).
    // app.databases.use(.sqlite(.memory), as: .sqlite)
    // NOTE: a maxConnectionsPerEventLoop: arg compiles but is IGNORED (always 1) for SQLite.

    // To turn FK enforcement OFF (rarely wanted) build the config explicitly:
    // app.databases.use(
    //     .sqlite(SQLiteConfiguration(storage: .file(path: "db.sqlite"), enableForeignKeys: false)),
    //     as: .sqlite
    // )
}
```
```swift
// ===== In-memory SQLite test fix =====
// CURRENT driver: `.sqlite(.memory)` is backed by ONE shared per-process temp file, so every pooled
// connection sees the same schema — the classic "no such table" is already handled. Just migrate first:
import XCTVapor
import Fluent
import FluentSQLiteDriver

final class AppTests: XCTestCase {
    func testCreatesRow() async throws {
        let app = try await Application.make(.testing)
        app.databases.use(.sqlite(.memory), as: .sqlite)   // shared temp-file-backed "memory" DB
        app.migrations.add(CreateTodo())
        try await app.autoMigrate()                        // schema now visible to ALL pool connections
        // ... exercise routes/queries ...
        try await app.asyncShutdown()
    }
}

// If you ever DO hit per-connection isolation ("no such table") — e.g. using RAW SQLiteNIO `.memory`
// (a true per-connection :memory: DB) or an older driver — force a single connection or a shared file:
app.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)  // 1 event loop => 1 SQLite conn
// or an explicit temp file that every pooled connection opens:
app.databases.use(
    .sqlite(.file(NSTemporaryDirectory() + "test-\(UUID().uuidString).sqlite")),
    as: .sqlite
)
```

### Failure modes
- "no such table" in tests with `.sqlite(.memory)` (current driver) → almost always a *missing migration*: call `try await app.autoMigrate()` (or `--auto-migrate`) before querying; the driver already shares one temp file across the pool, so it is not the old multi-connection split.
- "no such table" when using raw SQLiteNIO `.memory` or an old driver → true `:memory:` is per-connection; use a single-threaded `EventLoopGroup(numberOfThreads: 1)` or a shared temp file instead.
- Bumping `maxConnectionsPerEventLoop` on SQLite to gain throughput → no effect (ignored, pinned to 1); SQLite is single-writer — move to Postgres for concurrent writers.
- Foreign-key constraints silently not enforced on SQLite → you passed `enableForeignKeys: false` or opened a bare SQLiteNIO connection; keep the default `true` (or run `PRAGMA foreign_keys = ON` on that connection).
- App appears to *hang* under concurrent SQLite writes (not error) → SQLITE_BUSY is retried forever by the installed busy handler; enable WAL (`PRAGMA journal_mode=WAL`) for more read/write overlap or switch to Postgres.
- `.postgres(url:)` won't compile without `try` / throws `URLError(.badURL)` at boot → `init(url:)` throws; a username is mandatory and the scheme must be `postgres[ql][+tcp|+uds]`.
- Need "TLS required but no certificate verification" via `DATABASE_URL` → impossible by design; construct `SQLPostgresConfiguration` with a hand-built `TLSConfiguration` instead of a URL.
- Raw `ILIKE ...` in a `.sql().raw(...)` query breaks on SQLite → `ILIKE` is Postgres-only; use `LIKE` (ASCII-case-insensitive by default) or `lower()`/Fluent `.filter(..., .contains(...))`.
- `@Enum` model works on SQLite but migration fails / diverges on Postgres → Postgres needs a native enum type created/dropped in the migration (`database.enum("…").case(...).create()`); SQLite just makes a `TEXT` column — don't assume the same migration body enforces validity on both.
- Two independent `.sqlite(.memory)` registrations that were "supposed to be the same DB" don't share data → each `.memory` mints a fresh UUID; use `SQLiteConfiguration(storage: .memory(identifier: "shared"))` for a deliberately shared in-memory DB.
- Temp files accumulate in `TMPDIR` after in-memory test runs → the temp-file backing violates SQLite's "delete on last close" semantics; clean the temp dir in CI if it matters.

### Version-sensitive
Config API shape for the pinned versions (Fluent/FluentKit 4.13, fluent-postgres-driver 2.12.x, fluent-sqlite-driver 4.9.x, postgres-kit/sqlite-kit as their deps, Vapor 4.122, Swift 6):
- Postgres factory: `DatabaseConfigurationFactory.postgres(configuration: SQLPostgresConfiguration, maxConnectionsPerEventLoop: Int = 1, connectionPoolTimeout: TimeAmount = .seconds(10), sqlLogLevel: Logger.Level = .debug)` and throwing `.postgres(url: String)` / `.postgres(url: URL)`; optional `pruneInterval:`/`maxIdleTimeBeforePruning:` overloads exist.
- `SQLPostgresConfiguration` inits: `init(url: String) throws`, `init(url: URL) throws`, `init(hostname:port:username:password:database:tls:)`, `init(unixDomainSocketPath:username:password:database:)`, `init(coreConfiguration:searchPath:)`. TLS enum values: `.disable`, `.prefer(NIOSSLContext)`, `.require(NIOSSLContext)` (build with `try .init(configuration: .makeClientConfiguration())`).
- SQLite factory: `DatabaseConfigurationFactory.sqlite(_ config: SQLiteConfiguration = .memory, maxConnectionsPerEventLoop: Int = 1, connectionPoolTimeout: TimeAmount = .seconds(10), …)` — `maxConnectionsPerEventLoop` is documented as "Ignored. The value is always treated as 1."
- `SQLiteConfiguration(storage: Storage, enableForeignKeys: Bool = true)`; storage helpers `SQLiteConfiguration.file(_ path: String)` and `SQLiteConfiguration.memory` (random UUID id) or `.memory(identifier:)`. The `enableForeignKeys` parameter is the current knob — this is the modern replacement for it.
- DatabaseIDs: `.psql` requires `import FluentPostgresDriver`; `.sqlite` requires `import FluentSQLiteDriver`.
- Deprecated / DO NOT present as current: the pre-`SQLPostgresConfiguration` `PostgresConfiguration` type, and the Fluent-3/Vapor-3-era `databases.enableReferences(on:)` / `enableForeignKeys(on:)` FK helpers — those do not exist in the 4.x line; FK enforcement is now the `SQLiteConfiguration.enableForeignKeys` flag (default `true`).
- fluent-postgres-driver 2.12.0 raised the Swift minimum to 6.0; fluent-sqlite-driver 4.9.0 tracks the Swift 6.3 toolchain (both are Swift 6 ready and compatible with Vapor 4.122).

### Sources
- https://docs.vapor.codes/fluent/overview/
- https://docs.vapor.codes/fluent/model/
- https://docs.vapor.codes/fluent/schema/
- https://github.com/vapor/fluent-postgres-driver
- https://github.com/vapor/fluent-postgres-driver/blob/main/Sources/FluentPostgresDriver/FluentPostgresConfiguration.swift
- https://github.com/vapor/fluent-sqlite-driver
- https://github.com/vapor/fluent-sqlite-driver/blob/main/Sources/FluentSQLiteDriver/FluentSQLiteConfiguration.swift
- https://github.com/vapor/postgres-kit/blob/main/Sources/PostgresKit/SQLPostgresConfiguration.swift
- https://github.com/vapor/sqlite-kit/blob/main/Sources/SQLiteKit/SQLiteConfiguration.swift
- https://github.com/vapor/sqlite-kit/blob/main/Sources/SQLiteKit/SQLiteConnectionSource.swift
- https://github.com/vapor/sqlite-nio/blob/main/Sources/SQLiteNIO/SQLiteConnection.swift
- https://sqlite.org/foreignkeys.html
- https://sqlite.org/forum/info/e2d1cd8e30a218e6
