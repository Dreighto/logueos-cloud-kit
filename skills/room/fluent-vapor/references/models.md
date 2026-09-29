## models-schemas

A Fluent model is a `final class` conforming to `Model`, requiring exactly three things: a static `schema` string (the table/collection name), an `@ID` property, and an empty `init()`. Property wrappers (@ID, @Field, @OptionalField, @Timestamp, @Enum, @Group) map Swift properties to database columns via explicit string keys — deliberately string-based (not keypaths) so migrations can reference columns that no longer exist on the model. The canonical identifier is `@ID(key: .id) var id: UUID?` (UUID for cross-driver compatibility, DB-generated automatically); integer/DB-generated/user keys use `@ID(custom:generatedBy:)`. Under Swift 6 strict concurrency the mutable `_wrappedValue` storage inside every property wrapper blocks compiler-synthesized Sendable, so Vapor's official guidance is to write `final class X: Model, @unchecked Sendable` on every model — this is a real, sanctioned escape hatch, not a hack, because the `Model` protocol requires Sendable but cannot confer `@unchecked` onto conformers. The FieldKeys pattern (a nested `enum FieldKeys` of `static let x: FieldKey`) is a widely used community idiom to avoid stringly-typed drift between model and migration, though the official docs still show inline string keys. Vapor strongly recommends decoupling API shape from the DB model with separate DTO structs rather than encoding/decoding models directly. `@Enum` stores native DB enums and requires a matching `database.enum(...)` migration; `@Timestamp(on: .delete)` enables soft-delete.

### Rules
- [verified-by-docs] Declare every Fluent model as `final class X: Model` with a static `schema` string, one `@ID` property, and an empty `init() { }` — these three are the only hard Model requirements. — _Fluent instantiates models via the empty init when hydrating query results; missing any of the three fails to conform._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] Default identifier is `@ID(key: .id) var id: UUID?` — UUID is the only id type supported by ALL drivers and Fluent auto-generates it on create. Use `@ID(custom: "name", generatedBy: .database) var id: Int?` only for auto-increment ints. — _UUID keeps the model portable across Postgres/SQLite/Mongo; int ids tie you to a driver and break the Mongo driver path._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] generatedBy cases: `.user` (you set it before save), `.random` (value type is RandomGeneratable), `.database` (DB assigns on save, e.g. SERIAL/auto-increment). — _Picking the wrong case makes Fluent either send a null id the DB rejects or overwrite a DB-assigned value._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] Use `@Field(key:)` for required columns and `@OptionalField(key:)` for nullable ones; keep DB keys snake_case and property names camelCase. The key is a string and need not match the property name. — _A non-optional `@Field` mapping a nullable column throws a decoding error when the DB returns NULL._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] Add `@Timestamp(key: "created_at", on: .create)`, `on: .update`, and `on: .delete` (soft-delete) as `Date?`. `.delete` turns on soft-deletion: normal queries hide rows, `.withDeleted()` includes them, `.restore(on:)` un-deletes, `.delete(force: true, on:)` hard-deletes. — _Without knowing `.delete` is soft, code that expects rows gone still finds them, and force:true is the only real delete._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] Set the timestamp storage format explicitly when it matters: `.default` (native datetime), `.iso8601` (string column), `.unix` (double). Match the migration column type to the chosen format. — _An `.iso8601` timestamp needs a `.string` column, not `.datetime`; a mismatch corrupts reads._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] For `@Enum`, the Swift enum must be `String`-backed (`RawRepresentable` where RawValue == String) and Codable; you MUST create the DB enum type in a migration via `database.enum("type").case(...).create()` before the schema references it. Use `@OptionalEnum` for nullable. — _@Enum maps to a native DB enum type; without the enum migration the schema create fails on an unknown type._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] Alternatively store an enum as a plain `.string`/`.int` column with `@Field` — any Codable-backed enum serializes as its raw value. This avoids enum migrations at the cost of native DB type safety, and adding a case needs no DB migration. — _Native @Enum requires a migration to add each new case; raw @Field storage does not — a real tradeoff to state up front._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] Under Swift 6 strict concurrency, conform every model as `final class X: Model, @unchecked Sendable`. This is Vapor's official recommendation, not a workaround. — _Every property wrapper synthesizes a mutable `_x` stored property, which blocks compiler-checked Sendable; the Model protocol requires Sendable but can't grant the @unchecked escape hatch._  (https://blog.vapor.codes/posts/fluent-models-and-sendable/)
- [verified-by-docs] Prefer a dedicated DTO struct for API request/response bodies instead of making the model itself the `Content` you encode/decode. Map model<->DTO explicitly. — _Encoding the model directly leaks DB columns (e.g. password hashes) and couples your public API to schema changes._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] Define columns as static `FieldKey`s in a nested `enum FieldKeys` on the model and reference them from BOTH the model and the migration, to eliminate stringly-typed drift. (Community idiom; official docs still show inline string literals.) — _A typo'd string in the migration silently creates the wrong column; a shared FieldKey constant makes it a compile error._  (https://forums.swift.org/t/idea-deletedfield-in-fluent/52824)
- [verified-by-docs] Set `static let space: String? = "schema_name"` on a model only when placing it in a non-default Postgres schema / MySQL database / secondary SQLite file. — _Needed for multi-schema Postgres deployments; omitting it puts the table in the default (public) schema._  (https://docs.vapor.codes/fluent/model/)
- [verified-by-docs] Use `@Group(key:)` with a `Fields`-conforming (not Model) nested type to flatten sub-fields into `prefix_subkey` columns and keep them filterable (`filter(\.$group.$sub == ...)`), unlike a nested Codable stored in a single `@Field`. — _A nested struct in a plain @Field is stored opaque and can't be filtered server-side; @Group keeps columns queryable._  (https://docs.vapor.codes/fluent/model/)

### Snippets

**Canonical model with FieldKeys, timestamps, enum, Swift 6 Sendable** · @unchecked Sendable is required under Swift 6 strict concurrency (Vapor official guidance). The nested FieldKeys enum is a community idiom — official docs use inline string keys. Each individual wrapper/usage is doc-verified; the composite is not shown verbatim in one official doc. · https://docs.vapor.codes/fluent/model/ + https://forums.swift.org/t/idea-deletedfield-in-fluent/52824 + https://blog.vapor.codes/posts/fluent-models-and-sendable/
```swift
import Fluent
import Vapor

final class Planet: Model, @unchecked Sendable {
    static let schema = "planets"

    @ID(key: .id)
    var id: UUID?

    @Field(key: FieldKeys.name)
    var name: String

    @OptionalField(key: FieldKeys.nickname)
    var nickname: String?

    @Enum(key: FieldKeys.type)
    var type: PlanetType

    @Timestamp(key: FieldKeys.createdAt, on: .create)
    var createdAt: Date?

    @Timestamp(key: FieldKeys.updatedAt, on: .update)
    var updatedAt: Date?

    @Timestamp(key: FieldKeys.deletedAt, on: .delete)
    var deletedAt: Date?   // soft-delete

    init() { }

    init(id: UUID? = nil, name: String, type: PlanetType) {
        self.id = id
        self.name = name
        self.type = type
    }

    enum FieldKeys {
        static let name: FieldKey = "name"
        static let nickname: FieldKey = "nickname"
        static let type: FieldKey = "type"
        static let createdAt: FieldKey = "created_at"
        static let updatedAt: FieldKey = "updated_at"
        static let deletedAt: FieldKey = "deleted_at"
    }
}

enum PlanetType: String, Codable, CaseIterable {
    case rocky, gasGiant, dwarf
}
```

**Matching migration: native enum type then schema referencing shared FieldKeys** · AsyncMigration is the Swift-concurrency migration protocol (Fluent 4). `database.enum(...).create()` returns the enum DatabaseSchema.DataType used in `.field(...)`. Revert should drop the enum type after the table. · https://docs.vapor.codes/fluent/schema/ + https://docs.vapor.codes/fluent/model/
```swift
import Fluent

struct CreatePlanet: AsyncMigration {
    func prepare(on database: Database) async throws {
        let planetType = try await database.enum("planet_type")
            .case("rocky")
            .case("gasGiant")
            .case("dwarf")
            .create()

        try await database.schema(Planet.schema)
            .id()
            .field(Planet.FieldKeys.name, .string, .required)
            .field(Planet.FieldKeys.nickname, .string)
            .field(Planet.FieldKeys.type, planetType, .required)
            .field(Planet.FieldKeys.createdAt, .datetime)
            .field(Planet.FieldKeys.updatedAt, .datetime)
            .field(Planet.FieldKeys.deletedAt, .datetime)
            .unique(on: Planet.FieldKeys.name)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Planet.schema).delete()
        try await database.enum("planet_type").delete()
    }
}
```

**Custom integer, DB-generated identifier** · Use only when you need auto-increment ints; UUID (`@ID(key: .id)` + `.id()`) is the portable default and the Mongo driver expects UUID. · https://docs.vapor.codes/fluent/model/ + https://docs.vapor.codes/fluent/schema/
```swift
final class Log: Model, @unchecked Sendable {
    static let schema = "logs"

    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    @Field(key: "message")
    var message: String

    init() { }
}

// migration
.field("id", .int, .identifier(auto: true))
```

**DTO separated from the model** · Vapor recommends DTOs for almost all API request/response bodies rather than conforming the Model to Content directly. · https://docs.vapor.codes/fluent/model/
```swift
struct PlanetDTO: Content {
    var id: UUID?
    var name: String
    var type: PlanetType

    init(_ model: Planet) {
        self.id = model.id
        self.name = model.name
        self.type = model.type
    }
}

// PATCH-style partial DTO
struct PatchPlanet: Decodable {
    var name: String?
    var nickname: String?
}
```

### Failure modes
- **Swift 6 build error: 'Stored property _id of Sendable-conforming class is mutable' on every model.** → Add `, @unchecked Sendable` to the class declaration (e.g. `final class Planet: Model, @unchecked Sendable`). This is Vapor's sanctioned fix. (cause: Property wrappers create mutable `_x` storage; the Model protocol requires Sendable but the compiler can't verify a class with mutable stored properties.)
- **Migration create() fails with an unknown/undefined type error on an @Enum column.** → Create the enum type first (await `database.enum(name).case(...).create()`), pass the returned type into `.field(key, enumType, ...)`, and drop it in revert. (cause: The native DB enum type was never created; @Enum requires a `database.enum(...).create()` migration before the schema references it.)
- **Deleted rows still appear (or expected rows vanish) in queries.** → Use `.withDeleted()` to include them, `.restore(on:)` to undelete, and `delete(force: true, on:)` for a real hard delete. (cause: A `@Timestamp(on: .delete)` field enables soft-delete: `delete(on:)` only stamps deleted_at, and normal queries filter those rows out.)
- **Timestamp reads fail or store garbage after choosing a non-default format.** → Align them: `.iso8601` → `.string` column, `.unix` → `.double`, `.default` → `.datetime`. (cause: The `@Timestamp` format (.iso8601 string / .unix double / .default datetime) does not match the migration column type.)
- **Sensitive DB fields leak into API responses, or an API break every time the schema changes.** → Introduce a DTO struct and map model<->DTO explicitly; keep the model out of the wire format. (cause: The Model is conformed to Content and encoded/decoded directly.)
- **Migration silently creates a wrongly-named column that the model can't read.** → Define keys once as `static let x: FieldKey` in a nested `FieldKeys` enum and reference that constant in both places so a mismatch is a compile error. (cause: Column key strings were typed independently in the model and the migration and drifted (typo).)

### Version-sensitive
- `@unchecked Sendable on Model classes`: Required under Swift 6 / strict concurrency because every Fluent property wrapper (@ID, @Field, …) synthesizes a mutable stored `_x` property that defeats compiler-checked Sendable. Pre-Swift-6 tutorials omit it. Vapor's official blog sanctions `final class X: Model, @unchecked Sendable`.  (https://blog.vapor.codes/posts/fluent-models-and-sendable/)
- `AsyncMigration / AsyncModelMiddleware`: Swift-concurrency (async/await) variants are current in Fluent 4. Older docs/tutorials show `Migration` returning `EventLoopFuture<Void>` and `ModelMiddleware`; both still compile but prefer the Async* forms in Swift 6 code.  (https://docs.vapor.codes/fluent/model/)
- `@ID default type`: UUID is the only identifier type supported by all drivers and is auto-generated on create; the old-school `.field("id", .uuid, .identifier(auto: false))` manual style is discouraged and can break the MongoDB driver.  (https://docs.vapor.codes/fluent/model/)
- `@Enum vs raw-value @Field for enums`: Two valid strategies persist: native `@Enum` (needs `database.enum(...)` migration, and a migration to add each new case) vs plain `@Field` storing the Codable raw value (no enum migration, adding cases is free). Not deprecated — a deliberate tradeoff.  (https://docs.vapor.codes/fluent/model/)
- `DEFAULT column constraint`: Not exposed by the Fluent module directly; use `.sql(SQLColumnConstraintAlgorithm.default(value))` after `import SQLKit`. Commonly-stale answers claim a native Fluent default helper.  (https://greypatterson.me/2021/03/default-values-in-vapor-fluent/)

### Open questions
- Context7 is NOT connected in this environment; substituted official docs.vapor.codes + blog.vapor.codes + api.vapor.codes-adjacent sources and Firecrawl/WebFetch as instructed.
- docs.vapor.codes is unversioned — could not confirm these exact APIs against the Fluent 4.13.x tag specifically; the documented surface (@ID/@Field/@Timestamp/@Enum/@Group, SchemaBuilder, AsyncMigration) is stable across Fluent 4.x but a precise 4.13.x changelog diff was not verified.
- The nested `enum FieldKeys` pattern is a strong community idiom (Swift Forums, kodeco, theswiftdev) but is NOT the form shown in the official model docs, which use inline string keys — flagged as inferred-from-research, not doc-canon.
- Did not independently verify against the FluentKit source repo that `generatedBy: .random` requires `RandomGeneratable` beyond the docs statement; treat as doc-asserted only.
- Whether Swift 6.2/6.3 introduces any macro-based alternative to `@unchecked Sendable` for Fluent models (e.g. a future @Model macro) was not confirmed; current guidance remains @unchecked Sendable as of the 2024 Vapor blog post.

### Sources
- https://docs.vapor.codes/fluent/model/
- https://docs.vapor.codes/fluent/schema/
- https://blog.vapor.codes/posts/fluent-models-and-sendable/
- https://forums.swift.org/t/fluent-model-the-id-property-and-a-sendable-warning/72489
- https://forums.swift.org/t/idea-deletedfield-in-fluent/52824
- https://theswiftdev.com/get-started-with-the-fluent-orm-framework-in-vapor-4/
- https://greypatterson.me/2021/03/default-values-in-vapor-fluent/
- https://www.kodeco.com/34237834-advanced-postgresql-with-vapor/page/2
