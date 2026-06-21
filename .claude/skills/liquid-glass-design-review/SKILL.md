---
name: liquid-glass-design-review
description: Design, implement, and review Apple Liquid Glass interfaces across SwiftUI, UIKit, AppKit, iOS, iPadOS, macOS, tvOS, watchOS, and visionOS. Use when adopting Liquid Glass, designing iOS 26/macOS 26+ UI, reviewing glass effects for legibility and accessibility, migrating custom chrome to standard controls, or auditing toolbar, sidebar, tab bar, sheet, popover, menu, icon, tint, scroll-edge, and custom glass usage.
---

# Liquid Glass Design Review

## Overview
Use this skill to help an agent make Apple-platform UI feel native to Liquid Glass without sacrificing clarity, accessibility, or maintainability. Prefer standard controls and system behaviors first; use custom glass only when it solves a specific interaction or hierarchy problem that standard controls cannot.

Liquid Glass guidance changes with Apple SDKs and OS releases. When making API-specific changes, verify the current Apple Developer documentation or local SDK symbols before coding.

## Reference Routing
Load only the references needed for the task:

- `references/apple-principles.md`: Load for design direction, visual hierarchy, component behavior, platform conventions, and Apple source summaries.
- `references/implementation-patterns.md`: Load before writing or reviewing SwiftUI, UIKit, or AppKit code.
- `references/accessibility-review.md`: Load for any review, any custom glass, any tinting, or any UI that places controls over dynamic content.
- `references/reviewer-critiques.md`: Load when asked to critique, polish, harden, or judge whether Liquid Glass helps or hurts the product.

For substantial implementation work, read `apple-principles.md`, `implementation-patterns.md`, and `accessibility-review.md` before editing. For pure visual critique, read `apple-principles.md`, `accessibility-review.md`, and `reviewer-critiques.md`.

## Operating Rules

1. Start with standard controls. Prefer `Button`, `Toggle`, `Slider`, `Picker`, `Menu`, `TabView`, `NavigationStack`, `NavigationSplitView`, `ToolbarItem`, `sheet`, `popover`, lists, tables, and platform command/menu APIs before custom drawing.
2. Keep Liquid Glass in the control and navigation layer. Do not turn content cards, tables, dense inspectors, article bodies, or data grids into glass unless there is a strong, testable reason.
3. Avoid glass on glass. When content sits on a glass surface, use labels, symbols, vibrancy, fills, or thin overlays rather than another glass material.
4. Treat legibility as a hard requirement. If a control cannot remain readable over realistic content, use the regular material, a stronger background, dimming, a scroll-edge effect, or no glass.
5. Use tint sparingly. Tint primary actions and semantically important controls; do not tint every control.
6. Preserve discoverability. Do not hide essential navigation or frequent actions only to show content. Collapsing chrome must remain obvious, reachable, and consistent.
7. Respect platform density. iPhone can use larger capsule-heavy controls; macOS inspector panels and dense tool surfaces often need smaller rounded-rectangle controls and less visual flourish.
8. Test accessibility modes. Native Liquid Glass adapts to Reduce Transparency, Increase Contrast, and Reduce Motion; custom layers must be checked manually.

## Workflow

### Designing New UI
1. Inventory the content layer, persistent navigation, contextual actions, transient actions, and modal tasks.
2. Map each control to the most native standard component available.
3. Decide where glass is useful: navigation bars, floating controls, tab bars, sidebars, sheets, popovers, media controls, or small contextual controls.
4. Specify shape, grouping, tint, scroll-edge behavior, and accessibility states before code.
5. Remove decorative backgrounds, borders, and custom blur that duplicate system emphasis.

### Implementing
1. Verify SDK/API availability for the target OS versions.
2. Implement standard controls first and let the system adopt Liquid Glass.
3. Add custom glass only for custom controls or custom floating surfaces.
4. Gate OS-specific APIs with availability checks and provide earlier-OS fallbacks.
5. Run the relevant build, tests, and UI checks for the host project.

### Reviewing
Lead with issues, ordered by severity. For each issue, identify the affected component, why it violates Liquid Glass or accessibility guidance, and the smallest practical fix. Separate design concerns from code/API concerns.

Review these dimensions:

- Standard controls: Is the UI reinventing controls the system already provides?
- Layering: Is glass limited to controls/navigation, or is content competing with chrome?
- Legibility: Does text, glyph, focus, and selected state remain clear over real content?
- Accessibility: Are Reduce Transparency, Increase Contrast, Reduce Motion, keyboard focus, VoiceOver, Dynamic Type, and target sizes handled?
- Platform fit: Does the design adapt between iPhone, iPad, Mac, and pointer/touch contexts?
- Motion: Do morphing and hiding behaviors aid orientation rather than distracting?
- Maintenance: Is the implementation relying on brittle custom blur, opacity, or screenshots?

## Output Expectations

For design plans, include:

- Component inventory.
- Liquid Glass placement decisions.
- Standard controls to use.
- Accessibility and test matrix.
- Open questions or assumptions.

For code changes, include:

- File references and concise rationale.
- Availability/fallback notes.
- Verification commands and results.
- Any residual accessibility risk that still needs manual inspection.
