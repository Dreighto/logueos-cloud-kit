## security-reliability

In Fluent 4.13 / FluentKit, the query builder is parameterized by default: `.filter(\.$field == value)` binds the value ("The supplied value ... is bound to the resulting query"), so ORM-level queries are not an injection surface. The real injection risk is raw SQL through SQLKit (the layer all Fluent SQL drivers sit on): a `SQLQueryString`/`raw(...)` where you interpolate `\(value)` as text instead of `\(bind: value)`, or `.filter(.sql(raw:))` custom filters, or the `unsafeRaw`/`raw` interpolation forms. Use `\(bind:)`/`\(binds:)` for every user value and `\(ident:)`/`\(literal:)` for identifiers/literals. The second big class is application-logic, not injection: mass-assignment and sensitive-field leakage from using a Fluent `@Model` as the wire type. Vapor's own model docs say to use a separate `Codable` DTO for request and response bodies "for almost all cases" — decode a create/update DTO, set server-controlled fields (id, isAdmin, balance, tenant_id) explicitly, and map Model→DTO on the way out so password hashes never serialize. Note the Fluent *overview* tutorial itself decodes straight into models (`req.content.decode(Galaxy.self)`), which is the exact footgun the model page warns against — treat tutorial code as demo-only. Reliability rests on: credentials from `Environment.get`/`DATABASE_URL` (never hardcoded), TLS `.require` in prod (docs examples use `.disable`, dev-only), tenant_id filters enforced via repository/QueryBuilder helpers with PostgreSQL row-level security as a backstop, unique constraints + `req.db.transaction {}` + SQLKit `ON CONFLICT` upserts + idempotency keys to prevent duplicate writes, and pool/statement timeouts tuned at the driver and DB layers.

### Rules
- [verified-by-docs] Never decode an HTTP body directly into a Fluent @Model type (`req.content.decode(User.self)`). Decode a purpose-built request DTO that contains ONLY client-writable fields; set server-controlled fields (id, isAdmin, balanceCents, tenantID, timestamps) explicitly in the controller. This is the primary defense against mass-assignment / over-posting. — _A Model conforming to Content decodes every codable field, so a client can set isAdmin=true or a new balance and save() persists it — privilege escalation with no low-level exploit._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] Never return a Fluent Model on the wire. Map Model -> a response DTO that omits sensitive fields (password_hash, internal flags, tenant_id). Vapor docs recommend DTOs for API responses in 'almost all cases'. — _Returning the model serializes every codable field, leaking passwordHash and coupling the API contract to the DB schema._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] For any raw SQL, interpolate user VALUES only via `\(bind:)` (or `\(binds:)` for lists); use `\(ident:)` for table/column names and `\(literal:)` for string literals. Never interpolate a bare `\(value)` string into a SQLQueryString / raw() call. — _`\(bind:)` emits a parameter placeholder ($1) and sends the value out-of-band; bare interpolation concatenates attacker text into SQL = injection._  (https://api.vapor.codes/sqlkit/documentation/sqlkit/sqlquerystring)
- [verified-by-docs] Treat `.filter(.sql(raw: "..."))` custom Fluent filters and SQLKit `.custom("...")` as static-SQL-only. If the fragment must include user input, bind it — do not string-interpolate the value into the raw fragment. — _The Fluent advanced guide's `.sql(raw:)` and `.custom` escape hatches bypass the builder's automatic binding, reintroducing the injection surface._  (https://docs.vapor.codes/fluent/advanced/)
- [verified-by-docs] Prefer a structured query (builder/expression) over any raw query; SQLKit docs explicitly say to prefer structured queries and to request missing features rather than reach for raw SQL. — _Structured queries bind and quote automatically; raw SQL shifts injection safety onto the developer._  (https://github.com/vapor/sql-kit)
- [verified-by-docs] Avoid the deprecated `\(raw:)` SQLQueryString interpolation. `appendInterpolation(raw:)` is marked [DEPRECATED]; the non-deprecated escape hatch is `\(unsafeRaw:)`, which by its name signals it disables injection defenses and must only carry static SQL, never user input. — _The API reference lists `appendInterpolation(raw:)` as Deprecated and `appendInterpolation(unsafeRaw:)` as the current raw-fragment form._  (https://api.vapor.codes/sqlkit/documentation/sqlkit/sqlquerystring)
- [verified-by-docs] Load DB credentials from the environment (`Environment.get("DATABASE_URL")` -> `.postgres(url:)`, or individual DB_* vars into `SQLPostgresConfiguration`). Never hardcode host/user/password; never log the connection string verbatim. — _Hardcoded credentials leak via version control and stack traces; env vars enable rotation and per-environment secrets._  (https://docs.vapor.codes/deploy/fly/)
- [verified-by-docs] In production set Postgres TLS to `.require` (verify the server cert). The docs' `.postgres(configuration: .init(..., tls: .disable))` example is development-only; MySQL docs carry an explicit 'Do not disable certificate verification in production' warning that applies equally. — _`tls: .disable` / certificateVerification=.none exposes credentials and data to man-in-the-middle attacks._  (https://docs.vapor.codes/fluent/overview/)
- [verified-by-docs] For multi-tenant data, always filter by tenant_id and derive tenant from the authenticated context, never from the request body/query. Centralize this in a repository or a `QueryBuilder.forTenant(_:)` helper so a forgotten filter can't leak cross-tenant rows. — _A single dropped tenant filter returns/updates another tenant's data — a silent, high-severity leak worse than most injection._  (https://docs.vapor.codes/basics/controllers/)
- [verified-by-docs] Add PostgreSQL row-level security (RLS) as a database-level backstop for tenant isolation, in addition to app-level filters; set a per-connection `app.tenant_id` and gate rows via a USING policy. — _App filters can be forgotten in new code paths; RLS enforces isolation even when the query omits the filter._  (https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
- [verified-by-docs] Prevent duplicate writes with a DB unique constraint (`.unique(on:)` in a migration) PLUS one of: SQLKit `INSERT ... ON CONFLICT DO NOTHING/DO UPDATE`, or a check-then-insert inside `req.db.transaction {}`. Constraints are the authoritative guard under concurrency; the transaction makes check+insert atomic. — _Without a unique constraint, two concurrent requests both see 'not found' and both insert; the transaction alone doesn't stop that unless a constraint exists._  (https://docs.vapor.codes/fluent/transaction/)
- [inferred-from-research] Make write endpoints idempotent for safe retries: accept a client `Idempotency-Key` header, store it in a column with a unique constraint, and coalesce/return the prior result on repeat. Only retry idempotent operations after timeouts. — _Retrying a non-idempotent POST after a transient timeout creates duplicate payments/orders._  (https://github.com/vapor/postgres-kit/issues/164)
- [verified-by-docs] Run all queries of an atomic operation on the `database` handle passed into `req.db.transaction { database in ... }` — not on `req.db` — or they execute outside the transaction and won't roll back. — _Docs: you must use the database supplied in the closure for all queries within the transaction._  (https://docs.vapor.codes/fluent/transaction/)
- [verified-by-docs] Validate input with `Validatable`: conform the DTO, call `try DTO.validate(content: req)` BEFORE `req.content.decode`, and/or use `afterDecode()` to trim/normalize. Validation complements DTOs; it does not replace the DTO field-whitelisting. — _validate(content:) runs against the raw payload before decoding, rejecting malformed/oversized input early._  (https://docs.vapor.codes/basics/validation/)
- [inferred-from-research] Tune reliability at the driver and DB layers: set a connection-pool acquisition timeout, a Postgres `statement_timeout` (e.g. `ALTER ROLE app SET statement_timeout='5s'` or `SET` per connection), and TCP keepalives to survive proxy/Docker idle-connection resets; handle unique-violation errors as HTTP 409. — _Pooled idle connections get reset by proxies/Docker Swarm (15-min default), and unbounded statements starve the pool._  (https://github.com/vapor/postgres-kit/issues/164)

### Snippets

**Safe raw SQL: bind values, quote identifiers** · SQLKit (ships in FluentSQL). \(bind:), \(binds:), \(ident:), \(literal:) are current; \(raw:) is DEPRECATED, \(unsafeRaw:) is the static-only escape hatch. · https://api.vapor.codes/sqlkit/documentation/sqlkit/sqlquerystring
```swift
// SQLKit raw query with parameter binding (injection-safe)
let planets = try await db.raw("""
    SELECT \(SQLLiteral.all) FROM \(ident: table)
    WHERE \(ident: name) = \(bind: "planet")
    """).all()
// Renders (Postgres): SELECT * FROM "planets" WHERE "name" = $1  bindings: ["planet"]

// UNSAFE - never do this with user input:
// db.raw("SELECT * FROM users WHERE email LIKE '%\(search)%'")  // string concat = injection
```

**Cast Fluent Database to SQLDatabase for raw/SQLKit access** · Fluent 4.13; req.db / app.db / migration database all cast to SQLDatabase on SQL drivers. · https://docs.vapor.codes/fluent/advanced/
```swift
import FluentSQL

if let sql = req.db as? SQLDatabase {
    let planets = try await sql.raw("SELECT * FROM planets").all(decoding: Planet.self)
} else {
    // underlying driver is not SQL
}
```

**DTO in / DTO out — prevents mass-assignment and hash leakage** · Vapor 4.122 / Swift 6 async-await. Pattern synthesized from docs' DTO recommendation; exact controller wording not copied from a single doc example. · https://docs.vapor.codes/fluent/model/
```swift
struct UserCreateDTO: Content { let email: String; let password: String }
struct UserResponseDTO: Content { let id: UUID; let email: String; let isAdmin: Bool }

func create(_ req: Request) async throws -> UserResponseDTO {
    try UserCreateDTO.validate(content: req)
    let input = try req.content.decode(UserCreateDTO.self)
    let user = User()
    user.email = input.email.lowercased()
    user.passwordHash = try req.password.hash(input.password)
    user.isAdmin = false            // server-controlled, NOT from client
    user.tenantID = try req.auth.require(Tenant.self).id
    try await user.save(on: req.db)
    guard let id = user.id else { throw Abort(.internalServerError) }
    return UserResponseDTO(id: id, email: user.email, isAdmin: user.isAdmin)
}
```

**Tenant-scoped update (isolation + selective field update)** · Fluent 4.13 QueryBuilder .filter binds values automatically. · https://docs.vapor.codes/fluent/query/
```swift
func update(_ req: Request) async throws -> UserResponseDTO {
    let tenant = try req.auth.require(Tenant.self)
    let input = try req.content.decode(UserUpdateDTO.self) // email/password optional
    guard let userID = req.parameters.get("userID", as: UUID.self) else { throw Abort(.badRequest) }
    guard let user = try await User.query(on: req.db)
        .filter(\.$tenantID == tenant.id)   // tenant filter first
        .filter(\.$id == userID)
        .first() else { throw Abort(.notFound) }
    if let email = input.email { user.email = email.lowercased() }
    if let pw = input.password { user.passwordHash = try req.password.hash(pw) }
    try await user.update(on: req.db)
    return try user.toResponseDTO()
}
```

**Atomic idempotent write inside a transaction** · Fluent 4.13 async transaction; all queries must run on the closure's db handle. · https://docs.vapor.codes/fluent/transaction/
```swift
try await req.db.transaction { db in            // use `db`, not req.db
    if let existing = try await Payment.query(on: db)
        .filter(\.$tenantID == tenant.id)
        .filter(\.$idempotencyKey == key)
        .first() {
        return try existing.toResponseDTO()
    }
    let payment = Payment()
    payment.idempotencyKey = key            // column has a UNIQUE constraint
    payment.tenantID = tenant.id
    try await payment.save(on: db)
    return try payment.toResponseDTO()
}
```

**Unique constraint in a migration (dedup backstop)** · Fluent 4.13 SchemaBuilder; auto-generates constraint name unless `name:` given. · https://docs.vapor.codes/fluent/schema/
```swift
try await database.schema("users")
    .id()
    .field("email", .string, .required)
    .unique(on: "email")            // or .unique(on: "email", name: "users_email_key")
    .create()
```

**Postgres config from env, TLS required in prod** · fluent-postgres-driver 2.x. Docs example shows tls: .disable; use .require(...) in production. · https://docs.vapor.codes/fluent/overview/
```swift
import FluentPostgresDriver

if let url = Environment.get("DATABASE_URL") {
    try app.databases.use(.postgres(url: url), as: .psql)   // parses sslmode etc.
} else {
    app.databases.use(.postgres(configuration: .init(
        hostname: "localhost", username: "vapor", password: "vapor",
        database: "vapor", tls: .disable)), as: .psql)      // .disable = DEV ONLY
}
```

**Validatable DTO** · Vapor 4.122 validation API. · https://docs.vapor.codes/basics/validation/
```swift
extension UserCreateDTO: Validatable {
    static func validations(_ v: inout Validations) {
        v.add("email", as: String.self, is: .email)
        v.add("password", as: String.self, is: .count(8...))
    }
}
// controller: try UserCreateDTO.validate(content: req) BEFORE decode
```

### Failure modes
- **Client sets isAdmin/balance/id via JSON and it persists (privilege escalation)** → Decode a request DTO with only client-writable fields; set privileged fields server-side (cause: Decoding request body directly into a Fluent @Model conforming to Content, then save()/update())
- **password_hash / internal flags appear in API responses and logs** → Map Model -> response DTO that omits sensitive fields; log DTOs not models (cause: Returning the Fluent Model (Content) directly instead of a response DTO)
- **SQL injection via a search/filter parameter** → Use \(bind:) for values, \(ident:) for identifiers; prefer the structured query builder (cause: String-interpolating user input into raw()/SQLQueryString/.sql(raw:) instead of binding)
- **One tenant reads/edits another tenant's rows** → Repository/forTenant helper enforcing tenant_id from auth context; PostgreSQL RLS as backstop (cause: A query path missing the tenant_id filter, or tenant taken from client input)
- **Duplicate payments/orders under retry or concurrency** → Unique constraint + transaction/ON CONFLICT upsert + Idempotency-Key column (cause: Check-then-insert without a unique constraint, or non-idempotent POST retried after timeout)
- **Intermittent 'connection reset by peer' after idle periods** → TCP keepalive sysctls, DB idle/statement timeouts, prune idle pool connections (cause: Pooled connections killed by proxy/Docker Swarm (~15 min) idle timeout)
- **Credentials leak via repo/stack trace, or MITM on DB connection** → Environment.get/DATABASE_URL for secrets; TLS .require with cert verification in prod (cause: Hardcoded credentials and/or tls: .disable in production)
- **Transaction changes unexpectedly commit despite an error / don't roll back** → Run every query in the transaction on the `database` passed into req.db.transaction { } (cause: Queries run on outer req.db instead of the closure's database handle)

### Version-sensitive
- `SQLQueryString.appendInterpolation(raw:) vs (unsafeRaw:)`: `\(raw:)` is marked [DEPRECATED] in the SQLKit API reference; the current raw-fragment escape hatch is `\(unsafeRaw:)`. Some secondary sources (and older answers) call `appendInterpolation(_:)` deprecated — that is INCORRECT: `appendInterpolation(_:)` embeds an arbitrary SQLExpression and is not deprecated. Safe value interpolation is `\(bind:)`/`\(binds:)`.  (https://api.vapor.codes/sqlkit/documentation/sqlkit/sqlquerystring)
- `Postgres TLS in SQLPostgresConfiguration`: fluent-postgres-driver 2.x uses `.postgres(configuration: .init(..., tls:))` where tls is a PostgresNIO TLS enum (.disable / .prefer / .require). Older 1.x used `tlsConfiguration:`/`TLSConfiguration`. Verify against the installed 2.12.x driver; docs example uses tls: .disable (dev only).  (https://docs.vapor.codes/fluent/overview/)
- `Model-as-Content in the Fluent overview tutorial`: The Fluent overview page decodes request bodies straight into models (`req.content.decode(Galaxy.self)`, `Star.self`) and returns models directly. This contradicts the Fluent MODEL page which recommends DTOs 'for almost all cases'. Treat the overview code as a quick-start demo, not a production pattern — it is the mass-assignment/leak footgun.  (https://docs.vapor.codes/fluent/model/)
- `.filter(\.$field == value) binding`: Fluent 4.13 value filters bind the supplied value into the query automatically ('is bound to the resulting query'), so ORM queries are parameterized by default. Injection risk only appears when you drop to `.sql(raw:)`, `.custom(...)`, or SQLKit raw with string interpolation.  (https://docs.vapor.codes/fluent/query/)
- `req.db.transaction closure handle`: Must run queries on the `database` value passed into the closure, not the outer req.db, or they run outside the transaction. Async and EventLoopFuture forms both exist in Fluent 4.13.  (https://docs.vapor.codes/fluent/transaction/)

### Open questions
- Context7 is NOT connected in this environment; substituted Firecrawl + WebFetch against official docs (docs.vapor.codes, api.vapor.codes) and GitHub. All snippets verified against those where tagged verified-by-docs.
- Exact fluent-postgres-driver 2.12.x SQLPostgresConfiguration TLS enum cases (.require/.prefer signatures) not read line-by-line from the 2.12 source; the GitHub repo README rendered with an error during fetch. Verify `.require(try .init(configuration: .makeClientConfiguration()))` form against the installed version.
- SQLKit onConflict/doNothing/doUpdateSet builder method names in the perplexity synthesis were not confirmed against the current api.vapor.codes SQLKit InsertBuilder reference — verify exact method spelling before use.
- Whether Vapor 4.122 exposes a first-class connection-pool acquisition timeout setter on SQLPostgresConfiguration (vs configuring at PostgresNIO/pool level) was not confirmed from an official API page.
- PostgreSQL RLS + Fluent connection pooling: setting per-request `SET app.tenant_id` safely across pooled connections (reset on release) has no official Vapor doc; pattern is inferred and needs a tested implementation (e.g. run SET LOCAL inside the same transaction).

### Sources
- https://docs.vapor.codes/fluent/model/
- https://docs.vapor.codes/fluent/overview/
- https://docs.vapor.codes/fluent/advanced/
- https://docs.vapor.codes/fluent/query/
- https://docs.vapor.codes/fluent/transaction/
- https://docs.vapor.codes/fluent/schema/
- https://docs.vapor.codes/basics/validation/
- https://docs.vapor.codes/basics/content/
- https://docs.vapor.codes/basics/controllers/
- https://docs.vapor.codes/deploy/fly/
- https://api.vapor.codes/sqlkit/documentation/sqlkit/sqlquerystring
- https://api.vapor.codes/sqlkit/documentation/sqlkit
- https://github.com/vapor/sql-kit
- https://github.com/vapor/fluent-postgres-driver
- https://github.com/vapor/postgres-kit/issues/164
- https://www.postgresql.org/docs/current/ddl-rowsecurity.html
