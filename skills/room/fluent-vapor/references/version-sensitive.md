## version-sensitive-apis

In the Fluent 4.13.x / FluentKit / Vapor 4.122.x era under Swift 6.2/6.3 strict concurrency, the async/await surface is the current, recommended API and the EventLoopFuture surface is legacy-but-still-present (it will not be removed until Vapor 5). Every high-level Fluent operation offers both forms: query terminators (.all(), .first(), .count(), .paginate()) and model CRUD (.save/.create/.update/.delete/.find) are all awaited with `try await` in current code, while the EventLoopFuture variants return `EventLoopFuture<...>` and are chained with .map/.flatMap. Migrations split into two protocols: `AsyncMigration` (prepare/revert are `async throws`) is current; `Migration` (prepare/revert return `EventLoopFuture<Void>`) is legacy. Testing has bifurcated: `VaporTesting` built on Swift Testing (`@Suite`/`@Test`, `#expect`, `app.testing()`) is the recommended module; `XCTVapor` built on XCTest (`XCTestCase`, `app.testable()`) is the older path. Application lifecycle changed to an async-first model: `try await Application.make(env)` + `try await app.asyncShutdown()` is current, replacing the synchronous `Application(env)` + `app.shutdown()` which can deadlock the concurrency pool in async contexts. Fluent's own release notes (2025) confirm adoption of the new async lifecycle APIs, async MigrateCommand, and soft-deprecation of AsyncKit. Do not mix the two programming models within a single route handler.

### Rules
- [verified-by-docs] Use `try await Application.make(env)` and `try await app.asyncShutdown()` in the entrypoint; do NOT use the synchronous `Application(env)` initializer or `app.shutdown()` in async code — they can deadlock the Swift Concurrency thread pool. — _Sync init/shutdown internally block threads; async pool starves under strict concurrency._  (https://github.com/vapor/template/blob/main/Sources/App/entrypoint.swift)
- [verified-by-docs] Write migrations as `struct X: AsyncMigration` with `func prepare(on database: any Database) async throws` / `func revert(...) async throws`. Reserve `Migration` (EventLoopFuture<Void> returns) only for legacy code you cannot convert. — _AsyncMigration is the current concurrency-native protocol; both are still shipped._  (https://docs.vapor.codes/fluent/migration/)
- [verified-by-docs] Await all Fluent query terminators and model ops: `try await Model.query(on: db).filter(...).all()` / `.first()` / `.count()` / `.paginate(for:)`, and `try await model.save(on: db)` / `.create` / `.update` / `.delete`. Use EventLoopFuture forms only for very-high-performance or explicit-event-loop code. — _async is the recommended default; ELF remains for advanced control until custom executors land._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Never mix EventLoopFuture and async/await inside one route handler; pick one programming model per handler. — _Vapor docs explicitly warn against mixing models in a single closure._  (https://docs.vapor.codes/basics/async/)
- [verified-by-docs] For new test targets depend on `VaporTesting` (not `XCTVapor`), import `VaporTesting` + `Testing`, and use `@Suite`/`@Test`, `#expect`, and `app.testing().test(...)`. XCTVapor/XCTest with `app.testable()` is the legacy path. — _Docs state Swift Testing is highly recommended over XCTest for concurrency projects._  (https://docs.vapor.codes/advanced/testing/)
- [verified-by-docs] In tests build the app with `try await Application.make(.testing)` and tear down with `try await app.asyncShutdown()`, wrapping the body so that on throw you `try? await app.autoRevert()` then `asyncShutdown()` before rethrowing. — _Mirrors the documented withAppIncludingDB helper; guarantees DB revert + shutdown on failure._  (https://docs.vapor.codes/advanced/testing/)
- [verified-by-docs] To bridge a legacy EventLoopFuture API into async code call `try await someFuture.get()`; never call `.wait()` on an event loop thread — it can deadlock the connection pool. — _AsyncKit release notes document that even Dispatch .wait() can deadlock the concurrency pool._  (https://docs.vapor.codes/basics/async/)
- [verified-by-docs] Do not add AsyncKit as a new dependency or write new AsyncKit-based pool code; it is soft-deprecated (kept only for Fluent/Vapor 4 compatibility, security fixes only). — _async-kit 1.19.0 officially soft-deprecated the package._  (https://github.com/vapor/async-kit/releases)
- [verified-by-docs] Prefer `AsyncModelMiddleware` (async throws) over the legacy `ModelMiddleware` (EventLoopFuture) when hooking model lifecycle events. — _AsyncModelMiddleware is the modern concurrency-native middleware protocol._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] Rely on async `--auto-migrate`/`--auto-revert` (and `app.autoMigrate()`/`app.autoRevert()`); in current Fluent these no longer call EventLoopFuture.wait() when booted in async mode, removing the prior crash risk. — _Fluent release notes: auto-migrate/revert flags dropped the unsafe .wait() in async boot._  (https://github.com/vapor/fluent/releases)

### Snippets

**Current async entrypoint (Application.make + asyncShutdown)** · Vapor 4.122.x current form. STALE: `let app = Application(env)` + `defer { app.shutdown() }`. · https://github.com/vapor/template/blob/main/Sources/App/entrypoint.swift
```swift
import Vapor
import Logging
import NIOCore
import NIOPosix

@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = try await Application.make(env)

        do {
            try await configure(app)
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.execute()
        try await app.asyncShutdown()
    }
}
```

**AsyncMigration (current) vs Migration (legacy)** · Both protocols ship in FluentKit; note `any Database` existential under Swift 6. · https://docs.vapor.codes/fluent/migration/
```swift
// CURRENT
struct CreateGalaxy: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("galaxies")
            .id()
            .field("name", .string, .required)
            .create()
    }
    func revert(on database: any Database) async throws {
        try await database.schema("galaxies").delete()
    }
}

// STALE (EventLoopFuture)
struct CreateGalaxyOld: Migration {
    func prepare(on database: any Database) -> EventLoopFuture<Void> {
        database.schema("galaxies").id().field("name", .string, .required).create()
    }
    func revert(on database: any Database) -> EventLoopFuture<Void> {
        database.schema("galaxies").delete()
    }
}
```

**Async query + CRUD forms (current)** · STALE equivalent returns EventLoopFuture and uses .map/.flatMap, e.g. `galaxy.create(on: req.db).map { galaxy }`. · https://docs.vapor.codes/fluent/query/
```swift
let planets = try await Planet.query(on: db).all()
let earth = try await Planet.query(on: db)
    .filter(\.$name == "Earth")
    .first()
let page = try await Planet.query(on: req.db).paginate(for: req)

let planet = Planet(name: "Earth")
try await planet.create(on: db)
try await planet.update(on: db)
try await planet.delete(on: db)
guard let found = try await Planet.find(req.parameters.get("id"), on: db) else {
    throw Abort(.notFound)
}
```

**VaporTesting (Swift Testing) with DB lifecycle** · STALE: XCTVapor — `final class AppTests: XCTestCase`, `let app = Application(.testing)`, `defer { app.shutdown() }`, `app.testable().test(...)`, XCTAssert*. · https://docs.vapor.codes/advanced/testing/
```swift
import VaporTesting
import Testing

@Suite("App Tests")
struct AppTests {
    private func withApp(_ test: (Application) async throws -> ()) async throws {
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

    @Test("GET /hello")
    func hello() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "hello") { res async in
                #expect(res.status == .ok)
            }
        }
    }
}
```

### Failure modes
- **App hangs on startup or shutdown, or deadlocks under load in an async server.** → Switch entrypoint to `try await Application.make(env)` + `try await app.asyncShutdown()`; replace `.wait()` with `try await future.get()`. (cause: Using synchronous `Application(env)` / `app.shutdown()` (or `.wait()`) in a Swift Concurrency context, starving the NIO/concurrency thread pool.)
- **Migration compiles but you want async and the compiler forces an EventLoopFuture return.** → Change the conformance to `AsyncMigration` so `prepare/revert` become `async throws`. (cause: Conformed to `Migration` instead of `AsyncMigration`.)
- **New tests won't compile against `#expect`/`@Test`, or `app.testing()` is unresolved.** → Depend on `VaporTesting`, `import VaporTesting` + `Testing`, use `@Suite`/`@Test`, `app.testing()`, and `Application.make(.testing)` + `asyncShutdown()`. (cause: Test target still depends on XCTVapor/XCTest instead of VaporTesting/Swift Testing (or vice-versa mixing `app.testable()`).)
- **Test DB left dirty / process leaks between test runs.** → Wrap the test body so a throw triggers `try? await app.autoRevert()` then `try await app.asyncShutdown()` before rethrowing (the documented withApp pattern). (cause: Missing autoRevert/asyncShutdown on the throwing path.)
- **Confusing/hard-to-reason race or type-mismatch inside one route handler.** → Use a single programming model per handler; convert with `try await future.get()` at the boundary if needed. (cause: Mixing EventLoopFuture chaining and async/await in the same closure.)

### Version-sensitive
- `Application creation/shutdown`: CURRENT: `try await Application.make(env)` + `try await app.asyncShutdown()`. STALE: `Application(env)` + `app.shutdown()` (sync; deadlock risk in async contexts).  (https://github.com/vapor/template/blob/main/Sources/App/entrypoint.swift)
- `Migration protocol`: CURRENT: `AsyncMigration` with `prepare/revert ... async throws`. STALE: `Migration` with `prepare/revert -> EventLoopFuture<Void>`.  (https://docs.vapor.codes/fluent/migration/)
- `Query terminators & model CRUD`: CURRENT: `try await ....all()/.first()/.count()/.paginate(for:)` and `try await model.save/create/update/delete(on:)`. STALE: EventLoopFuture-returning variants chained with .map/.flatMap.  (https://docs.vapor.codes/fluent/query/)
- `Testing module`: CURRENT: `VaporTesting` + Swift `Testing` (`@Suite`/`@Test`/`#expect`, `app.testing()`). STALE: `XCTVapor` + XCTest (`XCTestCase`, `app.testable()`, `XCTAssert*`).  (https://docs.vapor.codes/advanced/testing/)
- `app.testing() vs app.testable()`: CURRENT: `app.testing()` (returns tester; supports `method: .inMemory` / `.running`). STALE: `app.testable()` from XCTVapor.  (https://docs.vapor.codes/advanced/testing/)
- `Model middleware`: CURRENT: `AsyncModelMiddleware` (async throws). STALE: `ModelMiddleware` returning EventLoopFuture<Void>.  (https://docs.vapor.codes/fluent/model/)
- `AsyncKit`: Soft-deprecated as of async-kit 1.19.0 — still bundled with Vapor/Fluent 4 for compatibility, security fixes only; do not use in new code. `shutdownAsync` added in 1.20.0 to avoid the .wait() deadlock.  (https://github.com/vapor/async-kit/releases)
- `--auto-migrate / --auto-revert`: In current Fluent these no longer call EventLoopFuture.wait() when the app boots in async mode (crash risk removed); MigrateCommand is now async.  (https://github.com/vapor/fluent/releases)
- `Bridging EventLoopFuture to async`: Use `try await future.get()` to await a legacy future. Never `.wait()` on an event-loop thread (pool deadlock).  (https://docs.vapor.codes/basics/async/)
- `EventLoopFuture overall`: Not deprecated in Fluent 4.13 — both models ship side by side; full removal is planned for Vapor 5, not this version. Do not present ELF as removed.  (https://forums.swift.org/t/async-await-and-the-future-of-vapor/52590)

### Open questions
- Context7 is not connected in this environment; per instructions I substituted Firecrawl/WebFetch against official docs.vapor.codes and github.com/vapor sources for all verification.
- docs.vapor.codes renders content client-side, so WebFetch returned model-summarized quotes rather than raw verbatim doc HTML; exact whitespace/signatures should be re-confirmed against api.vapor.codes for a final skill, though the API shapes here match the template repo and release notes.
- Could not independently pin the exact fluent-postgres-driver 2.12.x / fluent-sqlite-driver 4.9.x deprecation deltas for this cluster; the async lifecycle adoption is confirmed at the Fluent provider level (vapor/fluent releases, 2025-09-25) but per-driver 4.13-era renames were not separately verified.
- The `any Database` existential in migration signatures reflects Swift 6 existential-any; confirm whether the skill should always emit `any Database`/`any AsyncMigration` vs bare protocol names for the target Swift 6.2/6.3 toolchain.

### Sources
- https://docs.vapor.codes/fluent/overview/
- https://docs.vapor.codes/fluent/query/
- https://docs.vapor.codes/fluent/model/
- https://docs.vapor.codes/fluent/migration/
- https://docs.vapor.codes/advanced/testing/
- https://docs.vapor.codes/basics/async/
- https://github.com/vapor/template/blob/main/Sources/App/entrypoint.swift
- https://github.com/vapor/fluent/releases
- https://github.com/vapor/async-kit/releases
- https://github.com/vapor/fluent-mysql-driver/releases
- https://forums.swift.org/t/async-await-and-the-future-of-vapor/52590
