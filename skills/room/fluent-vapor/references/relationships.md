## relationships

Fluent 4 models three relation families via property wrappers: Parent/Child one-to-one, Parent/Children one-to-many, and Siblings many-to-many through a pivot model. @Parent stores the foreign key on the root model (it wraps a @Field named `id`), while @Children, @OptionalChild, and @Siblings store nothing on the root and are defined by a keypath (`for:`) back to the owning @Parent relation. @Siblings needs a pivot model containing at least two @Parent relations and takes `through:`, `from:`, `to:` keypaths; attach/detach manage pivot rows automatically. Eager loading with `.with(\.$rel)` runs exactly one extra query per relation regardless of row count, which is the primary defense against N+1; nested loads chain via a closure `.with(\.$star){ $0.with(\.$galaxy) }`. Joins (`.join`) are a separate mechanism that fold related rows into one SQL query and let you filter/sort on joined fields, decoded via `model.joined(Other.self)`. Self-referencing relations are not called out in the official docs but are expressed by pointing an @OptionalParent and @Children at the same model. All of this is current in Fluent 4.x including 4.13; the wrapper APIs have been stable across the 4.x line. Key production traps: @Parent decodes/encodes as a nested `{"id": ...}` object (use a DTO), and forgetting eager loading turns a loop over N parents into N+1 queries.

### Rules
- [verified-by-docs] Define a to-one FK with @Parent(key: "star_id") var star: Star; set/update it through the projected id field: model.$star.id = other.id. Never assign the whole object to establish the link. — _@Parent wraps a @Field named id; the relation is stored as that column._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] Use @OptionalParent(key:) var star: Star? for a nullable FK; its migration field omits the .required constraint that @Parent requires. — _Only difference from @Parent is nullability at the column level._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] @Children(for: \.$parentRel) and @OptionalChild(for: \.$parentRel) store nothing on the root model and need no schema column on the root; the FK lives on the child. The `for:` keypath must point at the child's @Parent/@OptionalParent that references this model. — _Children relations are computed from the child's parent key, not stored._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] For one-to-one via @OptionalChild, enforce uniqueness with .unique(on: "planet_id") in the CHILD schema. Without it the child table can hold multiple rows per parent and @OptionalChild loads an arbitrary one. — _@OptionalChild does not itself constrain cardinality; the DB unique constraint does._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] A pivot is any Model with at least two @Parent relations (one per side). Define @Siblings(through: PivotType.self, from: \.$thisSide, to: \.$otherSide). The inverse side flips from/to. — _@Siblings resolves the join through the pivot's two parent keys._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] Add .unique(on: "planet_id", "tag_id") to the pivot schema to prevent duplicate sibling links. — _attach() with default method will otherwise create redundant pivot rows._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] Manage siblings with model.$tags.attach(tag, on: db) / .attach([tags], on: db){ pivot in ... } / .detach(tag, on: db) / .isAttached(to: tag). Pass method: .ifNotExists to attach to skip if the link already exists. The attach closure is where you set extra pivot fields. — _attach/detach create and delete pivot rows automatically; the closure populates pivot attributes._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] Add a child through its relation with parent.$children.create(child, on: db) (or $governor.create for @OptionalChild) — this sets the child's parent id automatically. — _create on the relation fills in the FK so you don't set it by hand._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] Eager load with .with(\.$star) on the query builder; each relation adds exactly ONE extra query no matter how many rows return. Only works on .all() and .first(). This is the fix for N+1. — _Accessing a non-loaded relation in a loop causes one query per row (N+1); eager loading batches it into one._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] Nested eager load via the closure form: .with(\.$star){ star in star.with(\.$galaxy) }. Nesting depth is unlimited. — _The second closure param of with gives an eager-load builder for the related model._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] Lazy-load a single relation you already have the root for with try await model.$star.get(on: db); pass reload: true to bypass the in-memory cache. Check load state with model.$star.value != nil; accessing an unloaded relation traps. — _Synchronous access to a relation is only safe after eager/lazy load; value is the loaded-state probe._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] Query a relation directly (filter/paginate without loading all) with model.$planets.query(on: db).filter(\.$name =~ "M").all(). — _query(on:) returns a QueryBuilder scoped to the related rows._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] Use .join(Star.self, on: \Planet.$star.$id == \Star.$id) when you need to FILTER/SORT by a related model's columns in one SQL statement; filter joined fields with .filter(Star.self, \.$name == "Sun") and decode with try planet.joined(Star.self). This differs from eager loading, which populates the relation property instead. — _Join folds related rows into the same query for cross-model filtering; eager loading is for accessing relation properties._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] When joining the same model twice, alias it with ModelAlias (e.g. HomeTeam/AwayTeam) so the two joins don't collide. — _Two joins on one table need distinct aliases to be addressable in filter._  (https://docs.vapor.codes/fluent/query/)
- [verified-by-docs] Never send/receive a @Parent as a bare id over the network — it JSON-encodes as {"star": {"id": ...}}. Use a DTO (Content struct) with star: Star.IDValue and map to the model. — _@Parent Codable shape is a nested object; naive clients sending a flat id fail to decode._  (https://docs.vapor.codes/fluent/relations/)
- [verified-by-docs] Model self-referencing relations (tree/hierarchy) by pointing an @OptionalParent and a @Children at the SAME model type (e.g. @OptionalParent(key: "parent_id") var parent: Category? plus @Children(for: \.$parent) var children: [Category]). Use @OptionalParent so roots can have a nil parent. — _Official docs don't show a self-ref example, but nothing restricts the related type from being Self; @OptionalParent avoids a non-nullable root._  (https://docs.vapor.codes/fluent/relations/)

### Snippets

**@Parent and @OptionalParent (to-one FK)** · Fluent 4.x incl. 4.13 · https://docs.vapor.codes/fluent/relations/
```swift
final class Planet: Model {
    static let schema = "planets"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String

    // Required parent
    @Parent(key: "star_id") var star: Star

    // (Alternative) nullable parent:
    // @OptionalParent(key: "star_id") var star: Star?

    init() {}
    init(id: UUID? = nil, name: String, starID: Star.IDValue) {
        self.id = id
        self.name = name
        self.$star.id = starID   // set relation by id, no Star fetch needed
    }
}

// Migration field (drop .required for @OptionalParent):
// .field("star_id", .uuid, .required, .references("stars", "id"))
```

**@Children (one-to-many) and @OptionalChild (one-to-one)** · Fluent 4.x · https://docs.vapor.codes/fluent/relations/
```swift
final class Star: Model {
    static let schema = "stars"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String

    // one-to-many: keypath to the child's @Parent
    @Children(for: \.$star) var planets: [Planet]

    init() {}
}

final class Planet: Model {
    // one-to-one child; enforce with .unique(on: "planet_id") in Governor schema
    @OptionalChild(for: \.$planet) var governor: Governor?
}

// Create through the relation (sets the FK automatically):
let earth = Planet(name: "Earth", starID: try sun.requireID())
try await sun.$planets.create(earth, on: db)
try await mars.$governor.create(Governor(name: "Jane"), on: db)
```

**@Siblings many-to-many with pivot + attach/detach** · Fluent 4.x · https://docs.vapor.codes/fluent/relations/
```swift
final class PlanetTag: Model {           // pivot
    static let schema = "planet+tag"
    @ID(key: .id) var id: UUID?
    @Parent(key: "planet_id") var planet: Planet
    @Parent(key: "tag_id") var tag: Tag
    @OptionalField(key: "comments") var comments: String?
    init() {}
}

final class Planet: Model {
    @Siblings(through: PlanetTag.self, from: \.$planet, to: \.$tag)
    var tags: [Tag]
}
final class Tag: Model {                 // inverse: from/to flipped
    @Siblings(through: PlanetTag.self, from: \.$tag, to: \.$planet)
    var planets: [Planet]
}

// attach creates the pivot row; closure sets extra pivot fields
try await earth.$tags.attach(inhabited, on: db) { $0.comments = "life-bearing" }
try await earth.$tags.attach(volcanic, method: .ifNotExists, on: db)
try await earth.$tags.detach(inhabited, on: db)
let linked = earth.$tags.isAttached(to: inhabited)

// Pivot schema: .unique(on: "planet_id", "tag_id") to block duplicates
```

**Eager loading: single + nested (avoids N+1)** · Fluent 4.x · https://docs.vapor.codes/fluent/relations/
```swift
// Single: one extra query for ALL stars, regardless of planet count
let planets = try await Planet.query(on: db)
    .with(\.$star)
    .all()
for planet in planets {
    print(planet.star.name)   // sync, already loaded
}

// Nested: load star, then star.galaxy
let ps = try await Planet.query(on: db)
    .with(\.$star) { star in
        star.with(\.$galaxy)
    }
    .all()
for planet in ps {
    print(planet.star.galaxy.name)
}
// Only works with .all() and .first().
```

**Join for cross-model filtering (vs eager load)** · Fluent 4.x · https://docs.vapor.codes/fluent/query/
```swift
let planets = try await Planet.query(on: db)
    .join(Star.self, on: \Planet.$star.$id == \Star.$id)
    .filter(Star.self, \.$name == "Sun")
    .all()
for planet in planets {
    let star = try planet.joined(Star.self)  // decode joined row
    print(star.name)
}

// Same table joined twice needs ModelAlias:
// final class HomeTeam: ModelAlias { static let name = "home"; let model = Team() }
```

**Lazy-load + load-state check** · Fluent 4.x · https://docs.vapor.codes/fluent/relations/
```swift
try await planet.$star.get(on: db)            // fetch (cached if already loaded)
try await planet.$star.get(reload: true, on: db)  // force re-fetch

if planet.$star.value != nil {
    print(planet.star.name)   // safe
} else {
    // accessing planet.star would trap
}
planet.$star.value = star     // attach manually, no query
```

**Self-referencing (tree) relation** · Pattern not shown verbatim in official docs; standard self-ref via same-model @OptionalParent + @Children · https://docs.vapor.codes/fluent/relations/
```swift
final class Category: Model {
    static let schema = "categories"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String

    @OptionalParent(key: "parent_id") var parent: Category?   // nil = root
    @Children(for: \.$parent) var children: [Category]

    init() {}
}
// Migration: .field("parent_id", .uuid, .references("categories", "id"))
```

**DTO to avoid @Parent nested-object JSON trap** · Fluent 4.x · https://docs.vapor.codes/fluent/relations/
```swift
struct PlanetDTO: Content {
    var id: UUID?
    var name: String
    var star: Star.IDValue   // flat id, not nested object
}

let dto = try req.content.decode(PlanetDTO.self)
let planet = Planet(id: dto.id, name: dto.name, starID: dto.star)
try await planet.create(on: req.db)
```

### Failure modes
- **Query loops over parents and issues one SQL query per row; latency scales with row count (N+1).** → Add .with(\.$star) to the query, or batch-load with a single join; each .with adds exactly one query total. (cause: Accessing a relation property (e.g. planet.star) inside a loop without eager loading it first.)
- **Runtime crash/trap when reading a relation property like planet.star.name.** → Eager load with .with(), or lazy load with $star.get(on:), or guard on $star.value != nil before access. (cause: Relation was never eager- or lazy-loaded; the projected value is nil.)
- **Client POST with a flat star id fails to decode into the model.** → Use a DTO (Content struct) exposing star: Star.IDValue and map it to the model with $star.id. (cause: @Parent encodes/decodes as a nested {"star": {"id": ...}} object, not a scalar.)
- **@OptionalChild returns an unpredictable/arbitrary child when several exist for one parent.** → Add .unique(on: "planet_id") to the child schema, or switch to @Children if multiple children are valid. (cause: Missing .unique constraint on the child's parent-id column, so the one-to-one invariant isn't enforced.)
- **Duplicate many-to-many links accumulate in the pivot table.** → Add .unique(on: "planet_id", "tag_id") to the pivot schema and/or use attach(_, method: .ifNotExists, on:). (cause: attach() called repeatedly without a uniqueness guard.)
- **.with(...) appears to be ignored / relation still unloaded.** → Eager loading only applies to .all() and .first(); restructure the query to use one of those. (cause: Eager loading was attached to a finalizer other than .all() or .first() (e.g. .count()).)

### Version-sensitive
- `@Parent / @OptionalParent / @Children / @OptionalChild / @Siblings`: Property-wrapper API is stable across Fluent 4.x including 4.13.x; the docs.vapor.codes/fluent pages target the current 4.0 line. No signature changes observed between 4.x minors for these wrappers.  (https://docs.vapor.codes/fluent/relations/)
- `@Siblings signature (through:from:to:)`: Three-parameter keypath form is current. Older Fluent 4 tutorials sometimes show it without the inverse relation or with a Pivot protocol conformance that is no longer required — any Model with two @Parent relations works as a pivot now.  (https://docs.vapor.codes/fluent/relations/)
- `.join(_:on:) and .filter(Model.self,...) / model.joined(_:)`: Documented on the query page; the on: expression must have one field already in the result set. Default join is inner; a method: parameter (.inner/.left) exists but is not shown in the relations page.  (https://docs.vapor.codes/fluent/query/)
- `get(reload:on:) lazy loading`: reload: parameter controls cache bypass; present in current 4.x. Some pre-4.x async/await migration guides show EventLoopFuture-only forms — current docs show both .map and async/await variants.  (https://docs.vapor.codes/fluent/relations/)

### Open questions
- Context7 is not connected in this environment; substituted Firecrawl scrape + WebFetch against docs.vapor.codes and api.vapor.codes-adjacent official pages, plus one Perplexity search for the self-referencing pattern. Recorded per instruction.
- The official relations page does not show a self-referencing example; the Category tree snippet is inferred-from-research (standard same-model @OptionalParent + @Children). Worth confirming against a FluentKit source test if a verified example is required.
- The join method's optional `method:` parameter (.inner vs .left) and its exact default are not spelled out on the relations page; confirming against api.vapor.codes FluentKit QueryBuilder.join reference would harden the joins guidance.
- Did not independently verify against the exact Fluent 4.13.x tag that these snippets compile unchanged; docs target the 4.0 line generally. No drift was found, but a compile check against 4.13.x + Swift 6.2 strict concurrency (Sendable of Model relations) was not performed.

### Sources
- https://docs.vapor.codes/fluent/relations/
- https://docs.vapor.codes/fluent/query/
- https://docs.vapor.codes/fluent/model/
- https://docs.vapor.codes/fluent/schema/
