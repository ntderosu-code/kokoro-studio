# Liquid Glass Accessibility Review

## Table of Contents
- Baseline
- Test matrix
- Legibility and contrast
- Transparency, contrast, and motion settings
- Focus, keyboard, and pointer access
- VoiceOver and semantics
- Touch and pointer target size
- Dynamic Type and layout resilience
- Cognitive and discoverability checks
- Accessibility implementation snippets
- Review checklist

## Baseline
Treat WCAG 2.2 Level AA as the floor for web-like and cross-platform UI decisions, even for native apps where Apple platform guidance also applies.

Useful references:
- W3C WCAG 2.2: https://www.w3.org/TR/WCAG22/
- Apple Accessibility: https://developer.apple.com/accessibility/
- Apple HIG Accessibility: https://developer.apple.com/design/human-interface-guidelines/accessibility
- Apple Accessibility Inspector: https://developer.apple.com/documentation/accessibility/accessibility-inspector

Important WCAG anchors for Liquid Glass work:
- 1.4.3 Contrast (Minimum): normal text 4.5:1, large text 3:1.
- 1.4.11 Non-text Contrast: meaningful controls and graphical objects 3:1 against adjacent colors.
- 2.3.3 Animation from Interactions: motion triggered by interaction should be disableable unless essential.
- 2.4.7 Focus Visible and 2.4.11 Focus Not Obscured: focus must be visible and not hidden by author-created UI.
- 2.5.8 Target Size (Minimum): pointer targets have a 24 by 24 CSS pixel minimum, with exceptions. Native touch UI should usually exceed this; follow platform target guidance.

## Test Matrix
For any Liquid Glass surface, test:
- Light appearance.
- Dark appearance.
- Increased Contrast.
- Reduced Transparency.
- Reduced Motion.
- Larger text or Dynamic Type sizes where supported.
- VoiceOver.
- Keyboard-only navigation.
- Pointer hover and focus on iPad/macOS.
- Active and inactive windows on macOS.
- Over representative content: plain light, plain dark, text-heavy, colorful media, motion/video, maps/canvas, and user-chosen wallpapers where relevant.
- User-facing Liquid Glass appearance controls when present in the OS.

For high-risk UI, capture screenshots or screen recordings for each state and compare them before declaring the design accessible.

## Legibility and Contrast
Liquid Glass adapts, but adaptation is not a substitute for testing.

Check:
- Text labels on glass over dynamic content.
- Icon-only controls over varied content.
- Selected, hovered, disabled, pressed, focused, and destructive states.
- Placeholder text and secondary labels.
- Toolbar/tab/sidebar labels while content scrolls underneath.
- Menu items and command lists.

Failure signs:
- Text readability changes substantially while scrolling.
- Symbols flip between light and dark in a distracting way.
- Blur or refraction makes glyph edges shimmer.
- Selection state is visible only through color or translucency.
- Disabled state is indistinguishable from inactive-window or reduced-transparency state.

Fixes:
- Use regular glass instead of clear glass.
- Add or strengthen scroll-edge separation.
- Add dimming behind transient surfaces.
- Move the control away from high-detail content.
- Use a stronger native control style.
- Replace icon-only controls with labels when recognition is weak.
- Remove glass from the surface.

## Transparency, Contrast, and Motion Settings
Native Liquid Glass should respond to system accessibility settings. Custom layers often do not unless explicitly designed.

Reduced Transparency:
- Glass should become more opaque/frosted and obscure more content behind it.
- Do not rely on background content being visible to explain state.
- Avoid custom alpha-only implementations that become low contrast.

Increased Contrast:
- Controls should gain stronger foreground/background separation.
- Focus, selected state, and borders should remain visible.
- Custom tints must be retested; a brand color that works normally may fail here.

Reduced Motion:
- Disable or simplify elastic, morphing, parallax, shine, and continuous refraction motion.
- Keep spatial orientation through layout, labels, and source anchoring rather than animation alone.

## Focus, Keyboard, and Pointer Access
On macOS and iPadOS, Liquid Glass surfaces often sit above content. Make sure they do not hide focus or trap keyboard movement.

Check:
- Tab order follows visual order.
- Escape closes transient glass surfaces.
- Focus rings remain visible against glass and content.
- A focused field or button is not covered by a floating bar, sheet, or accessory.
- Menus and popovers return focus to the invoking control.
- Hover and pointer feedback are present but not required to understand the UI.

Do not remove system focus rings to make glass look cleaner. If a custom focus treatment is necessary, it must be at least as visible as the platform default.

## VoiceOver and Semantics
For standard controls, preserve the native semantic role. For custom glass, add explicit semantics.

Check:
- Icon-only controls have `accessibilityLabel`.
- Toggle-like controls expose selected/on/off state.
- Sliders expose value, range, and increment/decrement behavior.
- Grouped toolbar controls are not announced as a single ambiguous item.
- Menus, sheets, and popovers announce their purpose and do not strand focus.
- Decorative glass, highlights, and background extensions are hidden from assistive technologies.

## Touch and Pointer Target Size
Use platform standard controls wherever possible because they provide target sizes and hit areas.

For custom controls:
- Touch-first controls should generally provide at least a 44 by 44 point hit area.
- Pointer-first macOS controls can be visually smaller, but must remain targetable and keyboard accessible.
- Do not make the visible glass shape much smaller than the hit target without a clear reason; it can confuse users.
- Increase spacing between adjacent icon-only controls to reduce accidental activation.

## Dynamic Type and Layout Resilience
Liquid Glass often uses compact rounded shapes. Text expansion can break them.

Check:
- Labels do not clip inside capsules.
- Larger text does not force toolbar groups into unreadable clusters.
- Important text buttons do not become ambiguous icons when space is constrained.
- Popovers and sheets resize without hiding focused controls.
- Localization with longer labels still works.

Prefer:
- Standard controls that adapt automatically.
- Menus for secondary actions.
- Text labels for ambiguous symbols.
- Layouts that allow wrapping or promotion to overflow rather than clipping.

## Cognitive and Discoverability Checks
Liquid Glass can hide or collapse controls to emphasize content. Use this carefully.

Check:
- Users can identify persistent navigation at rest.
- High-frequency actions are not hidden behind changing or unlabeled icons.
- Critical actions do not move unpredictably between platforms or window sizes.
- Motion and morphing communicate a source/target relationship, not decoration.
- Color, transparency, or shape alone is not the only indicator of state.
- Repeated actions keep the same symbol and label across the app.

## Accessibility Implementation Snippets
SwiftUI environment values:

```swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
@Environment(\.accessibilityReduceMotion) private var reduceMotion
@Environment(\.accessibilityContrast) private var accessibilityContrast
@Environment(\.dynamicTypeSize) private var dynamicTypeSize
```

Custom fallback example:

```swift
var body: some View {
    Label("Enhance", systemImage: "wand.and.sparkles")
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            if reduceTransparency || accessibilityContrast == .increased {
                Capsule().fill(.regularMaterial)
            } else if #available(iOS 26.0, macOS 26.0, *) {
                Capsule().fill(.clear)
            } else {
                Capsule().fill(.ultraThinMaterial)
            }
        }
        .accessibilityLabel("Enhance audio")
}
```

Motion gating:

```swift
withAnimation(reduceMotion ? nil : .snappy) {
    isExpanded.toggle()
}
```

Prefer native controls and native Liquid Glass adaptation over custom conditionals when the SDK provides them.

## Review Checklist
- Did the review include reduced transparency, increased contrast, and reduced motion?
- Did it include dynamic content behind glass, not just a clean mockup?
- Do text and icons pass contrast expectations in every meaningful state?
- Are focus indicators visible and unobscured?
- Are controls reachable by keyboard and assistive technologies?
- Are touch/pointer targets large enough and spaced enough?
- Does the UI remain understandable without motion, transparency, or color?
- Are custom glass effects hidden from accessibility when decorative?
- Are standard controls used wherever possible?
