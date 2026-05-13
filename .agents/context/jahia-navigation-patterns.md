# Context — Jahia Navigation Patterns

Navigation in Jahia must be **JCR-driven and CMS-editable** — never hardcoded. This document covers the canonical `MainNavigation` + `SiteHeader` pattern.

---

## Core Rules

1. **Never hardcode nav items.** Use `getChildNodes` filtered by `jmix:navMenuItem` to read the live page tree. Editors can reorder, rename, or add pages without touching code.
2. **Language switcher is dynamic.** Use `getSiteLocales()` — it hides automatically when only one language is configured. Never hardcode `["en", "fr"]`.
3. **Two separate components, not one.** `SiteHeader` = logo + utility bar + hamburger trigger. `MainNavigation` = nav links + language switcher. Both are content nodes in the same `header` area.
4. **Cross-component communication via `data-*` attributes.** `SiteHeader` and `MainNavigation` render independently (separate Jahia components, no shared React tree). Use `data-mobile-nav-toggle` + a small inline script — no Islands, no hydration cost.
5. **Support all 4 nav item types**, not just `jnt:page`:
   - `jnt:page` — regular CMS page → `<a href="...">`
   - `jnt:navMenuText` — label with no link, used as group heading → `<span>`
   - `jnt:nodeLink` — link to another JCR node
   - `jnt:externalLink` — link to an external URL

---

## JCR Structure

```
/sites/{siteKey}/home/header   (jnt:contentList)
  /site-header                 (ns:siteHeader)       ← logo + utility bar + hamburger
  /main-navigation             (ns:mainNavigation)   ← nav links + language switcher
```

Nav items are read from the **home page's children** — the standard Jahia navigation tree:

```
/sites/{siteKey}/home          (jnt:page)   ← nav root
  /about-us                    (jnt:page)   ← level-1 item
  /our-services                (jnt:page)   ← level-1 item (with level-2 children)
    /advisory                  (jnt:page)   ← level-2 → dropdown
    /financing                 (jnt:page)   ← level-2 → dropdown
```

---

## CND Definition

`MainNavigation` has **no content properties** — all data comes from the JCR tree at render time:

```cnd
[ns:mainNavigation] > jnt:content, nsmix:component
```

Where `nsmix:component` inherits from `jmix:droppableContent, jmix:accessControllableContent`.

---

## Helper Functions

```tsx
import type { JCRNodeWrapper } from "org.jahia.services.content";
import { getChildNodes, buildNodeUrl } from "@jahia/javascript-modules-library";

/** Items that are nav-eligible (exclude jmix:navMenu containers) */
const getNavItems = (node: JCRNodeWrapper) =>
  getChildNodes(node, -1, 0, (n) => {
    if (!n.isNodeType("jmix:navMenuItem")) return false;
    if (n.isNodeType("jmix:navMenu")) return false;
    return true;
  });

/** Resolve href for any nav item type */
const getItemUrl = (node: JCRNodeWrapper): string => {
  try {
    if (node.isNodeType("jnt:page")) return buildNodeUrl(node);
    if (node.isNodeType("jnt:nodeLink") && node.hasProperty("j:node"))
      return buildNodeUrl(node.getProperty("j:node").getNode() as JCRNodeWrapper);
    if (node.isNodeType("jnt:externalLink") && node.hasProperty("j:url"))
      return node.getProperty("j:url").getString();
  } catch (_) {}
  return "#";
};

/** Resolve display title for any nav item type */
const getItemTitle = (node: JCRNodeWrapper): string => {
  try {
    if (node.isNodeType("jnt:nodeLink") && node.hasProperty("j:node")) {
      const ref = node.getProperty("j:node").getNode() as JCRNodeWrapper;
      if (ref.hasProperty("jcr:title")) return ref.getProperty("jcr:title").getString();
      return ref.getName();
    }
    if (node.hasProperty("jcr:title")) return node.getProperty("jcr:title").getString();
  } catch (_) {}
  return node.getName();
};
```

---

## `default.server.tsx` — Full Pattern

```tsx
import {
  buildNodeUrl, getChildNodes, getSiteLocales,
  jahiaComponent, useServerContext,
} from "@jahia/javascript-modules-library";
import type { JCRNodeWrapper } from "org.jahia.services.content";
import "./component.css";

jahiaComponent(
  { nodeType: "ns:mainNavigation", displayName: "Main Navigation", componentType: "view" },
  (_, { renderContext, mainNode }) => {
    const { currentResource } = useServerContext();

    const site = renderContext.getSite() as JCRNodeWrapper;
    const homePage = site.getNode("home") as JCRNodeWrapper;
    const level1Items = getNavItems(homePage);

    const currentLang = currentResource.getLocale().getLanguage();
    const siteLocales = getSiteLocales();
    const localeEntries = Object.entries(siteLocales);
    const showLangSwitcher = localeEntries.length > 1;

    return (
      <>
        <nav id="main-nav" role="navigation" aria-label="Main navigation" data-expanded="false">
          <ul className="nav-items">
            {level1Items.map((item) => {
              const isMenuText = item.isNodeType("jnt:navMenuText");
              const level2Items = getNavItems(item);
              const hasDropdown = level2Items.length > 0;
              const isActive =
                item.isNodeType("jnt:page") &&
                (item.getPath() === mainNode.getPath() ||
                  mainNode.getPath().startsWith(item.getPath() + "/"));

              return (
                <li key={item.getPath()} className={`nav-item${hasDropdown ? " has-dropdown" : ""}`}>
                  {isMenuText ? (
                    <span className="nav-label">{getItemTitle(item)}</span>
                  ) : (
                    <a
                      href={getItemUrl(item)}
                      className={isActive ? "nav-link active" : "nav-link"}
                      aria-current={item.getPath() === mainNode.getPath() ? "page" : undefined}
                    >
                      {getItemTitle(item)}
                    </a>
                  )}
                  {hasDropdown && (
                    <ul className="dropdown-menu">
                      {level2Items.map((sub) => (
                        <li key={sub.getPath()}>
                          <a href={getItemUrl(sub)} className="dropdown-link">
                            {getItemTitle(sub)}
                          </a>
                        </li>
                      ))}
                    </ul>
                  )}
                </li>
              );
            })}
          </ul>

          {showLangSwitcher && (
            <ul aria-label="Language selection" className="lang-switcher">
              {localeEntries.map(([langCode]) => {
                const isCurrent = langCode === currentLang;
                const url = buildNodeUrl(
                  renderContext.getMainResource().getNode() as JCRNodeWrapper,
                  { language: langCode },
                );
                return (
                  <li key={langCode}>
                    <a
                      href={url}
                      lang={langCode.toUpperCase()}
                      aria-current={isCurrent ? "true" : "false"}
                      className={isCurrent ? "lang-link active" : "lang-link"}
                    >
                      {langCode.toUpperCase()}
                    </a>
                  </li>
                );
              })}
            </ul>
          )}
        </nav>

        {/* Mobile toggle — wires SiteHeader hamburger to this nav */}
        <script dangerouslySetInnerHTML={{ __html: `(function(){
  var toggle = document.querySelector('[data-mobile-nav-toggle]');
  var nav = document.getElementById('main-nav');
  if (!toggle || !nav) return;
  toggle.addEventListener('click', function() {
    var expanded = nav.getAttribute('data-expanded') === 'true';
    nav.setAttribute('data-expanded', String(!expanded));
    toggle.setAttribute('aria-expanded', String(!expanded));
  });
  document.addEventListener('click', function(e) {
    if (nav.getAttribute('data-expanded') === 'true'
        && !nav.contains(e.target) && !toggle.contains(e.target)) {
      nav.setAttribute('data-expanded', 'false');
      toggle.setAttribute('aria-expanded', 'false');
    }
  });
})();` }} />
      </>
    );
  },
);
```

---

## SiteHeader — Hamburger Trigger

```tsx
<button
  type="button"
  data-mobile-nav-toggle
  aria-expanded="false"
  aria-controls="main-nav"
  aria-label="Toggle navigation menu"
  className="lg:hidden"
>
  <span /><span /><span />
</button>
```

**Why `data-*` not React state?** The two components have no shared React tree — they are separate Jahia nodes rendered independently. Attribute-based communication requires no hydration and no Islands.

---

## CSS Skeleton (Mobile-First)

```css
@media (max-width: 1023px) {
  #main-nav { display: none; }
  #main-nav[data-expanded="true"] { display: block; }
}

.nav-item { position: relative; }
.dropdown-menu { display: none; position: absolute; top: 100%; left: 0; }

@media (min-width: 1024px) {
  .nav-item:hover .dropdown-menu,
  .nav-item:focus-within .dropdown-menu { display: block; }
}

@media (max-width: 1023px) {
  .dropdown-menu { position: static; display: block; padding-left: 1rem; }
}
```

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| `getChildNodes` without type filter — includes files and other content | Always filter by `jmix:navMenuItem` |
| `isNodeType("jmix:navMenu")` not excluded — includes nav menu containers | Add `if (n.isNodeType("jmix:navMenu")) return false` |
| Hardcoded `["en", "fr"]` for language switcher | Use `getSiteLocales()` |
| `buildNodeUrl(mainResource.getNode())` without `{ language }` | Add `{ language: langCode }` option |
| Nav and hamburger in same component requiring shared state | Keep in separate components, use `data-*` attributes |
| Using `<Island>` for the toggle script | Use a small `dangerouslySetInnerHTML` inline script |
| Putting nav inside `SiteHeader` TSX | Separate `MainNavigation` node in the header area |

---

## Checklist

- [ ] `definition.cnd` uses a mixin inheriting `jmix:droppableContent`
- [ ] Nav items filtered by `jmix:navMenuItem`, excluding `jmix:navMenu`
- [ ] All 4 item types handled: `jnt:page`, `jnt:navMenuText`, `jnt:nodeLink`, `jnt:externalLink`
- [ ] Active state checks `mainNode.getPath()` and `startsWith(path + "/")`
- [ ] Language switcher uses `getSiteLocales()` — never hardcoded locale codes
- [ ] `#main-nav` has `data-expanded="false"` for CSS targeting
- [ ] Hamburger button in SiteHeader has `data-mobile-nav-toggle`
- [ ] Content node created and published in JCR after deploy
