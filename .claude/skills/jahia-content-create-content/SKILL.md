---
name: jahia-content-create-content
description: Creates and publishes JCR content nodes in a running Jahia instance via the GraphQL API. Use when asked to populate a site with content, create articles, tutorials, or any JCR node programmatically.
allowed-tools: Bash, Read, Write, Edit, WebFetch
context: fork
---

# Skill: jahia-content-create-content

Creates content nodes in a running Jahia instance using the GraphQL JCR mutation API, then publishes them.

---

## Prerequisites

- Jahia running at `http://localhost:8080`
- Credentials: `root` / `root1234` (default)
- GraphQL endpoint: `http://localhost:8080/modules/graphql`

**Auth pattern — always use both flags:**
```bash
curl -u root:root1234 \
     -H "Content-Type: application/json" \
     -H "Origin: http://localhost:8080" \
     ...
```

> ⚠️ The `Origin: http://localhost:8080` header is **required**. Requests without it return `Permission denied` even with correct credentials.

---

## Step 1 — Identify target site and content folder

Before creating content, verify the target site and content folder exist:

```bash
curl -s -u root:root1234 \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:8080" \
  -X POST http://localhost:8080/modules/graphql \
  -d '{
    "query": "{ jcr { nodeByPath(path: \"/sites\") { children { nodes { name path } } } } }"
  }'
```

Standard content folder paths:
- `/sites/<siteKey>/contents/articles/` — for `docArticle` nodes
- `/sites/<siteKey>/contents/tutorials/` — for `tutorialPage` nodes
- `/sites/<siteKey>/contents/` — for any other content folder

---

## Step 2 — Look up the content type's properties

Before creating a node, inspect the CND definition to know:
1. The exact `primaryNodeType` name (e.g. `llmacademy:docArticle`)
2. Which properties are **i18n** (need `language:` in the mutation)
3. Which properties are mandatory

```bash
find . -name "definition.cnd" | xargs grep -l "<typeName>" 2>/dev/null
cat <path-to-definition.cnd>
```

---

## Step 3 — Create a node

Use `jcr { addNode(...) }` to create a node with properties inline:

```bash
curl -s -u root:root1234 \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:8080" \
  -X POST http://localhost:8080/modules/graphql \
  -d '{
    "query": "mutation { jcr { addNode(parentPathOrId: \"/sites/mySite/contents/articles\", name: \"my-article\", primaryNodeType: \"llmacademy:docArticle\", properties: [{name: \"jcr:title\", value: \"My Article\", language: \"en\"}, {name: \"body\", value: \"<p>Content here</p>\", language: \"en\"}, {name: \"product\", value: \"jahia\", language: \"en\"}]) { uuid node { path } } } }"
  }'
```

### Property rules

| Situation | GraphQL syntax |
|-----------|---------------|
| i18n property (declared `i18n` in CND) | `{name: "body", value: "...", language: "en"}` |
| Non-i18n property | `{name: "product", value: "jahia"}` |
| Title (from `mix:title`) | `{name: "jcr:title", value: "...", language: "en"}` |
| Date property | `{name: "updatedAt", value: "2024-01-15T00:00:00.000Z", type: DATE}` |
| Multiple values | `{name: "tags", values: ["a", "b"]}` |

### Node name rules
- Use lowercase kebab-case: `my-article`, `getting-started`
- No spaces, no special characters
- Must be unique within the parent folder
- Use `useAvailableNodeName: true` to auto-suffix if name is taken

---

## Step 4 — Publish the node

After creation, publish to make it visible on the live site:

```bash
curl -s -u root:root1234 \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:8080" \
  -X POST http://localhost:8080/modules/graphql \
  -d '{
    "query": "mutation { jcr { mutateNode(pathOrId: \"/sites/mySite/contents/articles/my-article\") { publish(languages: [\"en\"]) } } }"
  }'
```

Expected response: `{"data": {"jcr": {"mutateNode": {"publish": true}}}}`

---

## Step 5 — Batch creation

To create multiple nodes efficiently, use `addNodesBatch`:

```bash
curl -s -u root:root1234 \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:8080" \
  -X POST http://localhost:8080/modules/graphql \
  -d '{
    "query": "mutation { jcr { addNodesBatch(nodes: [{parentPathOrId: \"/sites/mySite/contents/articles\", name: \"article-1\", primaryNodeType: \"llmacademy:docArticle\", properties: [{name: \"jcr:title\", value: \"Article One\", language: \"en\"}, {name: \"body\", value: \"<p>Body 1</p>\", language: \"en\"}]}, {parentPathOrId: \"/sites/mySite/contents/articles\", name: \"article-2\", primaryNodeType: \"llmacademy:docArticle\", properties: [{name: \"jcr:title\", value: \"Article Two\", language: \"en\"}, {name: \"body\", value: \"<p>Body 2</p>\", language: \"en\"}]}]) { uuid node { path } } } }"
  }'
```

Then publish all at once using `mutateNodesByQuery`:

```bash
curl -s -u root:root1234 \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:8080" \
  -X POST http://localhost:8080/modules/graphql \
  -d '{
    "query": "mutation { jcr { mutateNodesByQuery(query: \"SELECT * FROM [llmacademy:docArticle] WHERE ISDESCENDANTNODE(\u0027/sites/mySite/contents/articles\u0027)\", queryLanguage: SQL2) { publish(languages: [\"en\"]) } } }"
  }'
```

---

## Step 6 — Verify

Query back the created content to confirm:

```bash
curl -s -u root:root1234 \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:8080" \
  -X POST http://localhost:8080/modules/graphql \
  -d '{
    "query": "{ jcr { nodesByQuery(query: \"SELECT * FROM [llmacademy:docArticle] WHERE ISDESCENDANTNODE(\u0027/sites/mySite/contents/articles\u0027)\", queryLanguage: SQL2) { nodes { name path properties(names: [\"jcr:title\"], language: \"en\") { name value } } } } }"
  }'
```

---

## Common errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Permission denied` | Missing `Origin` header | Add `-H "Origin: http://localhost:8080"` |
| `Couldn't find definition for property X` | Wrong property name or non-i18n prop given with `language:` | Check CND definition; remove `language:` for non-i18n props |
| `ConstraintViolationException: mandatory property` | A mandatory CND property was not provided | Provide all mandatory properties |
| `ItemExistsException` | Node name already taken | Use `useAvailableNodeName: true` or choose a different name |
| `deletePropertiesBatch` fails with missing required fields | `language` is NON_NULL in `InputJCRDeletedProperty` — required even for non-i18n properties | Always provide `language: "en"` in every `deletePropertiesBatch` entry |

---

## Setting `j:linkType` links via GraphQL

> 🚫 **NEVER use `j:linkType: "external"` to link to an internal Jahia page.** Always use `"internal"` with `j:linknode`. Hardcoding an internal URL as an external link will break on environment changes (dev/staging/prod), language switching, vanity URLs, and live/preview workspace toggling. If no target page exists yet, omit the link entirely — don't use an external URL as a workaround.

CND fields using `choicelist[linkTypeInitializer]` require manually adding the correct mixin before the link property can be set. The editor normally does this automatically, but via GraphQL you do it in two steps.

### Internal link (`j:linkType: "internal"`)

`j:linknode` is defined in `jmix:internalLink` (from the `default` Jahia module) as an **internationalized** weakreference. You must add the mixin first, then set the property with `language:`.

```graphql
# Step 1 — add mixin + set j:linkType
mutation {
  jcr {
    mutateNode(pathOrId: "/sites/mySite/home/features/my-card") {
      addMixins(mixins: ["jmix:internalLink"])
      setPropertiesBatch(properties: [
        {name: "j:linkType", value: "internal"}
      ]) { path }
    }
  }
}

# Step 2 — set j:linknode (i18n weakreference — must include language)
mutation {
  jcr {
    mutateNode(pathOrId: "/sites/mySite/home/features/my-card") {
      mutateProperty(name: "j:linknode") {
        setValue(value: "<target-node-uuid>", language: "en", type: WEAKREFERENCE)
      }
    }
  }
}
```

### External link (`j:linkType: "external"`)

`j:url` and `j:linkTitle` are defined in `jmix:externalLink` (also `default` module) as **internationalized** strings.

```graphql
mutation {
  jcr {
    mutateNode(pathOrId: "/sites/mySite/home/features/my-card") {
      addMixins(mixins: ["jmix:externalLink"])
      setPropertiesBatch(properties: [
        {name: "j:linkType", value: "external"}
        {name: "j:url", value: "https://example.com", language: "en"}
        {name: "j:linkTitle", value: "Visit Example", language: "en"}
      ]) { path }
    }
  }
}
```

> **Source:** `jmix:internalLink` and `jmix:externalLink` are defined in the `default` Jahia module (not in core nodetypes). For native Jahia type definitions, see https://github.com/Jahia/jahia/tree/master/war/src/main/webapp/WEB-INF/etc/repository/nodetypes — module-level types like these require inspecting the deployed module JAR.

---

## References

- Jahia GraphQL API playground: `http://localhost:8080/modules/graphql` (GET in browser, POST for queries)
- JCR mutation docs: https://academy.jahia.com/documentation/developer/jahia/8/api-documentation/graphql-api
- Native Jahia node types (CND source): https://github.com/Jahia/jahia/tree/master/war/src/main/webapp/WEB-INF/etc/repository/nodetypes
