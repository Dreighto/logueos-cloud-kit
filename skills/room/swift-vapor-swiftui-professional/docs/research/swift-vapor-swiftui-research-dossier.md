# Swift / Vapor / SwiftUI Mastery Dossier

Reference research for building a native SwiftUI app backed by a Vapor API.
Evidence-first. Every non-obvious claim carries a source. Version-verified in
July 2026 against official docs (Context7 + direct scrapes), Swift Package Index,
and named practitioner sources. Conflicts and uncertainty are flagged, not hidden.

## Version reality (read this first)

Verified, mid-2026. Build against these; do not trust older tutorials.

| Thing                 | Current                            | Note                                                                                                                                                                                      |
| --------------------- | ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Swift                 | 6.2 stable (Xcode 26)              | "Swift 6" is the strict-concurrency language mode. New Xcode 26 projects default to main-actor isolation ("Approachable Concurrency").                                                    |
| Vapor                 | 4.122.x stable                     | Vapor 4 is in maintenance mode (no new features). Vapor 5 is alpha only; its `main` branch is Swift-tools 6.2 + full structured concurrency + macro routing. Production stays on Vapor 4. |
| Fluent                | 4.13.x                             | + FluentPostgresDriver 2.12.x. Both require Swift 6.0+.                                                                                                                                   |
| vapor/jwt + JWTKit    | 5.x                                | New async `JWTKeyCollection` actor API. The old `JWTSigners` / `app.jwt.signers` is gone.                                                                                                 |
| SwiftUI baseline      | iOS 17 Observation (`@Observable`) | Current through iOS 26. NavigationView, ObservableObject, @StateObject are legacy-but-compiling.                                                                                          |
| iOS design generation | iOS 26 "Liquid Glass" (WWDC 2025)  | Apple uses year-based numbers; 26 is the 2025 release, not the 26th iOS.                                                                                                                  |
| Testing               | Swift Testing (`@Test`/`#expect`)  | Current + default for new unit tests. XCTest still required for UI (XCUITest) and performance tests; not deprecated.                                                                      |
| Persistence           | SwiftData (`@Model`/`@Query`)      | iOS 17+ default. Core Data still wins for pre-iOS-17 targets, complex migrations, and public/shared CloudKit sync.                                                                        |

Currency caveat: as of mid-2026 the live Apple docs already render the Xcode 27 /
iOS "2027" beta SDK. Some availability strings there are 2027-cycle, not iOS 26.
Confirmed iOS 26 (safe): Liquid Glass, `WebView`/`WebPage`, rich-text `TextEditor`,
`@Animatable`, `Observations` async sequence, SwiftData class inheritance.
Confirmed 2027-cycle (do NOT ship on iOS 26): a `State()` lazy macro, unified
`ContentBuilder`, `reorderable()`, expanded Document API, `AsyncImage` HTTP caching.
Always confirm the availability badge in Xcode before adopting anything "new."

---

# Vapor Framework Mastery Notes

## What Vapor Is

Plain English: Vapor is a framework for writing the server side of an app in Swift.
It is the backend, the program that runs on a Linux machine, listens for HTTP
requests from your iPhone app (or a browser), talks to a database, and sends JSON
back. It is the Swift equivalent of Node/Express, Django, or Rails, and it lets one
language (Swift) cover both the phone app and the server.

Where it fits: your SwiftUI app is the frontend the user taps; Vapor is the backend
that stores and serves the data. They talk over HTTP with JSON. Vapor is built on
SwiftNIO (Apple's async networking engine) and, since Vapor 4.50+, is written with
async/await.

## Core Concepts

### Application lifecycle and entrypoint

The current template splits bootstrap into two files: `entrypoint.swift` owns the
`Application` lifecycle, `configure.swift` wires it. The modern lifecycle is
`Application.make(env)` then `configure(app)` then `app.execute()` then
`app.asyncShutdown()`. The old synchronous `boot.swift` is gone; its work moved into
`configure`. Custom boot/shutdown hooks register via `LifecycleHandler` on
`app.lifecycle.use(...)`.

```swift
// entrypoint.swift  (source: github.com/vapor/template-bare)
@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = try await Application.make(env)
        do { try await configure(app); try await app.execute() }
        catch { app.logger.report(error: error); try? await app.asyncShutdown(); throw error }
        try await app.asyncShutdown()
    }
}
```

Conflict flagged: the docs Environment page still shows the older
`Application(env)` / `app.shutdown()` pattern. Prefer the live template pattern above;
the docs page lags. Source: docs.vapor.codes/basics/environment vs the template.

### Routes

Method helpers take variadic path components. Path kinds: constant (`foo`),
parameter (`:foo`), anything (`*`), catchall (`**`). Read params from
`req.parameters`, typed with `.get("x", as: Int.self)`. Group routes by prefix and/or
middleware. Source: docs.vapor.codes/basics/routing.

```swift
app.get("hello", ":name") { req -> String in
    guard let name = req.parameters.get("name") else { throw Abort(.badRequest) }
    return "Hello, \(name)!"
}
let users = app.grouped("users")            // prefix group
let auth = app.grouped(AuthMiddleware())    // middleware group
```

### Controllers

Group related routes in a `RouteCollection` with `boot(routes:)`, then
`app.register(collection:)`. Handlers take `Request`, return anything
`ResponseEncodable`, sync or async. Source: docs.vapor.codes/basics/controllers.

### Middleware

Two protocols; new code uses `AsyncMiddleware`. Request flows in order, response
flows in reverse. Route middleware always runs after application middleware.
Load-bearing rule: `CORSMiddleware` must be registered before `ErrorMiddleware`
(`app.middleware.use(cors, at: .beginning)`) or error responses lose their CORS
headers. Source: docs.vapor.codes/advanced/middleware.

```swift
struct EnsureAdminMiddleware: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let u = req.auth.get(User.self), u.role == .admin else { throw Abort(.unauthorized) }
        return try await next.respond(to: req)
    }
}
```

### Request / Response and Content (encode/decode)

`Request` carries `parameters`, `query`, `content`, `headers`, `logger`, `db`, `auth`.
`Content` is Codable plus helpers: `req.content.decode(T.self)` for the body,
`req.query.decode(T.self)` for the query string. Default coder is JSON; override
globally in `configure` via `ContentConfiguration.global.use(encoder:for:)`. Lifecycle
hooks `beforeEncode()` / `afterDecode()` allow per-type normalization. Set the JSON
date and key strategies once, and make the client mirror them exactly. Source:
docs.vapor.codes/basics/content.

### Services and dependency injection

Vapor 4 has no runtime service container. You extend `Application` (and `Request`)
with computed properties, using a `StorageKey` for stateful services. How
professionals actually do DI: front concretes behind protocols returned from the
extension property, and prefer constructor injection into `RouteCollection`
controllers so tests can swap `app.userRepository = MockUserRepository()`.
Application-scoped singletons (DB pool, HTTP client) must be safe for concurrent
access under Swift 6: immutable, lock-guarded, or an `actor`. Third-party DI
containers (e.g. Factory) exist but are not mainstream in Vapor. Source:
docs.vapor.codes/advanced/services; Kodeco "Server-Side Swift with Vapor".

### Async/await model

Route handlers are `req async throws -> T`. Keep one concurrency model per handler
(do not interleave `EventLoopFuture` and async/await). Never call blocking work or
`.wait()` on an event-loop thread; offload to `req.application.threadPool.runIfActive`.
Bridge with `try await future.get()` when only the future form exists. Source:
docs.vapor.codes/basics/async.

### Error handling

Throw `Abort(.notFound)` or `Abort(.unauthorized, reason: "...")`. `Abort` conforms to
`AbortError` (controls HTTP status + reason) and `DebuggableError` (controls logging).
Conform your own error type to `AbortError` to map cases to statuses. `ErrorMiddleware`
(added by default) turns thrown errors into HTTP responses. Critical nuance: error
detail is stripped in **release build mode**, not by environment. So always deploy
release-built, and never put secrets/SQL/stack detail in an `Abort` reason (the reason
is returned to clients even in release). Source: docs.vapor.codes/basics/errors.

### Environment configuration

`Environment.get("KEY")` returns `String?`. Vapor auto-loads `.env`, then
`.env.<environment>` which takes precedence; existing process env vars are never
overwritten by `.env`. Commit a template `.env`, git-ignore `.env.*`. Select the
environment with `--env production|development|testing`. Source:
docs.vapor.codes/basics/environment.

### Logging

Built on Apple's SwiftLog. Bootstrap once in `entrypoint.swift`
(`try LoggingSystem.bootstrap(from: &env)`). Use `req.logger` inside handlers (carries
a per-request id) and `app.logger` at boot. Levels trace to critical; production
defaults to `notice`, others to `info`. Override with `--log debug` or `LOG_LEVEL`.
Source: docs.vapor.codes/basics/logging.

## Data Layer (Fluent + PostgreSQL)

### Fluent overview

Fluent is Swift's type-safe ORM. You define `Model` classes; it generates CRUD and
queries. Add `Fluent` + a driver, register the DB in `configure`. PostgreSQL is the
recommended driver (also SQLite, MySQL, MongoDB). `req.db` is the default DB in
handlers. Source: docs.vapor.codes/fluent/overview.

### Models

```swift
final class Planet: Model {
    static let schema = "planets"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?   // enables soft delete
    @Parent(key: "star_id") var star: Star
    init() {}
    init(id: UUID? = nil, name: String) { self.id = id; self.name = name }
}
```

Mark models `final`. `try model.requireID()` throws if unsaved. Recommended: expose
DTOs, not models, on your API (avoid leaking columns like a password hash and avoid
lazy-relation serialization). Source: docs.vapor.codes/fluent/model.

### Migrations

Every schema change is an `AsyncMigration` with `prepare` and a real `revert`.
Register in `configure` in dependency order. Treat a shipped migration as immutable:
never edit it, write a new one. Fluent has no first-class index API; for plain
indexes drop to SQLKit (`create(index:).on(...).column(...)`). Foreign-key actions
(`.cascade`, `.setNull`, ...) run in the DB and bypass Fluent middleware and soft
delete. Source: docs.vapor.codes/fluent/migration, /fluent/schema,
blog.vapor.codes/posts/adding-db-table-index.

```swift
struct CreateGalaxy: AsyncMigration {
    func prepare(on db: any Database) async throws {
        try await db.schema("galaxies").id().field("name", .string, .required).create()
    }
    func revert(on db: any Database) async throws { try await db.schema("galaxies").delete() }
}
```

### PostgreSQL setup and pooling (production-critical)

```swift
if let url = Environment.get("DATABASE_URL") {
    try app.databases.use(.postgres(url: url), as: .psql)
} else {
    app.databases.use(.postgres(configuration: .init(hostname: "localhost",
        username: "vapor", password: "vapor", database: "vapor", tls: .disable)), as: .psql)
}
```

Pooling: the driver builds one connection pool per event loop, each capped at
`maxConnectionsPerEventLoop` (default 1). Total connections per app instance is
approximately `eventLoopCount * maxConnectionsPerEventLoop`, where `eventLoopCount`
is about `System.coreCount`. Bumping to 2 to 4 per loop often relieves contention.
Multiply by instance count and keep the product under Postgres `max_connections`;
use PgBouncer for many instances. `connectionPoolTimeout` (default 10s) is the wait
to acquire a pooled connection. Source: fluent-postgres-driver
`FluentPostgresConfiguration.swift`; Swift Forums "Generic Connection Pool".

### Relationships and eager loading

`@Parent`/`@Children`/`@OptionalChild`/`@Siblings`. Avoid N+1 by eager-loading with
`.with(\.$rel)` (one extra query per relation, regardless of row count); nest with a
closure. `.with()` only works with `.all()` / `.first()`. Encoding a `@Parent` uses a
nested `{ "star": { "id": ... } }` shape, so use a DTO field (`var star: Star.IDValue`)
for request/response bodies. Source: docs.vapor.codes/fluent/relations.

### Query patterns

```swift
let planets = try await Planet.query(on: db)
    .filter(\.$type == .gasGiant)
    .sort(\.$name)
    .with(\.$star)
    .range(..<5)
    .all()
try await Planet.query(on: db).filter(\.$name == "Earth").first()   // Optional
try await Planet.query(on: db).set(\.$type, to: .dwarf).filter(\.$name == "Pluto").update()  // bulk
```

Pagination is first-class: `Planet.query(on: req.db).paginate(for: req)` responds with
`{ items, metadata: { page, per, total } }` for `?page=2&per=5`. Share the pagination
DTO so the client's infinite scroll is unambiguous. Source:
docs.vapor.codes/fluent/query.

### Validation

`Validatable` validates body/query before decode and reports all failures at once
(unlike Codable, which stops at the first). Treat it as a defense-in-depth input
allow-list, not just UX. Source: docs.vapor.codes/basics/validation.

```swift
extension CreateUser: Validatable {
    static func validations(_ v: inout Validations) {
        v.add("email", as: String.self, is: .email)
        v.add("password", as: String.self, is: .count(8...))
        v.add("username", as: String.self, is: .count(3...) && .alphanumeric)
    }
}
// handler: try CreateUser.validate(content: req) before decode
```

### Transactions

`req.db.transaction { tx in ... }`: nothing commits until the closure returns; any
throw rolls back. All queries inside must use the closure's handle, not `req.db`.
Source: docs.vapor.codes/fluent/transaction.

### Production concerns

Pool sizing (above). N+1 (use `.with()`). Indexes via SQLKit. Fluent parameterizes
queries (safe from injection); the risk is the SQLKit/`.raw` escape hatches, so bind
parameters and code-review any raw SQL. DTOs over models on the wire. Uncertain:
whether Fluent caches named prepared statements across executions is undocumented;
do not design production behavior around it.

## Authentication and Security

### Sessions vs tokens

Official guidance: sessions for browser HTML apps, stateless token auth for APIs.
Sessions are trivially revocable but stateful (need a shared driver across instances)
and CSRF-exposed. Tokens scale statelessly but revocation before expiry is hard unless
you add server state. The default session driver is in-memory (fine for tests, not
multi-instance production). Source: docs.vapor.codes/advanced/sessions,
/security/authentication.

### JWT (JWTKit 5, the changed API)

`JWTSigners` is gone; keys live in a `JWTKeyCollection`, which is an `actor`, so
adding keys, signing, and verifying are all `async` and must be `await`ed. Prefer
EdDSA/ECDSA; RSA is gated behind an `Insecure.` namespace on purpose (min 2048 bits).

```swift
// configure:
await app.jwt.keys.add(hmac: Environment.get("JWT_SECRET")!, digestAlgorithm: .sha256)
struct SessionToken: JWTPayload {
    var sub: SubjectClaim; var exp: ExpirationClaim
    func verify(using algo: some JWTAlgorithm) throws { try exp.verifyNotExpired() }
}
// sign:   try await req.jwt.sign(payload)
// verify: try await req.jwt.verify(as: SessionToken.self)   // reads Authorization: Bearer
```

Source: docs.vapor.codes/security/jwt. Verify all claims inside `verify(using:)`.

### Password hashing

Bcrypt via `app.passwords.use(.bcrypt(cost: 12))`. Use the async form in handlers
(`req.password.async.hash/verify`) to offload the CPU-bound hash. The `.plaintext`
hasher is test-only; gate it with `if app.environment == .testing`. Source:
docs.vapor.codes/security/passwords, /security/crypto.

### Authenticatable and the authenticator pattern

Authenticators never reject; they only attach a user to `req.auth` on success.
Rejection is `guardMiddleware`'s job (this enables composition). The Fluent pattern:
`ModelAuthenticatable` (username/password, used once at `/login`) plus
`ModelTokenAuthenticatable` (bearer token, protects everything else). `isValid`
returning false deletes the token row, giving you a revocation hook.

```swift
let passwordProtected = app.grouped(User.authenticator())
passwordProtected.post("login") { req async throws -> UserToken in
    let user = try req.auth.require(User.self)
    let token = try user.generateToken(); try await token.save(on: req.db); return token
}
let tokenProtected = app.grouped(UserToken.authenticator(), UserToken.guardMiddleware())
tokenProtected.get("me") { req -> User in try req.auth.require(User.self) }
```

Recommended default for a single first-party app: opaque DB-backed bearer tokens
(trivial revocation: delete the row; global logout: delete all a user's tokens).
Reach for JWT only when you need stateless/cross-service tokens. The common hybrid:
short-lived JWT access token + long-lived, revocable, hashed refresh token in the DB.
Source: docs.vapor.codes/security/authentication.

### CORS

Register `at: .beginning` (before ErrorMiddleware). The docs `allowedOrigin: .all` is a
demo, not best practice: restrict origins whenever credentials/cookies are involved;
reserve `.all` for genuinely public, credential-less APIs. Source:
docs.vapor.codes/advanced/middleware.

### Secrets

`Environment.get`. Never commit real secrets; git-ignore `.env.*`. In production inject
via the process environment (systemd `EnvironmentFile`, container/orchestrator secrets,
or a secret manager), not a committed `.env`.

### Common security mistakes

- Leaking internal errors: deploy release-built (strips detail); keep `Abort` reasons
  secret-free (returned even in release).
- Missing auth on a route: authenticators do not reject, so forgetting `guardMiddleware`
  or mis-grouping leaves a route open. Register every protected endpoint under the
  guarded group.
- SQL/ORM misuse: only the SQLKit/`.raw` escape hatches are injectable; bind parameters.
- Weak hashing: keep Bcrypt cost at 12+; never ship `.plaintext` outside testing.
- CSRF: Vapor ships no CSRF middleware, and the session cookie is not `Secure`/`httpOnly`
  by default. Set `app.sessions.configuration.cookieFactory` (isSecure, isHTTPOnly,
  sameSite) and add tokens for state-changing routes (community package
  `brokenhandsio/vapor-csrf`). SameSite alone is insufficient.
- Over-permissive CORS with credentials: restrict origins.
- Secrets in code/VCS: inject via env/secret store.

## Testing Vapor

Current approach: `VaporTesting` (built on Swift Testing), recommended by the docs over
`XCTVapor` (XCTest, still supported for existing suites). Pattern: `withApp(configure:)`
sets up and tears down an `Application`; assign mocks inside the closure; drive routes
with `app.testing().test(.GET, "/...")`.

```swift
@Suite("App Tests", .serialized)   // serialize DB suites
struct AppTests {
    @Test func hello() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "hello") { res async in
                #expect(res.status == .ok); #expect(res.body.string == "Hello, world!")
            }
        }
    }
}
```

Database test strategy and its real tradeoff: in-memory SQLite is fast and
dependency-free, but its dialect diverges from Postgres (JSONB, indexes, transaction
semantics), so tests can pass on SQLite yet fail on Postgres. For a production team,
run the integration tier against the same engine as prod (a disposable Postgres, ideally
via Testcontainers per run); that also tests your migrations. Pragmatic split: SQLite
in-memory for fast unit/service tests, containerized Postgres for integration. Mock
dependencies through the `Application.storage` protocol pattern (swap
`app.emailClient = RecordingEmailClient()`). Source: docs.vapor.codes/advanced/testing.

## Deployment

- Linux release build: `swift build -c release`; release mode also suppresses the
  error-detail leak.
- Docker: use the official multi-stage template Dockerfile (`swift:6.3-noble` build
  stage, `ubuntu:noble` runtime), `--static-swift-stdlib` so the runtime image needs no
  toolchain, jemalloc, a dedicated non-root `vapor` user, `EXPOSE 8080`, prod entrypoint
  binding `0.0.0.0`. The generated compose file includes `app`, `db`, and a separate
  `migrate` service (with `replicas: 0` so it does not auto-run). Source:
  raw.githubusercontent.com/vapor/template/main/Dockerfile, docs.vapor.codes/deploy/docker.
- systemd: `Type=simple`, `Restart=always`, `RestartSec=3`, `ExecStart=.../App serve
--env production`, secrets via `EnvironmentFile`. Source: docs.vapor.codes/deploy/systemd.
- Reverse proxy: docs recommend nginx in front, Vapor on an internal port; nginx serves
  static files and owns 80/443. TLS terminates at nginx (Let's Encrypt). Source:
  docs.vapor.codes/deploy/nginx.
- Migrations in production: prefer explicit `swift run App migrate` as a separate
  one-shot step before scaling app instances. Auto-migrate-on-boot risks concurrent
  instances migrating, and a bad migration crash-loops the process. Zero-downtime uses
  expand/contract (add nullable column, backfill, cut over, drop later). `--revert` runs
  your `revert` methods but cannot recover deleted data; keep verified backups.

---

# SwiftUI Mastery Notes

## What SwiftUI Is

Plain English: SwiftUI is Apple's modern way to build the screens of an iPhone/iPad/Mac
app. You describe what the screen should look like for a given piece of data ("a list
of these todos, each a row with a title and a checkmark"), and SwiftUI draws it and
re-draws it automatically whenever the data changes. You do not manually update labels
and buttons the way the older UIKit did; you change the data and the UI follows.

How it differs from UIKit: UIKit was imperative (you create a label, then later call
`label.text = ...` to change it). SwiftUI is declarative (the view is a function of
state; change the state, the view recomputes). This removes a whole class of "the UI is
out of sync with the data" bugs, at the cost of learning how state flows.

## Core Concepts

### View composition

A view is a value type conforming to `View` with a `body`. The protocol is `@MainActor`,
so view code is main-actor isolated by default. Prefer many small `View` structs over
`@ViewBuilder` helper functions; SwiftUI diffs structs by identity and small views keep
`body` re-evaluation scoped. Source: developer.apple.com/documentation/swiftui/view.

### State, Binding, Observable (the heart of it)

- `@State` is the single source of truth a view owns. Since iOS 17 it also owns
  `@Observable` reference instances (replacing `@StateObject`).
- `@Binding` is a two-way reference to state owned elsewhere, passed with the `$`
  projection.
- `@Bindable` projects bindings into an `@Observable` model you were handed.
- `@Observable` (Observation framework, iOS 17) makes a class's stored properties
  automatically tracked; SwiftUI records exactly which properties a `body` reads and
  re-renders only on those. `@ObservationIgnored` opts a property out.

```swift
@Observable @MainActor final class DataModel {
    var name = "Some Name"; var count = 0
    @ObservationIgnored var cache: [String: Int] = [:]
}
struct BookView: View {
    @State private var book = Book()     // @State owns the @Observable's lifetime
    var body: some View { Text(book.title) }
}
struct Editor: View {
    @Bindable var book: Book
    var body: some View { TextField("Title", text: $book.title) }
}
```

The single most consequential shift: object-level to property-level invalidation. Apple:
"with `Observable`, a view updates only when an observable property changes and is
directly read by the view's body; with `ObservableObject`, a view updates when any
published property changes, even if the view does not read it." This is why per-view
ViewModels are no longer a default (see Architecture). Source:
developer.apple.com/documentation/swiftui/managing-model-data-in-your-app.

### Environment

Inject an `@Observable` model with `.environment(model)`; read it by type with
`@Environment(Type.self)`. This replaces `@EnvironmentObject`. Custom environment values
use the `@Entry` macro (iOS 18) instead of the old `EnvironmentKey` boilerplate. Source:
developer.apple.com/documentation/swiftui/view/environment(_:).

### Navigation

`NavigationView` is deprecated on every platform. Use `NavigationStack` (single stack)
and `NavigationSplitView` (multi-column). Value-based `NavigationLink` +
`navigationDestination(for:)` decouple links from destinations; a path binding enables
programmatic navigation, deep links, and state restoration. Source:
developer.apple.com/documentation/swiftui/migrating-to-new-navigation-types.

```swift
@State private var path: [Color] = []
NavigationStack(path: $path) {
    List { NavigationLink("Pink", value: Color.pink) }
        .navigationDestination(for: Color.self) { ColorDetail(color: $0) }
}
// programmatic: path.append(.pink); deep link: .onOpenURL { path = [.pink] }
// heterogeneous stacks: NavigationPath (type-erased)
```

### Lists and forms

`ForEach` needs stable identity (`Identifiable` or an explicit `id:`). Edit via
`editActions:` or `onDelete`/`onMove`; `swipeActions` for custom row actions. `Form { Section { ... } }`
for settings-style input. Source: developer.apple.com/documentation/swiftui/foreach, /list.

### Sheets and modals

Boolean (`isPresented:`) or item-based (`item:`, driven by an `Identifiable?`, the
cleaner choice when the sheet needs the value). `presentationDetents([.medium, .large])`
for resizable sheets. `.alert` and `.confirmationDialog` replace the retired
`Alert`/`ActionSheet` value types. Source:
developer.apple.com/documentation/swiftui/modal-presentations.

### Animations

`withAnimation(.snappy) { ... }` (explicit) or `.animation(.snappy, value: x)` (implicit,
value-scoped). The one-argument `.animation(_:)` is deprecated (iOS 15); always use the
`value:` form or `withAnimation`. `matchedGeometryEffect` for shared-element transitions.
`PhaseAnimator` and `KeyframeAnimator` (iOS 17) for multi-step animations. iOS 26 adds
the `@Animatable` macro. Gate large motion on `@Environment(\.accessibilityReduceMotion)`.
Source: developer.apple.com/documentation/swiftui/controlling-the-timing-and-movements-of-your-animations.

### Async tasks and concurrency

`.task { ... }` runs async work tied to view lifetime and auto-cancels on disappear;
`.task(id:)` cancels and restarts when `id` changes (the idiomatic "reload on input
change"). Because `View` is `@MainActor`, async results land on the main actor
automatically. Swift 6.2 shift: new Xcode 26 projects default to main-actor-by-default
isolation, so most code is main-actor-isolated unless you opt out with `nonisolated`.
This materially simplifies SwiftUI concurrency. Source:
developer.apple.com/documentation/swiftui/view/task(...), swift.org/blog/swift-6.2-released.

### App lifecycle

`@main struct MyApp: App`, `WindowGroup` as the standard scene, observe
`@Environment(\.scenePhase)` (`.active`/`.inactive`/`.background`) via `.onChange` to
persist or clean up. Source:
developer.apple.com/documentation/swiftui/migrating-to-the-swiftui-life-cycle.

### Previews

`#Preview` replaces `PreviewProvider`. `@Previewable` (iOS 18) lets you use `@State`/`@Query`
directly inside a preview; `PreviewModifier` injects shared/cached sample data (e.g. an
in-memory `ModelContainer`). Build one preview per state. Source:
developer.apple.com/documentation/swiftui/preview(...).

## Architecture

### Modern app structure

Feature-first, not layer-first. Models/services are `@Observable`; views own transient
state with `@State` and read shared state from `@Environment`. There is no
framework-mandated folder structure; Apple's sample apps put observable models next to
the views that own them.

```
App/          @main, root scene, environment wiring
Features/     Checkout/ (CheckoutView, CheckoutModel @Observable, subviews), Search/, Auth/
Models/       domain @Model / @Observable types shared across features
Services/     API client (actor), persistence, auth, protocol-backed
DesignSystem/ reusable views, styles, Liquid Glass components
```

### MVVM vs Observation-native ownership (the current debate, resolved)

Bottom line: a rigid "one ViewModel per view" built on `ObservableObject` is no longer
the default for new SwiftUI. The baseline is SwiftUI views + `@Observable` domain/feature
models, with `@State`/`@Environment` for ownership. ViewModels are not dead; they
specialize.

Why the calculus shifted: under `ObservableObject`, invalidation is object-level, so
teams fragmented ViewModels along view boundaries purely to narrow re-render scope.
`@Observable`'s property-level tracking removes that motivation. On the view side, the
property wrappers now govern ownership/lifetime, not observation.

When a ViewModel still earns its place: coordinating multiple models/services;
orchestrating async side-effects and loading state machines; bridging legacy
UIKit/AppKit; isolating complex logic for unit tests. The modern refinement is
feature-scoped models (a `CheckoutModel` across several screens), themselves `@Observable`,
not one granular ViewModel per view. A ViewModel that only forwards to a model is pure
overhead.

Source conflict and safest interpretation: the genuine disagreement is Point-Free
("always a testable model/store") vs the Apple/Hudson/Wals camp ("views + `@Observable`,
add a model only when it pays for itself"). Safest production stance the majority
converge on: treat `@Observable` + SwiftUI state primitives as the baseline; prefer
`@Observable` over `ObservableObject` for new code; own view-local state with `@State`,
share via `@Environment`, bind with `@Bindable`; introduce a ViewModel/FeatureModel only
when it coordinates multiple models/services, orchestrates async work, bridges legacy
code, or isolates logic for tests, never mechanically one-per-view; migrate existing
`ObservableObject` code opportunistically. Swift 6.2 wrinkle: a plain
`@MainActor @Observable` model already gives safe, isolated, testable state with almost
no ceremony, which further weakens the "you need a ViewModel layer" argument for simple
screens. Sources: WWDC23 "Discover Observation in SwiftUI"; Nil Coalescing; Donny Wals;
Apple Forums thread 699003; Paul Hudson; Point-Free (dissent).

### Dependency injection

Three mechanisms, used together: Environment injection for cross-cutting singletons
(`.environment(authService)` + `@Environment(AuthService.self)`); initializer injection
for explicit dependencies a model needs; protocol abstractions for swap/test. Put
business logic in an `@Observable @MainActor` service that is testable without a view.

### State ownership rules

Apple frames architecture as sources of truth + data flow, not MVVM. Each piece of state
has exactly one owner; everyone else gets a `@Binding`/`@Bindable` or reads via
`@Environment`. Own state at the lowest common ancestor of the views that need it. Keep
derived values as computed properties, not duplicated state. Source:
developer.apple.com/documentation/swiftui/managing-model-data-in-your-app.

### Networking layer

A protocol-backed `actor` client with a generic Codable fetch, called from `.task`,
results applied on the main actor by the `@Observable` model.

```swift
protocol APIClient: Sendable { func get<T: Decodable>(_ e: Endpoint) async throws -> T }
actor LiveAPIClient: APIClient {
    private let decoder = JSONDecoder()
    func get<T: Decodable>(_ e: Endpoint) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: e.request)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { throw APIError.badStatus }
        return try decoder.decode(T.self, from: data)
    }
}
@Observable @MainActor final class FeedModel {
    private let client: APIClient
    var state: LoadState<[Post]> = .idle
    init(client: APIClient) { self.client = client }
    func load() async {
        state = .loading
        do { state = .loaded(try await client.get(.feed)) }   // back on MainActor automatically
        catch { state = .failed(error) }
    }
}
```

### Error / loading / empty / success states

Model the four states explicitly with an enum; render `ContentUnavailableView` for empty
and error, `redacted(reason: .placeholder)` for loading skeletons.

```swift
enum LoadState<T> { case idle, loading, loaded(T), failed(Error) }
switch model.state {
case .idle, .loading: ProgressView()
case .failed(let e): ContentUnavailableView("Couldn't Load", systemImage: "wifi.slash",
                        description: Text(e.localizedDescription))
case .loaded(let items) where items.isEmpty:
    ContentUnavailableView { Label("No Posts", systemImage: "tray") }
        description: { Text("New posts appear here.") }
        actions: { Button("Refresh") { Task { await model.load() } } }
case .loaded(let items): List(items) { PostRow($0) }
}
```

### Local persistence

- SwiftData (`@Model`, `@Query`, `.modelContainer`, `#Predicate`) is the iOS 17+ default
  object graph. iOS 26 adds model/class inheritance; `#Index`/`#Unique` are iOS 18.
- Core Data still wins for: deployment below iOS 17; heavy/complex migrations and very
  dynamic predicates; public/shared CloudKit sync (SwiftData is private-DB-oriented);
  data-loss-sensitive apps wanting explicit save control. They interoperate (SwiftData's
  default store uses Core Data underneath).
- Lighter storage: `@AppStorage`/UserDefaults for a few non-sensitive prefs; `@SceneStorage`
  for transient per-scene UI state; file-based Codable for documents / App Group sharing;
  Keychain for anything secret (never UserDefaults).

## Professional UI Patterns

- iPhone-first: prefer `safeAreaInset`/`safeAreaPadding` over raw offsets; drive sizing
  with `layoutPriority` and stack `spacing`, not magic frames; use semantic text styles
  (`.font(.body)`) so text scales with Dynamic Type.
- Adaptive: `@Environment(\.horizontalSizeClass)` (compact vs regular), `ViewThatFits`
  (declarative "pick the first child that fits"), `Grid`/`GridRow` (true 2-D alignment),
  `containerRelativeFrame`. Use `GeometryReader` sparingly (it is greedy and collapses
  sibling layout); scope it to a background/overlay when you must measure.
- Dark mode: semantic/system colors adapt automatically; custom colors via asset catalog
  light/dark variants (`Color("name")`); force with `.preferredColorScheme`, read with
  `@Environment(\.colorScheme)`; preview both.
- Accessibility (non-negotiable): system components give most of it for free; the work is
  labeling custom views: `accessibilityLabel/Value/Hint`, group cards with
  `accessibilityElement(children: .combine)`, `accessibilityAddTraits(.isHeader)`, gate
  motion on `accessibilityReduceMotion`. `accessibilityIdentifier` is a test hook (not
  spoken); do not overload it for the label.
- Loading/empty/error/offline: `ContentUnavailableView` (+ `.search`) for empty/error,
  `redacted(reason: .placeholder)` for skeletons, `NWPathMonitor` for connectivity, an
  explicit `LoadState` enum switched in `body`.
- Component reuse and design system: `ButtonStyle`/`LabelStyle` (get `configuration.isPressed`
  free), `ViewModifier` for repeated modifier stacks, design tokens (spacing/color/type)
  in one place, feed themes through `@Environment`/`.tint`. Prefer native style protocols
  over bespoke if/else styling; they compose, inherit environment, and auto-adopt system
  look (Liquid Glass).

### iOS 26 Liquid Glass (verified against Apple docs and HIG)

What it is (HIG, verbatim): "Liquid Glass forms a distinct functional layer for controls
and navigation elements, like tab bars and sidebars, that floats above the content
layer." Two variants: `.regular` (most components) and `.clear` (over photos/video, add a
35% dark dimming layer). Governing principles: do not use Liquid Glass in the content
layer (use standard `Material` there); use it sparingly on custom controls; it responds to
reduce-transparency / increase-contrast. You mostly get it free: build against the iOS 26
SDK and `TabView`, `NavigationStack`, toolbars, and sidebars adopt it automatically.

Custom-view API (all verified iOS 26.0+):

```swift
Text("Hi").padding().glassEffect()                                   // default capsule, regular
Text("Hi").padding().glassEffect(.regular.tint(.orange).interactive())
Label("Flag", systemImage: "flag.fill").glassEffect(.clear).background(.black.opacity(0.3))
Button("Continue") { }.buttonStyle(.glassProminent)
GlassEffectContainer(spacing: 40) { /* glassEffectID + Namespace for morphing */ }
```

Other iOS 26 chrome: `backgroundExtensionEffect`, `scrollEdgeEffectStyle(.soft/.hard)`,
`tabBarMinimizeBehavior(.onScrollDown)`, `tabViewBottomAccessory`, `Tab(role: .search)`.
Standard `Material` (`.ultraThinMaterial` ...) is not deprecated; it layers beneath glass
for content backgrounds; do not stack `Material` directly under glass (double blur).
Uncertain: the exact Info.plist opt-out key to retain the pre-glass look could not be
pinned to a verified page; confirm against the iOS 26 release notes. There is a separate
`swiftui-liquid-glass-craft` skill for deeper iOS 26 design work. Source:
developer.apple.com HIG Materials, /documentation/swiftui/applying-liquid-glass-to-custom-views.

## Testing SwiftUI

- Swift Testing is current and the default for new unit tests: `import Testing`,
  `@Test`/`@Suite`, `#expect` (soft), `#require` (unwrap-or-throw), `arguments:` for
  parameterized tests, tags/traits, parallel by default (`.serialized` to opt out),
  `init()`/`deinit` instead of setUp/tearDown (use a class/actor suite if you need
  deinit). Source: developer.apple.com/documentation/testing.
- XCTest is still required for UI tests (XCUITest, `XCUIApplication`, wire elements with
  `accessibilityIdentifier`, `waitForExistence(timeout:)`) and performance tests. Not
  deprecated. Xcode 26 adds a record/replay/review UI-automation workflow with video.
- View-model testing: `@Observable` models are plain objects; inject a protocol-backed
  mock service, call methods, assert published properties, no UI host needed.
- Preview-driven development is the fast iteration loop (build each state as a named
  preview with sample/edge-case data), but previews are not tests (no pass/fail); keep
  Swift Testing/XCUITest for regression.
- Networking mocks: a `URLProtocol` stub (intercepts real URLSession without changing
  architecture) or a protocol-abstracted client you inject (simplest to mock). Most
  codebases use the protocol seam for unit tests.
- Snapshot testing (pointfreeco/swift-snapshot-testing) is still a recognized practice;
  it runs under XCTest (not yet Swift Testing). Tradeoffs: fragile to font/layout/OS
  differences, needs pinned device/OS and consistent CI runners, and record mode can
  rubber-stamp a real regression. Use for high-value stable component surfaces, not
  everything.

---

# Vapor + SwiftUI Together

Plain English: the app and the server agree on a "contract" (the shape of the JSON and
the URLs). The server exposes resources; the app calls them, decodes the JSON into Swift
types, stores a token securely, and shows loading/error/empty/success states. Keep each
side's job clean: the server owns data and access control; the app owns navigation and
presentation.

### API contract design

REST resources: plural collection nouns, nest only for ownership (`/users/{id}/reminders`),
method expresses the action. Under a versioned prefix `/api/v1`. Never reuse one DTO for
create and update (required-on-create fields are optional-on-update); use distinct
`...CreateObject` / `...UpdateObject` / `...GetObject`. Pagination is Fluent's
`Page<T>` shape.

Envelope vs bare (genuine unresolved conflict): Vapor's defaults and most named sources
return bare resources on 2xx; a minority wrap everything. Safest interpretation: bare
JSON on 2xx plus a single structured error envelope on non-2xx, relying on HTTP status as
the first signal. Vapor's default error body is `{ "error": true, "reason": "..." }`; for
anything non-trivial, ship a richer envelope with a machine-readable `code` and optional
`fieldErrors` in the shared package.

Versioning (sources conflict): prefer additive, non-breaking changes; when you must break,
use path-based `/api/v1` -> `/api/v2` (visible, clean for logs/proxies). Avoid
header/media-type and method-based versioning for a single first-party client.

### Sharing / mirroring JSON models

Resolved: a Foundation-only shared Swift package of Codable DTOs is feasible and
production-proven (e.g. the Technicolor build's 164-struct `tv-models` package imported by
both sides). The hard constraint: you cannot import Vapor or Fluent into the iOS target;
the shared package must be Foundation-only. Layering: Fluent `Model` classes (server-only,
tied to schema) -> plain `public Codable + Sendable` DTOs (the only shared layer; add
`extension DTO: Content {}` on the server via a retroactive extension so the package stays
Foundation-only) -> client `@Observable` types holding decoded DTOs. Access-control gotcha:
the DTO type, its stored properties, and its `init` must all be `public` to cross the
package boundary. Alternative: Apple's `swift-openapi-generator` (1.12.2) generates a
URLSession client and Vapor server stubs from one `openapi.yaml`, kept in sync at build
time (choose it for language-agnostic contracts or non-Swift clients). Hand-mirroring is
the fallback but reintroduces drift (a field rename becomes a silent runtime decode failure
instead of a compile error). Sources: SwiftLee, theswiftdev, twocentstudios Technicolor,
apple/swift-openapi-generator.

### Authentication end to end

Login endpoint issues a token; the app stores it in the Keychain (never UserDefaults,
which is an unencrypted plist readable from backups/jailbreak), under
`kSecClassGenericPassword` with accessibility `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
(blocks iCloud sync/backup migration); production teams use the KeychainAccess wrapper. The
API client attaches `Authorization: Bearer <token>` centrally. On a 401 meaning "expired,"
call refresh with the refresh token, then retry. Logout revokes the refresh token
server-side, clears all tokens from Keychain and in-memory state, and purges user-tied
cache. Revocation endpoints return 200 even for an already-invalid token (do not leak
validity). Never log tokens.

### Networking client, error mapping, cache

`@MainActor @Observable` store so post-await state mutations are race-free; a typed request
layer that owns the Authorization header, decoding, and error mapping; `.task { await
store.load() }` for lifecycle-tied cancellation; timeouts on the URLSessionConfiguration;
retry only idempotent GETs with backoff, never blind-retry POSTs. Set the JSON key/date
strategies once and mirror the server. Map HTTP status to a domain `NetworkError` then to a
`LoadState` the view switches over (401 -> refresh/re-login, 5xx -> serverError, decode
failure -> decoding). Cache content (not tokens) in SwiftData or files; on logout, purge
all user-tied cache (the same moment you revoke the refresh token). Keychain for
credentials, SwiftData/files for content only.

### Dev environment and production flow

Run Vapor locally on `:8080` with Postgres via the template's docker-compose. Point the app
at localhost (simulator), the Mac's LAN IP (physical device), or the prod host via a build
configuration/scheme, not a hard-coded string. Add a scoped App Transport Security exception
for local HTTP in the Debug Info.plist only (`NSAllowsLocalNetworking` / a localhost
exception), never in Release (Release requires HTTPS). Production: build the release binary
in the multi-stage Dockerfile, run migrations as a pre-deploy one-shot (`migrate -y` or a
Fly `release_command`), inject secrets from env, point the Release app at the prod host over
HTTPS, version the API before you have clients you cannot force-update. Linux caveat: use
`swift-crypto`, not `CryptoKit`; test on Linux/CI, not just macOS.

---

# Recommended Project Structure

### Vapor backend

```
server/
  Package.swift
  docker-compose.yml        # local Postgres
  Dockerfile
  openapi.yaml              # optional (OpenAPI strategy)
  Sources/App/
    entrypoint.swift        # @main lifecycle
    configure.swift         # DB, migrations, middleware, JWT keys (wiring only)
    routes.swift            # top-level route registration
    Controllers/            # RouteCollection per resource (thin: parse, authorize, service, map DTO)
    Models/                 # Fluent @Model classes (DB only, never returned to clients)
    Migrations/             # one AsyncMigration per change, immutable once shipped
    Middleware/             # auth, custom error middleware, sanitized logging
    DTOs/                   # server-side extension DTO: Content {} (or import the shared package)
    Services/               # business logic, external clients (injected via app.storage)
  Tests/AppTests/           # Swift Testing + VaporTesting, in-memory SQLite or containerized Postgres
```

Rationale: `configure`/`routes` stay wiring-only; controllers are thin; models never leave
the DB layer (map to DTOs); services hold logic so controllers stay testable.

### SwiftUI frontend

```
app/
  App.xcodeproj             # (XcodeGen project.yml recommended for CI/agent friendliness)
  Sources/
    MyAppApp.swift          # @main, builds RootStore, injects dependencies
    Root/                   # boot, restore token, signedIn vs signedOut
    Features/               # Todos/ (TodoListView, TodoListStore @MainActor @Observable, TodoDetailView), Auth/
    Networking/             # APIClient (typed send), Endpoints/, NetworkError
    Persistence/            # SwiftData models + cache (content only, never tokens)
    Security/               # KeychainStore
    Models/                 # import the shared DTO package (or hand-mirrored DTOs)
    DesignSystem/
```

Rationale: `@Observable` stores live per feature and own that feature's UI/LoadState; views
are pure presentation; networking/persistence are injected, protocol-fronted services;
global state (auth) goes through the Root store/environment but stays lean.

### Shared model package

```
APIModels/                  # its own SwiftPM package, ZERO Vapor/Fluent deps (Foundation only)
  Sources/APIModels/
    DTOs/                   # public Codable + Sendable structs
    Errors/ErrorEnvelope.swift
    Pagination/Page.swift
```

Server `Package.swift` depends on both `APIModels` and `Vapor`, adds `extension DTO: Content {}`.
App adds the package as a dependency. A field rename now fails at compile time on both sides.
A mono-repo with one workspace lets you breakpoint a request across both sides; build both in
CI because Xcode only pre-builds the active scheme.

---

# Professional Developer Playbook (new full-stack feature)

1. Understand the requirement: what the user sees, what data, which states (loading/empty/
   error), offline behavior.
2. Define the data model: Fluent `@Model` fields, relations, indexes/uniqueness.
3. Define the API contract first: resource path under `/api/v1`, method, separate
   Create/Update/Get DTOs, pagination shape, error codes. Add DTOs to the shared package.
   Mark them `Sendable`.
4. Write the migration: a new `AsyncMigration` with a real `revert`; register in `configure`;
   never edit a shipped migration.
5. Build the backend route: thin `RouteCollection`, attach auth to the group, `req.auth.require`,
   validate input, service does the work, eager-load relations with `.with(\.$rel)`, map
   Model to DTO, return. Throw `Abort`/`AbortError` for failures.
6. Test the backend: Swift Testing + VaporTesting against in-memory SQLite (or containerized
   Postgres for integration); assert status + decoded DTO; cover auth-required and validation
   paths.
7. Migrate and run locally: `swift run App migrate` then `serve`; hit it with curl before
   touching the app.
8. Build the SwiftUI screen: `View` + `@MainActor @Observable` store; model `LoadState`;
   `.task { await store.load() }`.
9. Wire networking: add an `Endpoint`; call it from the store; decode the shared DTO; attach
   Bearer from the Keychain.
10. Handle loading/error/empty explicitly: switch over `LoadState`; friendly per-error
    messages; retry affordance; 401 -> refresh/re-login.
11. Test the frontend: inject a mock API client into the store; assert state transitions
    without rendering.
12. Verify the full flow: run server + app together, exercise the real path end to end. Budget
    real QA time (multi-device, multi-user); verification often dwarfs implementation.
13. Document: update `openapi.yaml`/README; bump the shared package version; note any
    migration/backfill for ops.

---

# Common Mistakes to Avoid

Vapor: blocking the event loop (wrapping a sync blocking call in `async` still stalls the
loop; never `.wait()` on a loop thread); mixing `EventLoopFuture` + async/await in one
handler; N+1 queries (use `.with()`); leaking Fluent models as responses (map to DTOs);
secrets hard-coded or from `.env` in prod; debug logging in prod (leaks tokens); forgetting
`guardMiddleware` on a protected group.

SwiftUI: logic/side-effects/networking in `body` (it re-runs constantly); misusing
`@State` vs `@StateObject` vs `@Observable`/environment; over-triggering updates (keep stores
lean, keep static config out of observable properties); inferring status from `items.isEmpty`
instead of a `LoadState` enum.

Swift 6 concurrency: silencing data-race diagnostics with blanket `@unchecked Sendable`;
blocking the main actor with heavy sync work; passing live reference types across actors
instead of value snapshots; `Task` in `init` capturing `self` (retain cycle); assuming
invariants hold across an `await` (actors are reentrant; snapshot state into locals first);
`@MainActor` on services that should run off-main. Reality: Fluent models are reference types
that must be `@unchecked Sendable`, and many teams still run the server in Swift 5 language
mode because strict concurrency on Fluent is rough.

API design: inconsistent response/error shapes; wrong status codes (200 with an error body,
GET for writes); no versioning / silent breaking changes; chatty UI-shaped endpoints
(`/screen1Data`) that break on redesign and compound N+1.

Database migrations: no `revert`; destructive in-place changes (retype/drop a populated
column); manual SQL hotfixes that drift the schema from code; untested migrations or
auto-migrate-on-boot straight to prod; editing/reordering a shipped migration (corrupts
Fluent's tracking). A migration is not a backup.

Authentication: token in UserDefaults instead of the Keychain; no expiry/rotation/revocation;
secrets in git or the app bundle; leaking secrets in logs; no HTTPS/ATS (keep the local-HTTP
exception out of Release).

App architecture: persistence logic in views or UI state in backend routes; networking
coupled to views with no DI; god view models / monolithic modules; APIs that encode UI state
(selected tab, "next screen"). The backend owns domain + access control; the client owns
navigation + presentation.

---

# Source Index

Grouped, with a trust note per source. Verified July 2026.

### Official docs (authoritative; primary basis for all verified API and version claims)

- docs.vapor.codes (routing, controllers, content, validation, errors, environment, logging,
  async, middleware, services, testing, sessions; fluent overview/model/migration/schema/query/
  relations/transaction; security authentication/jwt/passwords/crypto; deploy docker/nginx/systemd).
  Canonical, actively maintained Vapor 4 docs (each page has an "Edit this page" link to
  github.com/vapor/docs).
- github.com/vapor/vapor + main Package.swift (latest release 4.122.0; main branch reveals
  Vapor 5 dev). github.com/vapor/template-bare and vapor/template (the vapor new template and
  the current Dockerfile). fluent-postgres-driver source (verified pool defaults). Primary
  artifacts, the code itself.
- swiftpackageindex.com/vapor/vapor, /vapor/fluent, /vapor/fluent-postgres-driver, /apple/
  swift-openapi-generator. Auto-updated version/compat data; the version-anchor of record.
- github.com/apple/swift-openapi-generator (+ swift-openapi-vapor, -urlsession, -runtime) and
  swift.org/blog/introducing-swift-openapi-generator. Apple's spec-driven client/server generation.
- swift.org/blog/swift-6.2-released, swift.org/migration. Swift 6.2 + strict concurrency authority.
- developer.apple.com/documentation/swiftui (view, managing-model-data, migrating-from-observable-
  object, migrating-to-new-navigation-types, task, modal-presentations, foreach, list, preview,
  contentunavailableview, applying-liquid-glass-to-custom-views, ...), /observation, /swiftdata,
  /Updates/SwiftData, /documentation/testing, /xctest, /security/keychain-services, /foundation/
  urlsession; HIG Materials/Dark Mode/Accessibility; WWDC 2023 10149, WWDC 2025 219/306/344/356.
  Apple's own docs, the API/availability/deprecation authority.
- blog.vapor.codes (the-future-of-vapor, vapor-next-steps, adding-db-table-index,
  fluent-models-and-sendable). Official Vapor blog; roadmap + the Fluent @unchecked Sendable caveat.

### Community references (respected practitioners; strong but secondary, verify against docs)

- nalexn.github.io/clean-architecture-swiftui (widely-cited SwiftUI layering); avanderlee.com
  (SwiftLee, shared-package + URLSession async); donnywals.com (Swift 6.2 concurrency,
  Observations); nilcoalescing.com (Observation vs ObservableObject invalidation); fatbobman.com
  (Observation, Core Data vs SwiftData 2026); swiftwithmajid.com (post-WWDC25 SwiftUI); Paul
  Hudson / hackingwithswift.com (pragmatic, high-reach, opinion pieces lighter-sourced);
  pointfree.co (the dissenting testable-model school); khanlou.com (JSON error middleware);
  forums.swift.org threads (connection pool, retain cycles, networking patterns; SSWG, directional);
  kodeco.com Server-Side Swift with Vapor (the standard Vapor book).
- ptkd.com (Keychain vs UserDefaults); curity.io / community.auth0.com (token revocation,
  OAuth-framed, adapt to a custom backend); learn.microsoft.com api-design, stackoverflow.blog,
  apisyouwonthate.com, gravitee.io (REST/versioning, non-Swift, by analogy; note the versioning
  conflict).

### Example repos / real builds (concrete, current architecture evidence)

- twocentstudios.com/2025/08/04 Technicolor full-stack architecture (strongest real-world source:
  production mono-repo, 164-struct shared package, @MainActor @Observable stores, KeychainAccess,
  Fly.io, honest cost/benefit + Linux caveats; Aug 2025).
- theswiftdev.com type-safe RESTful APIs with Vapor (Tibor Bodecs; shared target, per-operation
  DTOs, create != update).
- github.com/apple/swift-openapi-generator Examples (hello-world-vapor-server, -urlsession-client;
  canonical spec-driven wiring).
- Apple sample apps: Landmarks (Liquid Glass), Wishlist / Planning travel (Observation +
  Environment), Food Truck (multiplatform).
- pointfreeco/swift-snapshot-testing (canonical snapshot library); brokenhandsio/vapor-csrf
  (de-facto CSRF package, third-party); kishikawakatsumi/KeychainAccess.

### Articles / how-tos (named-author; cross-checked, lower trust)

- avanderlee.com share-swift-code-on-server (shared package pattern; 2023/24, cross-checked);
  losingfight.com (share only request/response bodies, not routing; 2019 reasoning still valid);
  Tim Condon "Full stack development with Swift and Vapor" (Vapor core contributor); oneuptime.com
  (Feb 2026, but its "Vapor 4 requires Swift 5.6" line is stale, superseded by the Swift 6.0
  template requirement); infoq.com Vapor 5 roadmap (2024, corroborates direction).

### Flagged uncertainties / conflicts (already noted inline)

1. Vapor entrypoint pattern: docs Environment page lags; use the live template (`Application.make`).
2. Envelope vs bare responses: no ecosystem consensus; safest = bare-on-2xx + structured error
   envelope on non-2xx.
3. API versioning: sources conflict; safest = additive-first then path-based v1 -> v2.
4. iOS 26 vs 2027 doc drift: live docs render the Xcode 27 beta SDK; verify availability badges;
   NavigationView reads as deprecated-27 but has been effectively deprecated since iOS 16.
5. Exact patch versions of jwt/jwt-kit/fluent and the Postgres pool default for your instance:
   check Swift Package Index / your config at build time; do not quote a hard number.
6. Liquid Glass Info.plist opt-out key: could not pin to a verified page; confirm in the iOS 26
   release notes.
7. Whether Fluent caches named prepared statements: undocumented; do not design around it.
