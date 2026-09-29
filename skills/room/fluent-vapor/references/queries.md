## queries

Fluent 4.13's query builder is a chainable, type-safe DSL rooted at Model.query(on: db), using @propertyWrapper key paths (\.$field) rather than plain KeyPaths. It covers value/field/subset/contains filters, .sort, .range and .paginate, model joins (with ModelAlias for self-joins), aggregates (count/sum/average/min/max), .field selection, .unique, and .group(.and/.or) nested predicates. Terminators are .all(), .first(), .count(), and .all(\.$field). Bulk mutation is expressed as .set(...).filter(...).update() and .filter(...).delete(). Soft delete is driven by @Timestamp(on: .delete); soft-deleted rows are hidden by default, surfaced with .withDeleted(), and permanently removed with delete(force: true). The type-safe builder cannot express arbitrary SQL functions, DISTINCT ON, window functions, CTEs, UPSERT/ON CONFLICT, or complex expressions — for those, cast req.db as? SQLDatabase (FluentSQL) and use sql.raw("...") with \(bind:)/\(ident:) interpolation, or the query.filter(.custom(...)) / .sql(raw:) escape hatch. SQL is logged at the driver's debug level; enable via app.logger.logLevel = .debug or LOG_LEVEL=debug, with a configurable sqlLogLevel on the driver.

### Rules
- [verified-by-docs] Filter with property-wrapper key paths and operators: value filters (== != > >= < <=), field-to-field filters (\.$a == \.$b), subset filters (~~ in set, !~ not in set), and string contains filters (=~ prefix, ~= suffix, ~~ contains, negations !=~ / !~=). — _These are the exact operators the type-safe builder exposes; using a plain Swift KeyPath instead of \.$ will not compile._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Combine predicates with .group(.or) { $0.filter(...).filter(...) } or .group(.and){...} to control AND/OR precedence; top-level chained .filter calls are ANDed together. — _Chained filters are implicit AND; OR requires an explicit group, and nesting groups controls parenthesization._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Sort with .sort(\.$field) (optionally .sort(\.$field, .descending)); chain multiple .sort calls for tie-break ordering. — _Second and later sorts act as fallbacks._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Page manually with .range(..<5) / .range(2...) / .range(2..<5); for API pagination use .paginate(for: req) (reads page & per query params) or .paginate(PageRequest(page:1, per:2)), which returns a Page with .items and .metadata. — _paginate is the production-safe cursor for request-driven pages; range is the low-level LIMIT/OFFSET._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Join with .join(Other.self, on: \Model.$rel.$id == \Other.$id), filter joined fields via .filter(Other.self, \.$field == value), and read joined rows with model.joined(Other.self). Use a ModelAlias to join the same table more than once. — _Joined columns are not on the base model; you must retrieve them through joined(_:), and self-joins collide without an alias._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Aggregate with .count(), .sum(\.$f), .average(\.$f), .min(\.$f), .max(\.$f); these are terminators returning a scalar, not a query builder. — _They execute immediately and short-circuit the fetch of full models._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Restrict selected columns with .field(\.$id).field(\.$name) before .all(); fetch a single column across rows with .all(\.$field); dedupe with .unique() (e.g. .unique().all(\.$firstName)). — _Field selection reduces payload; .unique() maps to SELECT DISTINCT._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Bulk update in one statement: Model.query(on: db).set(\.$field, to: value).filter(...).update(); bulk delete: Model.query(on: db).filter(...).delete(). These run a single UPDATE/DELETE without loading models into memory. — _Avoids the fetch-then-save N+1 pattern; note bulk .delete() bypasses per-model middleware/lifecycle hooks._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Soft delete uses @Timestamp(key: "deleted_at", on: .delete); soft-deleted rows are auto-excluded from normal queries, included with .withDeleted(), and hard-deleted with model.delete(force: true, on: db) or query .delete(force: true). — _Without withDeleted() you will silently miss soft-deleted rows; force:true is the only way to physically remove them._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] Filter on @Group nested fields with dot-syntax key paths: .filter(\.$pet.$name == "Zizek"); the columns are stored flat as pet_name, pet_type etc. — _Grouped properties are queryable because they flatten to underscore-joined columns._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] When the type-safe builder can't express something, cast: if let sql = req.db as? SQLDatabase { try await sql.raw("SELECT ... WHERE \(ident: col) = \(bind: value)").all(decoding: Model.self) }. Always use \(bind:) for user input and \(ident:) for identifiers. — _Raw string interpolation without \(bind:) is a SQL-injection hole; \(bind:) parameterizes and \(ident:) safely quotes names._  (https://github.com/vapor/sql-kit)
- [verified-by-docs] For a small dialect gap inside an otherwise type-safe query, use the .custom escape hatch: query.filter(\.$name, .custom("ILIKE"), "earth") or FluentSQL's query.filter(.sql(raw: "LOWER(name) = 'earth'")); guard on db is SQLDatabase / is PostgresDatabase first. — _Lets you keep the rest of the query type-safe while injecting one unsupported operator/expression; the guard prevents runtime traps on non-SQL drivers._  (https://docs.vapor.codes/fluent/advanced/)
- [verified-by-docs] Justify raw SQL only when Fluent genuinely cannot express it: UPSERT/ON CONFLICT, window functions, CTEs, DISTINCT ON, DB-specific functions, or complex GROUP BY/HAVING. Prefer SQLKit's query builder (sql.select()/update()...run()) over sql.raw for structured queries so identifiers/binds stay safe. — _SQLKit builder methods parameterize and quote automatically; hand-written raw strings are the last resort._  (https://github.com/vapor/sql-kit)
- [verified-by-docs] See generated SQL by setting app.logger.logLevel = .debug (or LOG_LEVEL=debug / --log debug); Fluent drivers log SQL at debug level. For the fully-serialized SQL with bind values on postgres, .trace is needed (very noisy, non-production). — _There is no query-builder .print(); logging level is the debugging mechanism, and debug now shows an abstracted query while trace shows raw SQL._  (https://blog.vapor.codes/posts/enable-db-query-logging/)

### Snippets

**Filters, groups, sort, pagination** · Fluent 4.13 / FluentKit — key paths use \.$ property-wrapper projection. · https://docs.vapor.codes/fluent/query/
```swift
// implicit AND across chained filters
let planets = try await Planet.query(on: req.db)
    .filter(\.$type == .gasGiant)
    .filter(\.$name ~~ ["Jupiter", "Saturn"])   // subset (IN)
    .filter(\.$name =~ "J")                        // prefix match
    .sort(\.$name).sort(\.$id)                     // primary + tie-break
    .range(..<10)
    .all()

// explicit OR group
let earthOrMars = try await Planet.query(on: req.db)
    .group(.or) { $0.filter(\.$name == "Earth").filter(\.$name == "Mars") }
    .all()

// request-driven pagination -> Page<Planet>
app.get("planets") { req in
    try await Planet.query(on: req.db).paginate(for: req)
}
```

**Join with filter and self-join alias** · ModelAlias required for repeated joins of the same table. · https://docs.vapor.codes/fluent/query/
```swift
let sunPlanets = try await Planet.query(on: req.db)
    .join(Star.self, on: \Planet.$star.$id == \Star.$id)
    .filter(Star.self, \.$name == "Sun")
    .all()
for planet in sunPlanets { let star = try planet.joined(Star.self) }

final class HomeTeam: ModelAlias { static let name = "home_teams"; let model = Team() }
let matches = try await Match.query(on: req.db)
    .join(HomeTeam.self, on: \Match.$homeTeam.$id == \HomeTeam.$id)
    .filter(HomeTeam.self, \.$name == "Vapor")
    .all()
```

**Aggregates, field selection, bulk update/delete** · Aggregate/terminator methods execute immediately. · https://docs.vapor.codes/fluent/query/
```swift
let count = try await Planet.query(on: req.db).count()
let total = try await Planet.query(on: req.db).sum(\.$mass)

// select only some columns
let names = try await Planet.query(on: req.db)
    .unique().all(\.$name)

// single-statement bulk update
try await Planet.query(on: req.db)
    .set(\.$type, to: .dwarf)
    .filter(\.$name == "Pluto")
    .update()

// single-statement bulk delete (bypasses per-model middleware)
try await Planet.query(on: req.db).filter(\.$name == "Vulcan").delete()
```

**Soft delete queries** · Default queries exclude soft-deleted rows automatically. · https://docs.vapor.codes/fluent/model/
```swift
// model declaration
@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

// include soft-deleted rows
let all = try await Planet.query(on: req.db).withDeleted().all()
// permanently remove a soft-deletable model
try await planet.delete(force: true, on: req.db)
```

**Raw SQL escape hatch (SQLKit) with safe binds** · \(bind:) parameterizes; \(ident:) quotes identifiers — required to avoid injection. · https://github.com/vapor/sql-kit
```swift
import FluentSQL
if let sql = req.db as? SQLDatabase {
    let planets = try await sql.raw("""
        SELECT \(SQLLiteral.all) FROM \(ident: "planets")
        WHERE \(ident: "name") = \(bind: userInput)
    """).all(decoding: Planet.self)
}

// dialect-gap escape hatch inside a type-safe query
let q = Planet.query(on: req.db)
if req.db is PostgresDatabase { q.filter(\.$name, .custom("ILIKE"), "earth") }
else { q.filter(.sql(raw: "LOWER(name) = 'earth'")) }
```

### Failure modes
- **Query silently returns fewer rows than exist in the table** → Add .withDeleted() to include soft-deleted rows, or delete(force: true) to remove them physically (cause: Model has a @Timestamp(on: .delete) soft-delete field; soft-deleted rows are excluded from normal queries by default)
- **Boolean logic wrong: an OR condition behaves like AND and returns nothing** → Wrap the alternatives in .group(.or) { $0.filter(...).filter(...) } (cause: Multiple chained .filter(...) calls are ANDed together, not ORed)
- **Joined model's fields are missing / accessing them crashes** → Retrieve them with model.joined(OtherModel.self); filter joined fields with .filter(Other.self, \.$field == v) (cause: Joined columns are not projected onto the base model automatically)
- **Runtime crash / trap when using .custom("ILIKE") or driver-specific SQL** → Guard with `if req.db is PostgresDatabase` / `is SQLDatabase` and provide a portable fallback branch (cause: The .custom operator or raw SQL was sent to a driver that doesn't support it (e.g. SQLite, MongoDB))
- **SQL injection or malformed query when building raw SQL** → Use \(bind: value) for values and \(ident: name) for table/column identifiers; never interpolate raw user strings (cause: User input concatenated directly into sql.raw("...") string interpolation)
- **as? SQLDatabase cast returns nil so raw block is skipped** → Handle the else branch (throw Abort or portable fallback); only force-cast when the SQL driver is guaranteed (cause: The underlying driver is not a SQL database (e.g. MongoDB), or the branch was written as as! and traps)
- **Set logLevel = .debug but only see abstracted 'query read ... filters=[...]' not real SQL** → Use logLevel = .trace to see raw SQL with bindings (very noisy; dev only), or configure sqlLogLevel on the driver (cause: Modern fluent-postgres-driver logs an abstracted representation at .debug, not the serialized SQL)
- **Bulk .delete() didn't fire model lifecycle hooks / middleware** → If you need hooks, fetch models with .all() then delete/save each; otherwise accept the bulk path for performance (cause: Query-builder bulk .delete()/.update() run a single SQL statement and bypass per-model ModelMiddleware and lifecycle callbacks)

### Version-sensitive
- `sqlLogLevel database config parameter`: The 2022 blog example uses the legacy .postgres(hostname:...) initializer with sqlLogLevel:. In fluent-postgres-driver 2.12.x the current form is .postgres(configuration: SQLPostgresConfiguration(...), sqlLogLevel: .debug). Verify the exact initializer against the driver's current README before quoting.  (https://blog.vapor.codes/posts/enable-db-query-logging/)
- `debug vs trace SQL logging`: Since fluent-postgres-driver 2.x, .debug logs an abstracted query representation (filters=[...]) not raw SQL; to see fully-serialized SQL with bindings you must use logLevel = .trace (postgres-nio connection tracing), which is very noisy and not for production.  (https://github.com/vapor/fluent-postgres-driver/issues/181)
- `delete(force:on:) argument order`: Async/EventLoopFuture signatures differ: model.delete(force: true, on: db). Confirm the current FluentKit signature (force flag position) against the API reference for 4.13.x.  (https://docs.vapor.codes/fluent/model/)
- `.paginate return type`: paginate(for:) / paginate(PageRequest) returns Page<Model> with .items and .metadata (page/per/total); Page is Content-encodable. Shape is stable in Fluent 4 but confirm metadata field names against api.vapor.codes.  (https://docs.vapor.codes/fluent/query/)

### Open questions
- Context7 is NOT connected in this environment; substituted WebFetch + Firecrawl/Perplexity against docs.vapor.codes, api.vapor.codes, and the vapor GitHub repos, plus the Vapor blog. Recorded per instructions.
- docs.vapor.codes is not explicitly version-pinned to Fluent 4.13.x on-page; the query-building API shown is Fluent 4 and stable, but exact method availability for 4.13.x was not cross-checked against api.vapor.codes symbol pages in this pass.
- Did not verify the precise current SQLPostgresConfiguration initializer / sqlLogLevel argument against fluent-postgres-driver 2.12.x README (the logging example sourced is from a 2022 blog post using the legacy initializer).
- Did not confirm whether Fluent 4.13 adds any newer builder conveniences (e.g. .aggregate custom, HAVING support, or window-function helpers) beyond what the query docs page enumerates.

### Sources
- https://docs.vapor.codes/fluent/query/
- https://docs.vapor.codes/fluent/model/
- https://docs.vapor.codes/fluent/advanced/
- https://docs.vapor.codes/basics/logging/
- https://github.com/vapor/sql-kit
- https://github.com/vapor/fluent-postgres-driver/issues/181
- https://blog.vapor.codes/posts/enable-db-query-logging/
- https://forums.swift.org/t/pitch-sql-kit-fluent-kit-function-builder-support/34794
- https://stackoverflow.com/questions/62144473/raw-query-in-vapor-4
