# AIStartupKit — Jahia Module Development Reference

This is the **canonical orientation guide** for AI agents and developers working on Jahia modules in this repository. Read this first; follow skill pointers for specific tasks.

---

## What this repo is

A living agentic harness for Jahia module development. It is **not** a starter kit to clone — it is the reference agents and humans read to understand how to work here. New findings, conventions, and skills are added over time.

---

## The agentic harness pattern

**All new Jahia module development follows the agentic harness pattern.**

Every Jahia module project — whether a JS/React template set or an OSGi/Java bundle — includes a `.agents/` directory at its root. This directory is the canonical source of truth for how AI agents work in that project across sessions. It contains:

```
.agents/
├── README.md         # Skill map and harness index for this project
├── context/          # Background docs loaded by agents when relevant
│   └── *.md
└── skills/           # Step-by-step guides per domain
    └── <skill-name>/SKILL.md
```

Skills are durable, project-specific knowledge — not chat context that evaporates. If an agent finds itself repeating instructions across sessions, those instructions belong in a skill file.

This repo's harness lives at [`.agents/`](.agents/README.md). Start there after reading this file.

---

## Three module types

Jahia projects combine these as needed. They are complementary, not competing.

| Module type | React | Build tool | Use when |
|---|---|---|---|
| **JS template set** | **19** | Vite | Public site: pages, component views, content types |
| **OSGi UI extension** | **18** | Webpack + Module Federation | Back-office: jcontent actions, panels, dialogs |
| **OSGi/Java bundle** | — | Maven | Services, GraphQL extensions, Java integrations |

### React version is non-negotiable

- **React 19** → JS template sets only (`@jahia/javascript-modules-library`, Vite)
- **React 18** → OSGi UI extensions only (`@jahia/ui-extender`, Webpack)

Using the wrong React version will cause silent failures. The two contexts share the jcontent host's React 18 singleton for back-office work; the public renderer uses React 19 independently.

### How they relate

The template set controls how the public site renders. OSGi UI extensions extend what editors see in jcontent. OSGi Java bundles provide server-side services that either the template set or the UI extension can call (via GraphQL or direct Java service reference).

---

## Jahia Platform — Compact Reference

### Layered architecture

| Layer | Tech |
|---|---|
| Persistence | JCR 2.0 (`javax.jcr`) backed by Apache Jackrabbit |
| Domain services | `JahiaSitesService`, `JCRStoreService`, `JCRTemplate` |
| Module runtime | OSGi (Apache Karaf), Declarative Services |
| HTTP / API | Servlet API + Jahia render filters + GraphQL (`graphql-dxm-provider`) |
| Front-end UI | jContent (React), Page Builder |

### Key abstractions

- **Site (`jnt:virtualsite`)** — top-level scope. All content lives under `/sites/<siteKey>/`.
- **Page (`jnt:page`)** — rendered by a template; contains Areas with droppable components.
- **Content folder (`jnt:contentFolder`)** — stores `jmix:mainResource` content (articles, posts) that needs its own URL.
- **Node type definition (CND)** — schema for content. Both module types ship CND files.
- **Workspace** — `default` (editing) vs `live` (published). Always publish after mutations.
- **Locale** — content is multi-lingual via translation nodes; i18n properties need `language:` in GraphQL.

### JCR sessions (Java)

- `JCRSessionWrapper` is per-user, per-workspace, per-locale — **not thread-safe**.
- Obtain via `JCRTemplate.getInstance().doExecuteWithUserSession(user, workspace, locale, callback)`.
- Save explicitly (`session.save()`). Do not rely on auto-commit.
- Never hold a session reference across threads.

> Extended reference: [`.agents/context/jahia-platform.md`](.agents/context/jahia-platform.md)

---

## Track 1 — JS/React Template Set

### Prerequisites

- Node 18+ and Yarn 4+ (use `mise` to manage versions)
- Local Jahia running (Docker Compose recommended)
- **Never run `yarn dev` from an agent** — it is interactive only. Always use `yarn build && yarn jahia-deploy`.

### Module scaffold

```bash
npm init @jahia/module@latest <module-name>
cd <project-name> && yarn install
```

### Module structure

```
<module>/
├── src/
│   ├── components/<Category>/<Name>/   # Single Directory Components (SDC)
│   │   ├── definition.cnd             # Content type definition
│   │   ├── types.ts                   # TypeScript Props interface
│   │   ├── default.server.tsx         # Default SSR view
│   │   ├── <name>.client.tsx          # Client island (optional)
│   │   └── component.module.css
│   └── templates/Page/                # Page templates (.server.tsx)
├── settings/
│   ├── definitions.cnd                # Namespace + shared mixins
│   ├── resources/<module>.properties  # Editor labels (EN + FR minimum)
│   └── content-types-icons/           # 32×32 PNG per type
├── docker-compose.yml
└── package.json
```

### Component pipeline (always in order)

1. Confirm spec (name, fields, views, placement) with the user
2. Define content type → `definition.cnd` + `types.ts`
3. Implement view → `default.server.tsx` using `jahiaComponent()`
4. Style → `component.module.css`
5. Deploy → `yarn build && yarn jahia-deploy`

### Critical CND rules

- Extend `jnt:content` and the module's custom component mixin — **never** `jmix:droppableContent` directly.
- Two-tier mixin system: `namespacemix:component` (general) → `namespacemix:pageComponent` (page areas only).
- Default all user-facing string/text/richtext fields to `i18n`.
- All `types.ts` props use `?:` (optional) — Jahia does not guarantee values at render time.
- `jmix:mainResource` only for content that needs a listing card AND a full-page URL.
- Structural container types use `jmix:hiddenType` (not `jmix:studioOnly`).
- **Never declare `j:linknode` or `j:url` in a CND** — injected by Jahia's mixins at runtime.

### Critical view rules

- Import `Props` from `./types.js` (`.js` extension at import time).
- Use `buildNodeUrl(node)` for all node URLs. Guard optional nodes: `node ? buildNodeUrl(node) : undefined`.
- Never read properties from a weakreference node inline — render it via `<Render node={ref} />` for correct cache invalidation.
- **Never hardcode links or URLs.** All navigable links come from contributed content (`j:linkType`, `buildNodeUrl`, weakreference).
- Interactive components (carousels, tabs) render flat in edit mode via `renderContext.isEditMode()`.
- Client islands: component in `.client.tsx`, wrapped with `<Island>` in the server view. Props must be serializable — no JCR objects.

### Scale of thumbs

A well-scoped module: 1–4 page templates, 5–10 content types, 2–5 mixins, 1–4 views per type.

---

## Track 2 — OSGi UI Extension

### What it is

A Webpack/Module Federation bundle that extends the **jcontent back-office** — adding toolbar action buttons, dialogs, admin panels, or sidebar panels. It is an OSGi bundle (Maven) that happens to include a compiled React 18 front-end.

### Build stack

- **Webpack** + `@jahia/webpack-config` (Module Federation)
- **React 18**, MUI 5, `@jahia/ui-extender`, `@jahia/moonstone`
- **Maven** `frontend-maven-plugin` runs `yarn build:production` during `mvn install`
- Output lands in `src/main/resources/javascript/apps/` (committed output — not `.gitignore`'d)

### Registration lifecycle

```
Maven build → webpack → remoteEntry.js in resources/javascript/apps/
     ↓
jcontent loads → jahiaApp-init:N callback fires
     ↓
init.js → await i18next.loadNamespaces() → register actions/panels
     ↓
registry.add('action', name, { targets, component })
```

### Java Action class (back-office → Java)

```java
@Component(service = Action.class)
public class MyAction extends Action {
    @Override public String getName() { return "myActionName"; }

    @Override
    public ActionResult doExecute(HttpServletRequest req, RenderContext ctx,
            Resource resource, JCRSessionWrapper session,
            Map<String, List<String>> params, URLResolver urlResolver) throws Exception {
        // runs as authenticated user — never escalate to system session
        // stream binary response or return JSON ActionResult
    }
}
```

Action endpoint: `POST /cms/render/default/{lang}{path}.{actionName}.do`

### CSRF guard (required for every Action)

```properties
# src/main/resources/META-INF/configurations/org.jahia.modules.jahiacsrfguard-<module>.cfg
whitelist = *.myActionName.do
```

### Critical rules for UI extensions

- `<Dialog disableEnforceFocus>` on all MUI dialogs rendered in portals — without it, FocusTrap causes an infinite loop.
- All dialogs rendered via a portal manager (`ReactDOM.createRoot` into `document.body`) — never inside the jcontent component tree.
- `window.jahia.*` APIs (`toastDispatcher`, `CE_API.openPicker`, `contextJsParameters`) always guarded with `?.`.
- RenderContext ordering when rendering page HTML from Java: `setSite()` → `setWorkspace()` → `setServletPath()` → `setMainResource()`.
- Embedded libraries that use `ServiceLoader` / `IIORegistry` (e.g. TwelveMonkeys ImageIO): instantiate SPI classes directly via the bundle's own classloader — never via global registries that go stale on bundle refresh.
- Switch TCCL (`Thread.currentThread().setContextClassLoader(getClass().getClassLoader())`) for any embedded library that reads it internally. Always restore in `finally`.

> Full detail: [`.agents/skills/jahia-osgi-ui-extension/SKILL.md`](.agents/skills/jahia-osgi-ui-extension/SKILL.md)

---

## Track 3 — OSGi/Java Bundle

### Maven invariants

- Parent POM: `org.jahia.modules:jahia-modules:8.2.0.0` — do not bump without a documented decision.
- Packaging: `bundle`. Manifest generated by `maven-bundle-plugin` (BND). Do not redeclare headers the parent already sets.
- Jahia API dependencies: `org.jahia.server:jahia-impl` and `jahia-api`, both `<scope>provided</scope>`. Exclude all transitives from `jahia-impl`.

### OSGi conventions

- Use **Declarative Services (DS)** annotations: `@Component`, `@Reference`, `@Activate`.
- Never use Blueprint or `BundleActivator` for new code.
- Services in a public SPI: `@Component(service = MyInterface.class)`.
- Public packages declared in `Export-Package`. Internal code under `*.internal.*` — not exported.

### Java baseline

- Java 17 max. Records, sealed types, pattern matching, `var` are all fine.
- Do not use Java 21+ features.

### JCR access

- Always run mutations as the calling user: `JCRTemplate.getInstance().doExecuteWithUserSession(...)`.
- For public-facing write actions (likes, reactions) where users don't own the target node, use `JCRTemplate.getInstance().doExecuteWithSystemSession(cb)` and record the username as a property on the created node.
- `JCRSessionWrapper` is not thread-safe — never hold across threads.

### Action endpoint workspaces

- Action URL always uses `live` workspace: `POST /cms/render/live/{lang}/sites/{siteKey}.{actionName}.do` — this is what OIDC-authenticated site readers can call.
- The `session` passed to `doExecute` is the live workspace session (read-only for content). Re-open a default session internally when writes are needed.

> Detailed reference: [`.agents/skills/jahia-osgi-module/SKILL.md`](.agents/skills/jahia-osgi-module/SKILL.md) and [`.agents/skills/jahia-dev-java/SKILL.md`](.agents/skills/jahia-dev-java/SKILL.md)

---

## Skill map

The full harness index is at [`.agents/README.md`](.agents/README.md). Quick reference:

### JS/React development

| Skill | Purpose |
|---|---|
| `/jahia` | Top-level GPS — start here if unsure |
| `/jahia-dev` | JS module GPS — detect state, pick next step |
| `/jahia-dev-create-template-set` | Scaffold a new JS/React module |
| `/jahia-dev-start-local` | Start Jahia locally |
| `/jahia-dev-build-component` | Build complete component (CND + view) ← shortcut |
| `/jahia-dev-define-content-type` | Define CND + `types.ts` |
| `/jahia-dev-create-view` | Implement React view + CSS Module |
| `/jahia-dev-create-page-template` | Create page template with Areas |
| `/jahia-dev-query-content` | JCR-SQL2 / `useJCRQuery` content listings |
| `/jahia-dev-review` | Code review: critical, warnings, suggestions |
| `/jahia-dev-screenshot` | Visual comparison: reference vs Jahia render |
| `/jahia-dev-debug` | Debug build/deploy/runtime errors |
| `/jahia-dev-cypress` | Scaffold Cypress e2e tests for any new component |

### Java actions (JS module + Java backend)

| Skill | Purpose |
|---|---|
| `/jahia-dev-java` | Action framework: live vs default workspace, system session, CSRF, Maven Java 17 |

### OSGi development

| Skill | Purpose |
|---|---|
| `/jahia-osgi-ui-extension` | Webpack/MF build, registry, actions, dialogs, CSRF, TCCL |
| `/jahia-osgi-module` | Maven, DS annotations, JCR patterns, Java services |

### Content management

| Skill | Purpose |
|---|---|
| `/jahia-content` | Content GPS — detect site state, route to sub-skill |
| `/jahia-content-query-content` | Query and inspect content via GraphQL |
| `/jahia-content-create-content` | Create nodes, folders, articles, bulk-populate |
| `/jahia-content-move-content` | Move, rename, reorder content tree |

---

## Development guidelines (CTO review standards)

All new code — regardless of module type — is held to these standards at merge time. Full detail: [`.agents/context/jahia-development-guidelines.md`](.agents/context/jahia-development-guidelines.md).

- **GraphQL APIs**: design for GraphQL, not as a port of another transport. Reuse `GQLJCRNode`. Inject via `@Inject @GraphQLOsgiService`. Authorize once in the mutation type constructor, not per-operation.
- **Services**: separate business logic from the GQL layer. Reuse platform batch APIs (`TaggingService`, pagination helpers). Don't thread singleton references through parameter chains.
- **Batch operations**: return counts + paths (strings), not full node instances. Enforce a maximum failure count. Use the two-interaction pattern (summary mutation → lazy detail query).
- **Performance**: single-pass loops. No redundant iterations over the same data.
- **Package structure**: `graphql/`, `service/spi/`, `service/internal/`, `model/`, `servlet/` — never flat.
- **Javadoc**: every public service class and method. Documents role, threading, params, return, throws. Critical for AI-assisted development quality.
- **Tests**: Cypress from the start. Happy path, authorization failure, edge cases. Not the legacy test framework.

---

## Non-negotiable rules (both tracks)

**All tracks**
1. **Never escalate to a system JCR session** for content the calling user authored or requested.
2. **Always publish after JCR mutations.** Writes go to `default`; live visitors see `live`.
3. **Always include `-H "Origin: http://localhost:8080"`** in GraphQL curl requests.
4. **New Jahia module projects include a `.agents/` directory** following the harness pattern above.
5. **All modules ship EN and FR at minimum.** No module ships English-only. See [i18n patterns](.agents/context/jahia-i18n-patterns.md) for file locations.

**JS template sets (Track 1)**

6. **Never use `yarn dev` from an agent.** Always use `yarn build && yarn jahia-deploy`.
7. **Never hardcode UI strings in views** — use `t("key")` from `useTranslation()`. Front-end labels go in `settings/locales/en.json` + `fr.json`. CND labels go in `settings/resources/<module>_en.properties` + `_fr.properties`.
8. **Never hardcode links or URLs** in views or templates. All navigable links come from contributed content.
9. **Never use `jmix:studioOnly`** on structural types — use `jmix:hiddenType`.
10. **Never declare `j:linknode` or `j:url` in a CND** — they are injected by Jahia's mixins.
17. **Any mixin that stores hidden child nodes must declare `+ childName (Type) = Type version` in the mixin body.** Without this, `session.addNode()` throws `ConstraintViolationException: No child node definition found` at runtime. The child node definition in the mixin is what grants Jackrabbit permission to add that child to any node of a type that extends the mixin.
18. **Keep all locale JSON files in sync (`fr.json`, `en.json`, `es.json`).** A key present in one file but missing in another renders as the raw key for visitors using that language.

**OSGi UI extensions (Track 2)**

11. **React 18 only.** Never import React 19 APIs in a UI extension — the host jcontent singleton is React 18.
12. **Always use `<Dialog disableEnforceFocus>`** for MUI dialogs rendered in portals.
13. **Every Action needs a CSRF Guard config file.** No `.cfg` = every POST is rejected.
14. **RenderContext order:** `setSite()` → `setWorkspace()` → `setServletPath()` → `setMainResource()`. Out of order causes silent rendering failures.
15. **Embedded SPI libraries (ImageIO, ServiceLoader):** instantiate via bundle classloader directly — never via global registries. Switch TCCL, restore in `finally`.
16. **Call `loadNamespaces('module-name')` before registering any UI extension.** Missing this means all `'module:label.key'` strings render as raw keys.

---

## Tooling URLs (local dev)

| Tool | URL |
|---|---|
| Jahia UI | http://localhost:8080 — default credentials: `root` / `root` |
| GraphQL playground | http://localhost:8080/modules/graphql |
| JCR browser | http://localhost:8080/modules/tools/jcrBrowser.jsp |
| Installed definitions | http://localhost:8080/modules/tools/definitionsBrowser.jsp |

---

## Further reading

- Jahia 8 documentation: https://academy.jahia.com
- Front-end tutorials: https://academy.jahia.com/tutorials-get-started/front-end-developer
- JavaScript modules monorepo: https://github.com/Jahia/javascript-modules
- JavaScript components (data-helper, ui-extender, moonstone): https://github.com/Jahia/javascript-components
- `@jahia/javascript-modules-library` API reference: [`.agents/context/javascript-modules-library-api.md`](.agents/context/javascript-modules-library-api.md)
- Production patterns reference (luxe-jahia-demo): [`.agents/context/jahia-js-reference-patterns.md`](.agents/context/jahia-js-reference-patterns.md)
- Front-end/back-end communication patterns: [`.agents/context/jahia-frontend-backend-patterns.md`](.agents/context/jahia-frontend-backend-patterns.md)
- **GraphQL schema reference** (introspected from live instance — JCRQuery, JCRMutation, JCRNode, JCRProperty, all input types, enums, survey extension, common patterns, traps): [`.agents/context/jahia-graphql-schema-reference.md`](.agents/context/jahia-graphql-schema-reference.md)
- Custom content editor widgets (SelectorType): [`.agents/context/jahia-selectortype-pattern.md`](.agents/context/jahia-selectortype-pattern.md)
- i18n file locations, key conventions, useTranslation, loadNamespaces: [`.agents/context/jahia-i18n-patterns.md`](.agents/context/jahia-i18n-patterns.md)
- Native node types (CND source): https://github.com/Jahia/jahia/tree/master/war/src/main/webapp/WEB-INF/etc/repository/nodetypes
- Developer training slides: https://github.com/Jahia/developer-training/blob/main/js-training/slides.md
