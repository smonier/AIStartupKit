---
name: jahia-js-module
description: Instructions for AI agents helping develop Jahia JavaScript modules — React-based template sets for Jahia 8+.
---

# Jahia JavaScript Module Development

## Context

You are helping develop a **Jahia JavaScript Module** — a React-based template set for Jahia 8+. The module renders content from Jahia's JCR (Java Content Repository) using server-side React components (`.server.tsx`) and optional client-side islands (`.client.tsx`). Content is modelled in CND files, managed via Page Builder or jContent, and queried with JCR-SQL2 or GraphQL.

## Agent Principles

1. **Always invoke a skill before any Jahia task** — skills are the canonical source of patterns, gotchas, and API syntax. Never operate from memory alone.
2. **Never use `yarn dev` from an agent** — it is an interactive file watcher for human developers only. Always deploy with `yarn build && yarn jahia-deploy` (one-shot, non-interactive).
3. **Never hardcode URLs** — all navigable links must come from contributed content (JCR nodes, `j:linkType`, `buildNodeUrl`). This is a CMS: content owns the URLs.
4. **Never use `j:linkType: "external"` for internal pages** — use `"internal"` + `j:linknode`. External URLs break on environment changes, language switches, and vanity URL rewrites.
5. **Always verify before creating** — check that content types are deployed, site keys are correct, and area structures exist before attempting GraphQL mutations.
6. **All props are optional at runtime** — even mandatory CND fields. Always guard against `undefined` in views.
7. **Always include `-H "Origin: http://localhost:8080"` in every GraphQL curl** — omitting it returns `Permission denied` even with correct credentials.
8. **Accessibility is mandatory** — every component must pass WCAG 2.1 AA. After building any component or completing a task, invoke `/jahia-dev-accessibility` to run an axe-core audit and fix all `critical` and `serious` violations before declaring work done.
9. **Never declare `jcr:title` in CND** — use `mix:title` as a supertype to inherit the `jcr:title` field. Declaring it explicitly causes duplicate fields and editor conflicts.
10. **`weakreference` without a `picker` type = full JCR node browser** — editors can select pages, content folders, folders, any node. Add `picker[type='page']` only when you specifically need to restrict to pages. This is the correct approach for `startNode` fields on listing components.
11. **Listing components require `jmix:list`, `jmix:renderableList`, `jmix:cache`** — any content type that auto-queries and renders a list of other nodes must extend these three mixins. Without them, Jahia's list rendering and cache invalidation do not work correctly.

### Adopted from `@jahia/agentic` (the upstream Jahia reference harness, v0.4.0)

- **Load CND reference files before writing any CND** — the Jahia-specific patterns (`choicelist[linkTypeInitializer]`, `mix:title`, child nodes for CTAs, `jmix:image` weakreferences, area types) are not in training data. Use `/jahia-cnd-author` (it loads the 9 `references/cnd-*.md` docs for you) for any non-trivial modeling, then validate with `/jahia-dev-review-cnd` until it reports PASS.
- **Use the TypeScript LSP for API discovery, never grep `node_modules`** — to learn a function signature or a module's exports, call `mcp__ide__getDiagnostics` on the file after writing it; the LSP reads live type definitions. Never grep `node_modules` for a name/signature.
- **MCP-first for all Jahia operations** — the `jahia` MCP server covers site, page, content, and publication. Never fall back to `curl` + GraphQL mutations for anything MCP can do. (GraphQL/`curl` reads stay valid where MCP has no equivalent.)
- **Run `/jahia-review` (or at least `/jahia-review-site`) after each deploy** — the site review runs the full axe ruleset + Lighthouse SEO audits and exits non-zero on ANY violation. It reads `pages-to-review.json` and writes `pages.json` only when everything passes — so `pages.json` existing IS the green signal. Fix all violations before declaring work done.

> See `AGENTIC-SYNC.md` for the full diff vs upstream and what we intentionally keep different.

## Migration / Website Import Principles

When migrating an existing website to Jahia or building a module inspired by an external site:

12. **Navigation must go 3 levels deep and use a Jahia Navigation Menu component** — never build direct hardcoded nav links or `<a>` lists. Create a `ns:mainNavigation` component type backed by the JCR page tree. Use `getChildNodes` on the home page for level 1, then recurse into level-1 children for level 2, and into level-2 children for level 3. Level 3 renders as a nested dropdown or fly-out. See the navigation patterns context.

13. **Use `linkTypeInitializer` for every contributor-facing link** — any link a contributor can configure (CTAs, banners, cards, teaser buttons, footer links, nav fallback items) must use `j:linkType (string, choicelist[linkTypeInitializer])` in the CND. This gives editors the choice of internal page, external URL, or none. Never declare a plain `string` field to store a URL.

14. **Never create CND properties for Tags or Categories** — Jahia has built-in capabilities. Do not invent custom `tags (string) multiple` or `category (string)` fields. Instead:
   - For free-form tags: extend `jmix:tagged` (adds `j:tagList`)
   - For taxonomy categories: use `(weakreference, category[autoSelectParent=false]) multiple`

15. **Always package a JCRQuery and GridRow component** — every migrated module ships these two structural components adapted to the module's namespace. They are the primary layout tools editors use without developer help.

16. **Design for mixin reuse from the start** — before writing a second content type, extract shared property groups into module-level mixins in `settings/definitions.cnd`. Common patterns: `nsmix:cta` (link + label), `nsmix:media` (image + alt + caption), `nsmix:badge` (label + color), `nsmix:seo` (metaTitle + metaDescription).

17. **Always add `ui.tooltip` to every resource bundle entry** — every property key in `.properties` files must have a companion `ui.tooltip` key with a plain-language description for editors.

```properties
ns_hero.title=Title
ns_hero.title.ui.tooltip=Main heading displayed at the top of the hero section.
ns_hero.j:linkType=Call to Action
ns_hero.j:linkType.ui.tooltip=Link for the primary CTA button. Choose internal page or external URL.
```

## Skill Map

Start with `/jahia` if unsure where to begin.

### Development

| Skill | Purpose |
|-------|---------|
| `/jahia-dev` | Entry point — detect project state, guide to next step |
| `/jahia-dev-create-template-set` | Scaffold a new Jahia JS module |
| `/jahia-dev-start-local` | Start Jahia locally (Docker or bare metal) |
| `/jahia-dev-build-component` | Build a complete component (CND + view) — start here |
| `/jahia-cnd-author` | CND modeling agent (`context: fork`): definition.cnd + types.ts + .properties, self-validating; loads 9 CND reference docs — from @jahia/agentic |
| `/jahia-dev-define-content-type` | Define a CND content type + types.ts (delegate depth to `/jahia-cnd-author`) |
| `/jahia-dev-review-cnd` | Lint a CND file for antipatterns (deterministic check-cnd.mjs) — run after writing any CND — from @jahia/agentic |
| `/jahia-dev-create-view` | Implement a React view (.server.tsx + CSS Module) |
| `/jahia-dev-create-page-template` | Create a page template with Areas |
| `/jahia-dev-query-content` | Write JCR-SQL2 queries and useJCRQuery |
| `/jahia-jcr-sql2` | Focused JCR-SQL2 query reference — from @jahia/agentic |
| `/jahia-review` | Full review umbrella: code + site review in parallel via subagents — from @jahia/agentic |
| `/jahia-review-code` | Code review: 12 critical checks, 9 warnings, 11 suggestions |
| `/jahia-review-site` | a11y (full axe ruleset) + SEO (Lighthouse) gate; writes `pages.json` on pass — from @jahia/agentic |
| `/jahia-dev-accessibility` | Audit live pages with axe-core, fix WCAG 2.1 AA violations |
| `/jahia-dev-screenshot` | Screenshot reference + local render for visual comparison |
| `/jahia-dev-migrate-jsp` | Migrate a JSP/Java template set to a JS module (audit → 3 scope questions → tag-by-tag port → companion Java bundle) — from @jahia/agentic |
| `/jahia-dev-debug` | Debug build/deploy/runtime errors end-to-end |

### Content Management

| Skill | Purpose |
|-------|---------|
| `/jahia-content` | Entry point — detect site state, route to content operations |
| `/jahia-content-explore-structure` | Map content types, properties, enums on an unknown site |
| `/jahia-content-query-content` | List and inspect content via GraphQL |
| `/jahia-content-create-content` | Create nodes, folders, articles, bulk-populate |
| `/jahia-content-move-content` | Restructure the content tree |
| `/jahia-content-translate-content` | Translate existing nodes to a new language and publish |

## Canonical References

Always fetch these when uncertain about version-sensitive topics:

| Topic | URL |
|-------|-----|
| Getting started / dev environment | https://academy.jahia.com/tutorials-get-started/front-end-developer/setting-up-your-dev-environment |
| Hero section tutorial | https://academy.jahia.com/tutorials-get-started/front-end-developer/making-a-hero-section |
| Blog / content listing | https://academy.jahia.com/tutorials-get-started/front-end-developer/making-a-blog |
| Page templates | https://academy.jahia.com/tutorials-get-started/front-end-developer/the-about-us-page |
| i18n (CND attribute, useTranslation, language switcher) | https://academy.jahia.com/documentation/jahia-cms/jahia-8-2/developer/javascript-module-development/preparing-for-internationalization-i18n |
| GraphQL API | https://academy.jahia.com/documentation/developer/jahia/8/api-documentation/graphql-api |
| Native Jahia mixins & node types | https://github.com/Jahia/jahia/tree/master/war/src/main/webapp/WEB-INF/etc/repository/nodetypes |
| JavaScript modules monorepo | https://github.com/Jahia/javascript-modules |
| Developer training | https://github.com/Jahia/developer-training/blob/main/js-training/slides.md |
| Integration best practices | https://github.com/Jahia/gautier-braindump/blob/main/articles/integration-best-practices/README.md |

## Local Development URLs

When Jahia is running at `http://localhost:8080` (default credentials: `root` / `root1234`):

- **Login**: http://localhost:8080/cms/login
- **Page Builder**: http://localhost:8080/jahia/page-builder
- **jContent**: http://localhost:8080/jahia/jcontent
- **GraphQL playground**: http://localhost:8080/modules/graphql
- **JCR browser**: http://localhost:8080/modules/tools/jcrBrowser.jsp
- **Definitions browser**: http://localhost:8080/modules/tools/definitionsBrowser.jsp
