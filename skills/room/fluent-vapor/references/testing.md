## testing

Vapor 4.122 + Fluent 4.13 testing centers on the VaporTesting module (built on Swift Testing), which replaces the older XCTVapor/XCTest path for new Swift 6.2 strict-concurrency projects. The canonical pattern is app-per-test: build an Application in the .testing environment, run the shared configure(_:), call autoMigrate(), run the test, then autoRevert() and asyncShutdown(). VaporTesting ships a withApp(configure:) helper for lifecycle management; for DB tests you write your own withAppIncludingDB wrapper that adds autoMigrate/autoRevert around it. Hermetic tests use in-memory SQLite (.sqlite(.memory)) selected via `app.environment == .testing`, which gives each app a fresh, discarded DB so tests can run in parallel; suites that share one DB must carry the .serialized trait. Send requests with `app.testing(method:).test(...)` (note: VaporTesting uses testing(); XCTVapor used testable()) defaulting to .inMemory transport, or .running for a live HTTP server. Migration tests assert both prepare and revert by calling them directly on app.db (or exercising autoMigrate/autoRevert). Two real gotchas dominate: SQLite disables foreign keys unless the driver issues PRAGMA foreign_keys=ON (the current fluent-sqlite-driver does this automatically, older ones needed enableReferences), and Fluent's N+1 detection uses the official `app.fluent.history` query recorder (`start()`/`queries.count`/`stop()`), with a `.debug` LogHandler as a SQL-layer fallback. For features SQLite can't emulate (JSONB, arrays, partial indexes, real UUID type, PG isolation levels) run a parallel PostgreSQL-backed suite, typically in Docker.

### Rules

- [verified-by-docs] Use the VaporTesting module (import VaporTesting + import Testing) with @Suite/@Test for new Fluent test suites; reserve XCTVapor/XCTest only for legacy code. Add .product(name: "VaporTesting", package: "vapor") to the test target. — _Official docs recommend Swift Testing over XCTest for newer projects/teams adopting Swift concurrency; wrong testing module = failures not reported._ (https://docs.vapor.codes/advanced/testing/)
- [verified-by-docs] Adopt app-per-test isolation: `let app = try await Application.make(.testing)`, run configure(app), `try await app.autoMigrate()`, run test, `try await app.autoRevert()`, then `try await app.asyncShutdown()` — call autoRevert AND asyncShutdown on the error path too. Wrap this in a reusable withAppIncludingDB helper. — _Exact scaffold shown in the official Database Integration Tests section; guarantees each test starts from a fresh, consistent schema/data state._ (https://docs.vapor.codes/advanced/testing/)
- [verified-by-docs] Select the test database by environment inside configure(_:): `if app.environment == .testing { app.databases.use(.sqlite(.memory), as: .sqlite) } else { ... }`. Never let tests touch the production/file DB. — _Documented pattern; docs explicitly warn about accidentally overwriting live data when tests run against the wrong DB._ (https://docs.vapor.codes/advanced/testing/)
- [verified-by-docs] Mark any @Suite that shares a single database/Application with the .serialized trait: `@Suite("App Tests with DB", .serialized)`. If instead every test builds its own Application+in-memory DB (app-per-test), tests can safely run in parallel without .serialized. — _Swift Testing runs tests in parallel by default; concurrent access to a shared DB causes flaky races. .serialized forces one-at-a-time execution._ (https://docs.vapor.codes/advanced/testing/)
- [verified-by-docs] Send requests with `try await app.testing().test(.GET, "path") { res async in #expect(res.status == .ok) }`; use beforeRequest to encode content and afterResponse for assertions. Transport defaults to .inMemory; use `app.testing(method: .running(port:))` for live-HTTP tests. — _Canonical request API in VaporTesting. .inMemory avoids opening a port and is faster/hermetic._ (https://docs.vapor.codes/advanced/testing/)
- [verified-by-docs] Test a migration's reversibility by calling prepare and revert directly on the DB: `try await CreateUser().prepare(on: app.db)` ... `try await CreateUser().revert(on: app.db)`, asserting schema/state before and after. Or exercise the whole chain via autoMigrate()/autoRevert(). — _Migrations are AsyncMigration with async prepare(on:)/revert(on:); directly invoking both is how you prove a migration round-trips cleanly._ (https://docs.vapor.codes/fluent/migration/)
- [verified-by-docs] For per-test rollback against a shared PostgreSQL test DB, run test work inside `try await app.db.transaction { db in ... }` — the closure commits on success and rolls back on any thrown error, leaving no residue. — _transaction(_:) is Fluent's documented transaction API; rolling back per test isolates PG-backed tests. Caveat: once a statement errors mid-transaction PostgreSQL aborts the whole transaction (savepoints needed to continue)._ (https://docs.vapor.codes/fluent/overview/)
- [verified-by-docs] Catch N+1 with FluentKit's OFFICIAL query recorder, `app.fluent.history` (`req.fluent.history` in a request): `app.fluent.history.start()`, run the endpoint, assert `app.fluent.history.queries.count <= N`, then `.clear()`/`.stop()`. Capture `app.db` AFTER `history.start()` (the recorder is snapshotted at db access). A `.debug` LogHandler counting the driver's serialized-SQL lines is an equivalent fallback at the SQL layer, but the recorder is first-class and preferred. — _Corrected 2026-07-11: an earlier version wrongly claimed "no official query-count API." `app.fluent.history` exposes public `start()`/`stop()`/`clear()`/`queries: [DatabaseQuery]` — verified in vapor/fluent `Fluent+History.swift` and fluent-kit `QueryHistory.swift`; matches the SKILL.md testing section._ (https://api.vapor.codes/fluent/documentation/fluentkit/)
- [verified-by-docs] Verify eager loading with `.with(\.$posts)` and assert the relation loaded: `#expect(loadedUser.$posts.value?.count == 2)` — the relation's .value is nil until eager-loaded. Combine with a query-count assertion to prove .with() collapses N+1 into a bounded number of queries. — _Docs describe .with() eager loading and the .value property indicating whether a relation was loaded; testing both correctness and query count guards against N+1 regressions._ (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] Test unique-constraint and FK violations by attempting the illegal operation and asserting a throw: `await #expect(throws: Error.self) { try await dupUser.save(on: app.db) }`. Remember FK cascade/onDelete actions execute in the database and bypass Fluent middleware (no soft-delete hooks fire). — _Schema builder defines unique(on:) and foreignKey(...onDelete:); docs state FK actions happen solely in the DB, so cascade tests must inspect DB rows, not rely on Fluent middleware._ (https://docs.vapor.codes/fluent/schema/)
- [verified-by-docs] When using in-memory SQLite, confirm foreign keys are actually enforced. The current fluent-sqlite-driver issues PRAGMA foreign_keys=ON per connection automatically; do not assume this on older driver versions — verify with a deliberate FK-violation test. — _SQLite disables FKs by default. Without the PRAGMA, referential-integrity tests silently pass (never enforce), giving false confidence._ (https://github.com/vapor/fluent-sqlite-driver/issues/9)
- [verified-by-docs] Run a separate PostgreSQL-backed suite (e.g. Docker container) for behavior SQLite can't emulate: real uuid type, JSONB/arrays, partial/expression indexes, ILIKE/collation case-sensitivity, and PG isolation levels. Keep fast SQLite tests for ORM/routing logic. — _SQLite's flexible typing and missing PG features mean SQLite-green tests can fail on production PostgreSQL; a hybrid suite balances speed and fidelity._ (https://losingfight.com/blog/2018/12/16/how-to-do-integration-testing-on-a-vapor-server/)
- [inferred-from-research] Build fixtures/factories as async helpers on the DB (e.g. `User.fixture(on: db, variant:)`) that generate deterministic unique values (counter- or test-name-derived) and never rely on implicit row ordering — always add explicit .sort() when order matters. — _Deterministic fixtures make failures reproducible; implicit ordering breaks when the query plan changes. Avoid global mutable factory state under strict concurrency._ (https://forums.swift.org/t/fixtures-support-for-simplified-testing-of-complex-model-structures/40655)

### Snippets

**Environment-split DB config (SQLite memory for tests)** · Vapor 4.122 / async configure. fluent-sqlite-driver 4.9.x enables PRAGMA foreign_keys=ON automatically. · https://docs.vapor.codes/advanced/testing/

```swift
public func configure(_ app: Application) async throws {
    app.migrations.add(CreateUser())
    app.migrations.add(CreatePost())
    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
    }
}
```

**withAppIncludingDB app-per-test scaffold with autoMigrate/autoRevert** · Application.make + asyncShutdown are the current async lifecycle APIs (Vapor 4.x). The older XCTVapor idiom Application(.testing) + defer { app.shutdown() } is legacy. · https://docs.vapor.codes/advanced/testing/

```swift
@testable import App
import VaporTesting
import Testing
import Fluent

private func withAppIncludingDB(
    _ test: (Application) async throws -> Void
) async throws {
    let app = try await Application.make(.testing)
    do {
        try await configure(app)
        try await app.autoMigrate()
        try await test(app)
        try await app.autoRevert()
    } catch {
        try? await app.autoRevert()
        try await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}
```

**Suite + request test (VaporTesting uses testing(), not testable())** · VaporTesting: app.testing(method: .inMemory|.running). XCTVapor used app.testable(method:). Do not mix. · https://docs.vapor.codes/advanced/testing/

```swift
@Suite("App Tests with DB", .serialized)
struct AppTests {
    @Test("Create todo")
    func createTodo() async throws {
        try await withAppIncludingDB { app in
            let newDTO = TodoDTO(id: nil, title: "test")
            try await app.testing().test(.POST, "todos", beforeRequest: { req in
                try req.content.encode(newDTO)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let models = try await Todo.query(on: app.db).all()
                #expect(models.map { $0.toDTO().title } == [newDTO.title])
            })
        }
    }
}
```

**Migration apply-and-revert test** · AsyncMigration.prepare/revert are async throws in Fluent 4.x. autoRevert() inside withAppIncludingDB will also revert; calling m.revert directly here is the explicit round-trip assertion. · https://docs.vapor.codes/fluent/migration/

```swift
@Test("CreateUser migration round-trips")
func migrationRoundTrips() async throws {
    try await withAppIncludingDB { app in
        let m = CreateUser()
        try await m.prepare(on: app.db)
        // table exists -> insert works
        try await User(email: "a@example.com").save(on: app.db)
        try await m.revert(on: app.db)
        // after revert the table is gone -> query throws
        await #expect(throws: Error.self) {
            _ = try await User.query(on: app.db).all()
        }
    }
}
```

**Per-test transaction rollback against shared PostgreSQL** · app.db.transaction(_:) commits on success, rolls back on throw. PG note: a mid-transaction error aborts the entire transaction — use savepoints to continue after an expected failure. · https://docs.vapor.codes/fluent/overview/

```swift
@Test("work rolls back")
func rollbackTest() async throws {
    try await withAppIncludingDB { app in
        try await app.db.transaction { db in
            try await User(email: "tx@example.com").save(on: db)
            let count = try await User.query(on: db).count()
            #expect(count == 1)
            struct Rollback: Error {}
            throw Rollback()   // forces rollback
        } // catch or expect the throw outside; DB left clean
    }
}
```

**Query-counting LogHandler for N+1 detection** · No official Fluent query-count API. Relies on drivers logging SQL at .debug. Hold the handler reference from LoggingSystem.bootstrap; do NOT cast app.logger.handler back to this type (unreliable). String-matching SQL is heuristic (BEGIN/COMMIT may add noise). · https://blog.vapor.codes/posts/enable-db-query-logging

```swift
import Logging
import Atomics

final class QueryCountingLogHandler: LogHandler {
    let counter = ManagedAtomic<Int>(0)
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .debug
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] } set { metadata[key] = newValue }
    }
    func log(level: Logger.Level, message: Logger.Message,
             metadata: Logger.Metadata?, source: String,
             file: String, function: String, line: UInt) {
        let t = message.description
        if t.contains("SELECT") || t.contains("INSERT")
            || t.contains("UPDATE") || t.contains("DELETE") {
            counter.wrappingIncrement(ordering: .relaxed)
        }
    }
    var queryCount: Int { counter.load(ordering: .relaxed) }
}
// usage: keep a reference; bootstrap once; app.logger.logLevel = .debug
// #expect(handler.queryCount <= 2)  // eager-loaded endpoint budget
```

**Eager-loading + relation assertion** · @Children(for:)/@Parent(key:) property wrappers; .with(\.$posts) eager loads; relation .value is the loaded-state accessor. · https://docs.vapor.codes/fluent/relations/

```swift
@Test("eager load posts with .with()")
func eagerLoad() async throws {
    try await withAppIncludingDB { app in
        let user = User(email: "e@example.com")
        try await user.save(on: app.db)
        try await Post(userID: user.requireID(), title: "a").save(on: app.db)
        try await Post(userID: user.requireID(), title: "b").save(on: app.db)
        let users = try await User.query(on: app.db).with(\.$posts).all()
        let loaded = try #require(users.first)
        #expect(loaded.$posts.value?.count == 2) // .value nil until eager-loaded
    }
}
```

**Unique-constraint violation test** · Requires the migration to declare .unique(on: "email"). Swift Testing async throwing form: await #expect(throws:) { }. Error type is driver-specific. · https://docs.vapor.codes/fluent/schema/

```swift
@Test("unique email enforced")
func uniqueEmail() async throws {
    try await withAppIncludingDB { app in
        try await User(email: "dup@example.com").save(on: app.db)
        await #expect(throws: Error.self) {
            try await User(email: "dup@example.com").save(on: app.db)
        }
    }
}
```

### Failure modes

- **Test suite crashes intermittently with a thread-allocation precondition failure after several tests** → Always pair Application.make(.testing) with try await app.asyncShutdown() (or defer { app.shutdown() } in XCTVapor) — put it in a withAppIncludingDB helper that shuts down on both success and error paths (cause: Application instances never shut down; each leaks its thread pool until allocation fails)
- **Flaky DB tests: data from one test bleeds into another, order-dependent failures** → Either use app-per-test with in-memory SQLite (fresh DB each test), or add the .serialized trait to the shared-DB suite; always .sort() queries whose order you assert on (cause: Tests run in parallel (Swift Testing default) against a shared database, or fixtures rely on implicit row ordering)
- **Foreign-key / cascade test passes but production PostgreSQL rejects the same operation** → Verify the driver enables FKs (current fluent-sqlite-driver does automatically); add a deliberate FK-violation test that must throw; run FK/cascade behavior against a real PostgreSQL suite too (cause: In-memory SQLite ran without PRAGMA foreign_keys=ON, so FK constraints were never enforced during the test)
- **Query-count assertion always reads 0 or a stale value** → Retain the handler reference returned from LoggingSystem.bootstrap and read the counter from it; set app.logger.logLevel = .debug (and/or sqlLogLevel: .debug on the driver) (cause: Casting app.logger.handler back to the custom QueryCountingLogHandler doesn't return the live instance, or SQL logging isn't at debug level)
- **Test that expects a constraint error then continues on the same PG transaction fails with 'transaction is aborted'** → Scope the expected-failure operation in its own transaction, or use SAVEPOINT and roll back to it before continuing (cause: PostgreSQL aborts the whole transaction after any statement error; subsequent statements fail until rollback)
- **SQLite-green tests fail on PostgreSQL: JSONB/array queries, real uuid comparisons, ILIKE case-insensitivity, or partial-index uniqueness** → Keep SQLite for fast ORM/routing tests; run a Docker-backed PostgreSQL suite for PG-specific features and don't rely on SQLite for those (cause: SQLite's flexible typing and missing PG features don't reproduce production behavior)
- **Vapor test failures don't show up / tests report success despite assertions failing** → Add .product(name: "VaporTesting", package: "vapor") to the test target and import both VaporTesting and Testing; use the module matching your test framework (cause: Wrong testing module linked (missing VaporTesting, or mixing XCTVapor with Swift Testing))

### Version-sensitive

- `app.testing(method:) vs app.testable(method:)`: VaporTesting (current, Swift Testing) exposes app.testing().test(...) and app.testing(method: .inMemory|.running). The legacy XCTVapor module used app.testable(method:). Using the wrong one for your test framework, or expecting testable() in a VaporTesting file, fails to compile / mis-reports. (https://docs.vapor.codes/advanced/testing/)
- `Application.make(.testing) + asyncShutdown() vs Application(.testing) + shutdown()`: Current async lifecycle is `try await Application.make(.testing)` paired with `try await app.asyncShutdown()`. The synchronous Application(.testing) + defer { app.shutdown() } pattern is the older XCTVapor idiom; missing shutdown leaks threads and crashes later tests with a thread-allocation precondition failure. (https://docs.vapor.codes/advanced/testing/)
- `withApp(configure:) helper`: Docs state VaporTesting provides withApp(configure:) for lifecycle management. Some project templates also/instead define withApp locally in the test target. The DB-including variant (withAppIncludingDB with autoMigrate/autoRevert) is code you write yourself — it is not shipped. (https://docs.vapor.codes/advanced/testing/)
- `SQLite PRAGMA foreign_keys`: SQLite disables FK enforcement by default. Current fluent-sqlite-driver auto-issues PRAGMA foreign_keys=ON per connection; older versions required explicit enableReferences(on:)/enableForeignKeys(on:). If FKs aren't on, referential-integrity tests silently never enforce. (https://github.com/vapor/fluent-sqlite-driver/issues/9)
- `Swift Testing #expect(throws:) / #require`: Async throwing assertions use `await #expect(throws: Error.self) { try await ... }` and `try #require(...)` to unwrap-or-fail. This replaces XCTAssertThrowsError / XCTUnwrap from XCTest. (https://developer.apple.com/documentation/testing/trait/serialized)
- `.serialized suite trait`: Swift Testing parallelizes tests by default; @Suite(..., .serialized) forces sequential execution. Required for suites sharing one DB/Application; unnecessary (and slower) for true app-per-test isolation. (https://docs.vapor.codes/advanced/testing/)
- `sqlLogLevel on driver config`: PostgreSQL driver config accepts sqlLogLevel (e.g. .debug/.info) to control where generated SQL is logged; combined with app.logger.logLevel = .debug this surfaces SQL for query-count instrumentation. There is no first-class query-count API. (https://blog.vapor.codes/posts/enable-db-query-logging)

### Open questions

- Context7 is not connected in this environment; the API-reference-level confirmations were substituted with Firecrawl/WebFetch scrapes of docs.vapor.codes plus one Perplexity deep-research pass. The verbatim VaporTesting page (docs.vapor.codes/advanced/testing) is the primary verified source; the Fluent migration/relations/schema/overview pages were cited via research rather than directly scraped this session.
- Fluent exposes NO official query-count / N+1 assertion API. The LogHandler-based counting shown is a community-synthesized approach (inferred-from-research), heuristic (string-matches SQL, may miss/overcount BEGIN/COMMIT), and needs its own reference held from LoggingSystem.bootstrap. Whether fluent-kit exposes a cleaner test hook in 4.13 was not confirmed against the API reference.
- The exact source of withApp(configure:) — shipped inside VaporTesting vs generated into the project template's test target — should be confirmed against the current template/API ref before asserting it is always importable.
- Exact per-version behavior of automatic PRAGMA foreign_keys=ON across fluent-sqlite-driver 4.9.x releases was inferred from an older GitHub issue, not re-verified against the 4.9.x source/release notes.
- Did not verify against fluent-postgres-driver 2.12.x whether the .postgres(...) config initializer signature (sqlLogLevel param, PostgresConfiguration.ianaPortNumber) shown in the research is current for that version vs the newer SQLPostgresConfiguration API.

### Sources

- https://docs.vapor.codes/advanced/testing/
- https://docs.vapor.codes/fluent/overview/
- https://docs.vapor.codes/fluent/migration/
- https://docs.vapor.codes/fluent/relations/
- https://docs.vapor.codes/fluent/schema/
- https://blog.vapor.codes/posts/enable-db-query-logging
- https://developer.apple.com/documentation/testing/trait/serialized
- https://github.com/vapor/fluent-sqlite-driver/issues/9
- https://github.com/vapor/fluent-kit/blob/master/Tests/FluentKitTests/FluentKitTests.swift
- https://forums.swift.org/t/transaction-aborted-after-catched-error/79520
- https://forums.swift.org/t/fixtures-support-for-simplified-testing-of-complex-model-structures/40655
- https://losingfight.com/blog/2018/12/16/how-to-do-integration-testing-on-a-vapor-server/
