# Swift / Vapor / SwiftUI Professional Developer Skill

Reusable operating guide for agents working on Vapor (Swift backend), SwiftUI (native
Apple frontend), or both. It makes an agent apply verified, current patterns instead of
memory or stale tutorials. Deep source-cited detail is in the research dossier (link at
the bottom); this file is the operating procedure, not a tutorial.

Version anchors (assume these unless a live doc check says otherwise):

- Swift 6.2, Xcode 26. New Xcode 26 projects default to main-actor isolation.
- Vapor 4.122.x on Swift 6 for production. Vapor 5 is alpha only; do not ship on it.
- Fluent 4.13.x + FluentPostgresDriver 2.12.x. JWTKit 5 async `JWTKeyCollection` actor.
- SwiftUI: `@Observable` (iOS 17) baseline through iOS 26. NavigationStack (NavigationView
  deprecated). SwiftData for object graphs. Swift Testing for new unit tests; XCTest still
  required for UI and performance tests. iOS 26 is the Liquid Glass generation.
- Currency trap: live Apple docs now render the Xcode 27 / iOS "2027" beta SDK. Confirm the
  availability badge in Xcode before adopting anything new; some APIs are 2027-cycle, not
  iOS 26.

## When To Invoke This Skill

Invoke when the task involves any of:

- Vapor routes, controllers, middleware, Fluent models, migrations, services,
  authentication, tests, or deployment configs.
- SwiftUI views, state management, navigation, networking, previews, observable models,
  app lifecycle, or UI tests.
- Connecting a SwiftUI client to a Vapor API (contract, DTOs, auth flow, networking client).
- Swift package or shared-model work between backend and frontend.
- Reviewing or refactoring any of the above.
- Planning a feature that involves an iOS frontend or a Swift backend.

For a pure iOS 26 visual-craft question (Liquid Glass look and feel, SF Symbol animation,
native component polish), prefer the `swiftui-liquid-glass-craft` skill. This skill covers
the full engineering stack and defers to that one for pure visual craft.

## Operating Rules

1. Verify APIs against official or current docs (Context7, developer.apple.com,
   docs.vapor.codes) when there is any doubt. Do not write unverified Swift/Vapor/SwiftUI
   from memory.
2. Prefer current Swift concurrency (async/await, actors, `@MainActor`). Do not invent APIs.
3. Do not blindly follow old SwiftUI tutorials. Prefer `@Observable` over ObservableObject,
   NavigationStack over NavigationView, Swift Testing for new unit tests.
4. Do not force MVVM everywhere. Baseline is views + `@Observable` models with
   `@State`/`@Environment` ownership; add a ViewModel/FeatureModel only when it coordinates
   multiple models/services, orchestrates async work, bridges legacy code, or isolates logic
   for tests. Never mechanically one-per-view.
5. Keep backend and frontend separated: the backend owns domain data and access control; the
   frontend owns navigation and presentation. No persistence logic in views; no UI state
   rules in routes.
6. Treat the API contract as an explicit agreement. Prefer a Foundation-only shared Swift
   package of Codable DTOs (or OpenAPI-generated types); separate Create vs Update vs Get.
7. Require a migration for every schema change (a new `AsyncMigration` with a real `revert`;
   never edit a shipped migration).
8. Require tests: Vapor route/data behavior via VaporTesting; critical frontend logic via
   Swift Testing on injected mocks.
9. Require loading, error, empty, and success states on every SwiftUI screen that loads data
   (an explicit `LoadState` enum + `ContentUnavailableView`).
10. Plain English before technical detail (the operator is a non-programmer).
11. Flag security risks rather than silently shipping unsafe patterns (tokens in the Keychain
    not UserDefaults, secrets from env not code, HTTPS in prod, `Abort` reasons secret-free,
    release-built deploy, restricted CORS with credentials).
12. Flag uncertainty when docs or examples conflict, and pick the safest production-ready
    interpretation.

## Vapor Backend Workflow

1. Understand the feature or bug in plain English.
2. Identify affected routes, models, services, middleware, migrations, and tests.
3. If any API usage is uncertain, check current Vapor/Fluent docs.
4. Design the route and contract (path under /api/v1, method, DTOs, status codes, errors).
5. Update models and migrations if the schema changes (new AsyncMigration with revert).
6. Implement: thin controller, auth on the group, validate input, service does the work,
   eager-load relations with `.with()`, map Model to DTO, throw `AbortError` for failures.
7. Add or update tests (VaporTesting; assert status + decoded DTO; cover auth + validation).
8. Verify (build, tests, `swift run App migrate` locally, curl the route).
9. Summarize what changed in plain English.

## SwiftUI Frontend Workflow

1. Understand the screen or interaction.
2. Decide state ownership: view (`@State`), an `@Observable` model, the environment, or the
   networking layer. One owner per piece of state.
3. If any API usage is uncertain, check current SwiftUI docs.
4. Build the UI as small reusable `View` structs; own transient state with `@State`, share
   via `@Environment`, bind with `@Bindable`.
5. Add loading, error, empty, and success states (`LoadState` switched in `body`;
   `ContentUnavailableView` for empty/error; `redacted(.placeholder)` for skeletons).
6. Add previews for each state (`#Preview` with sample and edge-case data).
7. Add tests where practical (Swift Testing on the `@Observable` model with a mock service).
8. Verify on iPhone-sized layouts (safe areas, Dynamic Type, dark mode).
9. Summarize what changed in plain English.

## Vapor + SwiftUI Full-Stack Workflow

1. Define the user-facing feature in plain English.
2. Define the data model (Fluent `@Model`).
3. Define the contract (path, method, Create/Update/Get DTOs in the shared package,
   pagination, error codes).
4. Implement or update the Vapor route/service/model/migration.
5. Test the backend (VaporTesting).
6. Implement or update the SwiftUI networking client (typed `Endpoint`, Bearer from Keychain,
   `@MainActor @Observable` store).
7. Implement or update the SwiftUI screen and state flow.
8. Handle auth, loading, error, empty, and success states.
9. Verify the full path from a UI action to the backend response (server + app together).
10. Document the result and any risks.

## Code Review Workflow

1. Identify whether the code is Vapor, SwiftUI, shared Swift, or full-stack.
2. Outdated APIs: ObservableObject/@StateObject/NavigationView, old JWTSigners,
   EventLoopFuture mixed with async, PreviewProvider.
3. Architecture: persistence in views, UI state in routes, god models, models returned on the
   wire instead of DTOs.
4. Async safety: blocking the event loop or main actor, blanket `@unchecked Sendable`,
   Task-in-init retain cycles, assuming state holds across an `await`.
5. Missing tests: routes, data behavior, critical frontend logic.
6. Security: token in UserDefaults, missing guardMiddleware, `.raw` SQL with user input,
   secrets in code, over-permissive CORS, `Abort` reasons leaking detail.
7. Error handling: no `LoadState`, 200 with an error body, wrong status codes, swallowed
   errors.
8. Plain-English findings first, then exact file-level recommendations.
9. Do not claim verification unless a check or test was actually run and named.

## Verification Checklist

Backend:

- [ ] `swift build` succeeds (release mode for a deploy check).
- [ ] Tests pass (VaporTesting; auth-required and validation paths covered).
- [ ] Migration applies and reverts cleanly (`migrate` then `migrate --revert` on a scratch DB).
- [ ] Route hit with curl returns the expected status + DTO shape.
- [ ] No secret in any `Abort` reason; deploy is release-built; protected routes are guarded.

Frontend:

- [ ] Project builds; previews render for loading, error, empty, and success.
- [ ] Model tests pass against an injected mock service.
- [ ] Checked at an iPhone size: safe areas, Dynamic Type larger sizes, dark mode.
- [ ] 401 path drives refresh or re-login; no token in UserDefaults or logs.

Full-stack:

- [ ] Server and app run together; the real UI action reaches the backend and back.
- [ ] Client JSON key/date strategy matches the server.
- [ ] Shared DTO change compiles on both sides (rename fails at compile time, not runtime).

Never mark work confirmed on a hunch. Name the check that was run.

## Common Mistakes

Vapor: blocking the event loop (wrapping a sync blocking call in `async` still stalls it;
never `.wait()` on a loop thread); mixing EventLoopFuture + async/await in one handler; N+1
queries (use `.with()`); returning Fluent models instead of DTOs; secrets hard-coded or from
`.env` in prod; debug logging in prod (leaks tokens); forgetting `guardMiddleware` on a
protected group; CORS registered after ErrorMiddleware (must be `at: .beginning`).

SwiftUI: logic, side-effects, or networking in `body` (it re-runs constantly); confusing
`@State` vs `@StateObject` vs `@Observable`/environment; inferring status from `items.isEmpty`
instead of a `LoadState` enum; NavigationView and ObservableObject in new code.

Swift 6 concurrency: silencing data-race diagnostics with blanket `@unchecked Sendable`;
blocking the main actor; passing live reference types across actors instead of value
snapshots; `Task` in `init` capturing `self` (retain cycle); assuming invariants hold across
an `await` (actors are reentrant; snapshot into locals first). Note: Fluent models are
reference types that need `@unchecked Sendable`, and many teams still run the server in Swift
5 language mode because strict concurrency on Fluent is rough.

API design: inconsistent response/error shapes; wrong status codes (200 with an error body,
GET for writes); no versioning or silent breaking changes; chatty UI-shaped endpoints that
break on redesign.

Migrations: no `revert`; destructive in-place changes on a populated column; manual SQL
hotfixes that drift schema from code; untested or auto-migrate-on-boot straight to prod;
editing or reordering a shipped migration. A migration is not a backup.

Auth: token in UserDefaults instead of the Keychain; no expiry/rotation/revocation; secrets
in git or the bundle; leaking secrets in logs; the local-HTTP ATS exception left in Release.

Architecture: persistence logic in views or UI state in routes; networking coupled to views
with no DI; god view models; APIs that encode UI state (selected tab, next screen). Backend
owns domain + access control; client owns navigation + presentation.

## Source Index (condensed)

Full, per-claim source list with trust notes is in the research dossier. Primary authorities:

- Official: docs.vapor.codes; github.com/vapor (vapor, template-bare, fluent-postgres-driver);
  swiftpackageindex.com (version of record); developer.apple.com/documentation (swiftui,
  observation, swiftdata, testing, xctest, security/keychain-services); swift.org/blog
  (Swift 6.2, migration); Apple HIG (Materials, Dark Mode, Accessibility); WWDC 2023/2025.
- Community: nalexn.github.io (clean architecture), avanderlee.com, donnywals.com,
  nilcoalescing.com, fatbobman.com, swiftwithmajid.com, hackingwithswift.com, pointfree.co
  (dissent on testable models), forums.swift.org, kodeco.com Vapor book.
- Real builds: twocentstudios.com Technicolor (production full-stack, shared package);
  theswiftdev.com type-safe Vapor APIs; apple/swift-openapi-generator examples; Apple sample
  apps (Landmarks, Food Truck); pointfreeco/swift-snapshot-testing; KeychainAccess.

Flagged conflicts (safest interpretation chosen in the dossier): Vapor entrypoint (use the
live template `Application.make`, docs page lags); response envelope (bare on 2xx + structured
error envelope on non-2xx); API versioning (additive first, then path-based v1 -> v2); iOS 26
vs 2027 doc drift (verify availability badges).

## Full Dossier

Deep detail, exact signatures, version nuance, and the source for every claim:
`../research/swift-vapor-swiftui-research-dossier.md`. Load it only when you need a specific
signature, a version nuance, or a citation. Do not paste the whole dossier into a working
prompt.
