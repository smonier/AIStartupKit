# Context — Jahia Front-End / Back-End Communication Patterns

Decision guide and implementation reference for all the ways a Jahia front-end (JS template set or UI extension) can talk to server-side logic. Load this when designing or implementing any feature that crosses the HTTP boundary.

---

## Decision tree

```
Need to communicate from front-end to back-end?
│
├─ Reading JCR data only (no business logic)?
│   ├─ From a UI extension (React 18, jcontent) → Jahia built-in GraphQL
│   └─ From a JS template set (server-side .server.tsx) → useJCRQuery / useGQLQuery
│
├─ Running business logic or calling an external service?
│   ├─ 1–3 endpoints, UI-only → Java Action (one class per endpoint)
│   ├─ Many endpoints, REST API style → Servlet filter with route dispatch
│   ├─ Complex domain logic shared by multiple callers → OSGi service + Action/servlet façade
│   └─ Needs to be queryable from external tools / DX APIs → GraphQL extension
│
├─ Calling an external API (Anthropic, OpenAI, CRM, etc.)?
│   ├─ Stateless (API key only) → Java Action proxy
│   └─ Session-based (cookie/token lifecycle) → OSGi session service + servlet proxy
│       └─ API key in .cfg, session cookie stored in-process, browser never sees either
│
└─ Writing JCR nodes from a UI extension?
    └─ Jahia built-in GraphQL mutation (jcr.addNode, jcr.mutateNode)
```

---

## Island Hydration — Server → Client Props

Islands are the **only supported hydration pattern** in JS template sets. `HydrateInBrowser`/`HydrateOnClient` are deprecated.

### Critical rule: never pass `props={props}`

```tsx
// ❌ WRONG — currentNode (JCR proxy) cannot be serialized by Island
export default function MyView(props: ServerProps) {
  return <Island component={MyClient} props={props} />;
}

// ✅ CORRECT — destructure to a plain serializable object
export default function MyView({ currentNode, renderContext }: ServerProps) {
  const title = currentNode.getProperty("jcr:title").getString();
  const count = currentNode.hasProperty("count")
    ? Number(currentNode.getProperty("count").getString())
    : 0;

  return <Island component={MyClient} props={{ title, count }} />;
}
```

**Why:** `Island` serializes props to JSON for client hydration. A `JCRNodeWrapper` is a Java proxy — it throws during JSON serialization. Always pass only primitives, plain objects, or arrays to `props`.

### CSS rule: regular CSS for client components

| Component type | CSS approach | Reason |
|---|---|---|
| Server (`.server.tsx`) | `component.module.css` ✅ | Scoped class names are safe — rendered once on server |
| Client (`.client.tsx`) | `component.css` ✅ | Regular CSS — class names must match between server and client |
| Client (`.client.tsx`) | ~~`component.module.css`~~ ❌ | Vite transforms class names → mismatch breaks hydration |

```tsx
// ✅ Server component — CSS Modules fine
import styles from "./HeroSection.module.css";
export default function HeroSection() {
  return <Island component={HeroSectionClient} props={{ ... }} />;
}

// ✅ Client component — regular CSS import only
import "./HeroSectionClient.css";
export default function HeroSectionClient({ title }: Props) {
  return <section className="hero-section"><h1>{title}</h1></section>;
}
```

### CSS rule for add-on modules: use `<AddResources>`

A **template set** (`module-type: "templatesSet"`) controls the page `<head>` and can include a `<link>` tag for `dist/assets/style.css` directly in its main template.

An **add-on module** (`module-type: "module"`) does not control the page — its CSS is never automatically injected. Use `<AddResources>` in every server view that needs styling:

```tsx
import { AddResources, jahiaComponent } from "@jahia/javascript-modules-library";

// Inside the jahiaComponent return:
return (
  <>
    <AddResources
      type="css"
      resources="dist/assets/style.css"
      key="my-module-css"           // ← deduplicates when multiple components appear on one page
    />
    <section className={classes.section}>
      ...
    </section>
  </>
);
```

`resources` is relative to the module root. Jahia resolves it to `/modules/<module-name>/dist/assets/style.css`.  
The `key` prop prevents duplicate `<link>` tags when several components from the same module appear on one page.

### Node URL rule: `buildNodeUrl(node)`, never `node.getPath()`

`node.getPath()` returns the raw JCR path (e.g. `/sites/mysite/contents/blog/my-post`). Used as an `href`, Jahia cannot route it and redirects to the homepage.

`buildNodeUrl(node)` builds the correct rendered URL including workspace, locale, and `.html` extension. Use it everywhere:

```tsx
import { buildNodeUrl } from "@jahia/javascript-modules-library";

// ✅ Server view — current node
const url = buildNodeUrl(currentNode);

// ✅ Server view — related node (e.g. transforming a list of JCR nodes to Island props)
const events = nodes.map(node => ({
  url: buildNodeUrl(node),    // ← correct
  // url: node.getPath(),     // ← WRONG — redirects to homepage
  title: node.getProperty("title").getString(),
}));
```

`buildNodeUrl` is also available client-side but requires `renderContext` passed explicitly — prefer resolving URLs server-side and passing the string as an Island prop.

---

## Pattern 1 — Jahia built-in GraphQL (no Java code required)

**When:** Reading or writing JCR data from a UI extension. Jahia exposes the full JCR tree, forms API, and workspace operations out of the box.

**Endpoint:** `POST /modules/graphql`

**Authentication:** Session cookie (`credentials: 'same-origin'`) + `X-Requested-With: XMLHttpRequest` header. GraphQL respects the user's JCR ACLs — agents see only what they have permission for.

### Required headers — missing any causes "Permission denied"

When calling the GraphQL endpoint directly (curl, scripts, introspection), all of these headers are required:

```bash
curl -s -X POST http://localhost:8080/modules/graphql \
  -u root:root \
  -H 'Origin: http://localhost:8080' \
  -H 'Referer: http://localhost:8080/jahia/developerTools/graphql-workspace' \
  -H 'accept: application/json, multipart/mixed' \
  -H 'content-type: application/json' \
  -d '{"query":"{ jcr { nodeByPath(path: \"/sites\") { name } } }"}'
```

| Header | Why required |
|---|---|
| `Origin` + `Referer` | CSRF guard checks same-origin — missing either → 403 |
| `-u root:root` | Basic auth (dev only) or replace with `Cookie: SESSION=...` for production |
| `accept: application/json, multipart/mixed` | Jahia returns `multipart/mixed` for subscriptions — plain `application/json` causes parse errors on some responses |
| `content-type: application/json` | Required for POST body to be read as JSON |

> For the **Jahia GraphQL Workspace** UI, the browser sends all these automatically. For scripts and migrations, they must be set explicitly.

### From a UI extension (React 18, Apollo)

```javascript
// Apollo client setup (init.js or apolloClient.js)
import { ApolloClient, InMemoryCache, createHttpLink } from '@apollo/client';

const client = new ApolloClient({
  link: createHttpLink({
    uri: '/modules/graphql',
    headers: { 'X-Requested-With': 'XMLHttpRequest' },
    credentials: 'same-origin',
  }),
  cache: new InMemoryCache(),
});

// Reading a node's properties
const GET_NODE = gql`
  query GetNode($path: String!, $lang: String!) {
    jcr {
      nodeByPath(path: $path) {
        displayName
        property(name: "jcr:title", language: $lang) { value }
        children { nodes { name path primaryNodeType { name } } }
      }
    }
  }
`;

const { data } = useQuery(GET_NODE, { variables: { path, lang } });
```

### Writing JCR nodes (UI extension → GraphQL mutation)

```javascript
const UPLOAD_FILE = gql`
  mutation UploadFile($name: String!, $parentPath: String!, $mimeType: String!) {
    jcr {
      addNode(name: $name, parentPathOrId: $parentPath, primaryNodeType: "jnt:file") {
        addChild(name: "jcr:content", primaryNodeType: "jnt:resource") {
          mutateProperty(name: "jcr:mimeType") { setValue(value: $mimeType) }
        }
        uuid
        node { path }
      }
    }
  }
`;

const [uploadFile] = useMutation(UPLOAD_FILE);
await uploadFile({ variables: { name, parentPath, mimeType } });
```

### From a JS template set (server-side, `.server.tsx`)

```tsx
import { useGQLQuery } from '@jahia/javascript-modules-library';
import { gql } from 'graphql-tag'; // or graphql from gql.tada

const QUERY = gql`
  query Children($path: String!) {
    jcr { nodeByPath(path: $path) { children { nodes { name displayName } } } }
  }
`;

jahiaComponent(
  { componentType: 'view', nodeType: 'ns:listing' },
  (_, { renderContext }) => {
    const data = useGQLQuery(QUERY, { path: `/sites/${renderContext.getSite().getName()}/contents` });
    const nodes = data?.jcr?.nodeByPath?.children?.nodes ?? [];
    return <ul>{nodes.map(n => <li key={n.name}>{n.displayName}</li>)}</ul>;
  },
);
```

> `useGQLQuery` runs synchronously on the server. Never use it in a `.client.tsx` file.

---

## Pattern 2 — Java Action (HTTP POST endpoint)

**When:** Business logic, file generation, AI calls, multi-step operations, or anything requiring server-side resources the user's browser must not access directly.

**URL:** `POST /cms/render/default/{lang}{nodePath}.{actionName}.do`

### Complete Java Action

```java
// src/main/java/org/example/actions/MyAction.java
@Component(service = Action.class)
public class MyAction extends Action {

    @Reference
    private MyService myService;   // inject business logic service

    @Activate
    public void activate() {
        setName("myAction");                         // must match CSRF whitelist and URL
        setRequireAuthenticatedUser(true);
        setRequiredPermission("jcr:write_default");  // checked on the target node
        setRequiredWorkspace("default");
        setRequiredMethods("POST");
    }

    @Override
    public ActionResult doExecute(
            HttpServletRequest request,
            RenderContext renderContext,
            Resource resource,
            JCRSessionWrapper session,            // authenticated user's session — never escalate
            Map<String, List<String>> parameters,
            URLResolver urlResolver) throws Exception {

        // Read parameters
        String input = getParameter(parameters, "input", "");

        // Call business logic
        String result = myService.process(input, session);

        // Return JSON
        JSONObject resp = new JSONObject();
        resp.put("success", true);
        resp.put("result", result);
        return writeJson(renderContext, HttpServletResponse.SC_OK, resp);
    }

    private static String getParameter(Map<String, List<String>> params, String key, String def) {
        List<String> vals = params.get(key);
        return (vals != null && !vals.isEmpty() && vals.get(0) != null) ? vals.get(0) : def;
    }

    private static ActionResult writeJson(RenderContext ctx, int status, JSONObject body) throws Exception {
        ctx.getResponse().setStatus(status);
        ctx.getResponse().setContentType("application/json;charset=UTF-8");
        ctx.getResponse().getWriter().print(body.toString());
        return ActionResult.OK;
    }
}
```

### Required CSRF config

```properties
# src/main/resources/META-INF/configurations/org.jahia.modules.jahiacsrfguard-mymodule.cfg
whitelist = *.myAction.do
```

### Calling from a UI extension (React 18)

```javascript
// Build the action URL
function actionUrl(lang, nodePath, actionName) {
  return `/cms/render/default/${encodeURIComponent(lang)}${nodePath}.${actionName}.do`;
}

// POST with form data
const body = new FormData();
body.append('input', 'hello');

const response = await fetch(actionUrl(lang, path, 'myAction'), {
  method: 'POST',
  headers: { 'X-Requested-With': 'XMLHttpRequest' }, // required by CSRF guard
  credentials: 'same-origin',                         // sends session cookie
  body,
});

const json = await response.json();
```

> **Never set `Content-Type` manually when using `FormData`** — the browser sets the multipart boundary automatically. Setting it manually breaks multipart parsing.

### Calling from a JS template set (client island, `.client.tsx`)

```tsx
// Inside a client component — uses buildEndpointUrl from the library
import { buildEndpointUrl } from '@jahia/javascript-modules-library';

async function callAction(path: string, lang: string, input: string) {
  const url = buildEndpointUrl('myAction'); // resolves to /cms/render/default/{lang}{path}.myAction.do
  const body = new FormData();
  body.append('input', input);

  const res = await fetch(url, {
    method: 'POST',
    headers: { 'X-Requested-With': 'XMLHttpRequest' },
    credentials: 'same-origin',
    body,
  });
  return res.json();
}
```

### Returning binary content (PDF, image, etc.)

```java
@Override
public ActionResult doExecute(...) throws Exception {
    byte[] pdfBytes = renderService.renderToPdf(...);

    HttpServletResponse response = renderContext.getResponse();
    response.setStatus(HttpServletResponse.SC_OK);
    response.setContentType("application/pdf");
    response.setHeader("Content-Disposition", "attachment; filename=\"export.pdf\"");
    response.getOutputStream().write(pdfBytes);
    response.getOutputStream().flush();
    return ActionResult.OK;
}
```

Client receives the blob:

```javascript
const response = await fetch(url, { method: 'POST', headers, credentials: 'same-origin', body });
const blob = await response.blob();
const objectUrl = URL.createObjectURL(blob);
window.open(objectUrl); // or <a href={objectUrl} download>
```

---

## Pattern 3 — Proxy for external services

**When:** The front-end needs to call an external API (AI providers, image services, analytics, CRMs, etc.). **Never call external APIs directly from the browser** — API keys would be exposed in the network tab.

The Java Action acts as a secure proxy: it holds the key in the OSGi `.cfg` file, calls the external service server-side, and returns only the result to the browser.

```
Browser → POST /cms/render/.../proxyAction.do
            ↓  (Java Action)
         External API (Anthropic, OpenAI, Unsplash, ...)
            ↓  (response)
         Java Action formats + returns JSON
            ↓
Browser receives clean JSON — API key never exposed
```

### Complete proxy pattern

**1. Store the key in the `.cfg` file** (never in code):

```properties
# org.example.mymodule.cfg
EXTERNAL_API_KEY=
EXTERNAL_API_BASE_URL=https://api.example.com
EXTERNAL_API_TIMEOUT_MS=30000
```

**2. Read configuration via `ManagedService`:**

```java
@Component(
    service = {ExternalApiService.class, ManagedService.class},
    property = {"service.pid=org.example.mymodule"},
    immediate = true
)
public class ExternalApiServiceImpl implements ExternalApiService, ManagedService {

    private volatile String apiKey;
    private volatile String baseUrl;
    private volatile int timeoutMs;
    private final HttpClient http = HttpClient.newHttpClient();

    @Override
    public void updated(Dictionary<String, ?> props) {
        this.apiKey    = getString(props, "EXTERNAL_API_KEY", "");
        this.baseUrl   = getString(props, "EXTERNAL_API_BASE_URL", "https://api.example.com");
        this.timeoutMs = getInt(props,    "EXTERNAL_API_TIMEOUT_MS", 30_000);
    }

    @Override
    public String callApi(String prompt) throws IOException, InterruptedException {
        if (apiKey.isBlank()) throw new IllegalStateException("EXTERNAL_API_KEY not configured");

        String requestBody = new JSONObject()
            .put("prompt", prompt)
            .toString();

        HttpRequest request = HttpRequest.newBuilder()
            .uri(URI.create(baseUrl + "/v1/complete"))
            .header("Authorization", "Bearer " + apiKey)  // key stays server-side
            .header("Content-Type", "application/json")
            .timeout(Duration.ofMillis(timeoutMs))
            .POST(HttpRequest.BodyPublishers.ofString(requestBody))
            .build();

        HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() != 200) {
            throw new IOException("External API error " + response.statusCode() + ": " + response.body());
        }
        return response.body();
    }
}
```

**3. Java Action delegates to the service (proxy façade):**

```java
@Component(service = Action.class)
public class ProxyAction extends Action {

    @Reference
    private ExternalApiService externalApiService;

    @Activate
    public void activate() {
        setName("proxyAction");
        setRequireAuthenticatedUser(true);
        setRequiredPermission("jcr:read");
        setRequiredMethods("POST");
    }

    @Override
    public ActionResult doExecute(...) throws Exception {
        String prompt = getParameter(parameters, "prompt", "");

        JSONObject resp = new JSONObject();
        try {
            String result = externalApiService.callApi(prompt);
            resp.put("success", true);
            resp.put("result", result);
            return writeJson(renderContext, 200, resp);
        } catch (IllegalStateException e) {
            // API key not configured — admin error, not user error
            resp.put("success", false).put("error", "Service not configured");
            return writeJson(renderContext, 503, resp);
        } catch (IOException e) {
            resp.put("success", false).put("error", "External service unavailable");
            return writeJson(renderContext, 502, resp);
        }
    }
}
```

**4. Browser calls the proxy — key never touches the client:**

```javascript
const body = new FormData();
body.append('prompt', userInput);

const res = await fetch(`/cms/render/default/${lang}${nodePath}.proxyAction.do`, {
  method: 'POST',
  headers: { 'X-Requested-With': 'XMLHttpRequest' },
  credentials: 'same-origin',
  body,
});
const { success, result } = await res.json();
```

### Additional proxy hardening

Always validate and sanitize user-supplied input before forwarding to external APIs:

```java
// Size limits — prevent prompt injection or token explosion
if (prompt.length() > 10_000) {
    resp.put("error", "Input too long");
    return writeJson(renderContext, 400, resp);
}

// Rate limiting — prevent abuse
if (!rateLimiter.tryAcquire(session.getUserID())) {
    resp.put("error", "Rate limit exceeded");
    return writeJson(renderContext, 429, resp);
}

// Host allowlist for URL fetching
if (!isAllowedHost(url)) {
    resp.put("error", "Host not allowed");
    return writeJson(renderContext, 400, resp);
}
```

### Stateful session proxy (CRM / legacy APIs)

Some external services are session-based: the first request authenticates and returns a session cookie; subsequent requests reuse it. The proxy must capture, store, and refresh that cookie server-side. The browser never sees it.

```java
// EfficySessionContext — immutable session snapshot
public final class ExternalSessionContext {
    private final String cookieName;
    private final String cookieValue;
    private final long lastUpdatedEpochMs;

    public String toCookieHeaderValue() {
        return cookieName + "=" + cookieValue;
    }
}

// Session service — volatile field for thread-safe reads
@Component(service = ExternalSessionService.class, immediate = true)
public class DefaultExternalSessionService implements ExternalSessionService {

    private volatile ExternalSessionContext sessionContext;
    private final long maxIdleMs;  // from config, e.g. 900_000 (15 min)

    public Optional<ExternalSessionContext> getActiveSession() {
        ExternalSessionContext current = this.sessionContext;
        if (current == null) return Optional.empty();
        if (System.currentTimeMillis() - current.getLastUpdatedEpochMs() > maxIdleMs) {
            this.sessionContext = null;   // expired — next call re-authenticates
            return Optional.empty();
        }
        return Optional.of(current);
    }

    public synchronized void capture(HttpHeaders responseHeaders) {
        String value = extractSessionCookie(responseHeaders, "ExternalSession");
        if (value != null && !value.isBlank()) {
            this.sessionContext = new ExternalSessionContext("ExternalSession", value,
                    System.currentTimeMillis());
        }
    }

    public void clear() { this.sessionContext = null; }
}
```

Gateway service that manages the cookie lifecycle:

```java
// In the RPC gateway — attach cookie if active session exists
public GatewayResponse execute(String method, String body) throws IOException {
    HttpRequest.Builder builder = HttpRequest.newBuilder()
        .uri(URI.create(config.baseUrl + "/api"))
        .header("X-Api-Key", config.apiKey)          // static auth
        .header("Accept", "application/json")
        .timeout(Duration.ofMillis(config.timeoutMs));

    // Reuse existing session cookie if present
    sessionService.getActiveSession().ifPresent(session ->
        builder.header("Cookie", session.toCookieHeaderValue())
    );

    HttpResponse<String> response = httpClient.send(
        builder.POST(HttpRequest.BodyPublishers.ofString(body)).build(),
        HttpResponse.BodyHandlers.ofString()
    );

    // Capture new session cookie from response
    sessionService.capture(response.headers());

    if (response.statusCode() >= 400) {
        throw new IOException("External API error " + response.statusCode());
    }
    return new GatewayResponse(response.statusCode(), response.body());
}
```

> The session cookie is stored in the OSGi service instance, not in the user's HTTP session. This means it is **shared across all users** of the proxy. Use this pattern only when the external service has a single system account (CRM service account, integration user). For per-user external sessions, each user's token must be stored separately (e.g. keyed by `session.getUserID()`).

### Servlet-based REST API (alternative to Java Actions)

For a proxy that exposes **many endpoints** (list, get, create, download), a single `AbstractServletFilter` with route dispatch is cleaner than one Action class per endpoint.

```
CSRF whitelist:  /modules/my-proxy/api/*     (wildcard covers all routes)
URL pattern:     /modules/my-proxy/api/v1/*
```

```java
@Component(
    service = Filter.class,
    property = {
        "pattern=/modules/my-proxy/api/v1/.*",
        "service.ranking=1"
    }
)
public class MyProxyApiServlet extends AbstractServletFilter {

    @Reference private MyProxyService proxyService;

    @Override
    public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain)
            throws IOException, ServletException {

        HttpServletRequest  request  = (HttpServletRequest) req;
        HttpServletResponse response = (HttpServletResponse) res;
        String path = request.getRequestURI()
            .replaceFirst(".*/api/v1", "");   // strip prefix

        try {
            if ("GET".equals(request.getMethod())) {
                if (path.equals("/health"))             handleHealth(response);
                else if (path.startsWith("/contacts/")) handleGetContact(request, response, path);
                else if (path.equals("/contacts/search")) handleSearchContacts(request, response);
                else chain.doFilter(req, res);
            } else if ("POST".equals(request.getMethod())) {
                if (path.startsWith("/cases"))          handleCreateCase(request, response);
                else chain.doFilter(req, res);
            } else {
                response.setStatus(HttpServletResponse.SC_METHOD_NOT_ALLOWED);
            }
        } catch (IllegalArgumentException e) {
            writeJsonError(response, 400, e.getMessage());
        } catch (Exception e) {
            writeJsonError(response, 500, "Unexpected error");
        }
    }

    private void writeJsonError(HttpServletResponse response, int status, String message)
            throws IOException {
        response.setStatus(status);
        response.setContentType("application/json;charset=UTF-8");
        response.getWriter().print(new JSONObject().put("error", message));
    }
}
```

CSRF config for the servlet (wildcard path, not per-action):
```properties
# org.jahia.modules.jahiacsrfguard-myproxy.cfg
whitelist = /modules/my-proxy/api/*
```

> Use **Actions** when you have 1–3 endpoints. Use a **Servlet filter** when you have many endpoints and want to group them under a versioned path (`/api/v1/`). The servlet approach also makes OpenAPI documentation easier.

### SPI / internal package split

For a proxy with many service collaborators, enforce the interface/implementation boundary via package naming:

```
src/main/java/org/example/myproxy/
├── spi/                     # Public interfaces — exported in OSGi manifest
│   ├── MyProxyService.java
│   ├── ContactService.java
│   └── SessionService.java
└── internal/                # Implementations — NOT exported
    ├── DefaultMyProxyService.java
    ├── DefaultContactService.java
    └── DefaultSessionService.java
```

In `pom.xml` BND config:
```xml
<Export-Package>org.example.myproxy.spi</Export-Package>
<!-- internal.* is NOT listed — other bundles cannot import it -->
```

Other modules reference only the `spi` interfaces via `@Reference`. This allows the implementation to change without breaking consumers.

### Input validation for proxy endpoints

Validate all user-supplied data before forwarding to the external API:

```java
// Field lengths
private static String normalizeName(String name) {
    if (name == null || name.isBlank()) throw new IllegalArgumentException("Name is required");
    if (name.length() > 128) throw new IllegalArgumentException("Name exceeds 128 characters");
    return name.trim();
}

// Date format
private static void validateDate(String date) {
    if (date != null && !date.matches("^\\d{4}-\\d{2}-\\d{2}$"))
        throw new IllegalArgumentException("Date must be YYYY-MM-DD");
}

// Positive ID
private static long validateKey(long key) {
    if (key <= 0) throw new IllegalArgumentException("Key must be positive");
    return key;
}

// Base64
private static byte[] decodeBase64(String b64) {
    try { return Base64.getMimeDecoder().decode(b64.replaceAll("\\s", "")); }
    catch (IllegalArgumentException e) { throw new IllegalArgumentException("Invalid Base64 content"); }
}

// JSON escaping before string interpolation into RPC payloads
private static String escapeJson(String value) {
    if (value == null) return "";
    return value.replace("\\", "\\\\").replace("\"", "\\\"")
                .replace("\r", "\\r").replace("\n", "\\n");
}
```

---

## Pattern 4 — GraphQL extension (custom Java-backed query or mutation)

**When:** You need to expose server-side logic as a first-class GraphQL field — queryable from the Jahia GraphQL playground, external tools, or DX APIs. Prefer Actions for UI-only operations; use GraphQL extensions when the operation needs to be part of the platform API surface.

### Provider registration

```java
@Component(service = DXGraphQLExtensionsProvider.class)
public class MyGraphQLProvider implements DXGraphQLExtensionsProvider {

    @Reference
    private MyService myService;

    @Override
    public void addQueries(Set<GqlJcrQuery> queries) {
        queries.add(new MyQuery(myService));
    }

    @Override
    public void addMutations(Set<GqlJcrMutation> mutations) {
        mutations.add(new MyMutation(myService));
    }
}
```

### Query class

```java
public class MyQuery implements GqlJcrQuery {

    private final MyService myService;

    public MyQuery(MyService myService) { this.myService = myService; }

    @Override
    @GraphQLField
    @GraphQLName("myQuery")
    @GraphQLDescription("Returns something useful")
    public MyResult getResult(
            @GraphQLName("input") @GraphQLNonNull String input,
            DataFetchingEnvironment env) {

        JCRSessionWrapper session = ((GraphQLContext) env.getContext()).getSession();
        // session is the authenticated user's session — respects ACLs
        return myService.compute(input, session);
    }
}
```

### Calling from the front-end

```javascript
// GraphQL extensions appear under the standard Jahia GraphQL endpoint
const QUERY = gql`
  query MyQuery($input: String!) {
    myQuery(input: $input) {
      field1
      field2
    }
  }
`;

// Same Apollo client / fetch pattern as built-in GraphQL
const { data } = useQuery(QUERY, { variables: { input: 'hello' } });
```

---

## Pattern 5 — OSGi service (server-to-server only)

**Not a front-end communication pattern.** OSGi services are the glue between server-side components. Actions delegate to services; services reference other services.

```
Browser → Action → Service → External API
                 ↘ Service → JCR
                 ↘ Service → Service
```

Rules:
- Actions are thin HTTP handlers. All logic lives in services.
- Never inject an OSGi service into a front-end JS module — there is no mechanism for this.
- Services are stateless workers; configuration comes from the `.cfg` file via `ManagedService`.

---

## Pattern comparison

| Criterion | Built-in GraphQL | Java Action | GraphQL Extension | Proxy Action |
|---|---|---|---|---|
| Reads JCR data | ✅ native | ✅ via session | ✅ via session | ❌ not the purpose |
| Writes JCR nodes | ✅ mutations | ✅ | ✅ | ❌ |
| Calls external API | ❌ | ✅ | ✅ | ✅ **preferred** |
| Hides API keys | — | ✅ in .cfg | ✅ in .cfg | ✅ in .cfg |
| File upload/download | ❌ | ✅ binary response | ❌ | ❌ |
| Rate limiting | ❌ | ✅ in Java | ✅ in Java | ✅ in Java |
| Accessible from external tools | ✅ | partial | ✅ | ❌ |
| Requires Java module | ❌ | ✅ | ✅ | ✅ |
| CSRF config required | ❌ | ✅ | ❌ | ✅ |

---

## Security checklist for every back-end endpoint

- [ ] API keys stored in `.cfg` file only — never in source code or responses
- [ ] `setRequireAuthenticatedUser(true)` on every Action
- [ ] `setRequiredPermission(...)` matches the operation (read → `jcr:read`, write → `jcr:write_default`)
- [ ] CSRF guard `.cfg` entry for every Action: `whitelist = *.actionName.do`
- [ ] User input validated (size, type, host) before forwarding to external services
- [ ] Rate limiter in place for any endpoint that calls an external paid API
- [ ] Binary responses sanitized — never stream user-supplied content directly

---

## References

- Real-world proxy: `/Users/stephane/Runtimes/0.Modules/ai-landing-page-generation`
- Real-world binary Action: `/Users/stephane/Runtimes/0.Modules/page-pdf-export`
- OSGi CFG / ManagedService pattern: [`.agents/skills/jahia-osgi-module/SKILL.md`](../skills/jahia-osgi-module/SKILL.md)
- OSGi UI extension Action registration: [`.agents/skills/jahia-osgi-ui-extension/SKILL.md`](../skills/jahia-osgi-ui-extension/SKILL.md)
