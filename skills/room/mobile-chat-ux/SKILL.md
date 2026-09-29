---
name: mobile-chat-ux
description: Apply mobile-first chat/messaging UX to the LogueOS Console chat tab or any conversational UI where messages stack and the operator types at the bottom. Use BEFORE writing chat layout code, BEFORE touching the chat page, or when the operator says "the chat is finicky", "the input box is hidden", "I have to scroll to find it", "messages don't auto-scroll", "the keyboard hides the input", "I have to dig the chat box out", or any phone-feel regression on a messaging surface. Do NOT use for non-chat scrolling lists (activity feed, run list — no stick-to-bottom, no composer) or pure safe-area-inset work (`ios-pwa-safe-area`).
---

# Mobile Chat UX

The operator works mobile-first via Tailscale PWA. Every chat-like surface in
LogueOS has to feel like iMessage / Slack — stick-to-bottom scroll, no
100vh/magic-number heights, correct iOS keyboard handling for the composer:
natural scroll, keyboard never hides the input, no magic numbers that break
on the next iOS update. This skill is the codified version of the bugs we
keep re-hitting.

## The four problem clusters (always check all four)

### 1. Scroll behavior — stick-to-bottom + new-messages pill

A chat thread should behave like every other chat app the operator uses:

- **On first paint**: jump to the bottom without animation. The user should see the most recent message immediately. They should NEVER have to scroll down to find the live edge of the conversation.
- **On new message + user is at bottom**: smooth-scroll to keep them pinned to the bottom.
- **On new message + user has scrolled up to read history**: DO NOT yank them back to the bottom — that's hostile. Instead, show a small "X new ↓" pill near the bottom of the feed that they can tap to jump to latest.
- **On user sending their own message**: always pin to bottom. They sent it, they expect to see it.

Reference implementation (Svelte 5 runes shown; adapt to your stack):

```ts
const SCROLL_NEAR_BOTTOM_PX = 80;
let userAtBottom = $state(true);
let unseenCount = $state(0);

function recomputeAtBottom() {
  if (!feedContainer) return;
  const remaining =
    feedContainer.scrollHeight -
    feedContainer.scrollTop -
    feedContainer.clientHeight;
  userAtBottom = remaining <= SCROLL_NEAR_BOTTOM_PX;
  if (userAtBottom) unseenCount = 0;
}

async function scrollToBottom(behavior: ScrollBehavior = "smooth") {
  await tick();
  if (!feedContainer) return;
  const el = feedContainer;
  // requestAnimationFrame is REQUIRED for the on-mount case — without it
  // scrollHeight is 0 because the messages haven't laid out yet.
  requestAnimationFrame(() => el.scrollTo({ top: el.scrollHeight, behavior }));
}

// On poll: if at bottom auto-scroll, else bump the unseen counter.
function onNewMessages(prev, next) {
  if (userAtBottom) scrollToBottom("smooth");
  else unseenCount += next.length - prev.length;
}

// On mount:
onMount(() => {
  requestAnimationFrame(() => {
    scrollToBottom("auto");
    recomputeAtBottom();
  });
});
```

Common mistakes:

- Calling `scrollTo` directly in `onMount` without `requestAnimationFrame` → no-op (scrollHeight is still 0).
- Auto-scrolling on every poll regardless of user position → yanks the operator when they're reading history.
- Forgetting to pin to bottom on operator-send → their own message scrolls off.
- Using `scrollIntoView({ block: 'end' })` on a child → triggers parent-scroll surprises.

### 2. Viewport sizing — flex propagation, never magic numbers

**Wrong:**

```html
<div class="h-[calc(100dvh-100px)] flex flex-col">
  <feed />
  <composer />
</div>
```

`100px` is a guess at the combined height of the top bar + bottom nav + safe-area insets. It's wrong on at least half of iPhones (different home-indicator heights, dynamic island vs notch). And `100dvh` SHRINKS when the iOS keyboard opens — so the magic-calculated total goes out of bounds and the composer drops below the visible area. The operator has to scroll the page to find it.

**Right:**

```text
<!-- In +layout.svelte: the app shell already owns 100dvh + safe-area-inset -->
<div
  class="flex h-[100dvh] flex-col"
  style="padding-top: env(safe-area-inset-top, 0px);"
>
  <header />
  <main class="flex-1 overflow-y-auto">
    <div class="h-full p-4">
      <slot /> <!-- child pages render here -->
    </div>
  </main>
  <nav style="padding-bottom: env(safe-area-inset-bottom, 0px);" />
</div>

<!-- In the chat page: h-full propagates from the parent. No magic numbers. -->
<div class="flex h-full flex-col overflow-hidden -m-4">
  <!-- -m-4 cancels the parent's p-4 so the chat goes edge-to-edge -->
  <feed class="flex-1 overflow-y-auto" />
  <composer class="shrink-0" />
</div>
```

Rules:

- Never use `100vh` on a mobile target. Always `100dvh` or `100svh`.
- Never use `calc(100dvh - <magic number>px)` to subtract chrome. Let flex propagate.
- The chat page should be `h-full` and rely on its parent for sizing.
- The composer should be `shrink-0` so it never compresses below content size.
- The feed should be `flex-1 overflow-y-auto` so it absorbs the remaining height and scrolls internally.

### 3. iOS keyboard handling

iOS Safari shrinks the visual viewport (what's visible) when the keyboard opens, but the LAYOUT viewport (where elements are positioned) does NOT shrink. This means anything `position: fixed; bottom: 0` gets hidden under the keyboard. Two safe patterns:

**Pattern A (preferred): flex column, composer naturally inside flow.**

The chat page is `flex h-full flex-col`. The composer is the last flex child. When iOS shrinks the visual viewport, the layout viewport stays the same — but because the composer is in normal flow inside a flex column, scrolling the page brings it back into view. Better still: WebKit will auto-scroll the focused input into view, and because the composer is in flow (not fixed), the auto-scroll lands it just above the keyboard.

Use this pattern by default.

**Pattern B (only if A doesn't work): VisualViewport API.**

```js
window.visualViewport?.addEventListener('resize', () => {
  const h = window.visualViewport!.height;
  composer.style.transform = `translateY(${h - window.innerHeight}px)`;
});
```

Only use B if you genuinely need `position: fixed` for the composer (e.g. it overlays content). Adds complexity and event-listener churn — pattern A is faster and simpler.

### 4. Safe-area-inset at the bottom

If your chat surface IS the entire page (no bottom nav below it), the composer must respect the home indicator:

```html
<composer style="padding-bottom: env(safe-area-inset-bottom, 0px);" />
```

If your chat surface sits ABOVE a bottom nav that already handles safe-area-inset (the LogueOS Console pattern), the composer does NOT need its own padding — the bottom nav reserves that space.

Quick check: scroll to the bottom of the page, focus the input, look at the home indicator. If it overlaps the composer, you're missing the inset.

## Diagnostic: "the chat feels finicky"

When the operator reports any of:

- "The chat is finicky"
- "I have to scroll to find the input"
- "The input is hidden under the bottom"
- "Messages don't auto-scroll"
- "I have to dig the chat box out"

Walk this checklist in order:

1. **Outer container uses magic-number height?** Grep for `100dvh-` or `calc(100`. If found, replace with `h-full` flex propagation (cluster #2).
2. **`onMount` calls `scrollToBottom` without `requestAnimationFrame`?** Wrap it (cluster #1).
3. **`pollMessages` always scrolls regardless of user position?** Add `userAtBottom` tracking (cluster #1).
4. **No "X new ↓" pill when scrolled up?** Add it (cluster #1).
5. **Composer is `position: fixed; bottom: 0`?** Switch to flex flow (cluster #3).
6. **No `safe-area-inset-bottom` on the bottom-most fixed/sticky element?** Add it (cluster #4).

## Quick checklist (paste into PR description for any chat surface)

- [ ] Outer chat container uses `h-full` + flex column, not a magic calc
- [ ] Feed is `flex-1 overflow-y-auto`
- [ ] Composer is the last `shrink-0` child of the flex column, not `position: fixed`
- [ ] `onMount` scroll-to-bottom is inside `requestAnimationFrame`
- [ ] `userAtBottom` tracked via scroll listener with ~80px tolerance
- [ ] Auto-scroll only fires when `userAtBottom === true`
- [ ] "X new ↓" pill shown when `userAtBottom === false && unseenCount > 0`
- [ ] Operator-send always force-pins to bottom
- [ ] Bottom-most element respects `env(safe-area-inset-bottom, 0px)` if no bottom nav below it
- [ ] Tested on phone with keyboard open — composer stays visible

## See also

- [[ios-pwa-input-hygiene]] — the 16px input zoom rule + viewport-fit + tap-action. Pair with this skill on every chat surface.
- [[ios-pwa-safe-area]] — the general safe-area-inset skill; cluster 4 above is the chat-specific instance of that same discipline.
- LogueOS-Console `src/routes/chat/+page.svelte` — reference implementation as of the 2026-05-25 polish pass.
- LogueOS-Console `src/routes/+layout.svelte` — the app shell that owns 100dvh + top/bottom safe-area-inset.

## Why this skill exists

Operator reported repeatedly: "the chat thread is finicky. it should work like a regular thread does without having to navigate. I also have to dig the chat box out from under the bottom when I land on the page." Both bugs were the same root cause family — magic-number heights + missing scroll discipline. Codifying so the next agent that touches a chat surface doesn't repeat them.
