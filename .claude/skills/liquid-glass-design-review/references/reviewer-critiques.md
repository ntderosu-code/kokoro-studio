# Liquid Glass Reviewer and Developer Critique Heuristics

## Table of Contents
- Source basis
- How to use critiques
- Common failure modes
- Positive design opportunities
- Review severity guide
- Critique checklist

## Source Basis
Last reviewed: 2026-06-21.

Public coverage and critique:
- Wired, designers react to Liquid Glass readability concerns: https://www.wired.com/story/designers-react-to-apple-liquid-glass/
- Wired, Liquid Glass as a divisive system design: https://www.wired.com/story/liquid-glass-could-be-one-of-apples-most-divisive-system-designs-yet/
- The Verge, first-look critique: https://www.theverge.com/apple/682833/apples-liquid-glass-redesign-doesnt-look-like-much
- The Verge, Apple made Liquid Glass more frosted in beta: https://www.theverge.com/news/700066/apple-liquid-glass-frosted-ios-26-developer-beta
- The Verge, user controls for clearer/tinted Liquid Glass in iOS 26.1 beta: https://www.theverge.com/news/802963/apple-liquid-glass-ios-26-1-beta-tint-option
- TechRadar, macOS menu icon backlash and later guideline correction: https://www.techradar.com/computing/glaringly-inconsistent-and-often-utterly-inscrutable-macos-27-golden-gate-just-fixed-one-of-my-biggest-macos-tahoe-gripes

These sources are not normative. Use them to stress-test a design against real usability concerns that Apple demos and API docs may underemphasize.

## How to Use Critiques
Translate opinion into testable questions:
- "Hard to read" becomes: Which labels or symbols fail contrast or become unstable over realistic backgrounds?
- "Distracting" becomes: Which effects draw attention away from the user's content or task?
- "Controls disappear" becomes: Which frequent or critical actions lose discoverability, reachability, or muscle memory?
- "Too much iconography" becomes: Which icons add noise without improving recognition?
- "Small teams cannot match Apple" becomes: Which custom effects should be deleted in favor of standard controls?

Do not reject Liquid Glass because critics dislike it. Reject or revise a specific use when it fails clarity, accessibility, task flow, or maintainability.

## Common Failure Modes
Legibility failures:
- Text over transparent controls changes readability while content scrolls.
- Icons rely on refraction or highlight to separate from content.
- Clear glass appears attractive in a mockup but fails over user content.
- Tinted controls do not hold contrast in high contrast or reduced transparency modes.

Distraction failures:
- Refraction, shine, or morphing competes with the task.
- A toolbar is more visually prominent than the content it controls.
- Background motion visible through controls draws the eye during reading or editing.
- Too many controls use tint, making no action feel primary.

Hierarchy failures:
- Content cards use glass and compete with navigation glass.
- Glass appears inside glass bars.
- Persistent navigation and contextual actions share the same surface.
- Primary and secondary actions are grouped as if equal.

Discoverability failures:
- Important controls collapse or vanish without a stable affordance.
- A symbol-only action has no obvious meaning.
- A menu uses many icons that repeat, conflict, or add clutter.
- Similar actions use different symbols across app sections.

Platform-fit failures:
- macOS productivity UI becomes touch-sized, translucent, and low-density without need.
- iPad resizing breaks the relationship between sidebar, tab bar, and content.
- iPhone chrome hides too aggressively, making frequent actions harder to reach.
- Pointer hover and keyboard focus states are missing because the design was tested only by touch.

Maintenance failures:
- Custom blur and opacity code imitates system material poorly.
- Pixel-perfect mockups depend on one background image.
- Brand color is embedded in every glass control.
- Fallback UI is less accessible than the Liquid Glass path.

## Positive Design Opportunities
Liquid Glass can help when it:
- Gives controls a clear functional layer over immersive media or canvas content.
- Makes a transient menu or sheet feel spatially connected to its source.
- Reduces hard dividers while preserving a readable boundary with scroll-edge effects.
- Lets content feel more expansive by moving navigation into a restrained floating layer.
- Adds delight to a low-frequency moment without slowing frequent work.
- Uses motion to preserve orientation during expansion, collapse, or context changes.

Use this standard: if the effect improves orientation, hierarchy, or emotional quality without harming speed or accessibility, it can stay.

## Review Severity Guide
Critical:
- Text, focus, or controls are unreadable or unreachable in common modes.
- VoiceOver, keyboard, or reduced-motion access is broken.
- Important actions disappear or become ambiguous during core workflows.

High:
- Custom glass replaces standard controls without preserving semantics.
- Glass sits on glass or content is glassed broadly enough to collapse hierarchy.
- Clear/translucent surfaces fail over realistic content.

Medium:
- Tint is overused.
- Icons are inconsistent or redundant.
- Motion is decorative and distracting but not blocking.
- macOS density or menu conventions are weakened.

Low:
- Shape radii feel inconsistent but do not affect use.
- A standard control could make the UI more native with minimal change.
- A visual effect is slightly too prominent in one state.

## Critique Checklist
- What would a skeptical reviewer call hard to read?
- What would a frequent user say moved, disappeared, or became slower?
- What would a low-vision user lose in clear glass, reduced transparency, or high contrast?
- What would a keyboard or VoiceOver user lose when a surface morphs?
- What would a Mac user find too touch-first or too icon-heavy?
- What would a small team regret maintaining six months from now?
- Which part of the design is actually better because it is Liquid Glass?
