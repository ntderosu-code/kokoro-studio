# Liquid Glass Implementation Patterns

## Table of Contents
- Before coding
- SwiftUI standard-control patterns
- SwiftUI custom glass patterns
- UIKit and AppKit guidance
- Availability and fallbacks
- Performance and maintainability
- Code review checklist

## Before Coding
Verify current API availability in the local SDK or Apple Developer docs before making exact API changes. Liquid Glass shipped with OS 26-era SDKs and has continued to evolve.

Start by deleting unnecessary custom chrome:
- Custom toolbar backgrounds.
- Hand-built blur views that mimic native material.
- Stacked shadows and borders around standard controls.
- Manual opacity tricks used only to make controls feel "glassy."

Then migrate to native controls. Only after that should custom glass be considered.

## SwiftUI Standard-Control Patterns
Use the system controls that already adopt the new appearance.

Toolbar grouping:

```swift
ToolbarItemGroup(placement: .primaryAction) {
    Button {
        save()
    } label: {
        Label("Save", systemImage: "checkmark")
    }

    Menu {
        Button("Duplicate", systemImage: "doc.on.doc") { duplicate() }
        Button("Export", systemImage: "square.and.arrow.up") { export() }
    } label: {
        Label("More", systemImage: "ellipsis")
    }
}
```

Primary actions:

```swift
Button {
    commit()
} label: {
    Label("Done", systemImage: "checkmark")
}
.buttonStyle(.borderedProminent)
```

When targeting Liquid Glass SDKs, prefer native glass button styles if present in the SDK:

```swift
if #available(iOS 26.0, macOS 26.0, *) {
    Button {
        commit()
    } label: {
        Label("Done", systemImage: "checkmark")
    }
    .buttonStyle(.glassProminent)
} else {
    Button {
        commit()
    } label: {
        Label("Done", systemImage: "checkmark")
    }
    .buttonStyle(.borderedProminent)
}
```

Search:
- Prefer platform search APIs and placements over a custom glass search field.
- Keep search persistent when it is a core navigation mode.

Tabs and navigation:
- Use `TabView` for persistent top-level sections.
- Use `NavigationSplitView` for sidebar/detail layouts.
- Avoid putting screen-specific actions in a persistent tab bar or sidebar accessory.

Sheets, popovers, and menus:
- Prefer `sheet`, `popover`, `confirmationDialog`, `Menu`, and platform commands.
- Use native presentation APIs so focus, VoiceOver, modality, escape handling, and source anchoring remain correct.

## SwiftUI Custom Glass Patterns
Use custom glass for custom floating controls, small contextual surfaces, and bespoke controls that cannot be expressed with standard components.

Basic custom glass:

```swift
struct FloatingControlLabel: View {
    var body: some View {
        Label("Trim Silence", systemImage: "waveform")
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
    }
}
```

Interactive custom control:

```swift
struct FloatingAction: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Play")
    }
}
```

Grouped glass:

```swift
GlassEffectContainer(spacing: 12) {
    HStack(spacing: 12) {
        Button("Back", systemImage: "chevron.left") { goBack() }
        Button("Forward", systemImage: "chevron.right") { goForward() }
    }
    .labelStyle(.iconOnly)
}
```

Morphing transitions:

```swift
@Namespace private var glassNamespace
@State private var expanded = false

GlassEffectContainer(spacing: 12) {
    HStack(spacing: 12) {
        Button {
            withAnimation(.snappy) { expanded.toggle() }
        } label: {
            Label("Tools", systemImage: "slider.horizontal.3")
        }
        .glassEffectID("tools", in: glassNamespace)

        if expanded {
            Button("Crop", systemImage: "crop") { crop() }
                .glassEffectID("crop", in: glassNamespace)
            Button("Markup", systemImage: "pencil.tip") { markup() }
                .glassEffectID("markup", in: glassNamespace)
        }
    }
}
```

Implementation rules:
- Apply `glassEffect` after layout and visual modifiers that define the view's size and shape.
- Use `GlassEffectContainer` when multiple glass elements coexist, merge, or morph.
- Use `.interactive()` only for tappable, draggable, hoverable, focusable, or otherwise interactive elements.
- Use stable shapes for related controls.
- Keep text and symbols readable before adding animation or refraction.
- Do not use custom glass in large repeated lists or grids.

## UIKit and AppKit Guidance
Prefer standard UIKit/AppKit controls and containers first:
- Navigation bars, tab bars, toolbars, split views, sidebars, inspectors, sheets, popovers, menus, segmented controls, sliders, switches, buttons, tables, and collection/list views.
- On supported SDKs, use the platform-provided Liquid Glass APIs and updated controls rather than custom `UIVisualEffectView` or `NSVisualEffectView` compositions.
- For earlier OS fallbacks, use established system materials/effect views conservatively.

UIKit:
- Keep custom material in `UIView` subclasses limited to small floating controls or presentation surfaces.
- Preserve `UIAccessibility` labels, traits, custom actions, and focus order.
- Avoid placing transparent custom chrome over text-heavy scroll views without a separation layer.

AppKit:
- Respect `NSToolbar`, menu, focus ring, keyboard shortcut, sidebar, split view, and table conventions.
- Avoid excessive menu icons and custom translucent inspector panels.
- Test vibrancy and material choices in active/inactive windows, light/dark, increased contrast, and reduced transparency.

Because UIKit/AppKit API names can shift across SDKs, do not guess exact new Liquid Glass symbols when not present in local documentation. Inspect the SDK, use Xcode documentation, or browse Apple Developer docs first.

## Availability and Fallbacks
Gate OS-specific APIs:

```swift
if #available(iOS 26.0, macOS 26.0, *) {
    content
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
} else {
    content
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
}
```

Fallbacks should:
- Preserve the same control hierarchy and semantics.
- Avoid visual jumps in layout.
- Use standard materials rather than hand-built blur shaders.
- Keep contrast at least as strong as the Liquid Glass version.

When supporting macOS 14/15 or iOS 17/18, do not import new APIs into code paths that must compile with older SDKs unless the project uses the newest SDK with availability checks.

## Performance and Maintainability
Check for:
- Excessive real-time blur over video, canvas, maps, or large scrolling regions.
- Many independent custom glass layers where a container or standard control would suffice.
- Continuous animations that fight scrolling or pointer movement.
- Custom shaders or snapshots used to imitate glass.
- Manual color sampling that ignores accessibility modes.

Prefer:
- Native material and control APIs.
- A small set of reusable style helpers.
- Static layout and grouping rules over per-pixel custom effects.
- Snapshot/UI tests across accessibility modes for high-risk screens.

## Code Review Checklist
- Are standard controls used before custom glass?
- Are exact APIs available in the target SDK?
- Is every `#available` branch behaviorally equivalent?
- Are custom glass modifiers ordered after sizing and shape modifiers?
- Are multiple glass elements contained in `GlassEffectContainer` when they need shared rendering or morphing?
- Is `.interactive()` limited to interactive surfaces?
- Are accessibility labels, traits, focus, keyboard shortcuts, and pointer targets intact?
- Does the fallback avoid losing information, semantics, or contrast?
- Did verification include build/tests plus manual or screenshot review in accessibility modes?
