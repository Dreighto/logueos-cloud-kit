---
name: svelte-5-runes-disciplinarian
description: Apply Svelte 5 runes discipline when writing or modifying any .svelte / .svelte.ts / .svelte.js file in a runes-mode project. Use BEFORE writing any new component with $state arrays or $effect blocks, BEFORE touching the chat surface (which has $effect-driven debounce caches, IntersectionObservers, and stream-buffer mutations), or whenever the operator reports "the page updates twice", "it doesn't refresh when I expect it to", "infinite loop in dev", "$effect ran with old values", or any reactive-feel bug. Do NOT use for legacy Svelte 4 stores / reactive statements (`$:`) — runes-mode is incompatible with those patterns.
---

# Svelte 5 Runes Disciplinarian

Svelte 5 runes ($state, $derived, $effect) replaced the implicit reactivity of Svelte 4 with explicit fine-grained reactivity. The trap: the API LOOKS like React hooks, but the semantics are different — and the differences are exactly where bugs slip in. This skill exists because the same reactive-loop / stale-closure / dependency-leak patterns keep showing up on the chat surface.

## The non-negotiables

### 1. `$state` — track what you mutate, not what you assign

`$state` makes ASSIGNMENTS reactive AND deep-mutations reactive (for objects/arrays). But:

**Reassign the whole reference, not mutate in place when the array is also rendered with `{#each}`:**

```ts
// WRONG — mutation works for state but {#each} with keyed entries doesn't always re-render
let messages = $state<Msg[]>([]);
messages.push(newMsg); // technically reactive, but...

// RIGHT — explicit reassign forces every reader to re-derive
messages = [...messages, newMsg];
```

**Functional updates inside async loops** — when you mutate `messages` inside a long-running stream loop, the old closure can capture a stale reference:

```ts
// WRONG — closure captures messages from when stream started; tokens from later sends interleave
const reader = response.body.getReader();
while (true) {
  const { value, done } = await reader.read();
  if (done) break;
  messages = messages.map(m => m.id === STREAM_ID ? {...m, text: m.text + value} : m);
  // ↑ this `messages` is whatever it WAS when the loop iteration started, not now
}

// RIGHT — read state fresh each iteration via a getter or immediately before the update
messages = $state.snapshot(messages).map(...)
```

This bug class is the source of "tokens from response B appearing in response A's bubble." Always treat `messages` as a snapshot at read time.

### 2. `$derived` — pure functions only, no side effects, no awaits

`$derived` re-evaluates synchronously whenever its dependencies change. It MUST be pure.

**Wrong:**

```ts
const selectedThread = $derived(() => {
  fetch("/api/log", { method: "POST", body: "selection-changed" }); // side effect!
  return threads.find((t) => t.id === activeThreadId);
});
```

**Right:**

```ts
const selectedThread = $derived(threads.find((t) => t.id === activeThreadId));

// Side effect goes in $effect, which fires AFTER the derive settles
$effect(() => {
  if (selectedThread) {
    void fetch("/api/log", { method: "POST", body: "selection-changed" });
  }
});
```

If you find yourself wanting `await` in a `$derived`, you don't want $derived — you want a `$state`updated by an`$effect`.

### 3. `$effect` — dependency tracking is implicit + EAGER

`$effect` tracks every `$state` you READ during its synchronous body. Reads inside async callbacks (then, await, setTimeout) are NOT tracked.

**The classic stale-closure trap:**

```ts
let count = $state(0);
$effect(() => {
  setTimeout(() => {
    console.log(count); // ← reads count AFTER the timeout fires; not tracked as dep
  }, 1000);
});
// Effect runs once on mount. count changes never re-trigger it.
```

**To depend on a value used inside async work, READ IT SYNCHRONOUSLY FIRST:**

```ts
$effect(() => {
  const c = count; // ← synchronous read; now `count` IS a tracked dep
  setTimeout(() => console.log(c), 1000);
});
```

### 4. `$effect` cleanup ALWAYS, every time the effect re-runs

Returning a cleanup function from `$effect` runs it on the NEXT effect fire AND on component destroy. Critical for:

- AbortControllers
- WebSocket / EventSource close
- setInterval / setTimeout clears
- IntersectionObserver disconnect

**Wrong (leaks intervals on every textDraft change):**

```ts
$effect(() => {
  const _ = textDraft;
  setInterval(saveDraft, 400);
});
```

**Right:**

```ts
$effect(() => {
  const _ = textDraft;
  const t = setTimeout(saveDraft, 400);
  return () => clearTimeout(t);
});
```

### 5. The 300ms debounce + localStorage pattern

For the chat composer's draft cache (`textDraft` → localStorage every 300ms after last keystroke):

```ts
let textDraft = $state("");
let saveTimer: ReturnType<typeof setTimeout> | null = null;

$effect(() => {
  const value = textDraft; // read synchronously to track
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    localStorage.setItem("chat-draft-" + activeThread, value);
  }, 300);
  return () => {
    if (saveTimer) clearTimeout(saveTimer);
  };
});
```

Three things this gets right: synchronous read of `textDraft`, clears the previous timer before scheduling a new one, returns a cleanup so component-destroy fires the clear too.

### 6. `$bindable` for two-way prop binding (Svelte 5 specific)

In runes mode, a parent's `bind:value={x}` requires the child to declare the prop as `$bindable`:

```ts
// Child
let {
  value = $bindable(""),
  onCommit,
}: { value?: string; onCommit?: () => void } = $props();
```

Without `$bindable`, the bind silently no-ops and the prop is read-only.

### 7. Type contracts — zero `any`

Every `$state`, `$derived`, `$props`, and `$effect` callback gets explicit types. `any` defeats the AST parser we just enabled (svelte-eslint-parser) and hides exactly the kind of reactive-dependency bugs this skill prevents.

```ts
// Wrong
let messages = $state([]);
let activeThread = $state(null);

// Right
let messages = $state<UIMessage[]>([]);
let activeThread = $state<string | null>(null);
```

## Verification

Before declaring a Svelte-runes change done:

1. `npx eslint <file>` — must report zero `parser` errors. Real lint findings are expected and good (means the AST parser is reading the runes correctly).
2. `npm run check` — Svelte's own typechecker. Catches missed `$bindable`, $effect-with-no-deps, etc.
3. Browser dev-mode visit with Svelte DevTools open. Watch the component tree. Effects that fire MORE than expected → suspect stale-closure or missing memoization. Effects that fire LESS than expected → suspect missing synchronous read of a dependency.

## Related

- `mobile-chat-ux` — the chat surface this skill most often applies to
- `ios-pwa-input-hygiene` — composer input rules that interact with reactive state
- [[reference-sveltekit-basepath-pathname]] — base-path gotcha that interacts with route reactivity
