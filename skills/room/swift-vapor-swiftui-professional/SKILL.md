---
name: swift-vapor-swiftui-professional
description: Use for any Swift server work (Vapor + Fluent + PostgreSQL), native SwiftUI work, or full-stack Swift connecting a SwiftUI app to a Vapor API — routes, controllers, middleware, models, migrations, auth, tests, deploy configs, views, state, navigation, networking. Applies current 2026 / Swift 6.2 / Vapor 4 / iOS 26 patterns instead of stale tutorials. For NASDOOM-specific Liquid Glass visual polish, use `swiftui-liquid-glass-craft` instead.
---

# Swift / Vapor / SwiftUI Professional Developer Skill (entry / quick reference)

This is the lightweight entry tier, so invoking the skill stays cheap on context. It carries
the rules and checklists you need to start. For the full operating guide, load the Skill file;
for source-cited depth, load the dossier. Both paths are under Links, and the load rule is at
the bottom.

Version anchors: Swift 6.2 / Xcode 26; Vapor 4.122 (v5 alpha only); Fluent 4.13; JWTKit 5
async; SwiftUI `@Observable` + NavigationStack + SwiftData + Swift Testing; iOS 26 Liquid
Glass. Live Apple docs render the iOS "2027" beta SDK, so confirm availability badges before
adopting anything new.

## When to use

Any Vapor backend work, any SwiftUI frontend work, connecting a SwiftUI app to a Vapor API,
shared Swift package work, or reviewing/refactoring any of it. For pure iOS 26 visual craft,
use `swiftui-liquid-glass-craft` instead.

## 10 most important rules

1. Verify APIs against current docs when unsure; do not write Swift from memory.
2. Prefer async/await, actors, `@MainActor`; never invent APIs.
3. Modern SwiftUI: `@Observable`, NavigationStack, Swift Testing. Not ObservableObject,
   NavigationView, PreviewProvider.
4. Do not force MVVM; views + `@Observable` baseline, add a model only when it earns its place.
5. Backend owns data + access control; frontend owns navigation + presentation. Keep separate.
6. API contract is explicit: shared Foundation-only Codable DTOs, separate Create/Update/Get.
7. Every schema change needs a migration with a real `revert`; never edit a shipped migration.
8. Tests required: VaporTesting for routes, Swift Testing on mocked models for frontend logic.
9. Every data screen shows loading, error, empty, and success (a `LoadState` enum).
10. Tokens in the Keychain, secrets from env, HTTPS in prod. Flag security risks and
    uncertainty; plain English first.

## Vapor checklist

- [ ] Contract: path under /api/v1, method, DTOs, status codes, errors.
- [ ] Migration for any schema change (new AsyncMigration + revert).
- [ ] Thin controller: auth on the group, validate input, service does the work.
- [ ] Eager-load relations with `.with()` (no N+1); map Model to DTO (never return the model).
- [ ] Throw `AbortError`; no secret in the reason; CORS `at: .beginning`.
- [ ] VaporTesting covers auth-required and validation paths.

## SwiftUI checklist

- [ ] One owner per piece of state (`@State` / `@Observable` model / `@Environment`).
- [ ] Small reusable `View` structs; no logic or networking in `body`.
- [ ] `LoadState` switched in `body`; `ContentUnavailableView` for empty/error.
- [ ] `.task { }` for load; `.task(id:)` to reload on input change.
- [ ] Previews for each state; check safe areas, Dynamic Type, dark mode.
- [ ] Model tests against an injected mock service.

## Full-stack checklist

- [ ] Model, then contract (shared DTOs), then backend, then frontend.
- [ ] Networking client: typed `Endpoint`, `@MainActor @Observable` store, Bearer from Keychain.
- [ ] Client JSON key/date strategy matches the server.
- [ ] Shared DTO change compiles on both sides (rename fails at compile time).
- [ ] 401 drives refresh or re-login; logout revokes server-side + clears Keychain + cache.

## Verification checklist

- [ ] Backend builds; tests pass; migration applies and reverts; route curl'd.
- [ ] Frontend builds; previews render all states; model tests pass.
- [ ] Server + app run together and the real UI action reaches the backend and back.
- [ ] No token in UserDefaults or logs; deploy is release-built.
- [ ] Never mark confirmed on a hunch; name the check that was run.

## Links

- **API/framework knowledge base** (how SwiftUI/Swift actually works — gestures, sheets,
  Combine, custom shapes, generics, CloudKit, etc., synthesized from the Swiftful Thinking
  corpus): `~/dev/knowledge-base/swift/SKILL.md`. Load this alongside the rules below —
  this skill is house style/architecture; the knowledge base is API/language mechanics.
- Full Skill (operating guide, workflows, mistakes, sources):
  `docs/skills/swift-vapor-swiftui-professional-skill.md`
- Quick reference (standalone copy of this tier):
  `docs/skills/swift-vapor-swiftui-quick-reference.md`
- Full research dossier (source-cited detail):
  `docs/research/swift-vapor-swiftui-research-dossier.md`

## Context Load Policy

- Default load: quick-reference only (this file).
- For implementation or review: quick-reference + Skill.
- For uncertainty, research, or debugging: quick-reference + Skill + the relevant section of
  the research dossier.
- Never paste the full dossier into a working prompt unless absolutely necessary.
