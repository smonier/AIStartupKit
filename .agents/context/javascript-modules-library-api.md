# Context — `@jahia/javascript-modules-library` API Reference

Accurate signatures and non-obvious behaviors for the public API of `@jahia/javascript-modules-library` (from the `javascript-modules` monorepo). Agents should load this when implementing or debugging views, hooks, or utilities in a JS template set.

---

## Registration

### `jahiaComponent(config, component)`

Registers a React server component with Jahia.

```ts
jahiaComponent(
  {
    componentType: "view" | "template",
    nodeType: "namespace:typeName",
    displayName?: string,
    name?: string,            // omit for the default view
    properties?: {
      "cache.expiration"?: string,   // seconds as string, e.g. "60"
      "cache.perUser"?: "true",
    },
  },
  (props: Props, context: ServerContext) => ReactElement | null,
)
```

`properties` also accepts `"cache.mainResource": "true"`: the fragment's cache key then includes the
main resource. Use it for the few per-page parts of shared chrome (a language switcher linking to
the current page in other languages); verified on 8.2.3.2.

The `props` object is a **Proxy** built by `getNodeProps(currentNode)` — property reads are lazy JCR calls. All props use `?:` optional types regardless of CND `mandatory` status.

**Auto-generated component ID**: `${bundleKey}_${componentType}_${nodeType}_${name}` — used internally by the engine.

---

## Hooks (server-side only)

### `useServerContext()`

Returns the full rendering context. Call only inside `.server.tsx` (the engine passes context implicitly).

```ts
interface ServerContext {
  renderContext: RenderContext;  // org.jahia.services.render.RenderContext
  currentResource: Resource;     // org.jahia.services.render.Resource
  currentNode: JCRNodeWrapper;   // the node being rendered
  mainNode: JCRNodeWrapper;      // the page's main resource node
  jcrSession: JCRSessionWrapper; // current JCR session (do NOT save across calls)
  bundleKey: string;             // e.g. "my-module"
}
```

Common uses:
```tsx
const { renderContext, currentNode, mainNode, jcrSession } = useServerContext();
const siteKey = renderContext.getSite().getName();
const isEdit = renderContext.isEditMode();
```

> The site: `renderContext.getSite()` is a `JCRSiteNode`. Its type comes from
> `import type { JCRSiteNode } from "org.jahia.services.content.decorator"` (not
> `org.jahia.services.content`). It has `getTitle()` (native `j:title`), `getHome()` (the home page,
> owner of shared AbsoluteAreas) and the usual node API.
>
> Cache dependency on a node outside the rendered subtree:
> `server.render.addCacheDependency({ node }, renderContext)` (also `{ path }`, `{ uuid }`,
> `{ flushOnPathMatchingRegexp }`), with `server` imported from the library.

> `mainNode` is the page, not the component. Use `currentNode` for the component's own data. Use `jcrSession` for JCR reads that cannot go through props (e.g. reading a node by path in a computed listing).

---

### `useGQLQuery<T>(query, variables?)`

Executes a GraphQL query **synchronously** on the server using `server.gql.executeQuerySync`. Returns the `data` portion of the response.

```ts
import { useGQLQuery } from "@jahia/javascript-modules-library";
import { gql } from "graphql-tag";

const SITE_QUERY = gql`
  query GetSiteNodes($path: String!) {
    jcr {
      nodeByPath(path: $path) {
        displayName
        children { nodes { name path } }
      }
    }
  }
`;

jahiaComponent(
  { componentType: "view", nodeType: "ns:listing" },
  (_, { renderContext }) => {
    const siteKey = renderContext.getSite().getName();
    const data = useGQLQuery(SITE_QUERY, { path: `/sites/${siteKey}/contents` });
    const nodes = data?.jcr?.nodeByPath?.children?.nodes ?? [];
    return <ul>{nodes.map(n => <li key={n.path}>{n.displayName}</li>)}</ul>;
  },
);
```

> Accepts `TypedDocumentNode` — pair with `graphql-codegen` for full type safety. Falls back to `any` without it.

---

### `useJCRQuery(options)`

Server-side JCR-SQL2 query. Wraps `getNodesByJCRQuery` using the session from `mainResource.getNode()`.

```ts
const nodes = useJCRQuery({
  query: "SELECT * FROM [ns:type] WHERE ISDESCENDANTNODE(node, '/sites/mysite/contents')",
  limit?: number,
  offset?: number,
});
// Returns JCRNodeWrapper[]
```

Use `useGQLQuery` when you need field-level projection or cross-node data in one round trip. Use `useJCRQuery` for simple node listings where you'll call Java methods on the results.

---

## Components

### `<Island component={C} props={P} clientOnly?>`

Hydrates a `.client.tsx` component in the browser. Uses `devalue` for serialization; props must be JSON-safe (no JCR objects, no functions).

```tsx
import Counter from "./Counter.client.jsx";  // .jsx at import time

<Island component={Counter} props={{ count: 0, label: "Clicks" }} />
```

`clientOnly` skips SSR entirely — required for components that use `window`/`document`:

```tsx
<Island component={MapWidget} props={{ lat, lng }} clientOnly>
  <p>Loading map…</p>   {/* fallback until hydration */}
</Island>
```

---

### `<Render node? path? content? view? params?>`

Four call signatures:

```tsx
<Render node={jcrNode} />                        // render a node
<Render node={jcrNode} view="small" />           // render with named view
<Render path="/sites/mysite/home" />             // render by path
<Render content={{ nodeType: "ns:navBar" }} />   // render a virtual node (no JCR storage)
```

Virtual node rendering is the correct pattern for structural components (navbars, footers) that have no authored content — avoids creating dummy JCR nodes.

---

### `<RenderChild name view? readOnly?>`

Renders a named child node. Shows `AddContentButtons` in edit mode when the child doesn't exist.

```tsx
<RenderChild name="hero" />
<RenderChild name="sidebar" view="compact" />
<RenderChild name="footer" readOnly={true} />
```

---

### `<RenderChildren pagination? filter?>`

Renders all child nodes. Supports two pagination styles and optional filtering.

```tsx
// No pagination (all children)
<RenderChildren />

// Offset pagination
<RenderChildren pagination={{ count: 10, start: 0 }} />

// Page-based pagination
<RenderChildren pagination={{ count: 10, page: 0 }} />

// Filter by node type (string or function)
<RenderChildren filter="ns:cardType" />
<RenderChildren filter={(node) => node.isNodeType("ns:highlight")} />

// Combined
<RenderChildren pagination={{ count: 5, page: 0 }} filter="ns:blogPost" />
```

---

### `<Area name nodeType? areaType?>`

Editorial drop zone — scoped to the current page. Default `nodeType` is `"jnt:contentList"`.

```tsx
<Area name="main" />
<Area name="sidebar" nodeType="ns:sidebarArea" />
```

---

### `<AbsoluteArea name parent nodeType? readOnly?>`

Like Area but shared across pages. `parent` is the node that OWNS the area node.

> 🚨 **Parent shared header/footer on the home page, never on `renderContext.getSite()`.** The site node is not a page: Page Builder never offers it, so an area parented there renders everywhere and is editable nowhere. Use `site.getHome()` (fall back to the site only while home does not exist). Proven on tenant-portal, 2026-09-22; existing content is fixed with `mutateNode.move` + publish.

The `readOnly` prop, as it actually behaves (checked in the Page Builder edit frame, engine 1.2.0 on
Jahia 8.2.3.2). The engine maps `"children"` to core's `limitedAbsoluteAreaEdit`, and the library's
doc comment ("read-only except on the page containing its node") does not match what happens:

| `readOnly` | Area marker | Children editable | Where |
|---|---|---|---|
| `false` (default) | yes | yes | every page |
| `true` | no | **yes** (children keep their module markers) | every page |
| `"children"` | no | no | **every page, home included** |

So "edit the header from the home page only" is computed per page:

```tsx
const { renderContext, mainNode } = useServerContext();
const home = renderContext.getSite().getHome();
const readOnly = mainNode.getPath() === home.getPath() ? false : "children";

<AbsoluteArea name="siteFooter" parent={home} nodeType="ns:footerArea" readOnly={readOnly} />
```

Verify with the edit frame (`/cms/editframe/default/<lang>/sites/<site>/<page>.html` with a
session): on home the area shows `jahiatype="module" ... type="absoluteArea"`; on any other page
no marker under the area path at all. Rendering the chrome in the edit frame is not proof that it
is editable.

---

### `<AddResources type resources key?>`

Injects CSS or JS resources into `<head>` or `<body>`. Deduplicates by `key`.

```tsx
<AddResources type="css" resources={buildModuleFileUrl("css/vendor.css")} key="my-module-css" />
<AddResources type="javascript" resources={buildModuleFileUrl("js/analytics.js")} key="my-module-js" />
```

> Scripts shipped in the module's `static/` folder load the same way:
> `<AddResources type="javascript" resources={buildModuleFileUrl("static/js/navigation.js")} key="ns-navigation" />`
> (with `/static` in `jahia.static-resources`). Prefer that to an inline `<script>`, which needs
> `dangerouslySetInnerHTML` and is always flagged by jahia-security-scan R10.
>
> **CRITICAL**: The prop is `resources` (not `url`). Passing `url` silently does nothing — TypeScript will error if strict. **Always** wrap the path with `buildModuleFileUrl()` — a bare string like `"dist/assets/style.css"` does not resolve to the correct module-scoped URL at runtime and the resource will never load. The `key` prop is required for deduplication when the same component can be placed multiple times on a page.

---

### `<AddContentButtons name? nodeType? parent?>`

Renders jContent's "Add Content" button in edit mode. Normally injected automatically by `RenderChild`; use this explicitly in custom edit-mode layouts.

---

## Utilities

### `buildNodeUrl(node, options?)`

Converts a `JCRNodeWrapper` to a URL. Never call with `undefined` — throws.

```ts
buildNodeUrl(node)
// → /sites/mysite/contents/blog/my-post.html (live workspace URL)

buildNodeUrl(node, { language: "fr" })
// → French variant of the same URL

buildNodeUrl(node, { extension: "json" })
// → /sites/mysite/contents/blog/my-post.json
```

---

### `buildModuleFileUrl(relativePath)`

Constructs the URL to a static file inside the module's bundle (CSS, JS, images).

```ts
buildModuleFileUrl("images/logo.svg")
// → /modules/my-module/javascript/apps/images/logo.svg (resolved at runtime)
```

Use for static assets that ship with the module — never hardcode `/modules/my-module/...`.

---

### `buildEndpointUrl(actionPath)`

Constructs the URL to a Java Action endpoint.

```ts
buildEndpointUrl("myActionName")
// → /cms/render/default/{lang}{path}.myActionName.do
```

---

### `getNodeProps(node)` — the Proxy under `jahiaComponent`

`jahiaComponent` wraps `props` in a `Proxy` that lazily reads JCR properties:

| CND type | Proxy returns |
|---|---|
| `string`, `name`, `path`, `uri` | `property.getString()` |
| `long` | `property.getLong()` (Java long) |
| `double` | `property.getDouble()` |
| `boolean` | `property.getBoolean()` |
| `date` | `property.getString()` — an **ISO 8601 string**, NOT a JS `Date` |
| `weakreference`, `reference` | `value.getNode()` — returns `JCRNodeWrapper` |
| `binary` | `property.getBinary()` — Jackrabbit `Binary` handle |
| `multiple` property | `property.getValues().map(unwrap)` — returns an array |
| Missing property | `undefined` |

> **`date` is always a string**: use `new Date(dateString)` or `dateString.toLocaleDateString(...)` in the view.
> **`weakreference` is a node**: call `.getPath()`, `.getDisplayableName()`, or pass to `buildNodeUrl()`.

---

### `getChildNodes(node, limit, offset, filterFn?)`

Returns an array of child nodes (no JCR iterator boilerplate).

```ts
import { getChildNodes } from "@jahia/javascript-modules-library";
import type { JCRNodeWrapper } from "org.jahia.services.content";

const pages = getChildNodes(
  renderContext.getSite(),
  -1,   // -1 = no limit
  0,    // offset
  (node: JCRNodeWrapper) => node.isNodeType("jnt:page"),
);
```

---

### `getNodesByJCRQuery(session, query, limit?, offset?)`

Direct JCR-SQL2 query returning `JCRNodeWrapper[]`.

```ts
import { getNodesByJCRQuery } from "@jahia/javascript-modules-library";

const posts = getNodesByJCRQuery(
  jcrSession,
  `SELECT * FROM [ns:post] WHERE ISDESCENDANTNODE(node, '/sites/${siteKey}/contents/blog')`,
  20,  // limit
  0,   // offset
);
```

---

### `getSiteLocales()`

Returns all configured site locales. Used to build language switchers.

```ts
import { getSiteLocales } from "@jahia/javascript-modules-library";

const locales = getSiteLocales();
// Returns Record<string, java.util.Locale>
// Keys are language codes: "en", "fr", "de", ...
```

**Language switcher pattern** — filter by `j:invalidLanguages` and `node.hasI18N()`:

```tsx
import { getSiteLocales, buildNodeUrl, useServerContext } from "@jahia/javascript-modules-library";

jahiaComponent(
  { componentType: "view", nodeType: "ns:languageSwitcher" },
  (_, { renderContext, currentNode }) => {
    const locales = getSiteLocales();
    const invalidProp = currentNode.hasProperty("j:invalidLanguages")
      ? currentNode.getProperty("j:invalidLanguages").getValues().map((v: any) => v.getString())
      : [];
    const invalidSet = new Set(invalidProp);

    const links = Object.entries(locales)
      .filter(([code, locale]) => !invalidSet.has(code) && currentNode.hasI18N(locale))
      .map(([code]) => ({
        code,
        url: buildNodeUrl(currentNode, { language: code }),
      }));

    return (
      <nav>
        {links.map(({ code, url }) => (
          <a key={code} href={url} lang={code}>{code.toUpperCase()}</a>
        ))}
      </nav>
    );
  },
);
```

---

## Full public API surface

```ts
// Components
export { Island, Render, RenderChild, RenderChildren }
export { Area, AbsoluteArea }
export { AddResources, AddContentButtons }

// Registration
export { jahiaComponent }

// Hooks (server-side)
export { useServerContext, useGQLQuery, useJCRQuery }

// JCR utilities
export { getNodeProps, getChildNodes, getNodesByJCRQuery }

// URL builders
export { buildNodeUrl, buildModuleFileUrl, buildEndpointUrl }

// i18n
export { getSiteLocales }

// Low-level server access (rarely needed directly)
export { server }   // server.gql.executeQuerySync — used internally by useGQLQuery
```

---

## References

- Source: https://github.com/Jahia/javascript-modules/tree/main/packages/javascript-modules-library/src
- `@jahia/data-helper` (useNodeChecks etc.): https://github.com/Jahia/javascript-components/tree/master/packages/data-helper
