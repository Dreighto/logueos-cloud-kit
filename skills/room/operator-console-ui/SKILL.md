---
name: operator-console-ui
description: Apply LogueOS Console visual-density discipline whenever writing or modifying Console UI, or any operator-facing surface that should match its feel. Use BEFORE designing a new pane, card, dropdown, modal, or chip, BEFORE pulling in a fresh shadcn-svelte primitive (they default to airy), or whenever the operator says "this looks like a landing page", "too much whitespace", "loses the console feel", "blends in", or any visual-density regression. Do NOT use for marketing pages, public docs, or Sully/Companion UI (`companion-ui-design` — opposite aesthetic, clean & premium not dense).
---

# Operator Console UI

The LogueOS Console is an operator instrument, not a marketing surface. Its discipline: a dark registry, 4px/8px rhythm, 1px borders over shadows, and tactile micro-interactions. It optimizes for **information density per pixel** the way a Bloomberg terminal or a daw or a flight-deck display does. Every primitive in the UI should reinforce that feel. This skill exists because Tailwind defaults + shadcn defaults + Vercel-template instincts all push the opposite direction — airy, marketing-glossy, "modern web app" — and the operator notices immediately.

## The visual registry (memorize this palette)

Backgrounds:

- Root canvas: `bg-[#050505]` (true near-black, not pure black — slight warmth)
- Surfaces: `bg-zinc-950/80` (panels, modals, dropdowns)
- Inputs: `bg-zinc-950` or `bg-zinc-900` (one step lighter than surface for visual separation)
- Hover surface: add ONE step (`hover:bg-zinc-900`)

Borders (always 1px, never thicker):

- Default: `border border-zinc-800/80`
- Active: `border border-zinc-700/50` with a subtle glow (`shadow-[0_0_20px_rgba(...,0.06)]`)
- Focus-within: `focus-within:border-zinc-600`

Accents (use sparingly — only for state):

- Operator (input/own bubble): `border-orange-500/30 bg-orange-500/[0.03]`
- Agent (reply bubble): `border-zinc-900 bg-zinc-950/40`
- Worker active / streaming: `border-purple-500/40 bg-purple-500/[0.04]` (subtle pulse)
- Recording / mic hot: `border-amber-500/40 bg-amber-500/[0.04]`
- Talkback / agent live: `border-emerald-500/40 bg-emerald-500/[0.04]`
- Image-gen mode: `border-cyan-500/40 bg-cyan-500/[0.04]`
- Failure: `border-red-500/30 bg-red-500/[0.04]`

Text:

- Primary: `text-white` or `text-zinc-100`
- Secondary: `text-zinc-300` or `text-zinc-400`
- Tertiary/hints: `text-zinc-500` or `text-zinc-600`
- NEVER `text-zinc-500` for primary content — only for hints, timestamps, sublabels
- Mono labels: `font-mono text-[9px] tracking-wider uppercase text-zinc-600` (used for column headers, badge labels, etc.)

## The 4 / 8 px constraint rhythm

Everything aligns on multiples of 4px (preferred) or 8px (for larger spacing). Tailwind's `gap-1` (4px), `gap-2` (8px), `p-1.5` (6px), `p-2` (8px), `px-3` (12px), `px-4` (16px) — these are your toolkit. Avoid `p-3.5` and similar half-step values unless there's a specific optical reason.

Why: visual hierarchy comes from consistent rhythm, not from custom one-off paddings. The eye reads the page as a grid even without grid lines.

## Density rules

- **Never** use shadcn defaults wholesale. Their `<Card>` has `p-6` (24px) — too airy. Override to `p-3` or `p-4`.
- **Never** use Tailwind's default `space-y-6` for list items. Use `space-y-1` or `space-y-2`.
- **Buttons** are compact: `h-7 w-7` for icon buttons, `h-8` for text buttons. Reserve `h-9`+ for the primary CTA (Send button, primary action).
- **Rounded corners**: `rounded-xl` (12px) for inputs and small elements, `rounded-2xl` (16px) for bubbles and chips, `rounded-3xl` (24px) ONLY for the composer hero pill.
- **No drop shadows unless they're state-encoded.** Replace `shadow-lg` and friends with state-based glows: `shadow-[0_0_20px_rgba(168,85,247,0.06)]` for streaming, etc.

## Tactile micro-interactions

Every clickable / tappable element gets ALL of:

- `transition-all` (or `transition-colors` for color-only changes)
- `active:scale-95` (visible press feedback — critical on iPhone PWA)
- `hover:scale-105` for important CTAs ONLY; for ordinary buttons, use color shift instead
- `disabled:opacity-40` (clear visual signal when blocked)

For touch surfaces, also: `select-none` on labels, `touch-action: manipulation` already global via app.css.

## Forbidden patterns

- **Airy whitespace dividers** (`<div class="h-12" />` to "give the section room"). Compress.
- **Pure pretty-gradient backgrounds** as the main canvas. Subtle radial overlays for atmosphere are fine (the chat surface does this), but the BASE must be one of the registry blacks.
- **Marketing-style call-to-actions** ("Get Started" pill in pink-gradient with sparkle icon). Operator surfaces use precise iconography + monospace labels.
- **Default Tailwind `text-base`** (16px) for everything. The console reads at 13.5-14px for body and 9-11px for labels. (Exception: input fields MUST be 16px on mobile — see [[ios-pwa-input-hygiene]].)
- **Skeleton loaders that pulse the whole screen.** Use small spinners or dots at the affected element only.

## Reuse existing primitives

Before building a new component:

```bash
ls src/lib/components/        # core components
ls src/lib/components/ui/     # shadcn primitives we've extended
```

If `ToastContainer.svelte`, `Drawer.svelte`, `Dropdown.svelte`, etc. already exist, use them. Operator's repeatedly burned by AGY/CC building parallel implementations of the same primitive — search before you build.

## Verification

Before declaring a UI change done:

1. Visit the changed surface on iPhone Safari (or 390x844 viewport) — does it FEEL like the rest of the Console, or does it visually break out?
2. Compare side-by-side with another Console surface (sidebar, header). Same backgrounds, borders, text colors, density?
3. Tap every interactive element. `active:scale-95` should be felt on each tap. If a tap feels dead, the missing transition is breaking the tactile loop.
4. Disable / loading / error states all visible? (Don't ship a button that just turns into a no-op without visual feedback.)

## Related

- `mobile-chat-ux` — chat-specific layout that builds on this visual base
- `ios-pwa-input-hygiene` — input rules that interact with this aesthetic
- `svelte-5-runes-disciplinarian` — reactive state for the interactive behavior these UI rules describe
