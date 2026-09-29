## architecture-concurrency

Fluent models are reference types (`final class` conforming to `Model`), which collides with Swift 6 strict-concurrency `Sendable` checking. Since FluentKit 1.48.0, FluentKit's internal APIs require models to be `Sendable`, but the compiler cannot prove a class with mutable property-wrapper setters is safe, so the official Vapor guidance (blog.vapor.codes) is to add `@unchecked Sendable` to every type conforming to `Model`, `ModelAlias`, `Schema`, or `Fields`. This is an assertion, not a proof: it is only safe if models are treated as ephemeral, single-event-loop, per-request objects and are NEVER shared or mutated across tasks or actors. The production idiom is to keep Fluent models confined to the persistence layer and cross every concurrency/API boundary with value-type `Codable & Sendable` DTO structs: fetch on `req.db`, map to a DTO immediately, return or pass the DTO. Use `req.db` (request-scoped, event-loop-affine) inside routes and request-scoped repositories; use `app.db` / `context.application.db` in background Queues jobs, commands, and long-lived services. Queue job payloads must be `Codable` (and should be `Sendable`), never a live model: pass the ID and re-fetch inside the job. Repositories and domain/persistence separation are optional Vapor patterns (shown in the upgrading guide, not mandated) that pay off as apps grow and make strict-concurrency boundaries cleaner. NOTE: the core docs' model pages still show examples WITHOUT `@unchecked Sendable`; the authoritative concurrency guidance lives in the Vapor blog and Swift forums, not the core docs.

### Rules
- [verified-by-docs] Add `@unchecked Sendable` to every type conforming to `Model`, `ModelAlias`, `Schema`, or `Fields` (e.g. `final class User: Model, @unchecked Sendable`). Required to silence Swift 6 strict-concurrency warnings since FluentKit 1.48.0. — _FluentKit's Sendable-constrained internals force the requirement, but the compiler cannot auto-prove a class with mutable @Field setters is Sendable, and a protocol cannot confer the escape hatch on conformers._  (https://blog.vapor.codes/posts/fluent-models-and-sendable/)
- [verified-by-docs] Treat `@unchecked Sendable` on models as a contract not a guarantee: keep models ephemeral, scoped to a single request/event loop, and NEVER share or mutate them across tasks, actors, or detached tasks. — _@unchecked disables the compiler's race diagnostics for that type; safety then depends entirely on usage discipline within Vapor's per-event-loop model._  (https://blog.vapor.codes/posts/fluent-models-and-sendable/)
- [verified-by-docs] Cross every concurrency/API boundary with a value-type `Codable & Sendable` DTO struct. Fetch the model on `req.db`, map to a DTO immediately, and return/pass the DTO. Never hand a live Fluent model to an actor, detached Task, or another service. — _DTO structs copy by value and are auto-Sendable, isolating non-Sendable reference-type models from concurrent code while also shaping the API and hiding internal fields like password hashes._  (https://docs.vapor.codes/basics/content/)
- [verified-by-docs] Use `req.db` for all database access inside route handlers and request-scoped code; it is tied to the request's event loop. Use `app.db` / `context.application.db` in background jobs, commands, actors, and startup services where no Request exists. — _req.db respects event-loop affinity for the request; Application-level database/logger/client services are designed for safe concurrent access from background contexts._  (https://docs.vapor.codes/fluent/overview/)
- [verified-by-docs] Queue job payloads must conform to `Codable` (and should be `Sendable`). Never put a live Fluent model in a payload: pass the model's ID (or a small DTO) and re-fetch with `context.application.db` inside the job's dequeue/run(context:). — _Payloads are serialized into the queue backend (e.g. Redis); reference-type models with live DB connections are not serializable, and embedding them breaks value-semantics safety across workers._  (https://docs.vapor.codes/advanced/queues/)
- [verified-by-docs] Register multiple databases with distinct `DatabaseID`s via `app.databases.use(_:as:)`, set one default with `app.databases.default(to:)`, and target a specific one per query with `Model.query(on: req.db(.someID))`. Configure all databases in configure.swift, not in middleware. — _Enables primary/read-replica routing; FluentKit's Databases service synchronizes access to the driver map and default ID, so per-ID handles remain event-loop-safe._  (https://forums.swift.org/t/using-multiple-databases-in-vapor-4/74454)
- [verified-by-docs] Do the repository pattern (protocol + struct holding a `Database`, registered on app.storage, resolved per-request via req.db) when the app is nontrivial or needs mock-based tests; skip it for small CRUD where direct model queries plus DTO mapping suffice. It is a documented pattern, not a Vapor requirement. — _Vapor 4 moved from the Container service locator to Application/Request extensions; repositories are value-type, request-scoped, and swappable for mocks, but add boilerplate._  (https://docs.vapor.codes/upgrading/)
- [inferred-from-research] Separate domain models (Sendable structs with business rules) from Fluent persistence models only when domain logic is complex or multiple client/API shapes exist; otherwise DTOs + models are enough. Mapping cost is negligible vs DB/network latency in typical web apps. — _Domain/persistence split lets schema and business rules evolve independently and confines @unchecked-Sendable reference types to the persistence layer, at the cost of extra types and mapping._  (https://docs.vapor.codes/fluent/overview/)
- [verified-by-docs] Prefer async/await consistently in route handlers; do not mix EventLoopFuture unless you need explicit event-loop control, and never block the event loop. When spawning detached work that needs the DB, give it app.db, not req.db. — _req.db is bound to the request's event loop and is not meant to be accessed from arbitrary threads; Application-level handles manage their own pooling and affinity._  (https://docs.vapor.codes/basics/async/)

### Snippets

**Fluent model with the required @unchecked Sendable conformance (Swift 6)** · @unchecked Sendable required since FluentKit 1.48.0 under Swift 6 strict concurrency. Apply to any @Fields/@Group struct, ModelAlias, and Schema-conforming type too. NOTE: docs.vapor.codes/fluent/model still shows the example WITHOUT @unchecked Sendable. · https://blog.vapor.codes/posts/fluent-models-and-sendable/
```swift
import Fluent

final class Galaxy: Model, @unchecked Sendable {
    static let schema = "galaxies"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    init() { }

    init(id: UUID? = nil, name: String) {
        self.id = id
        self.name = name
    }
}
```

**Fetch on req.db, map to a Sendable DTO, return the DTO (boundary idiom)** · Content conforms to Codable; a struct of Sendable fields is auto-Sendable. Standard idiom, not quoted verbatim from a version-pinned doc. · https://docs.vapor.codes/basics/content/
```swift
struct UserDTO: Content, Sendable {
    let id: UUID
    let name: String
    let email: String
}

func getUser(_ req: Request) async throws -> UserDTO {
    guard let id = req.parameters.get("userID", as: UUID.self) else {
        throw Abort(.badRequest)
    }
    guard let user = try await User.find(id, on: req.db) else {
        throw Abort(.notFound)
    }
    return UserDTO(id: try user.requireID(), name: user.name, email: user.email)
}
```

**Queue job: carry an ID, re-fetch the model inside the job (never embed a live model)** · Docs confirm payloads must be Codable and jobs use context.application.db; AsyncJob is the async/await variant of Job. Combined idiom synthesized, not one verbatim doc example. · https://docs.vapor.codes/advanced/queues/
```swift
struct SendWelcomeEmailPayload: Codable, Sendable {
    let userID: UUID
}

struct SendWelcomeEmailJob: AsyncJob {
    typealias Payload = SendWelcomeEmailPayload

    func dequeue(_ context: QueueContext, _ payload: Payload) async throws {
        let db = context.application.db
        guard let user = try await User.find(payload.userID, on: db) else { return }
        let dto = UserDTO(id: try user.requireID(), name: user.name, email: user.email)
        // send email using dto + context.application.client
    }
}
// dispatch: try await req.queue.dispatch(SendWelcomeEmailJob.self, .init(userID: user.requireID()))
```

**Multiple databases + read-replica routing** · DatabaseID + app.databases.use(_:as:) and req.db(_:) are stable Fluent 4 API; verify the exact default(to:) label against your FluentKit version. · https://forums.swift.org/t/using-multiple-databases-in-vapor-4/74454
```swift
extension DatabaseID {
    static let primary = DatabaseID("primary")
    static let readReplica = DatabaseID("read-replica")
}

// configure.swift
app.databases.use(.postgres(configuration: primaryConfig), as: .primary)
app.databases.use(.postgres(configuration: replicaConfig), as: .readReplica)
app.databases.default(to: .primary)

// reads target the replica; writes use the default (primary)
let users = try await User.query(on: req.db(.readReplica)).all()
```

**Request-scoped repository registered on app.storage (Vapor 4 services pattern)** · Derived from the Vapor 4 upgrading guide's repository example; under Swift 6 the stored factory closure typically needs @Sendable. · https://docs.vapor.codes/upgrading/
```swift
protocol UserRepository { func all() async throws -> [User] }

struct DatabaseUserRepository: UserRepository {
    let database: Database
    func all() async throws -> [User] { try await User.query(on: database).all() }
}

extension Application {
    private struct Key: StorageKey { typealias Value = @Sendable (Request) -> UserRepository }
    var userRepositoryFactory: (@Sendable (Request) -> UserRepository)? {
        get { storage[Key.self] } set { storage[Key.self] = newValue }
    }
}
extension Request {
    var users: UserRepository {
        guard let make = application.userRepositoryFactory else { fatalError("UserRepository not configured") }
        return make(self)
    }
}
// configure.swift: app.userRepositoryFactory = { req in DatabaseUserRepository(database: req.db) }
```

### Failure modes
- **Compiler warnings/errors: 'Type X does not conform to Sendable' or 'capture of non-Sendable type Model in @Sendable closure' on every Fluent model under Swift 6.** → Add @unchecked Sendable to each Model/ModelAlias/Schema/Fields-conforming type. (cause: Fluent models are final classes with mutable @Field property-wrapper setters; the compiler cannot prove them Sendable, but FluentKit 1.48+ requires it.)
- **Intermittent data corruption or crashes when a fetched model is passed into an actor, TaskGroup, or Task.detached and mutated.** → Never share a live model across concurrency domains; map to a value-type Codable+Sendable DTO at the boundary and pass the DTO. (cause: @unchecked Sendable silences the compiler but does not make the reference-type model thread-safe; concurrent access is a real data race.)
- **Encoding/serialization failure or nonsensical data when dispatching a queue job.** → Make the payload a Codable & Sendable struct carrying the model's ID; re-fetch with context.application.db inside the job. (cause: A live Fluent model (or a type holding a DB connection) was placed in the job payload, which must serialize to the queue backend.)
- **Event-loop / 'wrong event loop' errors or hangs when a background task or detached task uses a database handle.** → In background jobs/services use app.db / context.application.db; reserve req.db for request-scoped code. (cause: req.db is bound to the request's event loop and was captured into work running on a different thread/loop.)
- **Runtime crash or nil when mapping a model to a DTO (e.g. force-unwrapping id or an unloaded relation).** → Eagerly load relations (.with(\.$relation)) before mapping and use try model.requireID() instead of model.id!. (cause: Model relations or the id were not loaded/persisted before mapping; @Parent/@Children are lazily loaded.)

### Version-sensitive
- `Model / Schema / Fields Sendable conformance`: FluentKit 1.48.0 made models effectively require Sendable; from that version you MUST add @unchecked Sendable to Model/ModelAlias/Schema/Fields types under Swift 6 strict concurrency. Pre-1.48 code and most older tutorials omit it and will emit warnings/errors.  (https://blog.vapor.codes/posts/fluent-models-and-sendable/)
- `docs.vapor.codes model examples`: Core Fluent docs (overview, model) still show model definitions WITHOUT @unchecked Sendable, stale vs the Vapor blog's concurrency guidance. Do not treat their absence as 'not needed'.  (https://docs.vapor.codes/fluent/model/)
- `Fluent vs FluentKit versioning`: vapor/fluent (4.13.x, the thin Vapor integration) and vapor/fluent-kit (the core ORM where the Sendable requirement lives, 1.48.x+) are versioned separately. Concurrency behavior tracks the FluentKit version, not the Fluent 4.13 number. Confirm the resolved FluentKit version in Package.resolved.  (https://github.com/vapor/fluent-kit)
- `AnyModel / Model protocol`: Verified in source: `public protocol AnyModel: Schema, CustomStringConvertible {}` and Model: AnyModel with `associatedtype IDValue: Codable, Hashable, Sendable`. The model protocols do NOT declare Sendable conformance (only IDValue is Sendable-constrained), which is why each concrete class must opt in via @unchecked Sendable.  (https://github.com/vapor/fluent-kit/blob/main/Sources/FluentKit/Model/Model.swift)
- `Job vs AsyncJob / ScheduledJob vs AsyncScheduledJob`: Use the Async* variants for async/await job bodies; the non-async variants return EventLoopFuture. Both receive QueueContext exposing `application` (hence context.application.db).  (https://docs.vapor.codes/advanced/queues/)

### Open questions
- Context7 is NOT connected in this environment; substituted Firecrawl/WebFetch against docs.vapor.codes, fluent-kit GitHub source, and the Vapor blog, plus Perplexity for production practice. Recorded per instructions.
- Exact FluentKit version bundled with Fluent 4.13.x was not pinned from an official release table this session. The Sendable requirement is confirmed landing in FluentKit 1.48.0, but confirm the resolved FluentKit version for the 4.13.x / Vapor 4.122.x anchor via Package.resolved or the fluent-kit releases page.
- The repository-pattern registration snippet (app.storage StorageKey factory) is synthesized from the Vapor 4 upgrading guide and community blogs; the exact current form (especially @Sendable closure requirements under Swift 6) should be validated against a live docs.vapor.codes/upgrading fetch and a compile.
- Whether official Vapor docs will be updated to include @unchecked Sendable in core model examples is unresolved; current core docs are stale vs the blog guidance.
- No official doc gives a canonical read-replica helper; the multi-DB routing shown is community practice from the Swift forums, not a documented Fluent feature. Verify app.databases.default(to:) label for the target version.

### Sources
- https://docs.vapor.codes/fluent/overview/
- https://docs.vapor.codes/fluent/model/
- https://blog.vapor.codes/posts/fluent-models-and-sendable/
- https://github.com/vapor/fluent-kit/blob/main/Sources/FluentKit/Model/Model.swift
- https://github.com/vapor/fluent-kit/blob/main/Sources/FluentKit/Model/AnyModel.swift
- https://github.com/vapor/fluent-kit/blob/main/Sources/FluentKit/Database/Databases.swift
- https://docs.vapor.codes/advanced/queues/
- https://docs.vapor.codes/basics/content/
- https://docs.vapor.codes/basics/async/
- https://docs.vapor.codes/upgrading/
- https://forums.swift.org/t/using-multiple-databases-in-vapor-4/74454
- https://forums.swift.org/t/concurrent-access-to-database-logger-and-http-client/66483
- https://theswiftdev.com/the-repository-pattern-for-vapor-4/
- https://swiftpackageindex.com/vapor/fluent
