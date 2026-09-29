---
name: ios-pwa-input-hygiene
description: Apply iOS Safari + PWA input hygiene to any web UI the operator reaches from their iPhone. Use BEFORE shipping a new input/textarea/select or a UI refresh, or when the operator reports "the page zooms when I tap the keyboard", "the layout breaks on my phone", "the buttons feel laggy on tap", "weird zoom in", or any phone-app-feel regression. Do NOT use for desktop-only surfaces, pure backend work, safe-area-inset regressions (`ios-pwa-safe-area`), or chat-specific scroll/keyboard behavior (`mobile-chat-ux`).
---

# iOS PWA Input Hygiene

The operator runs LogueOS from his iPhone via Tailscale Funnel. Every operator-facing web surface — the LogueOS Console, the dev page (port 18768), PM Storefront (when revived), or any future operator-facing surface — MUST follow these rules (the 16px input-zoom rule, dvh/svh units, 300ms tap delay, tap-highlight color, overscroll behavior) or the experience degrades: auto-zoom on input focus, content hidden under the home indicator, sluggish taps, layout jumps when the keyboard appears. This skill exists because the same handful of bugs keep showing up across ports.

## The non-negotiables (apply in order)

### 1. Input font-size MUST be ≥ 16px (the zoom rule)

The single most common bug. If `<input>`, `<textarea>`, or `<select>` has a computed font-size below 16px, iOS Safari **will** zoom the viewport on focus. There is no exception, no workaround flag, no setting on the user's side that disables this. The fix is the font size.

**Wrong (Tailwind `text-sm` is 14px, `text-xs` is 12px):**

```html
<textarea class="text-sm ..."></textarea> <input class="text-xs ..." />
```

**Right:**

```text
<textarea class="text-base ..."></textarea>   <!-- 16px -->
<input class="text-[16px] ..." />             <!-- explicit 16px -->
```

**If the design demands visually-smaller text inside an input**: keep the font-size at 16px, reduce padding to compensate. Do NOT use `transform: scale(0.875)` — it breaks caret positioning and copy-paste selection.

**Do NOT use the viewport-meta hack** (`maximum-scale=1.0` or `user-scalable=no`). It disables pinch-zoom across the entire app, which is a WCAG 2.1 accessibility violation. The 16px rule is the correct fix.

**Sweep pattern when auditing a codebase**:

```bash
# In any web repo, find candidates:
grep -rnE 'class="[^"]*\b(text-xs|text-sm|text-\[1[0-5]px\])[^"]*"' src/ | \
  grep -iE 'input|textarea|select|<input|<textarea|<select'
```

Then read each match and confirm the size applies to the input itself (not a child label).

### 2. Viewport meta tag MUST include `viewport-fit=cover`

Without it, every `env(safe-area-inset-*)` value resolves to `0px` and content hides under the notch / home indicator. Set once in `app.html` (SvelteKit) or equivalent.

```html
<meta
  name="viewport"
  content="width=device-width, initial-scale=1, viewport-fit=cover, interactive-widget=resizes-content"
/>
```

- `viewport-fit=cover` — REQUIRED for safe-area insets to resolve to real values.
- `interactive-widget=resizes-content` — Chrome/Firefox keyboard handling. Not yet honored by Safari but harmless to include; degrades to default behavior.
- Do NOT add `maximum-scale=1.0`. See rule 1.

### 3. Safe-area insets on any edge-touching element

Top app bar:

```css
header {
  padding-top: env(safe-area-inset-top, 0px);
}
```

Bottom nav / footer (the operator's home indicator lives here on Face ID devices — 34pt overlap if you don't pad):

```css
nav.bottom-nav {
  padding-bottom: env(safe-area-inset-bottom, 0px);
}
```

Always include the fallback (`, 0px`). Without it, browsers without the env() function resolve to nothing and the rule is dropped entirely.

For the Console's main flex container shell, the existing pattern (LogueOS-Console `+layout.svelte`) is correct:

```html
<div style="padding-top: env(safe-area-inset-top, 0px);">
  ...
  <nav style="padding-bottom: env(safe-area-inset-bottom, 0px);">
</div>
```

### 4. Use `100dvh` or `100svh`, not `100vh`

On iOS, `100vh` returns the height when the browser chrome is fully retracted — meaning the page is taller than the visible area when toolbars are showing. The visible bottom 80-100px gets pushed below the fold on load.

- `100svh` — small viewport height. Stable across address-bar transitions. Use for layouts that should fit on screen at all times.
- `100dvh` — dynamic viewport height. Resizes when chrome changes. Use for chat-like full-bleed feeds (the Chat tab uses this correctly: `h-[calc(100dvh-100px)]`).
- `100vh` — large viewport height. Almost always wrong on mobile.

Pick `dvh` unless you're explicitly avoiding the reflow cost (e.g., something inside `scroll-snap`).

### 5. Tap delay: `touch-action: manipulation` on clickable elements

Without it, Safari waits ~300ms after every tap to check whether a second tap is coming (double-tap-to-zoom). This makes the UI feel laggy. Add to all interactive elements:

```css
button,
a,
[role="button"],
.tap-target {
  touch-action: manipulation;
}
```

Doesn't disable pinch-to-zoom on the body — only short-circuits the double-tap-to-zoom check on the element. Combine with rule 6.

### 6. Tap highlight color

iOS Safari shows a translucent gray flash on tap by default. Customize per design, or kill it:

```css
* {
  -webkit-tap-highlight-color: transparent;
}
button {
  -webkit-tap-highlight-color: rgba(255, 255, 255, 0.1);
}
```

### 7. Overscroll containment (prevent pull-to-refresh)

If the operator pulls down on a scrollable list, Safari runs page-level pull-to-refresh, reloads the page, and dumps any local state (typed-but-unsent chat draft, in-progress action). Block it on the body:

```css
html,
body {
  overscroll-behavior: none;
}
```

Per-element if you want a specific list to not bounce:

```css
.feed {
  overscroll-behavior-y: contain;
}
```

### 8. Keyboard pushes content (cosmetic but important)

When the keyboard appears in Safari iOS:

- The Visual Viewport shrinks (what you see).
- The Layout Viewport does NOT shrink (where elements are positioned).

This means `position: fixed` bottom bars get hidden by the keyboard. Two mitigations:

(a) Put the input INSIDE a flex column with `100dvh` rather than `position: fixed; bottom: 0`. Flex naturally yields to the keyboard.

(b) Or use the VisualViewport API to listen for resize and translate the input:

```js
window.visualViewport?.addEventListener("resize", () => {
  inputBar.style.transform = `translateY(${window.visualViewport.height - window.innerHeight}px)`;
});
```

The Chat tab uses pattern (a) — preferred. Don't introduce pattern (b) without a reason.

### 9. Auto-capitalize / auto-correct on chat-like inputs

For terminal-style inputs (code, commands, identifiers), disable iOS's helpfulness:

```html
<textarea
  autocomplete="off"
  autocorrect="off"
  autocapitalize="none"
  spellcheck="false"
  ...
></textarea>
```

For prose chat with another human, leave the defaults on.

## Quick checklist (paste into PR description for any UI surface)

- [ ] All `<input>` / `<textarea>` / `<select>` font-size ≥ 16px
- [ ] `viewport-fit=cover` in viewport meta
- [ ] No `maximum-scale=1.0` / `user-scalable=no` in viewport meta
- [ ] Safe-area-inset padding on top app bar + bottom nav
- [ ] Full-height containers use `dvh`/`svh`, not `vh`
- [ ] Tappable elements have `touch-action: manipulation`
- [ ] `-webkit-tap-highlight-color` set (transparent or custom)
- [ ] `overscroll-behavior: none` on html/body
- [ ] Terminal-style inputs have `autocorrect="off" autocapitalize="none"`

## When auditing an existing surface

```bash
# Find inputs likely below 16px:
grep -rnE '<(input|textarea|select)' src/ | grep -E 'text-xs|text-sm|text-\[1[0-5]'

# Find vh that should be dvh/svh:
grep -rn '100vh\|min-h-screen\b' src/

# Find missing viewport-fit:
grep -rn 'name="viewport"' src/ public/
```

For LogueOS-Console specifically, `app.html` carries the viewport meta. `app.css` carries any global rules. `+layout.svelte` carries the safe-area inset padding.

## Why this skill exists

The operator hits the auto-zoom-on-tap bug REPEATEDLY across different ports — Chat, dev page, PM Storefront, Console settings. Each time it's the same root cause (input below 16px) and the same fix (bump to 16px or text-base). Codifying it here so the next agent that adds an input doesn't repeat the bug.

## See also

- [[reference_linux_migration_lessons]] — for systemd / PEP 668 / Tailscale specifics on ROOM.
- LogueOS-Console `src/app.html` — owns the viewport meta.
- LogueOS-Console `src/app.css` — owns global tap/scroll rules.
- LogueOS-Console `src/routes/+layout.svelte` — owns the safe-area shell.
