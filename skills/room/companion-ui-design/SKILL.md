---
name: companion-ui-design
description: >-
  Apply Sully's "clean & premium" visual language when building or restyling ANY
  LogueOS-Companion UI — chat replies, composer, header, drawers, sheets, buttons,
  the orb. Load this BEFORE styling a companion component, or whenever the operator
  says the companion "looks off", "too boxy", "not premium", wants the magenta
  brand / the orb / a redesign / "make it clean". IMPORTANT: the companion's
  aesthetic is the OPPOSITE of the `operator-console-ui` skill (that one is
  high-density Console) — for Sully use THIS skill, never that one.
---

# companion-ui-design — Sully "clean & premium" (D7)

Source of truth: `docs/superpowers/specs/2026-05-30-sully-companion-rebuild-design.md`.
Sully is calm, warm, premium — generous whitespace, magenta reserved for identity.
This is NOT the Console's dense utilitarian feel; do not import `operator-console-ui`
density here.

## Brand tokens (in `src/app.css` @theme — use utilities, never raw hex)

`--color-brand #ec2d78` · `-bright #ff4d94` · `-deep #c4186a` · `-soft #ff7eb3` ·
`-glow #ff8fc0`. Use `bg-brand` / `text-brand-soft` / `border-brand`, NOT literal
`#ec2d78`. Background `#050505` with the faint ambient magenta glow (already in
app.css). Functional MODE colors stay (amber=recording, emerald=talkback,
cyan=image, purple=sending) — magenta = identity only.

## Reusable classes (app.css @layer components)

`.sully-orb` (glossy magenta thought-drop) · `.icon-btn` (44px mobile / 36px
desktop tap target) · `.btn-brand` (the ONE magenta CTA — the send button) ·
`.popover-panel`. Global `:focus-visible` ring on `--color-ring`.

## Look & feel rules

- Sully's replies render **flat** (no card) under a small `● Sully` magenta
  name-tag. Operator messages in a subtle neutral zinc pill.
- Magenta is for: the orb, the name dot, the send button, active/selected states,
  and links. Everything else stays neutral / near-black.
- Generous vertical rhythm; 1px borders over chunky shadows; tactile
  `active:scale-95` micro-interactions; `font-feature-settings` polish already set.

## Always pair with

`mobile-chat-ux`, `ios-pwa-safe-area`, `ios-pwa-input-hygiene`,
`svelte-5-runes-disciplinarian` (the app is Svelte 5 runes), and verify with
`companion-deploy-verify` (browser-load QA is mandatory). Markdown link color +
the code-block theme live in `src/lib/components/Markdown.svelte`.
