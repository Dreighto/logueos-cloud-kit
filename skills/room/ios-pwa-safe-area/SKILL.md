---
name: ios-pwa-safe-area
description: |
  Apply iOS PWA safe-area-inset discipline to any container that could touch
  the edges of the viewport. Use BEFORE writing any new
  fixed/absolute layout container, BEFORE touching the chat surface's layout,
  or when the operator reports "doesn't fit", "overlapped by dynamic island",
  "covered by status bar", "content gets hidden under the home indicator",
  "home indicator", "notch", "iPhone PWA layout", or "safe area". Do NOT use for desktop surfaces, non-PWA pages where iOS
  Safari's URL bar already handles it, or general input-zoom issues
  (`ios-pwa-input-hygiene`).
---

# iOS PWA safe-area discipline

This applies to chat surfaces, sidebars, drawers, modals, headers, footers,
fixed overlays, and toolbar pills — any container that could touch a
viewport edge.

The Dynamic Island, status bar, and Home Indicator are NOT in the viewport.
They overlay it. `100vh` and `100dvh` include the overlay regions on iOS PWA
standalone mode, so any element positioned at coordinate (0,0) ends up
UNDER the Dynamic Island.

CSS provides `env(safe-area-inset-{top,right,bottom,left})` to expose the
overlay sizes. **You must use them on every container that touches a
viewport edge.**

## Required at app.html level (one-time)

```html
<meta
  name="viewport"
  content="width=device-width, initial-scale=1, viewport-fit=cover,
               interactive-widget=resizes-content"
/>
```

Without `viewport-fit=cover` the `env(safe-area-inset-*)` values resolve to
0 — your padding does nothing.

## The recurring failure mode

Operator reports: "the sidebar is covered by the Dynamic Island", "the
composer sits under the home indicator", "the header chips run off the
edge of my phone".

Cause: a `fixed` or `absolute` container at viewport edges with no inset
padding. Examples that have shipped this regression in LogueOS-Console:

| Container                                              | Problem                                        | Fix                                                                            |
| ------------------------------------------------------ | ---------------------------------------------- | ------------------------------------------------------------------------------ |
| `<aside class="fixed top-0">` (sidebar)                | Top edge covered by Dynamic Island             | Add `padding-top: env(safe-area-inset-top)` to the aside (or its inner header) |
| `<div class="fixed inset-0">` (modal backdrop)         | Modal panel sits under island when full-screen | Add `padding-top: max(1rem, env(safe-area-inset-top))` to the panel            |
| `<header class="z-50 ... pt-3 pb-2">` (top header)     | Header gets occluded                           | Add `padding-top: max(0.75rem, env(safe-area-inset-top))`                      |
| `<div class="fixed bottom-0">` (composer pill / nav)   | Footer below home indicator                    | Add `padding-bottom: max(0.5rem, env(safe-area-inset-bottom))`                 |
| `<aside class="absolute right-0">` (landscape sidebar) | Notch overlap                                  | Add `padding-right: env(safe-area-inset-right)`                                |

**The chat-root padding-top fix from 2026-05-27 ONLY covers the chat's own
content, NOT the sidebar.** Fixed-position children escape the root's
padding box. You must apply inset padding to EACH fixed/absolute container
independently.

## Mandatory checklist

Before opening any layout PR touching /chat or a similar PWA surface:

- [ ] Every `position: fixed` or `position: absolute` element that has
      `top: 0` (or equivalent: `inset-0`, `top-0`, `inset-y-0`) gets
      `padding-top: max(<min>, env(safe-area-inset-top, 0px))` where
      `<min>` is the desktop-friendly spacing you want.
- [ ] Same rule for `bottom: 0` → `padding-bottom: max(..., env(safe-area-inset-bottom))`
- [ ] Same rule for `right: 0` → `padding-right: env(safe-area-inset-right)`
      (landscape orientation handling; less common but the notch can occlude)
- [ ] Same rule for `left: 0` → `padding-left: env(safe-area-inset-left)`
- [ ] Drawer/sidebar that slides in from off-screen: the slid-in state has
      the inset padding; the off-screen state still has it (no flicker
      when sliding).
- [ ] Multi-line content that uses `100dvh` / `100vh` for height: subtract
      safe-area-bottom from the dvh so the bottom of content isn't
      occluded. Use `calc(100dvh - env(safe-area-inset-top) - env(safe-area-inset-bottom))`
      for inner content height, OR wrap inside a container that's
      `100dvh` minus the insets.

## Verification

After applying:

1. Open the surface in 390×844 viewport (iPhone 14 size) via Playwright MCP
2. Check `getBoundingClientRect()` of the offending container — `top` should
   be ≥ ~47 (iOS status bar + Dynamic Island), `bottom` should be ≤
   viewport height − ~34 (home indicator)
3. Operator-visible test: open the PWA on iPhone, navigate to every
   surface, confirm no UI element is covered

## Anti-patterns

- Don't use `padding-top: env(safe-area-inset-top)` _without_ the `max()`
  wrapper — on devices with no inset (Android, desktop, iOS pre-X) the
  inset is 0 and you'll have zero top padding which looks broken on
  desktop. Always: `max(<desktop-min>, env(...))`.
- Don't apply inset padding to inner content if the parent already has
  inset padding via `box-sizing: border-box` — you'll double-pad.
- Don't rely on the chat root's padding to protect sidebar/modal — fixed
  positioning bypasses it.
- Don't forget `env(safe-area-inset-top, 0px)` requires the `0px` fallback
  for older iOS — without it the env() may not resolve and the property
  is dropped.

## Quick recipe

For a brand-new fixed overlay:

```html
<div
  class="fixed top-0 left-0 right-0 z-[60] bg-zinc-900 p-3"
  style="padding-top: max(0.75rem, env(safe-area-inset-top));
         padding-left: max(0.75rem, env(safe-area-inset-left));
         padding-right: max(0.75rem, env(safe-area-inset-right));"
>
  ...
</div>
```

For a sidebar sliding from the left:

```html
<aside
  class="fixed top-0 bottom-0 left-0 z-[60] w-72 ..."
  style="padding-top: env(safe-area-inset-top, 0px);
         padding-bottom: env(safe-area-inset-bottom, 0px);"
>
  <header class="px-4 py-4 ...">...</header>
  ...
</aside>
```

For a bottom-anchored composer:

```html
<div
  class="px-4 pt-2 pb-4 ..."
  style="padding-bottom: max(1rem, env(safe-area-inset-bottom));"
>
  <textarea ... />
</div>
```
