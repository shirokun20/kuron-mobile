# Kuron Design System

> Visual identity & component design language for Kuron mobile reading app.
> Reflects actual tokens in code — not aspirational.
> **Values mirror the code.** If a hex here disagrees with
> `lib/core/constants/colors_const.dart`, the code is right and this file is
> stale — fix this file. Re-synced 2026-09-30 after the warm-palette revision.

---

## Brand Identity

| Attribute | Value |
|-----------|-------|
| **Vibe** | Warm, intimate, privacy-first reading |
| **Tone** | Mature, calm, unobtrusive — content is hero |
| **Inspiration** | Dark-mode reading apps, Material Design 3 |
| **Source** | `Frame.svg` brand assets → coral palette |

### Brand Colors

```
brandCoral  #F1958E  — Main accent, actionable elements
brandMuted  #E0827E  — Secondary accent
brandDusty  #9D555B  — Tertiary, deeper tone
brandDark   #1A1A1F  — Near black, dark surfaces
```

### Design Principles

1. **Content First** — UI recedes; typography & color serve readability
2. **Warmth** — Coral/pink undertones replace cold blue Material defaults
3. **Cohesive Darkness** — 3 calibrated modes (dark/amoled/light)
4. **Flat + Bordered** — Cards use `elevation: 0` + 1px colored borders, not shadows

---

## Color System

### Palette

```
Core Brand
  brandCoral  #F1958E
  brandMuted  #E0827E
  brandDusty  #9D555B
  brandDark   #1A1A1F
  warm        #D48A6A  (secondary accent)
  readGold    #C8A06A  (read / completed)

Light Theme — warm cream, aged paper
  bg       #EFE6DC
  surface  #F5EDE4
  card     #FCF7F0
  cardAlt  #FAF3EC
  border   #D6C8BC
  text     #2E2722
  textSub  #7A6E66
  accent   #C76A62  (lightCoral, deepened for AA)

Dark Theme — warm dark, library at night (default)
  bg       #1C1816
  surface  #221E1C
  card     #2A2522
  cardAlt  #2E2926
  border   #4A3D36
  text     #D4CCC4
  textSub  #9E948C

AMOLED — pure black, warm text
  bg       #000000
  surface  #0C0A08
  card     #12100E
  cardAlt  #161412
  border   #362C28
  text     #CCC4BC
  textSub  #8E847C

Note — pure monochrome (note-dark mirrors it inverted)
  bg       #FFFFFF
  surface  #F5F5F5
  card     #EEEEEE
  cardAlt  #E0E0E0
  border   #BDBDBD
  text     #000000
  textSub  #757575

Semantic
  primary           brandCoral  (light: lightCoral)
  primaryContainer  #4A2A28 dark · #B87054 light
  secondary         warm
  tertiary          brandMuted

Status
  error    #C86858  muted brick
  success  #8AB87A  muted leaf green
  warning  #D4A060
  info     #7BB8FF
```

### Color Roles

| Role | Usage |
|------|-------|
| **Primary** | Accent actions, FAB, selected nav, active controls — one per surface |
| **Primary Container** | Selected states, badge and affordance-tile backgrounds |
| **Background** | Scaffold, the page the content sits on |
| **Surface** | Drawers, sheets, anything above the background |
| **Card** | Content cards, list tiles — defined by a border, not a shadow |
| **Border** | Card outlines — primary visual boundary (flat look) |
| **Text** | Body, headings |
| **Text Sub** | Captions, secondary info, metadata |
| **Status** | Semantic states + download progress |

### Theme Variants

| Variant | Background | Surface | Character |
|---------|-----------|---------|-----------|
| **Light** | `#EFE6DC` | `#F5EDE4` | Warm cream, aged paper |
| **Dark** | `#1C1816` | `#221E1C` | Warm dark, library at night (default) |
| **AMOLED** | `#000000` | `#0C0A08` | Pure black, warm text |
| **Note** | `#FFFFFF` | `#F5F5F5` | Pure monochrome, for reading text |
| **Note dark** | `#000000` | `#111111` | Monochrome at night, no accent at all |

---

## Typography

**Font**: `google_fonts` — **Playfair Display** for display/headline, **Inter** for
body and labels, applied to `ThemeData.textTheme` in all five themes
(`theme_cubit.dart` `_googleFontsTextTheme`). `TextStyleConst` styles are plain
`TextStyle`s, so they fall back to the system face — using one directly opts that
run of text out of Inter. Monospace only for debug output.

### Weight Scale

| Token | Weight | Usage |
|-------|--------|-------|
| Light | 300 | Captions, subtitles, placeholders |
| Regular | 400 | Body text |
| Medium | 500 | Labels, small headings, buttons |
| SemiBold | 600 | Content titles, active nav |
| Bold | 700 | Headings, section titles |
| ExtraBold | 800 | Display text, hero |

### Type Scale (from `TextStyleConst`)

```dart
Display  57/700   Hero numbers (rare)
Headline 32/700   Screen titles
Title    22/600   Section headers
Body     16/400   Primary reading text
Label    14/500   Buttons, chips
Caption  12/300   Metadata
Overline 10/400   Section markers
```

Full scale in `lib/core/constants/text_style_const.dart`. Includes component-specific: `contentTitle` (SemiBold 16), `buttonLarge` (Medium 16), `navigationLabel` (Medium 14).

**Line height**: Uniform `1.4`. Styles inherit color from `Theme` — no hardcoded colors.

---

## Design Tokens

**`lib/core/constants/design_tokens.dart`** — central token scale, replacing inline numeric literals.

### Spacing (geometric progression 4→48)

| Token | Value | Usage |
|-------|-------|-------|
| `spaceXs` | 4 | Tight icon gaps, badges |
| `spaceSm` | 8 | Card grid gaps, chip padding |
| `spaceMd` | 12 | Internal card padding |
| `spaceLg` | 16 | Screen edges (`defaultPadding`) |
| `spaceXl` | 24 | Section spacing |
| `space2xl` | 32 | Large section breaks |
| `space3xl` | 48 | Screen-level groups |

### Border Radius

| Token | Value | Usage |
|-------|-------|-------|
| `radiusSm` | 4 | Badges, small tags |
| `radiusMd` | 8 | Buttons, compact cards |
| `radiusLg` | 12 | Input fields (most used) |
| `radiusXl` | 16 | Cards |
| `radius2xl` | 20 | Bottom sheets, modals |
| `radiusFull` | 999 | Status pills, circular elements |

### Elevation

| Token | Value | Usage |
|-------|-------|-------|
| `elevationNone` | 0 | All cards, lists |
| `elevationSm` | 1 | Subtle lift |
| `elevationMd` | 2 | FAB |
| `elevationLg` | 4 | Modal dialogs |
| `elevationXl` | 8 | Overlays, drawers |

### Durations

| Token | Value | Usage |
|-------|-------|-------|
| `durationInstant` | 50ms | Tap feedback |
| `durationFast` | 150ms | Hover, press states |
| `durationPageTurn` | 200ms | Reader page turns |
| `durationNormal` | 300ms | UI transitions |
| `durationSlow` | 500ms | Overlay fade |
| `durationPageEnter` | 700ms | Screen transitions |

### Curves

| Token | Curve | Usage |
|-------|-------|-------|
| `curveStandard` | `easeInOutCubic` | Most UI motion |
| `curveReaderPage` | `easeOutCubic` | Reader page turns |
| `curveEnter` | `easeOut` | Entrance animations |
| `curveExit` | `fastEaseInToSlowEaseOut` | Exit animations |

---

## Components

### Cards
```
CardThemeData(
  color: {light: #FCF7F0, dark: #2A2522, amoled: #12100E, note: #EEEEEE},
  elevation: elevationNone,
  shape: RoundedRectangleBorder(
    borderRadius: radiusXl (16),
    side: BorderSide(color: themeBorder, width: 1),
  ),
)
```

### Navigation Bar
- Selected: brandCoral indicator (15-25% alpha) + SemiBold label
- Unselected: textSub + Medium label
- Background: surface color per theme

### Input Fields
- Filled, surface-colored bg, radiusLg (12)
- Border: border color → primary 2px (focused)

### FAB
- Primary bg, white foreground, elevationMd (2) / elevationSm (1 amoled)

---

## Source Files

| File | Role |
|------|------|
| `lib/core/constants/colors_const.dart` | Brand palette, theme, semantic colors |
| `lib/core/constants/text_style_const.dart` | Weight system, type scale, component styles |
| `lib/core/constants/design_tokens.dart` | Spacing, radius, elevation, duration, curves |
| `lib/core/utils/tag_color_palette.dart` | Tag→color mapping (12 categories) |
| `lib/core/constants/app_constants.dart` | Config-driven UI values |
| `lib/presentation/cubits/theme/theme_cubit.dart` | ThemeData (light / dark / amoled / note / note-dark) |

---

*Updated 2026-09-30 — palette, fonts, and card values re-synced to the code after the
warm-palette revision (2026-06-24) had left this file describing the old cool greys.
Type scale and token scales were already accurate.*
