# Agents — Jahia Development Harness

This directory is the **AI coding harness** for Jahia module development. It is the canonical source for "how we work here." Anything an agent should know across sessions belongs here, not in chat history.

If you are an AI agent, this is the second file you read after [`../CLAUDE.md`](../CLAUDE.md).

---

## Layout

```
.agents/
├── README.md             # This file — start here
├── context/              # Background reference docs (load when relevant)
│   └── jahia-platform.md # Jahia 8.2 architecture cheat sheet
└── skills/               # Step-by-step guides per domain
    ├── jahia/            # Top-level GPS — route to dev or content
    ├── jahia-dev/        # JS module GPS — detect state, pick next step
    ├── jahia-osgi-module/ # OSGi/Java module conventions
    ├── jahia-dev-*/      # JS module sub-skills (see skill map below)
    ├── jahia-content/    # Content management GPS
    └── jahia-content-*/  # Content management sub-skills
```

---

## Skill map

### JS/React module development

| Skill | When to use |
|---|---|
| [`/jahia`](skills/jahia/SKILL.md) | Top-level GPS — start here if unsure whether to build code or manage content |
| [`/jahia-dev`](skills/jahia-dev/SKILL.md) | JS module GPS — detect project state, recommend next step |
| [`/jahia-dev-create-template-set`](skills/jahia-dev-create-template-set/SKILL.md) | Scaffold a new JS/React module |
| [`/jahia-dev-start-local`](skills/jahia-dev-start-local/SKILL.md) | Start Jahia locally (Docker or bare metal) |
| [`/jahia-dev-build-component`](skills/jahia-dev-build-component/SKILL.md) | Build a complete component (CND + view) ← shortcut |
| [`/jahia-dev-define-content-type`](skills/jahia-dev-define-content-type/SKILL.md) | Define a CND content type + `types.ts` |
| [`/jahia-dev-create-view`](skills/jahia-dev-create-view/SKILL.md) | Implement a React view (`.server.tsx` + CSS Module) |
| [`/jahia-dev-create-page-template`](skills/jahia-dev-create-page-template/SKILL.md) | Create a page template with Areas |
| [`/jahia-dev-query-content`](skills/jahia-dev-query-content/SKILL.md) | Write JCR-SQL2 / `useJCRQuery` for content listings |
| [`/jahia-dev-review`](skills/jahia-dev-review/SKILL.md) | Code review: critical checks, warnings, suggestions |
| [`/jahia-dev-screenshot`](skills/jahia-dev-screenshot/SKILL.md) | Screenshot reference + Jahia render for visual comparison |
| [`/jahia-dev-debug`](skills/jahia-dev-debug/SKILL.md) | Debug build/deploy/runtime errors end-to-end |
| [`/jahia-dev-cypress`](skills/jahia-dev-cypress/SKILL.md) | Scaffold and write Cypress e2e tests: directory setup, site seed/teardown, addNode, CSS Module selectors, three mandatory spec files |

### OSGi UI extension development (React 18, Webpack, jcontent back-office)

| Skill | When to use |
|---|---|
| [`/jahia-osgi-ui-extension`](skills/jahia-osgi-ui-extension/SKILL.md) | Webpack/MF build, registry API, actions, dialogs, CSRF, TCCL, embedded libs |

### OSGi/Java module development (pure Java, no front-end)

| Skill | When to use |
|---|---|
| [`/jahia-osgi-module`](skills/jahia-osgi-module/SKILL.md) | Maven setup, DS annotations, JCR patterns, testing |

### Content management (running Jahia)

| Skill | When to use |
|---|---|
| [`/jahia-content`](skills/jahia-content/SKILL.md) | Content GPS — detect site state, route to sub-skill |
| [`/jahia-content-query-content`](skills/jahia-content-query-content/SKILL.md) | List, inspect, search content via GraphQL |
| [`/jahia-content-create-content`](skills/jahia-content-create-content/SKILL.md) | Create nodes, folders, articles, bulk-populate |
| [`/jahia-content-move-content`](skills/jahia-content-move-content/SKILL.md) | Restructure the content tree: move, rename, reorder |

### Context documents

| Document | When to load |
|---|---|
| [`context/jahia-development-guidelines.md`](context/jahia-development-guidelines.md) | **Always** — CTO review standards: GraphQL API design, service patterns, memory/batch rules, Javadoc requirements, Cypress testing, code quality |
| [`context/jahia-platform.md`](context/jahia-platform.md) | Any task requiring platform architecture recall (sessions, workspaces, service entry points) |
| [`context/jahia-frontend-backend-patterns.md`](context/jahia-frontend-backend-patterns.md) | Decision tree + complete code for all front-end/back-end patterns: built-in GraphQL, Java Action, external service proxy, GraphQL extension, OSGi service |
| [`context/jahia-selectortype-pattern.md`](context/jahia-selectortype-pattern.md) | Custom content editor widgets: registry.add('selectorType'), React component contract, JSON fieldset override, adaptValue/initValue, built-in keys, common pitfalls |
| [`context/javascript-modules-library-api.md`](context/javascript-modules-library-api.md) | Accurate API signatures and non-obvious behaviors for `@jahia/javascript-modules-library` (Island, Render, RenderChildren, useGQLQuery, getNodeProps Proxy, buildModuleFileUrl, getSiteLocales, AbsoluteArea readOnly) |
| [`context/jahia-js-reference-patterns.md`](context/jahia-js-reference-patterns.md) | Production patterns from real modules: design-system monorepo, Layout wrapper, cache invalidation, responsive images, CTA mixin, CSS variables with fallbacks, theme scoping, gql.tada, clsx, locale formatting, content-editor-forms fieldsets, empty area workaround |
| [`context/jahia-i18n-patterns.md`](context/jahia-i18n-patterns.md) | i18n file locations and key conventions for JS template sets (settings/resources + settings/locales) and OSGi modules (src/main/resources/resources); useTranslation, loadNamespaces, EN+FR minimum rule |

---

## How to extend this harness

1. If you find yourself repeating context across agent sessions → add a file to `context/`.
2. If you find yourself repeating step-by-step instructions → add a skill to `skills/`.
3. If a skill grows too long → split it. One concept per file.
4. Keep every file short and link-heavy. The harness is a map, not the territory.

## Conventions

- **Markdown only** in `.agents/`. No code, no config.
- **One concept per file.** Long files defeat the purpose.
- **Link, don't duplicate.** If a fact lives in `CLAUDE.md`, link to it.
- Skill files carry a YAML front-matter block with `name` and `description` — used by agent routers to decide relevance.
