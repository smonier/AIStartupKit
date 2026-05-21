---
name: jahia-content-query-content
description: Queries JCR content from a running Jahia instance via the GraphQL API. Use when asked to list, inspect, or retrieve content nodes, check what content exists, or audit a site's content.
allowed-tools: Bash, Read, WebFetch
model: haiku
---

# Skill: jahia-content-query-content

Retrieves JCR content from a running Jahia instance using the GraphQL JCR query API.

---

## Prerequisites

- Jahia running at `http://localhost:8080`
- Credentials: `root` / `root` (default for local Docker; may be `root:root` on older installs)
- GraphQL endpoint: `http://localhost:8080/modules/graphql`

**Auth pattern — always use both flags:**
```bash
curl -u root:root \
     -H "Content-Type: application/json" \
     -H "Origin: http://localhost:8080" \
     ...
```

> ⚠️ The `Origin: http://localhost:8080` header is **required**. Requests without it return `Permission denied` even with correct credentials.

---

## Query patterns

### 1 — Get a node by path

```bash
curl -s -u root:root \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:8080" \
  -X POST http://localhost:8080/modules/graphql \
  -d '{
    "query": "{ jcr { nodeByPath(path: \"/sites/mySite/contents/articles\") { children { nodes { name path primaryNodeType { name } } } } } }"
  }'
```

### 2 — Query by node type (JCR-SQL2)

```bash
curl -s -u root:root \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:8080" \
  -X POST http://localhost:8080/modules/graphql \
  -d '{
    "query": "{ jcr { nodesByQuery(query: \"SELECT * FROM [llmacademy:docArticle] WHERE ISDESCENDANTNODE(\u0027/sites/mySite\u0027) ORDER BY [jcr:created] DESC\", queryLanguage: SQL2) { nodes { name path uuid } } } }"
  }'
```

### 3 — Read node properties (including i18n)

```bash
curl -s -u root:root \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:8080" \
  -X POST http://localhost:8080/modules/graphql \
  -d '{
    "query": "{ jcr { nodeByPath(path: \"/sites/mySite/contents/articles/my-article\") { name uuid properties(language: \"en\") { name value } } } }"
  }'
```

> ⚠️ **i18n properties require `language:` in the `properties()` call.** Without it, i18n properties are returned empty.

### 4 — Filter by property value

```bash
# All articles tagged as "jahia" product
-d '{
  "query": "{ jcr { nodesByQuery(query: \"SELECT * FROM [llmacademy:docArticle] WHERE [product] = \u0027jahia\u0027 AND ISDESCENDANTNODE(\u0027/sites/mySite\u0027)\", queryLanguage: SQL2) { nodes { name path } } } }"
}'
```

### 5 — List all sites

```bash
curl -s -u root:root \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:8080" \
  -X POST http://localhost:8080/modules/graphql \
  -d '{
    "query": "{ jcr { nodesByQuery(query: \"SELECT * FROM [jnt:virtualsite] WHERE ISCHILDNODE(\u0027/sites\u0027)\", queryLanguage: SQL2) { nodes { name path } } } }"
  }'
```

### 6 — Check publication status

```bash
curl -s -u root:root \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:8080" \
  -X POST http://localhost:8080/modules/graphql \
  -d '{
    "query": "{ jcr { nodeByPath(path: \"/sites/mySite/contents/articles/my-article\") { name aggregatedPublicationInfo(language: \"en\") { publicationStatus } } } }"
  }'
```

Publication status values: `PUBLISHED`, `MODIFIED`, `NOT_PUBLISHED`, `UNPUBLISHED`, `MARKED_FOR_DELETION`

---

## JCR-SQL2 quick reference

```sql
-- All nodes of a type under a path
SELECT * FROM [ns:typeName] WHERE ISDESCENDANTNODE('/sites/mySite')

-- Direct children only
SELECT * FROM [ns:typeName] WHERE ISCHILDNODE('/sites/mySite/contents/articles')

-- Filter by property
SELECT * FROM [ns:typeName] WHERE [propName] = 'value'

-- Order by date (newest first)
SELECT * FROM [ns:typeName] WHERE ISDESCENDANTNODE('/sites/mySite') ORDER BY [jcr:created] DESC

-- Limit results (use offset for pagination)
SELECT * FROM [ns:typeName] WHERE ISDESCENDANTNODE('/sites/mySite') ORDER BY [jcr:created] DESC
-- pass limit/offset as query params: nodesByQuery(query: "...", queryLanguage: SQL2, limit: 10, offset: 0)
```

---

## Useful node type names

| Content | JCR type |
|---------|----------|
| Site | `jnt:virtualsite` |
| Page | `jnt:page` |
| Content folder | `jnt:contentFolder` |
| Doc article | `llmacademy:docArticle` |
| Tutorial page | `llmacademy:tutorialPage` |
| Hero section | `llmacademy:heroSection` |
| Feature card | `llmacademy:featureCard` |

---

## File Upload (binary content)

Upload a file (image, PDF, etc.) to Jahia as a `jnt:file` node using pure GraphQL — no multipart/XML needed.

### The correct mutation

```graphql
mutation uploadFile(
  $nameInJCR: String!,
  $path: String!,
  $mimeType: String!,
  $fileHandle: String!
) {
  jcr {
    addNode(
      name: $nameInJCR
      parentPathOrId: $path
      primaryNodeType: "jnt:file"
    ) {
      addChild(name: "jcr:content", primaryNodeType: "jnt:resource") {
        content: mutateProperty(name: "jcr:data") {
          setValue(type: BINARY, value: $fileHandle)
        }
        contentType: mutateProperty(name: "jcr:mimeType") {
          setValue(value: $mimeType)
        }
      }
      uuid
    }
  }
}
```

### Required transport: Jahia-specific multipart (NOT graphql-multipart-request-spec)

`setValue(type: BINARY)` requires binary data as a multipart form part. **Jahia uses its own convention** — different from the standard graphql-multipart-request-spec:

| Field | Content-Type | Body |
|-------|-------------|------|
| `query` | `text/plain` | The GQL mutation string |
| `variables` | `text/plain` | JSON where **`fileHandle = "fileToUpload"`** (the PART NAME, not `null`) |
| `fileToUpload` | `image/jpeg` etc | Raw binary file bytes |

Jahia reads the `fileHandle` variable value (`"fileToUpload"`), finds the multipart part with that name, and reads its bytes as the binary content. Do **not** use the graphql-multipart-request-spec `operations`/`map` fields — those cause Jahia to store `ApplicationPart@...` (49 bytes) instead of the actual binary.

### Python example (no extra dependencies)

```python
import json, base64, urllib.request, uuid as uuidmod

UPLOAD_MUTATION = ('mutation uploadFile($nameInJCR: String!, $path: String!, $mimeType: String!, $fileHandle: String!) '
                   '{ jcr(workspace: EDIT) { addNode(name: $nameInJCR, parentPathOrId: $path, primaryNodeType: "jnt:file") '
                   '{ addChild(name: "jcr:content", primaryNodeType: "jnt:resource") '
                   '{ content: mutateProperty(name: "jcr:data") { setValue(type: BINARY, value: $fileHandle) } '
                   '  contentType: mutateProperty(name: "jcr:mimeType") { setValue(value: $mimeType) } } '
                   'uuid } } }')

def upload_file_to_jahia(local_path, name_in_jcr, parent_path, mime_type,
                          jahia="http://localhost:8080", creds="root:root"):
    _auth = base64.b64encode(creds.encode()).decode()

    with open(local_path, "rb") as f:
        file_bytes = f.read()

    boundary = f"JahiaUpload{uuidmod.uuid4().hex}"

    variables = {
        "fileHandle": "fileToUpload",   # ← the NAME of the part containing the file
        "nameInJCR":  name_in_jcr,
        "path":       parent_path,
        "mimeType":   mime_type,
    }

    def field(name, content_bytes, content_type="text/plain", filename=None):
        cd = f'Content-Disposition: form-data; name="{name}"'
        if filename:
            cd += f'; filename="{filename}"'
        return f'--{boundary}\r\n{cd}\r\nContent-Type: {content_type}\r\n\r\n'.encode() + content_bytes + b"\r\n"

    raw = (
        field("query",        UPLOAD_MUTATION.encode()) +
        field("variables",    json.dumps(variables).encode()) +
        field("fileToUpload", file_bytes, content_type=mime_type, filename=name_in_jcr) +
        f"--{boundary}--\r\n".encode()
    )

    req = urllib.request.Request(
        f"{jahia}/modules/graphql", data=raw, method="POST",
        headers={
            "Authorization": f"Basic {_auth}",
            "Origin":        jahia,
            "Referer":       f"{jahia}/jahia/developerTools/graphql-workspace",
            "Accept":        "*/*",
            "Content-Type":  f"multipart/form-data; boundary={boundary}",
        }
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        result = json.load(r)

    if "errors" in result:
        raise RuntimeError(result["errors"])
    return result["data"]["jcr"]["addNode"]["uuid"]
```

### Adding the `jmix:image` mixin (for images used as hero images, etc.)

After uploading, add the mixin so the file can be referenced by `weakreference` image pickers:

```graphql
mutation addImageMixin($uuid: String!) {
  jcr {
    mutateNode(pathOrId: $uuid) {
      addMixins(mixins: ["jmix:image"])
    }
  }
}
```

Or combine into the upload by using `mutateNode` on the result (two-step, same session).

### Checking if a file already exists before uploading

```graphql
{ jcr(workspace: EDIT) { nodeByPath(path: "/sites/mySite/files/images/my-image.jpg") { uuid } } }
```

Returns `null` for `nodeByPath` if the node doesn't exist — guard with: `(result.get("data") or {}).get("jcr", {}).get("nodeByPath") or {}`.

### ⚠️ What NOT to do (Jahia 8.2.3 bugs / common mistakes)

| Approach | Problem |
|----------|---------|
| `setValue(type: BINARY, value: $b64)` sent as plain JSON (not multipart) | `Cannot read parts` — Jahia expects binary data as a multipart part, not inline |
| `addNode(..., properties: [{name: "jcr:data", type: BINARY, value: $b64}])` | NPE: `Cannot invoke "DataFetchingEnvironment.getGraphQlContext()"` |
| JCR REST API binary endpoint (`PUT /api/jcr/...`) | NPE in `JCRRestAPIDeprecationFilter` |
| `importContent` multipart with system view XML (`sv:node`) | `Cannot import /sv:node` |
| `importContent` multipart with file node as root XML element | Nothing created — root element = the `parentPathOrId` wrapper, children = nodes to create |

Always use the `addNode` → `addChild("jcr:content")` → `mutateProperty("jcr:data").setValue(BINARY, ...)` pattern **with the graphql-multipart-request-spec** transport.

---

## Common errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Permission denied` | Missing `Origin` header | Add `-H "Origin: http://localhost:8080"` |
| i18n properties returned empty | `language:` not specified | Add `language: "en"` to `properties()` call |
| Node not found | Wrong path or node doesn't exist | Verify path with `nodeByPath(path: "/sites")` first |
| NPE on `getGraphQlContext()` | BINARY type in `addNode.properties` array (Jahia 8.2.3 bug) | Use `addChild` + `mutateProperty.setValue(type: BINARY)` instead |
| `nodeByPath` returns `null` then `.get()` crashes | `result["data"]["jcr"]["nodeByPath"]` is `null` (not missing), so `.get("nodeByPath", {})` returns `None` | Guard with `(result.get("data") or {}).get("jcr", {}).get("nodeByPath") or {}` |

---

## References

- Jahia GraphQL API: `http://localhost:8080/modules/graphql` (open in browser for interactive playground)
- JCR-SQL2 language spec: https://docs.adobe.com/content/docs/en/spec/jcr/2.0/6_Query.html
