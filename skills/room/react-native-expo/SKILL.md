---
name: react-native-expo
description: >-
  Use when writing, reviewing, or debugging React Native or Expo code: screens and components,
  Reanimated animations, native modules and Fabric components, config plugins, EAS Build or
  EAS Update / OTA, Metro bundler problems, ProMotion 120Hz and frame-rate work, or streaming
  chat transcripts on iOS. Activates on React Native, Expo, Reanimated, worklets, LegendList,
  FlashList, Metro, EAS, prebuild, dev client, `app.config.ts`, or iOS mobile app work. Also
  activates when choosing a mobile framework at all, since the 120Hz constraint rules options out.
---

# React Native + Expo

Operational rules for React Native and Expo work on this machine. The depth lives in the
knowledge base at `~/dev/knowledge-base/react-native/`; this file carries the rules that stop
an agent going wrong, plus a map of where to read more.

The reference implementation is `~/dev/reference/t3code` (T3 Code, kept as a reference and parts bin, not
a base to fork). It is a real Expo SDK 56 / RN 0.85 / React 19 app that streams AI coding-agent
output on a real iPhone, so it is the grounding for nearly every claim here. Read it before
inventing a pattern.

## Framework selection: the constraint that rules options out

**A webview cannot hit 120Hz on iOS. Do not propose Capacitor, Ionic, or Tauri for an iOS
surface that must feel smooth.** WKWebView is hard-capped at 60fps. WebKit bug 294338 ("Allow
WKWebView to Support 120Hz on ProMotion") has been open since 2025-06-11, an Apple Frameworks
Engineer confirmed the cap on the developer forums, and the only project that forces it needs
private API that iOS 26 disconnected from the compositor. Safari itself got 120Hz in iOS 18, but
behind a preference that ships in the 60fps position and does not exist for WKWebView at all.

Only frameworks rendering real UIKit views reach 120Hz: React Native, SwiftUI, and Flutter.
Flutter fails on Apple platform integration (its own widget set, always trailing iOS releases,
no sanctioned OTA). That leaves React Native and SwiftUI.

## Hard rules

**The ProMotion plist key is `CADisableMinimumFrameDurationOnPhone`.** It ships on by default
through Expo's config plugins and the RN template, so you do not add it. The name
`CADisableMinimumFrameDurationClamp` circulates widely in secondary sources and appears in zero
real packages; verified by grep across a fresh Expo scaffold and t3code's installed tree. Never
cite that spelling.

**Do not build a streaming transcript on RN's built-in `Text`.** It does not sit on
TextKit/attributed-text APIs, so it cannot back a real selectable text surface at volume.
t3code renders every iOS message through `t3-markdown-text`, a Fabric component wrapping
`UITextView`, derived from Bluesky's MIT `react-native-uitextview`. This is the single most
consequential design decision in a chat-shaped app.

**Streaming text is a re-layout and re-render problem, not a frame-rate problem.** Models emit
tokens far slower than the display refreshes, so the frame budget is not the constraint. The
costs that actually bite are text re-measurement as a row grows and re-render fan-out.

**A native module is a last resort, not a performance shortcut.** Profile first. Every native
module in t3code exists because RN categorically lacks a capability (attributed text, a terminal
emulator, inline styled editable tokens), never because a screen felt janky. Going native also
crosses the OTA boundary and costs you a rebuild.

**Know where the OTA boundary sits before promising fast iteration.** EAS Update ships JS-only
changes. Anything touching native code, a config plugin, or a `patches/` entry needs a new
binary build. `runtimeVersion.policy: "fingerprint"` enforces this automatically.

**Use `expo install`, never bare `npm`/`pnpm install`, for Expo modules.** Expo's real version
enforcement is `bundledNativeModules.json`, read by `expo install` and `expo-doctor`. The `expo`
package declares a loose `"react-native": "*"` peer range, so semver will not catch a mismatch
and nothing else will either.

**RN 0.82+ ignores `newArchEnabled` but does not remove it.** Fabric is always on. The flag is
present and inert, and `RCT_NEW_ARCH_ENABLED` still appears in live podspec branches. Do not
claim it was removed, and do not trust pre-Fabric bridge patterns or `NativeModules`
registration from training data.

**Liquid Glass is iOS 26+ only**, both libraries, falling back silently to a plain `View` below
that. Gate on the availability check rather than assuming it rendered.

**Reanimated 4 moved worklets into a separate `react-native-worklets` package.** Animation must
run on the UI thread; JS-thread animation cannot hold 120Hz.

## The one that catches everyone

LegendList does not invalidate rows when the `renderItem` closure identity changes. `extraData`
drives it. Memoizing the callback does nothing for row freshness.

```tsx
// WRONG: changing this callback will not re-render rows
const renderItem = useCallback(
  ({ item }) => <Row item={item} highlighted={highlightedId === item.id} />,
  [highlightedId],
);
return <LegendList data={items} renderItem={renderItem} />;

// RIGHT: state the rows depend on goes in extraData
const listAppearanceData = useMemo(
  () => ({ highlightedId, unsettledTurnId }),
  [highlightedId, unsettledTurnId],
);
return (
  <LegendList
    data={items}
    renderItem={renderItem}
    extraData={listAppearanceData}
  />
);
```

See `~/dev/reference/t3code/apps/mobile/src/features/threads/ThreadFeed.tsx` around lines 1418 and 1919
for the real thing, including a source comment stating the behavior directly.

## Where the depth lives

All under `~/dev/knowledge-base/react-native/`:

- `SKILL.md`: entry point, version facts, and the misconceptions worth knowing before you write.
- `01-react-native-fundamentals.md`: the New Architecture (Fabric, TurboModules, JSI), the
  JS/UI thread split, Hermes, what `Text` really maps to, and uniwind styling.
- `02-expo-and-eas.md`: config plugins, prebuild and CNG, dev clients, EAS Build, and the
  EAS Update native boundary in detail. Read this before promising an iteration story.
- `03-performance-and-120hz.md`: the ProMotion key, Reanimated worklets, frame budget
  arithmetic, list virtualization (LegendList vs FlashList vs FlatList), and profiling.
- `04-streaming-text.md`: the most important doc for a chat app. Token batching, freezing
  completed messages, keeping the live tail out of the virtualized list, scroll pinning,
  incremental markdown against partial input, text re-measurement cost, and the client-side
  streaming guards (`applyLock`, `historyEpoch`).
- `05-native-modules.md`: Expo Modules API, Swift modules, Fabric components with custom
  ShadowNodes, and how local modules are actually discovered and linked.
- `06-apple-platform-integration.md`: `@expo/ui` SwiftUI components, Liquid Glass and its iOS 26
  floor, native menus, safe areas and keyboard, Dynamic Type, and hardware keyboard commands.
- `07-dev-loop-and-testing.md`: Metro in a pnpm workspace, Fast Refresh boundaries, the
  reload vs prebuild vs rebuild tiers, running on a device over the LAN, and testing patterns.

## Pair with

- `craft-frontend`: design-engineer process for distinctive frontend work. Load it before UI
  iteration; it sets craft process, this sets platform correctness.
- `no-ai-slop`: applies to any prose you write, including docs and PR bodies.

## Refresh triggers

Re-verify this skill and the knowledge base on: an Expo SDK major bump, an RN minor bump, a
Reanimated major, an iOS major release, or any change to EAS Update's runtimeVersion policies.
The 120Hz webview verdict should be rechecked if WebKit bug 294338 ever closes.

Researched and verified 2026-08-20 against live sources, `~/dev/reference/t3code`, and a fresh Expo
scaffold. Two adversarial review rounds corrected 15 defects in the underlying knowledge base,
including one fabricated version claim and two documents contradicting each other on native text
rendering. Where this file and live documentation disagree, trust the live docs and flag drift.
