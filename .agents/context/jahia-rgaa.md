# RGAA 4.1.2 for Jahia JS template sets

RGAA (Référentiel Général d'Amélioration de l'Accessibilité, version 4.1.2) is the French standard:
106 criteria in 13 themes, built on WCAG 2.1 AA, legally required for French public bodies and
large companies (loi 2005-102, article 47). axe-core and Lighthouse cover only part of it. A site
can pass the automated gate (`/jahia-review-site`) in every theme and still fail RGAA.

Everything below was measured on classic-templates (Jahia 8.2.3.2, 2026-09-30). A manual audit of
twelve pages in six looks found **11 template defects after a clean axe + Lighthouse run**. All
of them are generic: check for each one in any new template set.

## What automation missed, and the fix

| RGAA | Defect found | Fix |
|---|---|---|
| 10.7 / 3.3 | Focus ring over a hero photo at 1.5-2.7:1 in light schemes. The page focus colour is tuned for page surfaces. | On the overlay variant, redeclare `--ns-color-focus: var(--ns-color-text-on-overlay)` **and** the composite `--ns-focus-ring`. A custom property that reads another one resolves where it is *declared* (`:root`), so overriding only the colour changes nothing. |
| 10.7 / 12.8 | Small-screen menu stays open when focus leaves it, so Tab lands on links hidden under the overlay. Escape only closed submenus. | Close the menu on `focusout` from the nav (when `relatedTarget` is outside) and on Escape when no submenu is open; Escape returns focus to the menu button. |
| 6.1.5 (WCAG 2.5.3) | Language switcher shows "FR" but its accessible name is "Français" (`aria-hidden` code plus a hidden name). | The visible code starts the name: `FR<span class="visually-hidden"> - Français</span>`, with `lang` and `hreflang` on the link. |
| 9.1 | Content page outline starts with the hero's `<h2>`, then the page `<h1>`. | Render the page `<h1>` before the hero area. |
| 10.12 | A `-webkit-line-clamp` teaser clips text (French at 320 px even without extra spacing). | Never clamp text; bound its length in the content model instead. |
| 1.2 / 1.3 | Alt text is always the library title of the image. An abstract backdrop is announced, and FR pages read the English title. | Add to the media mixin an optional i18n `imageAlt` (the alternative for *this* use) and an `imageDecorative` boolean. Translate library titles. The upstream `redundantImageAlt` CND rule then needs a documented `cnd-check-ignore`, because RGAA 1.3 asks for an alternative that fits the context. |
| 8.7 | The rich-text sanitizer drops `lang`. | Keep `lang`/`dir` on every element, validated (BCP 47, `ltr`/`rtl`/`auto`). |
| 9.3 | The sanitizer drops `dl`/`dt`/`dd`, so a definition list becomes run-on text. | Allow them. |
| 5.x | The sanitizer drops `th id`, `td headers` and `role="presentation"`. | Allow them, prefixing the ids. |
| 9.1 / 8.2 | Editor headings skip levels (h2 then h4), and editor ids can collide with the page's ids or between blocks. | Renumber body headings under the section heading (rank the levels used, then never more than one level down). Prefix ids per block (`rt-<node id>-`), and rewrite the `#anchors` and `headers` that point at them. |
| 13.2 / 1.2 | `target="_blank"` kept with no warning, `title` kept on links and images, `<img>` without alt passed through. | Drop link `target`/`title` and image `title`. Give a missing alt `alt=""` and show an edit-mode hint (a missing alt fails 1.1 outright). |

## Criteria to design for from the start

- **12.1 Two navigation systems** among menu, site map and search, on every set of pages. A
  breadcrumb does **not** count. Ship a visitor site map component (nested lists from the page
  tree, pages hidden from the menu included) and link it from the footer. Jahia's `sitemap`
  module only produces `sitemap.xml` for search engines (`jseomix:sitemap` on the site,
  `jseomix:noIndex` / `jseomix:noFollow` on pages). Its `jnt:sitemap` is a legacy hidden type
  with no view, so it does not replace a visitor site map. Leave `noIndex` pages out of both maps.
- **12.6 / 12.7** One banner, one main, one contentinfo, and every `<nav>` uniquely labelled. The
  skip link is the first focusable element and moves focus to `<main tabindex="-1">`.
- **10.11 Reflow** at 320 CSS px with no horizontal scroll and no loss. Use `overflow-wrap: anywhere`
  on breadcrumbs, big figures and site-map entries.
- **10.13** Hover content stays open while hovered, and Escape dismisses it.
- **Stretched-link cards:** the link's name is the title. When the card shows a visual cue ("See the
  services"), repeat it visually hidden inside the link ("Services: See the services") so voice
  control finds it, and keep the visible cue `aria-hidden`.
- **Quotes:** `figure > blockquote + figcaption`, with quotation marks from CSS (`quotes: auto`, plus
  `:lang(fr) { quotes: "\00ab\00a0" "\00a0\00bb" }` for the French non-breaking spaces). Generated
  content carries no information, so 10.2 holds with CSS off.

## The legal side: site content, not the template set

Article 47 requires a **déclaration d'accessibilité** and the mention "Accessibilité : non /
partiellement / totalement conforme" on the home page. Both are contributed content. The template
set makes them easy: a footer legal link list (so the link shows on every page, home included) and
rich text for the statement. An example statement contains:
- the commitment (article 47) and its scope;
- the compliance status with the RGAA version, and the audit result (the percentage of criteria met);
- the non-accessible content;
- the date, technologies, tools, browsers and assistive technologies used (say plainly when screen
  readers were not tested), and the pages tested;
- the contact (a real form: an empty contact page fails the "report a problem" promise);
- the remedy through the Défenseur des droits.

## How to audit

1. Pass the automated gate first (`/jahia-review-site`, every theme and scheme).
2. With Playwright/Chromium, measure on the live pages:
   - focus stops and ring contrast, pixel-sampled over images;
   - tab order and keyboard traps, at desktop width and at 320 px with the menu open;
   - 320 px reflow and 200% zoom;
   - the WCAG 1.4.12 text-spacing bookmarklet (look for `scrollHeight > clientHeight`);
   - CSS disabled;
   - accessible names against visible labels;
   - `lang` on language links and phrases.
3. Feed hostile rich text through the sanitizer (lang, dl, tables, heading jumps, ids, targets,
   images without alt).
4. Report per criterion, with evidence and file:line. Say "not tested" for screen readers rather
   than guessing.

Reference implementation: classic-templates `src/lib/sanitize.ts`, `src/lib/RichText.tsx`,
`static/js/navigation.js`, `src/components/Navigation/SiteMap`, `scripts/seed-demo.py`
(example statement).
