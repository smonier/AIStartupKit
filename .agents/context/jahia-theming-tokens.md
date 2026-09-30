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

Only `tokens.css` may match. Components must not read tier-1 primitives either
(`var(--ns-slate-900)`, `var(--ns-white)`): they bypass the theme overrides just like a literal.
classic-templates' `scripts/check-tokens.mjs` checks both.

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

**Cache:** the rendered page now depends on the site node, which is not below the page. Declare it
in the Layout, or publishing a new theme leaves every cached live page on the old one (seen on
8.2.3.2: preview switched, live did not):

```tsx
server.render.addCacheDependency({ node: site }, renderContext);
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

Use `light-dark()` for every colour role, so dark mode is never written twice:

```css
:root {
  color-scheme: light dark;            /* auto: follow the visitor's system */
  --ns-color-text: light-dark(var(--ns-slate-900), var(--ns-slate-50));
  --ns-color-surface-page: light-dark(var(--ns-white), var(--ns-slate-950));
}
:root[data-ns-scheme="light"] { color-scheme: light; }   /* the site forces a scheme */
:root[data-ns-scheme="dark"] { color-scheme: dark; }
:root[data-ns-theme="ocean"] {                          /* a theme overrides pairs, not blocks */
  --ns-color-accent: light-dark(var(--ns-teal-700), var(--ns-teal-300));
}
```

- The half that applies follows the used `color-scheme`, so a theme's dark variant is simply the
  second half of its pairs: no `[data-theme][data-scheme]` combinations, no media-query twin.
- `light-dark()` only takes colours; non-colour tokens (fonts, radii) are per theme, not per scheme.
- Browser support is Baseline 2024. Jahia's CSS aggregation and minification keep `light-dark()`,
  `color-mix()` and `clamp()` intact (verified on 8.2.3.2; it only drops the quotes of attribute
  selectors, which stays valid).
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
tokens. Catch that in the token file with a script, then let `/jahia-review-site` (full axe
ruleset) confirm on rendered pages in each theme. classic-templates ships both as package scripts
to copy: `scripts/check-contrast.mjs` resolves `tokens.css` the way a browser does (theme block over
`:root`, `var()` substituted, `light-dark()` split by scheme, translucent colours composited) and
checks every pair for every theme × scheme; `scripts/check-tokens.mjs` fails on any literal colour
outside `tokens.css`. Break a token on purpose once to see each gate fail before trusting it.

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
- [ ] Every colour role a `light-dark()` pair; `data-ns-scheme` only sets `color-scheme`
- [ ] Layout declares a cache dependency on the site node
- [ ] Contrast table checked for every theme × scheme pair; `/jahia-review-site` green in each
- [ ] `prefers-reduced-motion` zeroes motion tokens; reveal effects off in edit mode
