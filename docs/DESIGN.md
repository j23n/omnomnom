# Design

Decisions for how the app looks and behaves. Written down so the next feature does not drift.

## Direction

Stock iOS done well. The app stays inside the iOS 26 system look: system type roles, system materials and Liquid Glass chrome, one accent colour, standard containers. Effort goes into hierarchy, spacing, empty states, Dynamic Type and one-handed reach, not into a custom visual language. A distinctive identity can come later as a skin over this base.

Room is left for light branding: an app icon and, later, a mascot in a few fixed places such as onboarding, first-run empty states and the Sources screen. The mascot never carries information the interface does not also show in text, and never comments on what was eaten.

## Yardstick

Every screen is held to the plan's targets rather than to taste:

- A repeat meal in under five seconds and three taps.
- A food never logged before in under twenty seconds.
- The add sheet opens with the keyboard up and recents listed before typing.
- The quantity sheet is prefilled with the last amount used for that food.
- All eight daily totals always visible: energy, protein, carbohydrates and fat large, the other four small.
- No colour-coded judgment, no over or under indicators, no traffic lights.
- Entries written by other apps, and entries partly or wholly missing from Health, are visually distinct and carry only the affordances the plan names.
- Primary actions reachable one-handed at the bottom of the screen.
- Dynamic Type everywhere, including the totals row.

## Process

1. Code-side audit per screen against the yardstick, recorded in `design/audit.md`.
2. A preview per screen and per notable state, using the fixture database and fake services.
3. Screenshots from the simulator in light and dark mode and at the largest accessibility size, kept in `design/screenshots/`.
4. Screen-by-screen pass in fast-path order: Today, Add, Quantity, then Library, Settings, onboarding, then the two module sheets. One commit per screen.
5. The outcomes land here: type roles, spacing, how provenance and partial states look, and what stays deliberately plain.

## Decisions

Filled in as the screen-by-screen pass settles each one.
