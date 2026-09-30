# Theming a Jahia JS template set with CSS tokens

How to make a template set re-themeable without touching a component: brand variants, light and
dark, all driven by CSS custom properties and switched from jContent. Distilled from
tenant-portal (`src/templates/tokens.css`, `tnpmix:siteTheme`) and the weaknesses found in
mysoprahr (about 100 hardcoded hex colours in component CSS, brand-named tokens, no spacing scale).

---

## The rule

**Components never contain a literal colour, font stack, shadow or radius.** They read semantic
tokens. A theme is a block of token overrides, nothing else. If re-theming needs a component edit,
a literal slipped in.

Enforce it with a gate, not with review. A grep over component CSS is enough:

```bash
grep -rn -E '#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(' src/components --include='*.css'
```

Only `tokens.css` may match.

---

## Three tiers

| Tier | Example | Who reads it |
|---|---|---|
| **1. Primitives** | `--ns-blue-600`, `--ns-gray-50`, `--ns-space-4`, `--ns-radius-md` | only tier 2 |
| **2. Semantic roles** | `--ns-color-surface`, `--ns-color-text`, `--ns-color-accent`, `--ns-color-border`, `--ns-focus-ring` | every component |
| **3. Component-local** | `--hero-overlay: var(--ns-color-overlay)` declared in `hero.module.css` | that component only |

- **Themes override tier 2** (and may add primitives). They never reach into a component.
- **Name tier 2 by role, not by brand.** `--ns-color-accent`, not `--ns-magenta`: a theme where the
  accent is green must not read `--ns-magenta: green`.
- **Tier 3 is optional.** Use it when a component needs a knob a theme may want to tune (hero
  overlay strength, card elevation). Always fall back to a semantic token.
- **Prefix every token with the module namespace** (`--ctpl-`, `--tnp-`). Page Builder's frame,
  other add-on modules and imported CSS all live in the same document. The jcontent 3.7 frame only
  defines `--moon-*`, and third-party HTML has been seen shipping `:root{--primary…}` blocks that
  repaint anything reading `--primary`.

---

## What goes in the token file

A single `src/templates/tokens.css` (imported once by `Layout.tsx`) holds:

- **Colour roles:** surface (page, raised, sunken, inverse), text (default, muted, on-accent,
  inverse), accent (+ hover, + subtle surface), border (default, strong), status (success, warning,
  danger, info, each with a surface pair), overlay, focus.
- **Typography:** `--ns-font-sans`, `--ns-font-serif` (for a classic headline pairing),
  `--ns-font-mono`, and a **fluid** type scale with `clamp()`:
  `--ns-text-2xl: clamp(1.5rem, 1.2rem + 1.5vw, 2rem)`. Line heights and heading tracking.
- **Spacing:** a single scale (`--ns-space-1` … `--ns-space-9`), used for padding, gaps and
  section rhythm. mysoprahr had none, so every component invented its own margins.
- **Shape:** radii (`sm`, `md`, `lg`, `pill`), border widths.
- **Elevation:** shadows built with `color-mix()` from a semantic colour so they follow the theme:
  `--ns-shadow-md: 0 4px 12px color-mix(in srgb, var(--ns-color-shadow) 14%, transparent)`.
  tenant-portal hardcoded navy `rgba()` in its shadows, which no theme could change.
- **Layout:** `--ns-container` (max content width), `--ns-gutter`.
- **Motion:** durations and easing, zeroed under `prefers-reduced-motion`.

**Breakpoints cannot be tokens.** CSS custom properties are not allowed in `@media` conditions.
Document two or three fixed breakpoints as constants at the top of `tokens.css` and use exactly
those. mysoprahr ended up with 767/768/900/1023/1024/640. Prefer container queries for components
that sit in columns of varying width.

---

## Switching themes from jContent

A site-level mixin carries the choice, so an administrator switches the theme with no deploy:

```cnd
[nsmix:siteTheme] mixin
 extends = jnt:virtualsite
 - nsTheme (string, choicelist) = 'default' autocreated < 'default', 'ocean', 'forest'
 - nsColorScheme (string, choicelist) = 'auto' autocreated < 'auto', 'light', 'dark'
```

`extends = jnt:virtualsite` makes it an optional section of the site node's edit form. The layout
reads it defensively, because the mixin may not have been applied yet:

```tsx
const site = renderContext.getSite();
const theme = site.isNodeType("nsmix:siteTheme") ? site.getPropertyAsString("nsTheme") : undefined;
// Leave the attribute off for the default theme: :root already carries it.
<html lang={lang} data-ns-theme={theme && theme !== "default" ? theme : undefined} data-ns-scheme={scheme}>
```

The theme blocks then override tier 2 only:

```css
:root[data-ns-theme="ocean"] {
  --ns-color-accent: var(--ns-teal-700);
  --ns-color-accent-hover: var(--ns-teal-800);
  --ns-font-serif: "Source Serif 4", Georgia, serif;
}
```

Plain `choicelist` is enough (proven on tenant-portal): labels for the values come from the resource bundle (`nsmix_siteTheme.nsTheme.ocean=Ocean`).
Every value needs an EN and an FR label, plus a `ui.tooltip` for the field.

---

## Light and dark

Two inputs, one outcome:

1. **The visitor's system preference:** `@media (prefers-color-scheme: dark)`.
2. **The site's explicit choice:** `data-ns-scheme="light|dark"` stamped by the layout (`auto` stamps nothing).

```css
:root { color-scheme: light; /* light semantic roles */ }

@media (prefers-color-scheme: dark) {
  :root:not([data-ns-scheme="light"]) { color-scheme: dark; /* dark semantic roles */ }
}
:root[data-ns-scheme="dark"] { color-scheme: dark; /* same dark semantic roles */ }
```

- The dark block is written twice (media query and explicit attribute). Keep them identical;
  a build-time copy or a shared `@layer` avoids drift.
- **Each brand theme needs its dark variant too** (`:root[data-ns-theme="ocean"][data-ns-scheme="dark"]`
  plus its media-query twin), otherwise a dark visitor gets the default dark accent on an ocean site.
- `color-scheme` makes form controls and scrollbars follow the theme for free.
- Images and logos: offer a dark logo slot on the header (`logoDark` weakreference) rather than
  inverting with a CSS filter.

---

## Contrast is checked per theme, not per component

Because components only read semantic roles, contrast is a property of the token file. For every
theme × scheme pair, check the pairs that are actually used together:

| Foreground | Background | Minimum |
|---|---|---|
| `text` | `surface-page`, `surface-raised` | 4.5:1 |
| `text-muted` | `surface-page` | 4.5:1 |
| `text-on-accent` | `accent`, `accent-hover` | 4.5:1 |
| `accent` (as link text) | `surface-page` | 4.5:1 |
| `border-strong`, `focus` | `surface-page` | 3:1 (non-text UI) |

tenant-portal found two real brand colours failing AA on white and had to darken the status
tokens. Catch that in the token file, then let `/jahia-review-site` (full axe ruleset) confirm on
rendered pages in each theme.

---

## Edit mode

- Page Builder renders the page inside an iframe with the same `<html>` attributes, so editors see
  the chosen theme. That is the point: editing in the real theme.
- Anything that starts hidden and is revealed by JavaScript (scroll-reveal at `opacity:0`) must be
  disabled in edit mode (`renderContext.isEditMode()`), otherwise editors click on invisible blocks.

---

## Checklist

- [ ] One `tokens.css`, imported once by `Layout.tsx`; every token prefixed with the module namespace
- [ ] Primitives → semantic roles → optional component-local; themes override semantic roles only
- [ ] No literal colour, font stack or shadow in any `*.module.css` (grep gate above passes)
- [ ] Shadows built with `color-mix()` from a semantic colour
- [ ] Spacing scale and fluid type scale in tokens; two or three documented breakpoints
- [ ] `nsmix:siteTheme` on `jnt:virtualsite` with theme + colour-scheme choicelists, EN/FR labels and tooltips
- [ ] Layout reads the mixin defensively and stamps `data-ns-theme` / `data-ns-scheme`
- [ ] Dark roles for every theme, in both the media query and the explicit attribute
- [ ] Contrast table checked for every theme × scheme pair; `/jahia-review-site` green in each
- [ ] `prefers-reduced-motion` zeroes motion tokens; reveal effects off in edit mode
