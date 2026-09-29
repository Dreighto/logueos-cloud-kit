---
name: node-professional
description: Use for any Node.js/TypeScript/JavaScript backend or service work in this workspace — the LogueOS-Orchestrator dispatch_listener (plain CommonJS Node/Express), or any other Node service/script. Also covers TypeScript fundamentals shared with the frontend side. Applies this codebase's actual conventions (module system, error-response shape, the unhandledRejection defense-in-depth pattern, the append-only jsonl rule) instead of generic Node advice. Make sure to use this whenever the user asks for a Node script, Express route, background service, webhook handler, or async/promise code, or mentions dispatch_listener, `.js`/`.ts` backend files, or Node process lifecycle — even if they don't say "Node" explicitly. For Svelte/SvelteKit-specific frontend work, use `svelte-5-runes-disciplinarian` instead.
---

# Node / TypeScript Professional Developer Skill (entry / quick reference)

Lightweight entry tier — cheap on context. Pairs with the API/language-mechanics
knowledge base under Links; load both before writing non-trivial Node/TS here.

Version anchor: `services/dispatch_listener` — plain CommonJS Node (no
`"type": "module"`, no TypeScript), Express `4.22.2`, Node `>=20` per
`package.json` `engines`. This is the reference codebase for the rules below;
don't assume ESM or TypeScript apply here just because other repos use them.

## When to use

Any Node service, Express route, webhook handler, background job, or
async/promise code in this workspace — especially `services/dispatch_listener`.
Also covers shared TypeScript-fundamentals questions. For Svelte 5
runes/SvelteKit-specific frontend work in `LogueOS-Console`, use
`svelte-5-runes-disciplinarian` instead — this skill is the API-mechanics
complement to that one, not a replacement.

## 8 most important rules

1. Verify Node/Express/TypeScript APIs against current docs when unsure. This
   workspace has real recent version jumps: `LogueOS-Console` pins
   `typescript ^6.0.2`, which ships breaking new defaults (`strict: true`,
   `module`/`target` moved to `esnext`/`es2025`, `types` defaults to `[]`) —
   don't assume 5.x defaults from memory.
2. `dispatch_listener` is CommonJS (`require`/`module.exports`), not ESM —
   match the existing module system in a file rather than introducing
   `import`/`export` into a CommonJS codebase.
3. **A dispatch daemon must never die from one stray unhandled promise
   rejection.** `dispatch_listener` learned this the hard way (LOS-148): the
   real fix is a `.catch` on every spawned worker promise; the
   process-level `unhandledRejection` handler is a seatbelt on top of that —
   it logs loudly (so a latent bug stays visible) but deliberately does
   **not** call `process.exit()`, because killing the listener would orphan
   every in-flight worker, the exact failure the fix targets.
   `uncaughtException` is intentionally left unhandled (Node's default
   crash) — a synchronous throw can leave truly inconsistent state, and the
   startup orphan-sweep recovers slots on the systemd restart that follows.
   Don't "fix" a crash by blanket-catching `uncaughtException`; that
   reintroduces the exact bug class LOS-148 removed.
4. No ESLint/Prettier config is wired into `dispatch_listener` as of this
   writing — match the surrounding file's existing style by eye; don't
   assume a linter will catch formatting drift.
5. Error responses follow a consistent shape in this codebase:
   `res.status(4xx/5xx).json({ error: 'snake_case_code', ...context })`
   (e.g. `{ error: 'pool_status_localhost_only' }`,
   `{ error: 'bad_request', reason: 'invalid_role' }`). Match this shape
   rather than inventing a new error envelope.
6. Tests use Node's own built-in test runner (`node --test test/*.test.js`),
   not Jest/Mocha/Vitest — `dispatch_listener`'s `package.json` `test`
   script is the source of truth. `LogueOS-Console` has separate
   `test:unit`/`test:e2e` scripts; check a repo's actual `package.json`
   before assuming which tool applies.
7. `data/*.jsonl` files in `LogueOS-Orchestrator` are **strictly
   append-only** — never edit, truncate, sort, dedupe, or read-modify-write
   one from Node either. Only append. This is a kernel hard rule, not a
   style preference, and `dispatch_listener` itself writes several of these
   ledgers.
8. Svelte 5 runes (`$state`/`$derived`/`$effect`) are a genuine paradigm
   shift from Svelte 4 stores, not a superficial React-hooks lookalike —
   don't port React mental models over. Load `svelte-5-runes-disciplinarian`
   for this codebase's specific hard rules and documented bug history
   before touching `LogueOS-Console` reactive code.

## Verification checklist

- [ ] Module system (CommonJS vs ESM) matches the file/repo you're in.
- [ ] Every spawned/background promise has an explicit `.catch` — don't rely
      on the process-level handler as the primary defense.
- [ ] Error responses match the existing `{ error: 'snake_case_code' }` shape.
- [ ] Tests run with the repo's actual test command from `package.json`.
- [ ] Any `data/*.jsonl` touch is append-only.
- [ ] Never mark confirmed on a hunch; name the check that was actually run.

## Links

- **API/framework knowledge base** (TypeScript 6.0's new defaults, Svelte 5
  runes mechanics, SvelteKit routing/load-functions, Node async patterns
  including the full LOS-148 incident writeup):
  `~/dev/knowledge-base/typescript/SKILL.md`. Load this alongside the rules
  above — this skill is house style/architecture; the knowledge base is
  API/language mechanics.
- **Svelte-specific house style and bug history**:
  `svelte-5-runes-disciplinarian` skill. Load it for any `LogueOS-Console`
  reactive-component work — it has the team's hard rules this skill doesn't
  duplicate.

## Context Load Policy

- Default load: this file only.
- For implementation or review touching Svelte/SvelteKit specifically: this
  file + `svelte-5-runes-disciplinarian` + the knowledge base's
  `02-svelte-5-runes.md`/`03-sveltekit.md`.
- For `dispatch_listener`/general Node work: this file + the knowledge
  base's `04-node-async.md`.
- Never assume a TypeScript/Svelte API from memory when the knowledge base
  or current docs are one read away — the version-jump risk is real here.
