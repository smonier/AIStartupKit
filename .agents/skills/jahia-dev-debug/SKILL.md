---
name: jahia-dev-debug
description: Debugs a Jahia JavaScript module end-to-end — build, deploy, and runtime errors. Finds the first error after deployment using live Docker logs.
---

# Skill: jahia-dev-debug

Diagnoses why a Jahia JavaScript module fails to load. Follows the deployment pipeline from source to runtime.

---

## Step 1 — Build

From the module directory (where `package.json` is):

```bash
yarn build
```

- **Build fails** → fix the TypeScript / bundling error shown and stop here. Do not proceed to deploy until the build is clean.
- **Build succeeds** → proceed to Step 2.

---

## Step 2 — Deploy

```bash
yarn jahia-deploy
```

Interpret the output:
- `"Operation successful"` in the response → deployment was accepted. Proceed to Step 3 — the module may still fail at runtime.
- `"{}"` or empty JSON → deployment was **rejected** (usually a CND parse error or missing dependency). Proceed to Step 3 to find the cause in the logs.
- Any other error → fix the connection issue (is Docker running?) then retry.

---

## Step 3 — Watch live Docker logs

> Do NOT analyse logs that already exist — an old error is not necessarily the cause of the current issue. Start a fresh log stream, then deploy again to capture only what happens as a result of this deployment.

### 3a — Start watching logs in the background

Find the Jahia container name:

```bash
docker ps --format '{{.Names}}' | grep -i jahia | head -1
```

Then start tailing:

```bash
docker logs -f <container-name> 2>&1 | grep -v "^\s*$" &
LOG_PID=$!
```

### 3b — Deploy again while logs are streaming

```bash
yarn jahia-deploy
```

### 3c — Wait ~15 seconds, then stop the log stream

```bash
sleep 15 && kill $LOG_PID 2>/dev/null
```

### 3d — Verify component registration

```bash
docker logs <container-name> 2>&1 | grep "Registered Jahia component"
```

Expected: one line per view registered, e.g.:
```
Registered Jahia component: mymodule_view_ns:hero_default
Registered Jahia component: mymodule_view_ns:hero_small
```

If a component you just deployed is **absent** from this list, its `jahiaComponent` call was never reached — usually a syntax/import error in the view file that prevented the module from fully loading.

---

## Step 4 — Find the first error

Scan the captured log output for the **first** error that appears **after** the deploy timestamp. Common patterns to look for:

| Pattern | Likely cause |
|---|---|
| `CND parse error` / `invalid node type` | CND syntax error or illegal field declaration |
| `NoSuchNodeTypeException` | A referenced type doesn't exist (wrong namespace, typo, missing dependency) |
| `ClassNotFoundException` / `NoClassDefFoundError` | Java dependency missing |
| `Cannot set property` / `TypeError` in JS stack | View runtime error |
| `Module ... failed to start` | Any of the above |
| `Unresolved requirement` | OSGi dependency not satisfied |
| Missing `Registered Jahia component` for a specific type | View file has a syntax/import error, or `jahiaComponent` not reached |

**Focus on the first error, not the last.** Later errors are often cascading failures caused by the first one.

---

## Step 5 — Fix and retry

Once the root cause is identified:

1. Fix the issue in the source files
2. Run `yarn build` again
3. Go back to Step 2

Repeat until `yarn jahia-deploy` succeeds and the module loads cleanly (no errors in the 15-second window after deploy).

---

## Common fixes by error type

### CND: `j:linknode` or `j:url` declared explicitly
These fields are injected by Jahia's `linkTypeInitializer` mixin. Remove them from the CND.

### CND: unknown mixin or type
Check that the namespace is declared at the top of `settings/definitions.cnd` and that all referenced types exist.

### import.xml: reference to a non-existent type
Any `jcr:primaryType` or `jcr:mixinTypes` value in `import.xml` must exist in the deployed CND. Check for typos.

### import.xml: `jmix:nolive` used as `jcr:primaryType`
`jmix:nolive` is a mixin — it goes in `jcr:mixinTypes`, not `jcr:primaryType`.

### import.xml: OSGi fails with `missing requirement … (nodetypes=jmix:nolive)`
Every `jcr:mixinTypes` value in `import.xml` is scanned by the OSGi bundle resolver. If the mixin is not declared in the module's own CND and is not provided by a resolvable dependency, the bundle will not start. Correct spelling is `jmix:nolive` (all lowercase). Verify the mixin exists in your Jahia instance before using it in `import.xml`.

### View: module loads but page is blank
Run `yarn dev` and check the Vite / SSR console for a React render error.

---

## GraalJS (server-side JS) debugging with Chrome DevTools

Use this when you need to step through server-side view code running inside GraalVM.

### Step 1 — Enable the inspector via GraphQL

In Jahia's Developer Tools > GraphQL editor, run:

```graphql
mutation {
  admin {
    jahia {
      configuration(pid: "org.jahia.modules.javascript.modules.engine.jsengine.GraalVMEngine") {
        polyGlotInspect: value(name: "polyglot.inspect", value: "0.0.0.0:9229")
        polyGlotInspectSuspend: value(name: "polyglot.inspect.Suspend", value: "false")
        polyGlotInspectSecure: value(name: "polyglot.inspect.Secure", value: "false")
      }
    }
  }
}
```

### Step 2 — Map the port

If running in Docker, ensure port `9229` is mapped in `docker-compose.yml`:

```yaml
ports:
  - "9229:9229"
```

### Step 3 — Connect Chrome

After the mutation, Jahia logs a `devtools://...` URL. Open it in Chrome (use latest; Chrome 117–118 had known debugger bugs).

### Step 4 — Set a breakpoint and debug

In Chrome DevTools Sources tab, open `<module>/dist/main.js`, set a breakpoint, then reload the page. The server-side render pauses at the breakpoint. Full scope inspection, step-over, and continue are supported.

The config file `org.jahia.modules.javascript.modules.engine.jsengine.GraalVMEngine.cfg` accepts any `polyglot.*` key as an engine option — you can persist these settings there instead of using the GraphQL mutation.

---

## Visual layout — section width and collapse

### Component is full-width when it should be constrained to 1140px

**Symptom:** A component's inner content spans the full viewport instead of the expected container width.

**Cause:** `container` + `col-*` on the same element. Bootstrap `col-*` classes set `max-width: 100%` which overrides `container`'s `max-width: 1140px`. Even `col-12` wins on the same element.

**Diagnosis:**
```javascript
// In browser console:
getComputedStyle(document.querySelector('.your-section .component-content')).maxWidth;
// Returns "100%" instead of "1140px" → container+col conflict
```

**Fix:** Remove the `container` class; use inline style on the content wrapper:
```tsx
<div className="component-content" style={{ maxWidth: "1140px", margin: "0 auto", width: "100%" }}>
```

### Component collapses to ~50px height

1. **JS carousel (`overflow: hidden`)** — Swiffy Slider and similar libraries set this; without JS init, height = 0. Fix: use flex layout in server views.
2. **`position: absolute` children inside non-positioned parent** — absolute children are out of flow, parent has no height. Fix: add `position: relative; min-height: Xpx`.
3. **Empty content** — check `document.querySelector('.component').innerHTML` before diagnosing CSS.

### JS-dependent carousel shows only one item

Carousels using Swiffy Slider, Swiper, etc. show only slide 0 in SSR without JS. Replace with a flex layout in `.server.tsx`:
```tsx
<ul style={{ display: "flex", flexWrap: "wrap", gap: "20px", listStyle: "none", padding: 0 }}>
  {items.map(item => <li key={item.getPath()}>...</li>)}
</ul>
```

## Module lifecycle traps (proven on 8.2.3.2, 2026-09-03)

- **Never `_uninstall` the last installed version of a module on an instance that has content.**
  Jahia removes the module from every site and deletes the nodes of its types that sit in pages.
  Deploying a higher version upgrades in place and keeps content; bump the version instead.
- **Maven module replaced by a JS module of the same name**: the JS bundle can stall in
  `moduleState=STARTING` ("A different Jahia Module with the Id X already exists", "has not yet
  been parsed. Delaying its startup"); every JS view then 500s with `JSView.getModule() is null`.
  Stop + uninstall the stuck JS bundle and redeploy once the Maven one is gone.
- Module manager REST (`_stop`/`_start`/`_uninstall`) needs
  `-X POST -H 'Content-Type: application/x-www-form-urlencoded'`; `_info` shows the Jahia-level
  `moduleState` (an OSGi ACTIVE `_localState` proves nothing).
- `ERROR_WITH_DEFINITIONS` with `failed to register namespace <p> -> <uri>` for a prefix your CND
  never declares means the instance's in-memory namespace map is poisoned by another module; every
  deploy fails until `NodeTypeRegistry.getInstance().getNamespaces().remove("<p>")` runs through
  the provisioning API's Groovy `executeScript` (then bump the version so the CND is re-read).
- The JS engine's CND reader wants every prefix declared (`mix`, `wemmix` included) and
  `static-resources` must list `/icons` for content-type icons. Jahia's log is
  `/var/log/jahia/jahia.log` inside the container, not `docker logs`.
