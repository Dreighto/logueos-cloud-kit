## transactions

In Fluent 4.13 you wrap multi-statement units of work in `database.transaction { db in ... }`, which on the Postgres driver issues a literal `BEGIN`, runs your closure, then `COMMIT` on normal return or `ROLLBACK` if anything throws — so rollback is automatic and tied to a thrown error, never manual [verified: fluent-postgres-driver source]. The single most important rule is to use the `database` handed to the closure for every query inside; using the outer `req.db` sends that statement on a different connection outside the transaction and silently defeats atomicity. Fluent's transaction API issues a bare `BEGIN` with no isolation level, so transactions run at the database default (READ COMMITTED on Postgres) and there is no Fluent method to raise the isolation level — you must `SET TRANSACTION ISOLATION LEVEL ...` as the first statement inside the closure. Fluent has no real nested transactions or savepoints: calling `.transaction` again on the in-transaction database short-circuits and just reuses the same connection, so an inner throw rolls back the entire outer unit, not a partial slice. Fluent's own query builder exposes no `FOR UPDATE`, upsert, or optimistic-lock construct; those live in SQLKit and require casting `db as? SQLDatabase`. Idempotency is best achieved with a DB `UNIQUE` constraint plus `ON CONFLICT` (`.ignoringConflicts` / `.onConflict`), pessimistic locking with `.for(.update)` inside a transaction (Postgres only), and optimistic concurrency with a hand-rolled version/`updated_at` compare-and-swap. Database constraints (unique, FK, check) remain the final integrity layer that catches the races your application logic misses.

### Rules
- [verified-by-docs] Use the `database` parameter from the closure for all work inside the transaction, never the outer `req.db` — the outer db checks out a different connection and its writes land outside the transaction, so they neither roll back nor see uncommitted rows (https://docs.vapor.codes/fluent/transaction/).
- [verified-by-docs] A throw anywhere inside the closure (yours or the database's) rolls back everything; normal return commits — this is the whole contract, so surface failures as thrown errors rather than swallowing them (https://docs.vapor.codes/fluent/transaction/).
- [verified-by-docs] The driver implements the transaction as `BEGIN` → closure → `COMMIT`, with `ROLLBACK` on error; there is no partial commit (https://github.com/vapor/fluent-postgres-driver/blob/main/Sources/FluentPostgresDriver/FluentPostgresDatabase.swift).
- [verified-by-docs] Fluent does NOT support nested transactions or savepoints: `transaction` guards `!self.inTransaction` and, when already inside one, just calls the closure on the same connection — a nested `.transaction` is effectively a no-op wrapper, and an inner throw aborts the whole outer transaction (https://github.com/vapor/fluent-postgres-driver/blob/main/Sources/FluentPostgresDriver/FluentPostgresDatabase.swift).
- [verified-by-docs] Fluent issues a bare `BEGIN` with no isolation level, so you get the DB default (Postgres = READ COMMITTED); to get REPEATABLE READ/SERIALIZABLE, run `SET TRANSACTION ISOLATION LEVEL ...` as the first statement inside the closure via the `SQLDatabase` cast — there is no Fluent-level isolation parameter (https://github.com/vapor/fluent-postgres-driver/blob/main/Sources/FluentPostgresDriver/FluentPostgresDatabase.swift).
- [verified-by-docs] Any Fluent SQL database can be cast with `db as? SQLDatabase` (import `FluentSQL`) to reach SQLKit features Fluent's own API lacks — upsert, `FOR UPDATE`, raw SQL (https://docs.vapor.codes/fluent/advanced/).
- [verified-by-docs] Idempotent insert = `UNIQUE` constraint + `.ignoringConflicts(with: [...])`, which serializes to `ON CONFLICT (...) DO NOTHING` (Postgres) / `INSERT IGNORE` (MySQL) (https://github.com/vapor/sql-kit/blob/main/Sources/SQLKit/Builders/Implementations/SQLInsertBuilder.swift).
- [verified-by-docs] Upsert = `.onConflict(with: [...]) { $0.set(excludedValueOf: "col") }`, which serializes to `ON CONFLICT (...) DO UPDATE SET col = EXCLUDED.col`; add `.where(...)` in the conflict builder for a conditional update (https://github.com/vapor/sql-kit/blob/main/Tests/SQLKitTests/SQLInsertUpsertTests.swift).
- [verified-by-docs] Pessimistic locking uses SQLKit's `.for(.update)` (or `.for(.share)`) on a `SELECT`; it only has an effect inside a transaction and only on dialects that support it — Postgres emits `FOR UPDATE`/`FOR SHARE`, SQLite emits nothing (the clause silently serializes to empty) (https://github.com/vapor/sql-kit/blob/main/Sources/SQLKit/Expressions/Clauses/SQLLockingClause.swift, https://github.com/vapor/postgres-kit/blob/main/Sources/PostgresKit/PostgresDialect.swift).
- [verified-by-docs] Fluent has no built-in optimistic-lock/`@Version` property wrapper; implement compare-and-swap manually with a `version` or `updated_at` column and a conditional `UPDATE ... WHERE version = :expected`, treating zero affected rows as a lost race (409/retry) (https://queryplane.com/blog/postgres-upsert/).
- [verified-by-docs] Treat DB constraints (unique/FK/check) as the final integrity layer — under concurrency, a `SELECT`-then-`INSERT` check-first pattern still races, and only the constraint reliably rejects the duplicate; catch the resulting error and convert to a 409 (https://wiki.postgresql.org/wiki/UPSERT).
- [verified-by-docs] For `ON CONFLICT DO UPDATE` the conflict target columns must exactly match an existing unique index/constraint (including a partial index's predicate), or the statement raises instead of upserting (https://queryplane.com/blog/postgres-upsert/).

### Snippets
```swift
import Fluent
import Vapor

// Canonical transaction with automatic rollback (async/await form, Fluent 4.13).
// `db` is the transaction-scoped connection — use it, NOT req.db, for every query.
func transfer(_ req: Request) async throws -> HTTPStatus {
    try await req.db.transaction { db in
        let sun = Star(name: "Sun")
        let sirius = Star(name: "Sirius")
        try await sun.save(on: db)      // uses closure `db`
        try await sirius.save(on: db)   // if THIS throws, `sun` is rolled back too
    }                                    // normal return => COMMIT; any throw => ROLLBACK
    return .ok
}
```

```swift
import Fluent
import FluentSQL   // brings the SQLDatabase cast + upsert builders

// Idempotent write: UNIQUE(email) constraint + ON CONFLICT.
func upsertUser(_ req: Request, id: UUID, email: String, name: String) async throws {
    guard let sql = req.db as? SQLDatabase else { throw Abort(.internalServerError) }

    // (a) DO NOTHING — pure idempotent insert keyed on the unique column.
    try await sql.insert(into: "users")
        .columns("id", "email", "name")
        .values(SQLBind(id), SQLBind(email), SQLBind(name))
        .ignoringConflicts(with: ["email"])          // ON CONFLICT (email) DO NOTHING
        .run()

    // (b) DO UPDATE — true upsert; EXCLUDED carries the values we tried to insert.
    try await sql.insert(into: "users")
        .columns("id", "email", "name")
        .values(SQLBind(id), SQLBind(email), SQLBind(name))
        .onConflict(with: ["email"]) { update in
            update.set(excludedValueOf: "name")      // name = EXCLUDED.name
        }
        .run()                                       // ON CONFLICT (email) DO UPDATE ...
}
```

```swift
import Fluent
import FluentSQL

// Pessimistic lock: SELECT ... FOR UPDATE, Postgres only, MUST be inside a transaction.
func withdraw(_ req: Request, accountId: UUID, amount: Int) async throws {
    try await req.db.transaction { db in
        guard let sql = db as? SQLDatabase else { throw Abort(.internalServerError) }
        // Row is locked until this transaction commits/rolls back.
        guard let account = try await sql.select()
            .columns("id", "balance")
            .from("accounts")
            .where("id", .equal, SQLBind(accountId))
            .for(.update)                             // -> FOR UPDATE (empty on SQLite!)
            .first(decoding: Account.self)
        else { throw Abort(.notFound) }

        try await sql.update("accounts")
            .set("balance", to: SQLBind(account.balance - amount))
            .where("id", .equal, SQLBind(accountId))
            .run()
    }
}
```

```swift
import Fluent
import FluentSQL

// Optimistic concurrency: compare-and-swap on a `version` column, no row lock held.
// RETURNING lets us detect whether we actually won the race.
func saveOptimistic(_ req: Request, id: UUID, newBalance: Int, expectedVersion: Int) async throws {
    guard let sql = req.db as? SQLDatabase else { throw Abort(.internalServerError) }
    let winners = try await sql.update("accounts")
        .set("balance", to: SQLBind(newBalance))
        .set("version", to: SQLBind(expectedVersion + 1))
        .where("id", .equal, SQLBind(id))
        .where("version", .equal, SQLBind(expectedVersion))  // only if unchanged
        .returning("id")
        .all()
    if winners.isEmpty {
        throw Abort(.conflict)   // someone else bumped the version first -> retry/refetch
    }
}
```

### Failure modes
- Writes inside a transaction silently persist even when a later step fails → you used `req.db`/`app.db` inside the closure instead of the closure's `db` parameter; route every query through the closure `db`.
- Inner `.transaction` "rollback" doesn't isolate a sub-step → Fluent has no savepoints; the nested call reuses the outer connection, so restructure logic or `catch` and compensate manually rather than expecting a partial rollback.
- Expected SERIALIZABLE/REPEATABLE READ but got phantom/lost-update anomalies → Fluent runs at READ COMMITTED by default; add `try await (db as! SQLDatabase).raw("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE").run()` as the first line inside the closure and be ready to retry on serialization failures.
- `.for(.update)` compiles but never locks → it emits nothing on SQLite, and on Postgres a lock only holds inside a transaction; wrap the select in `req.db.transaction { }` and run on Postgres.
- `ON CONFLICT DO UPDATE` throws `no unique or exclusion constraint matching the ON CONFLICT specification` → the target columns don't exactly match a unique index; fix the conflict target or add the matching `UNIQUE` constraint in a migration.
- Check-then-insert still creates duplicates under load → the read/write gap is a race; rely on a `UNIQUE` constraint + `.ignoringConflicts`/`.onConflict` (or `SELECT ... FOR UPDATE`) instead of an application-side existence check.
- Optimistic CAS "succeeds" but overwrote a concurrent change → you didn't check affected rows; use `.returning("id").all()` (or fetch rowcount) and treat empty as a conflict, because Fluent's `QueryBuilder.update()` returns `Void` and hides the count.

### Version-sensitive
- Async form (preferred, Swift 6 / Fluent 4.13): `try await db.transaction { db in try await x.save(on: db) }` — defined in FluentKit's Concurrency extension as `func transaction<T: Sendable>(_ closure: @escaping @Sendable (any Database) async throws -> T) async throws -> T` (https://github.com/vapor/fluent-kit/blob/main/Sources/FluentKit/Concurrency/Database%2BConcurrency.swift). This is a thin wrapper over the future form; both ship in 4.13.
- Legacy `EventLoopFuture` form (still present, avoid for new code): `func transaction<T>(_ closure: @escaping @Sendable (any Database) -> EventLoopFuture<T>) -> EventLoopFuture<T>`, chained with `.flatMap { }` and `.transform(to: HTTPStatus.ok)` (https://docs.vapor.codes/fluent/transaction/, https://github.com/vapor/fluent-kit/blob/main/Sources/FluentKit/Database/Database.swift). The Vapor docs still show this alongside the async form.
- SQLKit upsert API note: current form is `.ignoringConflicts(with:)` and `.onConflict(with:) { $0.set(...).set(excludedValueOf:) }`. Older tutorials referencing a Fluent `query.upsert = .upsert(...)` case or a hand-written `PostgreSQLModel.upsert` extension are pre-Fluent-4 and do not compile against FluentKit/SQLKit today.
- `.for(.update)` / `.lockingClause(_:)` and `SQLLockingClause.update/.share` are the current SQLKit locking API; Fluent's own `QueryBuilder` still exposes no locking method in 4.13, so this must go through the `SQLDatabase` cast.

### Sources
- https://docs.vapor.codes/fluent/transaction/
- https://docs.vapor.codes/fluent/advanced/
- https://github.com/vapor/fluent-kit/blob/main/Sources/FluentKit/Concurrency/Database%2BConcurrency.swift
- https://github.com/vapor/fluent-kit/blob/main/Sources/FluentKit/Database/Database.swift
- https://github.com/vapor/fluent-postgres-driver/blob/main/Sources/FluentPostgresDriver/FluentPostgresDatabase.swift
- https://github.com/vapor/sql-kit/blob/main/Sources/SQLKit/Expressions/Clauses/SQLLockingClause.swift
- https://github.com/vapor/sql-kit/blob/main/Sources/SQLKit/Builders/Prototypes/SQLSubqueryClauseBuilder.swift
- https://github.com/vapor/sql-kit/blob/main/Sources/SQLKit/Builders/Implementations/SQLInsertBuilder.swift
- https://github.com/vapor/sql-kit/blob/main/Tests/SQLKitTests/SQLInsertUpsertTests.swift
- https://github.com/vapor/postgres-kit/blob/main/Sources/PostgresKit/PostgresDialect.swift
- https://wiki.postgresql.org/wiki/UPSERT
- https://queryplane.com/blog/postgres-upsert/
