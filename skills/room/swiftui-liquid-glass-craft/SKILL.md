---
name: swiftui-liquid-glass-craft
description: Use when building or reviewing SwiftUI UI for the NASDOOM app — iOS 26 Liquid Glass adoption, SF Symbol animation, and native-feeling component craft, so the result reads as a considered native app instead of a generic SwiftUI template. For general Vapor/Fluent work or non-NASDOOM SwiftUI, use `swift-vapor-swiftui-professional` instead.
---

# SwiftUI Liquid Glass & Native Craft — NASDOOM

NASDOOM targets iOS 26 minimum, Swift 6, and ships its own design language (NASDOOMKit: `NDColor`, `NDSpacing`, `NDRadius`, `NDFont`, `Pill`, `NeuCard`, `Icon`, `NDPressable`) plus a fully custom bottom tab bar (`PadBar`) that intentionally avoids native `TabView` chrome to keep tab state alive across switches. This doc reconciles Apple's iOS 26 Liquid Glass system with that reality — where to adopt it straight, where to fake it deliberately, and where native tricks are simply off the table.

## 1. The 5 rules that break things if you violate them

1. **Glass cannot sample glass.** Any time more than one `glassEffect()` view sits near another, wrap them in a single `GlassEffectContainer`. Uncoordinated overlapping glass produces double-processed, incoherent results — this isn't a style preference, it's how the sampling pass works. One container per visually-grouped cluster (e.g. one for a floating action cluster), not one per item.
2. **Liquid Glass belongs on the chrome layer, never the content layer.** Nav bars, toolbars, floating controls, sheets, `PadBar` itself — yes. List rows, cards, body content, anything that scrolls — no, use a standard `Material` (`.ultraThinMaterial` etc.) or a flat token-driven fill there instead. The one named exception is a slider/toggle taking on a glass look only while actively being dragged.
3. **Never mix `.regular` and `.clear` glass in one visual cluster**, and treat `.clear` as rare — it requires media-rich, bold/bright content behind it and no adaptivity, so it's wrong for anything with real text or on NASDOOM's near-black surfaces.
4. **Tint one control per group, never the whole cluster.** `Glass.tint(_:)` is for marking the single primary action (e.g. the "Grab" button), not a decorative pass over every button in a toolbar. Also: tint on custom glass has a documented, unexplained failure mode where it silently drops on views ≥65pt tall or against certain backgrounds after a state change — spot-check every concrete instance at real size, don't trust it to "just render" from a token.
5. **A near-black theme gets legibility "for free" only if you actually feed it real content.** Glass keys off live pixel luminosity behind it, not a `.preferredColorScheme` flag — over genuine near-black backgrounds it renders dark correctly, but bright thumbnails/posters (which NASDOOM has everywhere — Plex art, episode stills) will locally lighten a glass bar in just that region. Test glass surfaces against real poster art, not solid dark mockups. And even in an all-dark app, still ship both light and dark color variants in asset catalogs — the system may need both to render legibly against varying local luminosity.

Corollary rule for correctness, not just polish: prefer toggling `Glass.regular` ↔ `Glass.identity` over structurally adding/removing the `.glassEffect()` modifier — avoids layout recalculation and is the documented way to conditionally disable glass.

## 2. Reconciling Liquid Glass with PadBar and NASDOOMKit

**PadBar keeps its custom implementation. Do not migrate it to native `TabView`.** The reason it exists (tab state staying alive across switches) is a real architectural constraint that native `TabView` doesn't solve for free, and none of the Liquid Glass tab-bar wins are worth breaking that. Concretely, here's what PadBar gets and doesn't get:

**What PadBar SHOULD adopt directly:**

- Apply `.glassEffect(.regular.interactive())` to PadBar's own container view. This is the officially-supported minimal path for custom chrome and is explicitly documented as working on arbitrary custom views, not just native components.
- Since PadBar sits over scrolling content, give scrollable screens the automatic iOS 26 scroll-edge effect for free (it's on by default under any `ScrollView`/`List`/`Form`) — don't fight it, and only reach for `.scrollEdgeEffectStyle(_:for:)` / `.scrollEdgeEffectHidden(_:for:)` if PadBar's own translucency plus the system's default double up and look muddy.
- If NASDOOM's dark posters/backgrounds cause the same "washed out glass over dark content" problem other dark-themed apps hit, use the **content-fade workaround**, not more tint: apply a bottom gradient to the scrolling content (transparent → ~85%-opacity background color) so content has faded to solid before it reaches PadBar's glass. This is a proven fix from a shipped dark-content app for exactly this failure mode — tint alone is unreliable (see rule 4) and won't fix it.

**What PadBar CANNOT get, full stop:**

- `Tab(role: .search)` — the separated search capsule, its morph-into-search-field animation, and the automatic Liquid Glass materials on it are rendered by `TabView`/`Tab` system machinery. This is not a modifier you can attach to an arbitrary `HStack`; Apple does not expose it as a standalone reusable component. If PadBar is staying custom, this feature is categorically off the table.
- `tabBarMinimizeBehavior` (only fires over _scrolling_ content under native `TabView`) and `tabViewBottomAccessory` (renders on every tab, not tab-specific) — both are native-`TabView`-only APIs with no custom equivalent.

**The actual NASDOOM search pattern, given the above:** since a `Tab(role: .search)` is unreachable, build search as a `.searchable()` attachment on the relevant `NavigationStack`-hosted screen(s), NOT as a slot in PadBar. Use `.navigationBarDrawer(displayMode: .automatic)` or `.toolbar` placement per screen, and consider the iOS 26 bottom-toolbar search pattern (`DefaultToolbarItem(kind: .search, placement: .bottomBar)` + `.searchToolbarBehavior(.minimize)`) for screens where search should live near thumb reach without requiring a PadBar tab at all. This gets NASDOOM the native glass search field, VoiceOver/Dynamic Type wiring, and iOS 26 placement conventions, while PadBar keeps owning navigation only — which also happens to match current HIG guidance that tab bars should be pure navigation, not dual-purpose action surfaces.

**Design-token discipline for glass, specifically:** don't let `.glassEffect()` calls scatter through screens with slightly different parameters. Add glass as one more layer in the existing NASDOOMKit token system — e.g. a single internal helper (`NDGlass.chrome`, `NDGlass.primaryAction`) that wraps the approved `Glass` recipes (which variant, which tint, which container spacing) so screens never call `.glassEffect()` directly with hand-picked values. Gate every call behind `#available(iOS 26, *)` with the existing `NeuCard`/material fallback for anything that might need to run pre-26 later, even though 26 is the current floor — cheap insurance, and keeps the "base material layer swappable" property other teams found valuable mid-migration.

## 3. Before/after: migrating `Pill.brandOutline` from faked glass to real glass

**Before** (current pattern — faking glass with a static material, tuned shadow/border values baked in):

```swift
struct Pill: View {
    enum Style { case brandOutline, filled, subtle }
    let style: Style
    let label: String

    var body: some View {
        Text(label)
            .font(NDFont.pill)
            .padding(.horizontal, NDSpacing.md)
            .padding(.vertical, NDSpacing.sm)
            .background(
                Group {
                    if style == .brandOutline {
                        RoundedRectangle(cornerRadius: NDRadius.pill, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: NDRadius.pill, style: .continuous)
                                    .stroke(NDColor.brand, lineWidth: 1)
                            )
                    }
                }
            )
    }
}
```

**After** (real Liquid Glass, iOS 26-gated, container-aware, token-routed):

```swift
struct Pill: View {
    enum Style { case brandOutline, filled, subtle }
    let style: Style
    let label: String

    var body: some View {
        Text(label)
            .font(NDFont.pill)
            .padding(.horizontal, NDSpacing.md)
            .padding(.vertical, NDSpacing.sm)
            .modifier(PillBackground(style: style))
    }
}

private struct PillBackground: ViewModifier {
    let style: Pill.Style

    func body(content: Content) -> some View {
        if #available(iOS 26, *), style == .brandOutline {
            content.glassEffect(
                .regular.tint(NDColor.brand.opacity(0.35)),
                in: .rect(cornerRadius: NDRadius.pill, style: .continuous)
            )
        } else {
            // pre-26 / non-glass styles: existing material fallback, unchanged
            content.background(
                RoundedRectangle(cornerRadius: NDRadius.pill, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: NDRadius.pill, style: .continuous)
                            .stroke(NDColor.brand, lineWidth: 1)
                    )
            )
        }
    }
}
```

Caller sites that place multiple `.brandOutline` pills adjacent to each other (e.g. a filter row) must wrap the row in one `GlassEffectContainer`, not rely on each `Pill` self-containing its own glass pass:

```swift
GlassEffectContainer(spacing: NDSpacing.sm) {
    HStack(spacing: NDSpacing.sm) {
        ForEach(activeFilters) { filter in
            Pill(style: .brandOutline, label: filter.title)
        }
    }
}
```

Notes on what changed and why:

- Radius comes from the existing `NDRadius.pill` token routed through `.rect(cornerRadius:style: .continuous)` — no hand-picked literal, and `.continuous` matches system chrome instead of a circular-arc squircle mismatch.
- Tint uses `NDColor.brand` at low opacity through `Glass.tint(_:)` rather than a hand-drawn stroke — this is the one-tinted-element-per-group case (a filter pill _is_ the primary/active-state signal in its row), so it's a legitimate use of tint, not decoration.
- Because pills at ≥65pt-tall or on unusual backgrounds have a known tint-drop bug (§1 rule 4), spot-check `Pill(style: .brandOutline)` at every size it actually ships in (compact filter chip vs. large hero pill) before trusting it renders consistently.
- Row-level `GlassEffectContainer` is mandatory the moment two or more pills render side by side — that's the "glass cannot sample glass" rule in practice.

## 4. Symbol/icon animation checklist for a media-library app

Only animate when the animation carries semantic meaning the user needs. Static is the default; motion is the exception.

| NASDOOM UI moment                                   | Effect                                          | Trigger pattern                            | Why                                                                                                                          |
| --------------------------------------------------- | ----------------------------------------------- | ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| Download/import in progress (queue row)             | `.pulse` or `.breathe`, `isActive:` gated       | `isActive: item.isDownloading`             | Ambient "still working," cheap to have 2-3 running at once in a visible viewport                                             |
| Item just added to library / grab confirmed         | `.bounce`, `value:` gated                       | `value: addedCount` (increment on success) | One-shot, discrete, reads as acknowledgment                                                                                  |
| New notification (friend request, alert)            | `.wiggle`, one-shot on arrival                  | `value: notificationID`                    | Matches system semantic of "don't miss this"; don't loop it forever                                                          |
| Play/Pause toggle                                   | `.replace` via `.contentTransition`             | swap `systemName` on tap                   | Purpose-built two-state icon swap, gets Magic Move morphing for free                                                         |
| Search/refresh in flight                            | `.rotate`, `options: .repeating`                | while request active                       | Standard "spinning = working" metaphor                                                                                       |
| Plex/seedbox reachability, signal-style status      | `.variableColor.iterative` or `.cumulative`     | gated on live/degraded state               | Matches Apple's own wifi/signal-bar usage                                                                                    |
| PadBar tab icons at rest                            | **no effect**                                   | —                                          | Constant-visible chrome; looping animation here is the textbook "everything animates, nothing means anything" failure        |
| Row status icons in a long list (every episode row) | **no effect**, or discrete-only on state change | —                                          | Never run indefinite/looping effects at list scale — reserve looping for the handful of items actually live/active on screen |
| Disclosure chevrons, static nav glyphs              | **no effect**                                   | —                                          | Purely structural; animating it is noise                                                                                     |

Mechanical notes:

- Discrete effects (`.bounce`, one-shot `.wiggle`) fire via `.symbolEffect(_:value:)` — value just needs to change identity, not change to anything specific.
- Indefinite effects (`.pulse`, `.breathe`, `.rotate`, `.variableColor` looping) fire via `.symbolEffect(_:isActive:)` or bare `.symbolEffect(_:options: .repeating)`.
- Reduce Motion is handled automatically by the system for all built-in symbol effects (dampened/suppressed/falls back to crossfade) — don't write manual `accessibilityReduceMotion` branches around these unless you need a hard override beyond what the system already does.
- `.variableColor` requires a symbol actually drawn with variable-color layers (wifi, battery, signal bars) — it's a no-op or wrong choice on symbols not designed for it.

## 5. "Still looks templated" smells — quick review checklist

Flag any of these on sight, in NASDOOM or any SwiftUI screen:

- **Emoji used as a functional icon** (nav button, tab item, status glyph) instead of an SF Symbol via `Icon`/`Image(systemName:)`.
- **Stock unstyled `Button`** — default system-blue text, no background, no shape, no press response. Every tappable control in NASDOOM should route through an `NDPressable`-backed style.
- **Missing press/haptic feedback** — a control that gives zero visual or tactile signal on tap until the destination screen appears. Expected baseline: scale ~0.92–0.95 over ~150–220ms plus a `.sensoryFeedback()` case matched to the action's semantics (not a generic impact for everything).
- **Uniform corner radius with no rhythm** — every card/button/sheet using the same raw `cornerRadius(8)` regardless of role/size instead of routing through `NDRadius` tokens with `.continuous` style.
- **Raw literals instead of tokens** — any `Color(hex:)`, `.font(.system(size:))`, or bare `.padding(14)` inside a screen file instead of `NDColor` / `NDFont` / `NDSpacing`.
- **`.circular` corner style where system chrome would use `.continuous`** — visible tangent discontinuity where the arc meets a straight edge; NASDOOMKit shapes should default to `.continuous` unless deliberately matching a non-Apple pattern.
- **Default `.insetGrouped` list styling used for content that isn't settings-like** — reads as an unstyled Settings-app clone rather than a designed media browser.
- **Flat single-color fills where a material or shadow should signal depth** — floating/elevated elements (FABs, dragged cards, detached sheets) with no shadow at all; OR conversely, content-layer rows/cards carrying an unnecessary shadow or glass fill they shouldn't have. Depth should mark hierarchy, not decorate everything.
- **Glass stacked on glass without a `GlassEffectContainer`**, or `.regular` and `.clear` mixed in one visually grouped cluster.
- **More than one tinted control in a group** (a whole toolbar tinted the same color instead of just the primary action).
- **Continuous/looping symbol animation on chrome or list-scale elements** (PadBar icons, every row in a long list) — see §4.
- **Custom search field built from scratch with no concrete reason** — default to `.searchable()`; a bespoke search UI should only exist because of a named constraint (inline content filter, non-text input, cross-platform parity requirement), not "for polish."

## References

- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [glassEffect(_:in:)](<https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)>)
- [Glass structure](https://developer.apple.com/documentation/swiftui/glass)
- [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [Materials — HIG](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Color — HIG](https://developer.apple.com/design/human-interface-guidelines/color)
- [Layout — HIG](https://developer.apple.com/design/human-interface-guidelines/layout)
- [SF Symbols — HIG](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
- [Meet Liquid Glass — WWDC25 session 219](https://developer.apple.com/videos/play/wwdc2025/219/) via [WWDCNotes](https://wwdcnotes.com/documentation/wwdc25-219-meet-liquid-glass/)
- [Get to know the new design system — WWDC25 session 356](https://developer.apple.com/videos/play/wwdc2025/356/)
- [Build a SwiftUI app with the new design — WWDC25 session 323](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Optimize SwiftUI performance with Instruments — WWDC25 session 306](https://developer.apple.com/videos/play/wwdc2025/306/)
- [conorluddy/LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference) — community reference, corroborating only
- [Swift with Majid — Glassifying custom SwiftUI views](https://swiftwithmajid.com/2025/07/16/glassifying-custom-swiftui-views/)
- [Donny Wals — Designing custom UI with Liquid Glass on iOS 26](https://www.donnywals.com/designing-custom-ui-with-liquid-glass-on-ios-26/)
- [Donny Wals — Exploring tab bars on iOS 26 with Liquid Glass](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/)
- [Donny Wals — Opting your app out of the Liquid Glass redesign with Xcode 26](https://www.donnywals.com/opting-your-app-out-of-the-liquid-glass-redesign-with-xcode-26/)
- [Itsuki — SwiftUI: Some Really Interesting (Annoying) Glass Effect Tint Behavior](https://medium.com/@itsuki.enjoy/swiftui-some-really-interesting-annoying-glass-effect-tint-behavior-58aea8bf8866)
- [Matej Kokošinek — Liquid Glass Migration, Real World Example, Part 1](https://medium.com/@matej-kokosinek/liquid-glass-migration-real-world-example-part-1-c1a840dd270f)
- [Yuvi Zalkow — Deliquified Glass: a SwiftUI Hack](https://medium.com/@yuvizalkow/deliquified-glass-a-swiftui-hack-82e62e1b4ffd)
- [Fatbobman — Grow on iOS 26: Liquid Glass Adaptation in UIKit + SwiftUI Hybrid Architecture](https://fatbobman.com/en/posts/grow-on-ios26/)
- [MacRumors — iOS 26.1 Transparency Toggle Changes Liquid Glass](https://www.macrumors.com/2025/10/20/ios-26-1-transparency-option-liquid-glass/)
- [Six Colors — Soaping up Liquid Glass: less transparency, more contrast](https://sixcolors.com/post/2025/11/soaping-up-liquid-glass-less-transparency-more-contrast/)
- [openclaw PR #98452 — token-based Liquid Glass migration case study](https://github.com/openclaw/openclaw/pull/98452)
- [scrollEdgeEffectStyle(_:for:)](<https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)>)
- [scrollEdgeEffectHidden(_:for:)](<https://developer.apple.com/documentation/swiftui/view/scrolledgeeffecthidden(_:for:)>)
- [sharedBackgroundVisibility(_:)](<https://developer.apple.com/documentation/swiftui/customizabletoolbarcontent/sharedbackgroundvisibility(_:)>)
- [SearchFieldPlacement](https://developer.apple.com/documentation/swiftui/searchfieldplacement)
- [Tab init(_:image:value:role:content:)](<https://developer.apple.com/documentation/swiftui/tab/init(_:image:value:role:content:)>)
- [TabRole](https://developer.apple.com/documentation/swiftui/tabrole)
- [searchToolbarBehavior(_:)](<https://developer.apple.com/documentation/swiftui/view/searchtoolbarbehavior(_:)>)
- [DefaultToolbarItem](https://developer.apple.com/documentation/swiftui/defaulttoolbaritem)
- [ToolbarSpacer](https://developer.apple.com/documentation/swiftui/toolbarspacer)
- [navigationBarTitleDisplayMode(_:)](<https://developer.apple.com/documentation/swiftui/view/navigationbartitledisplaymode(_:)>)
- [nilcoalescing.com — SwiftUI Search Enhancements in iOS and iPadOS 26](https://nilcoalescing.com/blog/SwiftUISearchEnhancementsIniOSAndiPadOS26/)
- [WWDC23 — Animate symbols in your app](https://developer.apple.com/videos/play/wwdc2023/10258/)
- [WWDC24 — What's new in SF Symbols 6](https://developer.apple.com/videos/play/wwdc2024/10188/)
- [WWDC25 — What's new in SF Symbols 7](https://developer.apple.com/videos/play/wwdc2025/337/)
- [symbolEffect(_:options:value:)](<https://developer.apple.com/documentation/SwiftUI/View/symbolEffect(_:options:value:)>)
- [SymbolEffectOptions](https://developer.apple.com/documentation/symbols/symboleffectoptions)
- [Sarunw — Animate SF Symbols with symbolEffect](https://sarunw.com/posts/animate-sf-symbols-with-symboleffect/)
- [Donny Wals — Animating SF Symbols on iOS 18](https://www.donnywals.com/animating-sf-symbols-on-ios-18/)
- [Blake Crosley — Symbol Effects: SwiftUI's Built-In Animation Vocabulary](https://blakecrosley.com/blog/symbol-effects-vocabulary)
- [SerialCoder.dev — Exploring Draw Effects and Gradient Rendering in SF Symbols](https://serialcoder.dev/text-tutorials/swiftui/exploring-draw-effects-and-gradient-rendering-in-sf-symbols/)
- [Apple Developer Docs — RoundedCornerStyle.continuous](https://developer.apple.com/documentation/swiftui/roundedcornerstyle/continuous)
- [Sarunw — SwiftUI List Style examples](https://sarunw.com/posts/swiftui-list-style/)
- [Hacking with Swift — Grouped/inset grouped lists](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-grouped-and-inset-grouped-lists)
- [Hacking with Swift — Adding haptic effects](https://www.hackingwithswift.com/books/ios-swiftui/adding-haptic-effects)
- [Swift by Sundell — Applying rounded corners to a UIKit or SwiftUI view](https://www.swiftbysundell.com/articles/rounded-corners-uikit-swiftui/)
- [Cargath — Continuous corners in SwiftUI](https://cargath.github.io/blog/2019/06/23/SwiftUI-Rounded-Corners)
- [Liam Rosenfeld — My Quest for the Apple Icon Shape](https://liamrosenfeld.com/posts/apple_icon_quest/)
- [Create with Swift — Understanding Spring Animations in SwiftUI](https://www.createwithswift.com/understanding-spring-animations-in-swiftui/)
- [Codakuma — Adding haptic feedback to buttons in SwiftUI](https://codakuma.com/swiftui-haptics/)
- [DEV Community — Micro-Interactions in SwiftUI](https://dev.to/sebastienlato/micro-interactions-in-swiftui-subtle-animations-that-make-apps-feel-premium-2ldn)
- [DEV Community — Master SwiftUI Design Systems](https://dev.to/swift_pal/master-swiftui-design-systems-from-scattered-colors-to-unified-ui-components-4i9c)
- [DEV Community — SwiftUI Design Tokens & Theming System (Production-Scale)](https://dev.to/sebastienlato/swiftui-design-tokens-theming-system-production-scale-b16)
- [freeCodeCamp — How to build a design system with SwiftUI](https://www.freecodecamp.org/news/how-to-build-design-system-with-swiftui/)
- [Think-it — Atomic design system using SwiftUI](https://think-it.io/insights/Atomic-Design-System-in-SwiftUI)
- [Cieden — Spacing best practices](https://cieden.com/book/sub-atomic/spacing/spacing-best-practices)
- [iosapptemplates — Liquid Glass in SwiftUI](https://iosapptemplates.com/blog/liquid-glass-swiftui-app-template-modernization/)
- [byteiota — iOS 27 Makes Liquid Glass Mandatory](https://byteiota.com/ios-27-makes-liquid-glass-mandatory-act-before-april-2027/)
