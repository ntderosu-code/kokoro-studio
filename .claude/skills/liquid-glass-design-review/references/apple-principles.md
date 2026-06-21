# Apple Liquid Glass Principles

## Table of Contents
- Source basis
- Design model
- Standard controls first
- Layering rules
- Variants and tinting
- Shapes and concentricity
- Bars, sidebars, tabs, and scroll edges
- Sheets, popovers, menus, and icons
- Platform notes
- Design review questions

## Source Basis
Last reviewed: 2026-06-21.

Primary sources:
- Apple Newsroom: https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/
- Apple WWDC25, Meet Liquid Glass: https://developer.apple.com/videos/play/wwdc2025/219/
- Apple WWDC25, Get to know the new design system: https://developer.apple.com/videos/play/wwdc2025/356/
- Apple Developer, Adopting Liquid Glass: https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
- Apple HIG, Materials: https://developer.apple.com/design/human-interface-guidelines/materials
- Apple HIG, Toolbars: https://developer.apple.com/design/human-interface-guidelines/toolbars
- Apple HIG, Icons: https://developer.apple.com/design/human-interface-guidelines/icons

Some Apple documentation pages require JavaScript. If coding against current APIs, verify exact signatures in the local SDK, Xcode documentation, or live Apple Developer docs.

## Design Model
Liquid Glass is a system material for the interface layer, not a general-purpose decoration. Apple frames it as a dynamic material that reflects, refracts, adapts to context, and supports a stronger separation between content and controls.

Use it to:
- Clarify the functional layer that floats above content.
- Make controls feel directly connected to touch, pointer, focus, and system motion.
- Preserve content prominence by reducing hard dividers and heavy opaque chrome.
- Connect interactions spatially, such as a menu or sheet emerging from its source control.

Do not use it to:
- Make every surface translucent.
- Add visual interest to otherwise weak layout.
- Replace information hierarchy with blur and highlights.
- Hide persistent or high-frequency controls.

## Standard Controls First
Use standard controls and containers before custom glass. They receive system behavior, accessibility adaptation, focus handling, keyboard support, hover states, and platform styling with less risk.

Prefer:
- `Button`, `Toggle`, `Slider`, `Stepper`, `Picker`, `Menu`, `TextField`, `SearchField` or native search placement.
- `NavigationStack`, `NavigationSplitView`, `TabView`, `List`, `Table`, inspector, sheet, popover, confirmation dialog, alert, toolbar, command, and menu APIs.
- Standard toolbar and tab bar grouping APIs instead of custom HStacks that mimic bars.
- SF Symbols for recognizable actions, with text labels when the symbol is ambiguous.

Use custom glass only when:
- The control is genuinely custom.
- The surface floats above content and needs material continuity.
- Standard components cannot express the interaction.
- You can verify accessibility, contrast, focus, and fallback behavior.

## Layering Rules
Apple's guidance separates the content layer from the functional controls/navigation layer.

Apply glass to:
- Floating bars.
- Toolbars and grouped toolbar items.
- Tab bars and navigation controls.
- Sidebars and inspectors where the system supports it.
- Popovers, sheets, action surfaces, and context surfaces.
- Media-rich overlays where content remains legible.

Avoid glass on:
- Dense tables, data grids, logs, code editors, long text, article bodies, forms, and repeated content cards.
- Content that must remain visually stable for scanning or comparison.
- Nested surfaces where glass would sit on glass.
- Controls inside a glass bar if their own glass material creates stacked glass.

When putting elements on glass, prefer fills, vibrancy, labels, symbols, and selection indicators. Use another glass layer only with a strong reason and a manual legibility pass.

## Variants and Tinting
Regular is the default. Use it for most controls because it adapts to background content and supports legibility.

Clear is specialized. Use it only when all are true:
- The element sits over media-rich content.
- A dimming layer or other separation does not harm the content.
- Text or symbols above it are bold, bright, and easy to read.

Do not mix regular and clear variants in the same control group. Their behaviors differ enough that mixed groups look accidental and can undermine hierarchy.

Tinting:
- Use tint to mark a primary action, selected state, destructive/constructive semantic action, or rare point of emphasis.
- Avoid tinting every control.
- Put broad color expression in the content layer, not in every glass control.
- Verify tinted controls in light, dark, high contrast, reduce transparency, and over varied content.

## Shapes and Concentricity
Liquid Glass relies on geometry that aligns with hardware, window, and parent shapes.

Use three shape ideas:
- Fixed rounded rectangles for compact dense controls, especially on macOS.
- Capsules for touch-friendly controls, large buttons, sliders, switches, and prominent actions.
- Concentric shapes for nested surfaces where inner radius should relate to parent radius and padding.

Watch for:
- Pinched corners in nested artwork, cards, and controls.
- Flared corners near window or device edges.
- Capsule overuse in dense desktop inspectors.
- Inconsistent radii within a single bar or control group.

Platform tendency:
- iPhone and touch-first layouts can use more capsules and larger hit areas.
- iPad balances touch targets with larger spatial layouts.
- macOS mini, small, and medium controls often remain rounded rectangles; large and extra-large controls can use capsules for emphasis.

## Bars, Sidebars, Tabs, and Scroll Edges
Toolbars:
- Remove custom backgrounds, strokes, and shadows that duplicate system chrome.
- Group related actions by function and frequency.
- Keep primary actions separate and visibly emphasized.
- Do not group a text button with an icon-only button if the pair could be read as one control.
- Move secondary or infrequent actions into menus.

Tab bars:
- Keep persistent navigation distinct from screen-specific actions.
- Use search placement that matches platform conventions.
- Use accessory views for persistent cross-app features such as playback, not for contextual actions like checkout or destructive screen actions.

Sidebars:
- Let sidebars use system Liquid Glass behavior when available.
- Allow content to extend behind sidebars only when the content is visual or environmental.
- Keep text and controls above the background extension layer to avoid distortion.
- Preserve alignment and predictable selection state.

Scroll edge effects:
- Use them to separate floating controls from scrolling content.
- Do not use them as decoration when no floating UI overlaps the scroll view.
- Prefer soft effects for most iOS/iPadOS floating controls.
- Use hard effects when pinned headers, text, or controls need stronger separation, especially on macOS.
- Apply one scroll edge effect per view and avoid stacking soft and hard effects.

## Sheets, Popovers, Menus, and Icons
Sheets and popovers:
- Anchor transient surfaces to the action or context that produced them when the platform supports it.
- Use dimming when a task interrupts the main flow.
- Use glass separation without dimming when the task runs in parallel and the original context should remain active.
- Preserve keyboard and VoiceOver focus order as the surface appears.

Menus:
- Use standard menus where possible.
- Include symbols when they improve recognition.
- Use text when no symbol has a clear conventional meaning.
- Do not invent multiple near-identical icons for related text actions.
- Do not put icons beside every menu item on macOS; excessive symbols reduce scanability.

Icons:
- Use SF Symbols or platform-preferred glyphs for common actions.
- Keep the same symbol meaning across platforms.
- Avoid using the same symbol for different actions in nearby contexts.
- Provide labels or accessibility labels for icon-only controls.

## Platform Notes
iOS:
- Keep persistent controls reachable and predictable.
- Collapsing bars must remain discoverable.
- Test under dynamic content, wallpapers, media, and sunlight-like low contrast.

iPadOS:
- Support resizing and pointer/touch interchange.
- Use sidebars, tabs, and accessory views to preserve continuity across window sizes.
- Avoid treating iPad as either a large phone or a small Mac.

macOS:
- Respect density, keyboard navigation, menu conventions, focus rings, and inspector workflows.
- Avoid excessive transparency in productivity tools.
- Prefer system toolbars, split views, tables, and sidebars over custom glass panels.
- Be conservative with menu icons and clear/translucent states.

watchOS/tvOS/visionOS:
- Prioritize platform standard controls and focus systems.
- Treat motion, focus scaling, and spatial depth as accessibility-sensitive.

## Design Review Questions
- What is content, and what is control/navigation?
- Which controls can be standard components?
- Does every glass surface have a functional reason?
- Is any content harder to scan because of the material?
- Is tint reserved for priority or semantic emphasis?
- Does the shape language match platform density and parent geometry?
- Does the UI work with no motion, reduced transparency, and increased contrast?
- Are persistent controls still discoverable after scroll, resize, focus, and state changes?
