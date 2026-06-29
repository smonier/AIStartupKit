# mcp-servlet — Issue Log

---

## Session 1 — 2026-06-10

### 🐛 Bugs

**1. `content.list_definitions` does not filter by site-installed modules**
Returned types include all namespaces available on the Jahia instance, not just those from modules installed on the target site. `ailp:heroBanner` was surfaced even though the `ailp` module is not in `sial-paris` `installedModules`.
→ The tool should cross-check with the site's `installedModules` and exclude types whose module is not installed.

**2. `content.create` — `name` field rejected, only `nodeName` accepted**
The error `property 'name' is not defined` is not intuitive. Any LLM or developer will naturally try `name` first.
→ Either accept `name` as an alias for `nodeName`, or return a clearer error message suggesting the correct field.

**3. `page.create` — `siteKey`, `slug`, `template` fields rejected**
First call failed because the actual fields are `name` and `templateName`. The schema diverges from natural naming conventions.
→ Align field names with intuitive conventions (`slug` → `name`, `template` → `templateName`) or document them more clearly.

### 💡 Improvements

**4. Missing `site.create` tool**
No tool exists to create a site via MCP. Currently requires falling back to GraphQL or the provisioning API.
→ Add `site.create` to the roadmap.

**5. `content.list_definitions` — properties empty for most types**
Most types returned `"properties": []` despite having real JCR properties. Correct properties were only returned after an explicit call with `useContribute: false`.
→ Investigate why properties are not populated by default.

**6. `content.list_definitions` — no way to scope results to site-installed modules**
Even if the LLM knows which modules are installed, the tool offers no `installedOnly` or `modules[]` filter parameter to restrict results server-side.
→ Add an optional filter so callers can request only types from a given module list.

---

## Session 2 — 2026-06-10 (continued)

### 🐛 Bugs

**7. `content.list_definitions` exposes types from non-installed modules — confirmed agent-side workaround needed**
Confirmed during `sparis:heroSlide` workflow: `ailp:heroBanner` was created successfully despite `ailp` not being in `installedModules` of `sial-paris`. The content node was saved in JCR but would not render correctly. Agent had to manually cross-check `site.get` → `installedModules` against the type namespace to identify safe types.
→ Server-side fix: scope `content.list_definitions` results to installed modules by default, with an opt-out flag (`includeAll: true`) for advanced use cases.

**8. `content.delete` — no dry-run / confirmation step for direct deletions**
`content.delete` deleted `/sites/sial-paris/home/test/hero/hero-banner` immediately without a preview or confirmation round-trip. For a `DESTRUCTIVE` tool this is risky — an LLM could delete the wrong node.
→ Add a `dryRun: true` option that returns what would be deleted without committing, consistent with the catalog design note ("Dry-run preview + confirmed deletion summary").

### 💡 Improvements

**9. Agent workflow: verify module namespace before `content.create`**
The correct agent workflow should be: (1) `site.get` → `installedModules`, (2) `content.list_definitions`, (3) filter types by matching namespace to installed module names, (4) only then call `content.create`. This is not enforced or documented in the tool descriptions.
→ Add explicit guidance in `content.list_definitions` and `content.create` descriptions warning that types from non-installed modules will not render.

**10. `content.create` / `content.update` — i18n properties not visible in jContent editor**
After setting i18n properties (`jcr:title`, `description`, `jcr:description`, `imageAlt`, `buttonText`, `metaTitle`, `metaDescription`) with `locale: "fr"` via both `content.create` and `content.update`, the properties are visible in the raw JCR via `content.get` but **do not appear in the jContent editor UI**. Only non-i18n properties (`backgroundImage`, `ogImage`, `j:linkType`) are visible. Site has a single language (`fr`).
Confirmed on: `sparis:heroSlide` at `/sites/sial-paris/home/test/hero/hero-slide`.
→ Likely cause: i18n properties declared as `i18n=true` in the CND must be saved via a locale-aware JCR session into the `j:translation_fr` child node. Both tools appear to save them on the main node instead, which Jahia's editor and renderer ignore.

**11. `content.get` — `locale` parameter rejected**
Calling `content.get` with a `locale` argument returns a validation error (`property 'locale' is not defined in the schema`). Since i18n properties live in translation sub-nodes, without locale support `content.get` cannot return the localized values, making it impossible to verify what was actually saved per language.
→ Add `locale` parameter to `content.get` input schema so i18n properties can be read back in context.
