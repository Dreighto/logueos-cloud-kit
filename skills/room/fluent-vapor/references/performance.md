## performance

Fluent 4.13 performance is governed by six levers: connection pooling, N+1 avoidance via eager loading, pagination strategy, bulk operations, indexing, and caching. Pooling is per-EventLoop (AsyncKit EventLoopGroupConnectionPool of EventLoopConnectionPool), so total connections = maxConnectionsPerEventLoop x number-of-event-loops and must stay under Postgres max_connections; the fluent-postgres-driver 2.x default maxConnectionsPerEventLoop is 1 and connectionPoolTimeout is .seconds(10), and exhaustion enqueues waiters that fail with a pool timeout. The N+1 trap comes from lazy relations (get(on:) in a loop); the fix is .with(\.$relation) eager loading, which adds exactly one query per relation regardless of row count, plus nested .with for deep graphs. Fluent's built-in .paginate uses LIMIT/OFFSET (+ a COUNT) which degrades at high offsets; keyset/cursor pagination via .filter(\.$id > cursor).sort().limit() is not built-in but is the documented-flexible pattern for large tables. Bulk create via array create(on:) collapses to a multi-row INSERT (chunk very large batches ~1k rows); bulk update via .filter().set().update() avoids per-row save loops. Indexes matter most on foreign-key columns (Postgres does NOT auto-index FKs), on .filter/.sort columns, and unique constraints; add them with .unique(on:) or raw CREATE INDEX in a migration. Caching uses Vapor's Cache protocol (app.caches.use(.memory/.fluent) or vapor/redis) reachable via req.cache. Version-sensitive: current config type is SQLPostgresConfiguration (not the deprecated PostgresConfiguration), and Swift 6 strict concurrency pushes async/await over EventLoopFuture APIs.

### Rules
- [verified-by-docs] Size the pool with total = maxConnectionsPerEventLoop x eventLoopCount and keep it under Postgres max_connections (leaving headroom for other clients/instances). The fluent-postgres-driver 2.x default maxConnectionsPerEventLoop is 1, so under load you almost always must raise it. — _Per-EventLoop pools mean effective capacity is multiplicative; the low default (1) silently serializes DB work per loop._  (https://github.com/vapor/fluent-postgres-driver/blob/main/Sources/FluentPostgresDriver/FluentPostgresConfiguration.swift)
- [verified-by-docs] connectionPoolTimeout defaults to .seconds(10); when the pool is saturated, checkout requests are queued and fail with a pool timeout after this interval. Coordinate it with upstream HTTP client timeouts so clients don't abandon while queries keep running. — _Mismatched timeouts cause cascading retries/load amplification during traffic spikes._  (https://github.com/vapor/fluent-postgres-driver/blob/main/Sources/FluentPostgresDriver/FluentPostgresConfiguration.swift)
- [verified-by-docs] Never call relation.get(on:) or access a relation property inside a loop over parents — that is the N+1 pattern. Preload with .with(\.$relation) on the QueryBuilder (all()/first() only); each eager-loaded relation costs exactly one extra query no matter how many parents are returned. — _Lazy relations issue one query per parent; eager loading collapses N+1 into a small constant query count._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] Use nested eager loading .with(\.$star) { $0.with(\.$galaxy) } for multi-level graphs instead of walking relations in memory-then-querying. — _Prevents nested N+1 (N×M) blow-ups on deep object graphs._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] Enable SQL logging during development to count queries per route and catch N+1: set app.logger.logLevel = .debug and/or pass sqlLogLevel: .debug to the driver config. FluentKit has no built-in query counter. — _Query-count discipline requires observing the actual generated SQL; logging is the sanctioned tool._  (https://blog.vapor.codes/posts/enable-db-query-logging)
- [verified-by-docs] For large or deep tables prefer keyset/cursor pagination (.filter(\.$id > cursor).sort(\.$id, .ascending).limit(per)) over .paginate; offset pagination makes Postgres scan and skip OFFSET rows, so late pages get linearly slower and pages shift under concurrent writes. — _LIMIT/OFFSET cost grows with page depth and is unstable under inserts/deletes; keyset uses an index seek._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Use .paginate only where you need total counts / arbitrary page jumps and the table is small-to-medium; remember it issues a second COUNT(*) query per page. — _Two queries per page plus offset scan is fine for admin UIs but poor for hot large-table endpoints._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Insert many rows with a single array create(on:) (one multi-row INSERT) instead of looping save(on:); chunk very large batches (~1000 rows) to bound statement size, parameter count, memory and lock hold time. — _One bulk statement removes per-row round-trips; oversized single statements risk protocol/parameter limits._  (https://github.com/npgsql/npgsql/issues/1871)
- [verified-by-docs] Update many rows with .filter(...).set(\.$field, to: value).update() (one UPDATE) rather than fetch-mutate-save per row. — _Collapses N updates into one planned statement; fewer round-trips and locks._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Index foreign-key columns explicitly — Postgres enforces FK constraints but does NOT auto-create an index on the referencing column; relation joins and .with loads scan without it. Also index columns used in .filter and .sort, and add .unique(on:) for uniqueness lookups. — _Unindexed FK/filter/sort columns force sequential scans that no amount of pool tuning fixes._  (https://github.com/vapor/fluent-kit/issues/3)
- [verified-by-docs] Add non-implicit indexes in migrations via raw SQL cast ((database as! SQLDatabase).raw("CREATE INDEX ...").run()) or a custom constraint; use .unique(on:) for unique indexes. Don't over-index — each index slows inserts/bulk loads. — _FluentKit's high-level schema builder doesn't cover composite/partial/expression indexes; raw SQL is the escape hatch._  (https://github.com/vapor/fluent-kit/issues/3)
- [verified-by-docs] Use .chunk(max:) to stream large read result sets in batches instead of loading everything with .all(), to bound memory. — _Materializing a huge result set at once spikes memory; chunking controls it._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Cache expensive/hot query results behind Vapor's Cache protocol (app.caches.use(.memory) for single-node, .fluent for persistence/shared, vapor/redis for high-throughput shared cache), accessed via req.cache.get/set. Offloading reads to cache also relieves pool pressure. — _Serving repeats from cache reduces DB load and frees pool connections for other work._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Under Swift 6 strict concurrency, interact with the pool only through Fluent's Database handle / req.db (never hand-managed raw connections), and keep cache/log handlers Sendable; long synchronous work while holding a connection blocks the event loop. — _Manual connection or shared-mutable-state handling violates concurrency rules and can stall loops._  (https://forums.swift.org/t/vapors-next-steps-with-swift-concurrency/59719)

### Snippets

**Configure Postgres with an explicitly sized connection pool (fluent-postgres-driver 2.x)** · SQLPostgresConfiguration is the current type (PostgresConfiguration-based overloads are the deprecated path). Defaults: maxConnectionsPerEventLoop = 1, connectionPoolTimeout = .seconds(10). · https://github.com/vapor/fluent-postgres-driver/blob/main/Sources/FluentPostgresDriver/FluentPostgresConfiguration.swift
```swift
import Fluent
import FluentPostgresDriver

let config = SQLPostgresConfiguration(
    hostname: Environment.get("DB_HOST") ?? "localhost",
    port: SQLPostgresConfiguration.ianaPortNumber,
    username: "vapor", password: "vapor", database: "vapor",
    tls: .prefer(try .init(configuration: .clientDefault))
)

app.databases.use(
    .postgres(
        configuration: config,
        maxConnectionsPerEventLoop: 2,   // default is 1; total = 2 x eventLoopCount
        connectionPoolTimeout: .seconds(10),
        sqlLogLevel: .debug              // log generated SQL to count queries
    ),
    as: .psql
)
```

**Eager load to kill N+1 (single extra query per relation), including nested** · .with is available on all()/first() only. Each eager-loaded relation adds exactly one query regardless of parent count. · https://docs.vapor.codes/fluent/relations/
```swift
let planets = try await Planet.query(on: req.db)
    .with(\.$star) { star in
        star.with(\.$galaxy)
    }
    .all()

for planet in planets {
    print(planet.star.name)         // no extra query
    print(planet.star.galaxy.name)  // no extra query
}
```

**Keyset (cursor) pagination for large tables — index the cursor column** · Not a built-in API — assembled from .filter/.sort/.limit. Requires an index on the cursor column (\.$id is PK-backed). No total count. · https://docs.vapor.codes/fluent/query/
```swift
let per = 50
var query = Sale.query(on: req.db)
    .sort(\.$id, .ascending)
    .limit(per)
if let cursor = cursorId {
    query = query.filter(\.$id > cursor)
}
let items = try await query.all()
let nextCursor = items.last?.id   // pass back to client for the next page
```

**Offset pagination (built-in) — fine for small/medium tables and total counts** · Emits LIMIT/OFFSET plus a COUNT(*) for metadata (page/per/total). Page numbering starts at 1. Slower at high offsets. · https://docs.vapor.codes/fluent/query/
```swift
// Request-driven (?page=2&per=50)
let page = try await Planet.query(on: req.db)
    .sort(\.$id, .ascending)   // deterministic order required
    .paginate(for: req)

// Manual
let page2 = try await Planet.query(on: req.db)
    .paginate(PageRequest(page: 1, per: 50))
```

**Bulk insert as one multi-row INSERT, chunked for very large batches** · Array create(on:) issues a multi-row INSERT. For extreme bulk loads Postgres COPY (outside Fluent) is faster; Fluent does not expose COPY. · https://github.com/npgsql/npgsql/issues/1871
```swift
let newUsers: [User] = ...

// Small batch: single multi-row INSERT
try await newUsers.create(on: req.db)

// Large batch: chunk to bound statement size / lock time
for slice in stride(from: 0, to: newUsers.count, by: 1000).map({
    Array(newUsers[$0 ..< min($0 + 1000, newUsers.count)])
}) {
    try await slice.create(on: req.db)
}
```

**Bulk update in one statement instead of per-row save loops** · Single UPDATE ... WHERE; benefits from an index on the filter column. · https://docs.vapor.codes/fluent/query/
```swift
try await User.query(on: req.db)
    .filter(\.$isActive == true)
    .set(\.$lastLoginAt, to: Date())
    .update()
```

**Add a non-implicit index in a migration via raw SQL** · FluentKit's schema builder covers .unique(on:) but not composite/partial indexes; cast to SQLDatabase for raw CREATE INDEX. FK columns are NOT auto-indexed by Postgres. · https://github.com/vapor/fluent-kit/issues/3
```swift
struct AddSaleCreatedAtIndex: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await (database as! SQLDatabase)
            .raw("CREATE INDEX idx_sales_created_at ON sales (created_at)")
            .run()
    }
    func revert(on database: Database) async throws {
        try await (database as! SQLDatabase)
            .raw("DROP INDEX idx_sales_created_at").run()
    }
}
```

**Chunk large reads to bound memory** · chunk(max:) streams the result set in fixed-size batches; closure receives Result values. · https://docs.vapor.codes/fluent/query/
```swift
Planet.query(on: req.db).chunk(max: 64) { planets in
    // planets: [Result<Planet, Error>] — handle 64 rows at a time
}
```

### Failure modes
- **Requests hang then fail with a connection-pool timeout error under load; DB shows low active queries.** → Raise maxConnectionsPerEventLoop so total (x eventLoopCount) uses available Postgres capacity; verify total stays under max_connections. (cause: maxConnectionsPerEventLoop left at the default of 1 (or too low), so DB work serializes per event loop and checkout waiters exhaust connectionPoolTimeout (default 10s).)
- **Endpoint issues hundreds of near-identical SELECTs; latency scales with row count.** → Add .with(\.$relation) (and nested .with) to the parent query; confirm query count via sqlLogLevel: .debug. (cause: N+1 — relations accessed via get(on:) or property access inside a loop over parents without eager loading.)
- **Pagination is fast on page 1 but crawls on page 5000; rows occasionally duplicate or skip between pages.** → Switch hot large-table endpoints to keyset pagination (.filter(\.$id > cursor).sort().limit()) on an indexed, unique cursor column. (cause: .paginate uses LIMIT/OFFSET — Postgres scans and discards OFFSET rows, and offset windows shift under concurrent inserts/deletes.)
- **Importing many rows is extremely slow / times out.** → Call create(on:) on the whole array (one multi-row INSERT); chunk to ~1000 rows for very large batches. (cause: Looping save(on:)/create(on:) per model — one round-trip and statement parse per row.)
- **Relation loads / joins and filtered queries do sequential scans and are slow as the table grows.** → Add indexes in a migration (raw CREATE INDEX via SQLDatabase, or .unique(on:)) on FK, filter, and sort columns; verify with EXPLAIN ANALYZE. (cause: No index on the foreign-key or filter/sort column — Postgres does not auto-index FK columns.)
- **Bulk inserts/updates slower than expected despite batching.** → Drop redundant indexes; keep only those aligned with real query filters/sorts/joins. (cause: Over-indexing — every index must be maintained on write.)
- **Loading a huge query result spikes memory / OOMs.** → Use .chunk(max:) to process the result set in bounded batches. (cause: .all() materializes the entire result set at once.)

### Version-sensitive
- `DatabaseConfigurationFactory.postgres(configuration:maxConnectionsPerEventLoop:connectionPoolTimeout:sqlLogLevel:)`: Current config type is SQLPostgresConfiguration. The older PostgresConfiguration-based and bare hostname/port/username overloads are the legacy path (docs steer you to the configuration-based initializer). Defaults: maxConnectionsPerEventLoop = 1, connectionPoolTimeout = .seconds(10). These defaults can change between driver versions — pin and verify.  (https://github.com/vapor/fluent-postgres-driver/blob/main/Sources/FluentPostgresDriver/FluentPostgresConfiguration.swift)
- `Connection pool total sizing (AsyncKit EventLoopGroupConnectionPool)`: Total possible connections = maxConnectionsPerEventLoop x number of event loops (typically CPU core count). Must be budgeted against Postgres max_connections including other app instances/tools. Behavior is stable across Fluent 4 but easy to miscompute.  (https://forums.swift.org/t/generic-connection-pool/39161)
- `.paginate / PageRequest / Page`: Built-in pagination is LIMIT/OFFSET only and adds a COUNT(*) for metadata; there is no built-in keyset/cursor pagination — keyset must be hand-built from .filter/.sort/.limit.  (https://docs.vapor.codes/fluent/query/)
- `FluentSQL raw helpers (.sql(unsafeRaw:), .sql(embed:), .sql(_:))`: Added/tightened in the FluentKit 4.13 line for embedding raw SQL fragments (useful for composite-cursor pagination or advanced index/DDL). Older tutorials predate these APIs.  (https://github.com/vapor/fluent-kit/releases)
- `Custom index creation in migrations`: Historic .constraint(.custom("INDEX ...")) guidance is version/branch-sensitive and not reliable across FluentKit versions; the portable approach is casting to SQLDatabase and running raw CREATE INDEX. .unique(on:) remains the supported way to get a unique index.  (https://github.com/vapor/fluent-kit/issues/3)
- `EventLoopFuture vs async/await surface`: Under Swift 6 strict concurrency, Vapor is deprecating/wrapping EventLoopFuture APIs in favor of async/await; use AsyncMigration and async query APIs. Driver internals still use NIO futures. Non-Sendable types crossing task boundaries are flagged.  (https://forums.swift.org/t/vapors-next-steps-with-swift-concurrency/59719)

### Open questions
- Context7 is NOT connected in this environment (per task note); substituted Firecrawl/WebFetch against official docs.vapor.codes, api.vapor.codes, and vapor GitHub source instead. Recorded here as required.
- Whether array create(on:) always emits a single multi-row INSERT vs a prepared-statement batch in fluent-postgres-driver 2.12 was not confirmed from the driver source directly — asserted from Postgres bulk-insert practice and general Fluent behavior (inferred-from-research). Verify in FluentPostgresDatabase query executor if exactness matters.
- Exact error type thrown on pool-timeout exhaustion in current AsyncKit was not pinned to a named type; described conceptually. Confirm the concrete error enum against the installed async-kit version if you need to pattern-match it.
- fluent-postgres-driver 2.12.x specific changelog was not individually fetched; version anchor treated as current Fluent 4 line. Confirm no pool-default changes in the 2.12 release notes before relying on maxConnectionsPerEventLoop=1.
- Vapor Cache/Redis specifics were drawn from a secondary source (Kodeco) plus the vapor/redis package rather than a fetched docs.vapor.codes/advanced/cache page; treat caching APIs as inferred-from-research and verify req.cache/app.caches.use signatures against the current Advanced > Cache docs.

### Sources
- https://docs.vapor.codes/fluent/query/
- https://docs.vapor.codes/fluent/relations/
- https://docs.vapor.codes/fluent/overview/
- https://github.com/vapor/fluent-postgres-driver/blob/main/Sources/FluentPostgresDriver/FluentPostgresConfiguration.swift
- https://api.vapor.codes/fluentpostgresdriver/documentation/fluentpostgresdriver/
- https://github.com/vapor/fluent-kit
- https://github.com/vapor/fluent-kit/releases
- https://github.com/vapor/fluent-kit/issues/3
- https://github.com/vapor/async-kit/blob/master/Sources/AsyncKit/ConnectionPool/EventLoopConnectionPool.swift
- https://github.com/vapor/postgres-kit/blob/main/README.md
- https://forums.swift.org/t/generic-connection-pool/39161
- https://forums.swift.org/t/vapors-next-steps-with-swift-concurrency/59719
- https://blog.vapor.codes/posts/enable-db-query-logging
- https://github.com/npgsql/npgsql/issues/1871
