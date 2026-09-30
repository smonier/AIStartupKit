---
name: jahia-osgi-ui-extension
description: Conventions and patterns for building Jahia OSGi UI extensions — modules that extend the jcontent back-office (actions, panels, dialogs) using React 18, Webpack/Module Federation, and the @jahia/ui-extender registry. Distinct from JS template sets (React 19, Vite).
---

# SKILL — Jahia OSGi UI Extension

## When this skill applies

You are extending the **jcontent back-office** — adding toolbar actions, admin panels, dialogs, or sidebar panels that editors see inside jcontent / Page Builder. This is **not** about rendering the public-facing site (that is the JS template set track).

Key indicators:
- `@jahia/ui-extender` in `package.json`
- `@jahia/webpack-config` / `webpack.config.js` (not Vite)
- Output to `src/main/resources/javascript/apps/`
- React 18, not React 19

---

## React version distinction — critical

| Module type | React version | Build tool | Library |
|---|---|---|---|
| **JS template set** (public site) | React **19** | Vite | `@jahia/javascript-modules-library` |
| **OSGi UI extension** (back-office) | React **18** | Webpack + Module Federation | `@jahia/ui-extender` |

Never mix them. A UI extension that imports React 19 APIs will silently break in jcontent. A template set that uses `@jahia/ui-extender` won't work in the page renderer.

---

## Scaffold a new UI extension module

Use archetype **4** (`jahia-reactjs-admin-module-archetype`) which scaffolds the Webpack/Module Federation wiring automatically.

```bash
mvn archetype:generate -Dfilter=org.jahia.archetypes:
```

At the prompts:
1. Enter `4` → `jahia-reactjs-admin-module-archetype` (Jahia DXP >= 8)
2. Enter the latest version
3. Fill in the properties, then confirm with `Y`

| Property | Example | Notes |
|---|---|---|
| `artifactId` | `my-ui-extension` | Maven artifact ID and folder name |
| `moduleName` | `My UI Extension` | Human-readable name shown in Jahia UI |
| `groupId` | `org.example.modules` | Java package root |
| `jahiaVersion` | `8.2.0.0` | **Always `8.2.0.0`** — the archetype default is outdated |
| `version` | `1.0.0-SNAPSHOT` | Module version |
| `package` | `org.example.modules` | Java package |

> ⚠️ After generation, update `react` and `react-dom` in `package.json` to `^18.3.1`. The archetype may scaffold an older React 18 minor — always pin to the latest React 18.x.

Build to verify:

```bash
cd <artifactId>
mvn clean install   # runs yarn build:production via frontend-maven-plugin
```

---

## Module structure

```
<module>/
├── pom.xml                                   # Maven OSGi bundle
├── package.json                              # Webpack/JS config
├── webpack.config.js
├── babel.config.js
├── src/
│   ├── javascript/                           # React / JS sources
│   │   ├── index.js                          # Entry point — registers jahiaApp-init callback
│   │   ├── init.js                           # Async init — loads i18n, calls register functions
│   │   ├── <Feature>/
│   │   │   ├── <Feature>.jsx                 # React component
│   │   │   ├── register<Feature>.js          # registry.add() call
│   │   │   ├── dialogManager.js              # Portal pattern (if feature has a dialog)
│   │   │   └── gql/
│   │   │       └── <Feature>.mutations.js    # Apollo mutations
│   │   └── AdminPanel/                       # Optional admin panel
│   │       ├── AdminPanel.jsx
│   │       └── AdminPanel.routes.jsx
│   └── main/
│       ├── java/org/jahia/<org>/<module>/
│       │   ├── actions/                      # Java Actions (@Component service = Action.class)
│       │   └── services/                     # OSGi services (@Component)
│       └── resources/
│           ├── META-INF/configurations/      # OSGi .cfg files
│           └── javascript/
│               ├── apps/                     # Webpack output (do not edit)
│               └── locales/                  # i18n JSON files
│                   ├── en.json
│                   └── fr.json
```

---

## Build stack

### package.json key fields

```json
{
  "jahia": {
    "remotes": {
      "jahia": "javascript/apps/remoteEntry.js"
    }
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "@jahia/ui-extender": "^1.x",
    "@jahia/moonstone": "^2.x",
    "@jahia/data-helper": "^1.x",
    "@apollo/client": "^3.x"
  },
  "devDependencies": {
    "@jahia/webpack-config": "^1.x"
  }
}
```

### webpack.config.js

```javascript
const path = require('path');
// The package ships NO index.js. Require the file directly (default export).
// `const {getModuleFederationConfig} = require('@jahia/webpack-config')` fails at build time.
const getModuleFederationConfig = require('@jahia/webpack-config/getModuleFederationConfig');
const {CleanWebpackPlugin} = require('clean-webpack-plugin');
const CopyWebpackPlugin = require('copy-webpack-plugin');
const ModuleFederationPlugin = require('webpack/lib/container/ModuleFederationPlugin');
const packageJson = require('./package.json');

module.exports = (env, argv) => ({
    entry: { main: './src/javascript/index' },
    output: {
        path: path.join(__dirname, 'src/main/resources/javascript/apps/'),
        publicPath: 'auto',
        filename: 'my-module.bundle.js',
        chunkFilename: '[name].my-module.[chunkhash:6].js',
    },
    resolve: { extensions: ['.mjs', '.js', '.jsx'] },
    module: {
        rules: [
            { test: /\.(js|jsx)$/, use: 'babel-loader', exclude: /node_modules/ },
            { test: /\.module\.css$/, use: ['style-loader', { loader: 'css-loader', options: { modules: true } }] },
            { test: /\.css$/, exclude: /\.module\.css$/, use: ['style-loader', 'css-loader'] },
        ],
    },
    plugins: [
        new ModuleFederationPlugin(getModuleFederationConfig(packageJson, {
            name: 'myModule',
            library: { type: 'assign', name: 'appShell.remotes.myModule' },
            filename: 'remoteEntry.js',
            exposes: { './init': './src/javascript/init' },
            remotes: {
                '@jahia/app-shell': 'appShellRemote',
                '@jahia/jcontent': 'appShell.remotes.jcontent',
            },
            shared: {
                react: { singleton: true, requiredVersion: packageJson.dependencies.react },
                'react-dom': { singleton: true, requiredVersion: packageJson.dependencies['react-dom'] },
                // Host-provided, never bundled. Without these entries any `useSelector`
                // import fails with "Module not found: react-redux" at webpack time.
                'react-redux': { singleton: true, import: false },
                redux: { singleton: true, import: false },
                '@apollo/client': { singleton: true, import: false },
            },
        })),
        new CleanWebpackPlugin({ verbose: false }),
        // app-shell discovers the remote through the "jahia.remotes" key of THIS file.
        // Without the copy the bundle deploys ACTIVE and the action never appears.
        new CopyWebpackPlugin({ patterns: [{ from: './package.json', to: '' }] }),
    ],
    mode: argv.mode === 'production' ? 'production' : 'development',
    devtool: argv.mode === 'production' ? 'source-map' : 'eval-source-map',
});
```

`getModuleFederationConfig(packageJson, overrides)` marks every dependency listed in `package.json` that
is also in its shared list as `{import: false}` — the host supplies it. This is what prevents version
conflicts with jcontent's own React 18 instance. It only looks at `dependencies`, so a host package you
import but did not declare must be added to `shared` explicitly (the `react-redux` case above).

**Verify the jar before deploying.** `unzip -l target/*.jar | grep apps/` must list `remoteEntry.js`,
`<name>.bundle.js` and `package.json`. A jar of ~20 kB with only `.class` files means webpack never ran.

### Maven — frontend-maven-plugin

The plugin must be declared in the module pom. Setting `<yarn.arguments>` in `<properties>` alone
runs nothing: the `jahia-modules` parent does not bind the plugin for you.

```xml
<plugin>
    <groupId>com.github.eirslett</groupId>
    <artifactId>frontend-maven-plugin</artifactId>
    <version>2.0.1</version>
    <executions>
        <execution>
            <id>install-node-and-yarn</id>
            <phase>generate-resources</phase>
            <goals><goal>install-node-and-yarn</goal></goals>
            <configuration>
                <!-- 22, not 18/20: an unpinned resolution pulls graphql@17, which refuses older Node -->
                <nodeVersion>v22.21.0</nodeVersion>
                <yarnVersion>v1.22.22</yarnVersion>
            </configuration>
        </execution>
        <execution>
            <id>yarn-install</id>
            <goals><goal>yarn</goal></goals>
        </execution>
        <execution>
            <id>yarn-build</id>
            <goals><goal>yarn</goal></goals>
            <configuration>
                <arguments>build:production</arguments>
            </configuration>
        </execution>
    </executions>
</plugin>
```

Commit `yarn.lock` and add `node/` (the plugin's Node install dir) to `.gitignore`. Without the
lockfile every fresh clone re-resolves the tree and the build breaks on the next incompatible transitive.

Build scripts in `package.json`:
- `build`: `yarn lint && webpack` (dev — fast, no minification)
- `build:production`: `webpack --mode=production` (for Maven/CI)
- `dev`: `webpack --watch` (interactive dev only — never run from an agent)

### Deploy

```bash
# Always use this for agentic builds
mvn clean install -pl .

# Or if a deployer script is configured:
yarn build && mvn install -DskipTests
```

---

## Registering UI extensions (JavaScript side)

### Entry point pattern

```javascript
// src/javascript/index.js
import { registry } from '@jahia/ui-extender';

export default function () {
    registry.add('callback', 'my-module', {
        targets: ['jahiaApp-init:50'],   // runs early in jcontent lifecycle
        callback: async () => {
            const { default: register } = await import('./init');
            register();
        }
    });
}
```

```javascript
// src/javascript/init.js
import i18next from 'i18next';
import { registerMyAction } from './MyAction';

export default async function () {
    await i18next.loadNamespaces('my-module');   // load translations before registering UI
    registerMyAction();
}
```

The `jahiaApp-init:N` priority controls load order. Use 50 for normal modules; use lower numbers only if another module must see your registry entries at init time.

> **SelectorType registration** uses the same `registry.add` mechanism — `registry.add('selectorType', 'MyKey', { cmp, dataType, adaptValue, initValue })` — wired to a CND property via a JSON fieldset override in `settings/content-editor-forms/fieldsets/`. Full pattern: [context/jahia-selectortype-pattern.md](../../context/jahia-selectortype-pattern.md)

### Action registration

```javascript
// src/javascript/MyAction/registerMyAction.js
import React from 'react';
import { registry } from '@jahia/ui-extender';
import { Download } from '@jahia/moonstone';
import { MyAction } from './MyAction';

export const registerMyAction = () => {
    registry.addOrReplace('action', 'myActionName', {
        targets: ['contentActions:900'],    // toolbar position (higher number = lower priority)
        buttonIcon: <Download />,
        buttonLabel: 'my-module:action.myAction.label',
        showOnNodeTypes: ['jnt:page'],      // visibility filter
        component: MyAction,
    });
};
```

Common targets:
- `contentActions:N` — jcontent content toolbar
- `headerPrimaryActions:N` — jcontent header
- `publishMenu:N` — publish menu
- `contextualMenu:N` — right-click menu

### Action component pattern

Every action component **must** call `useNodeChecks` and return `null` when `checksResult` is falsy. This is what controls visibility — jContent does not hide the action for you.

**Minimal pattern** — module-scoped action with no node-type filtering:

```jsx
// src/javascript/MyAction/MyAction.jsx
import React from 'react';
import { useNodeChecks } from '@jahia/data-helper';

export const MyAction = ({ path, render: Render, ...rest }) => {
    const { checksResult } = useNodeChecks(
        { path },
        { requireModuleInstalledOnSite: ['my-module'] }  // hides on sites where module is not installed
    );

    if (!checksResult) return null;

    return <Render {...rest} onClick={handleClick} />;
};
```

**Full pattern** — with node-type guards, permissions, and a drawer opened via portal:

```jsx
import React, { useState } from 'react';
import ReactDOM from 'react-dom';
import { Language } from '@jahia/moonstone';  // include Language only when language-aware checks are needed
import { useNodeChecks } from '@jahia/data-helper';
import { MyDrawer } from './MyDrawer';

export const MyAction = ({ path, render: Render, ...rest }) => {
    const [isOpen, setIsOpen] = useState(false);

    const { checksResult } = useNodeChecks({ path, Language }, {
        showOnNodeTypes: ['jnt:page'],
        hideOnNodeTypes: ['jmix:someExcludedMixin'],
        hideForPaths: ['^/sites/((?!/).)+/SomeFolder/?$'],  // regex supported
        requiredPermission: ['myPermission'],                // always an array
        requireModuleInstalledOnSite: ['my-module'],
    });

    if (!checksResult) return null;

    return (
        <>
            <Render {...rest} onClick={() => setIsOpen(true)} />
            {ReactDOM.createPortal(
                <MyDrawer isOpen={isOpen} onClose={() => setIsOpen(false)} />,
                document.body
            )}
        </>
    );
};
```

> `Language` is only needed in the first argument when the check must be language-aware (e.g. `requiredPermission` that varies by locale). Omit it for module-scoped checks with no language dependency.

`useNodeChecks` returns `checksResult: true` only when all declared conditions pass. When `false`, the action is hidden from the UI.

> ⚠️ **Always include `requireModuleInstalledOnSite`** — without it, the action appears on every Jahia site regardless of whether the module is installed there. This is the primary guard that scopes a UI extension to sites where it is relevant.

### `useNodeChecks` — full options

All options are optional. An action is visible only when all provided conditions pass.

```jsx
import { useNodeChecks } from '@jahia/data-helper';
// Add Language from @jahia/moonstone to the first arg only if language-aware checks are needed

const { checksResult } = useNodeChecks({ path }, {
  // Node type filters
  showOnNodeTypes: ['jnt:page', 'jnt:file'],       // show only on these types
  hideOnNodeTypes: ['jmix:externalLink'],           // hide on these types (both can coexist)

  // Permission checks (checked on the node) — always use arrays
  requiredPermission: ['jcr:write'],               // array of permission names
  requiredSitePermission: 'adminTemplates',         // checked on the site root

  // Module installation check — always include this; scopes the action to sites where the module is installed
  requireModuleInstalledOnSite: ['my-module'],     // array of module keys

  // Path-based filters (regex strings supported)
  showForPaths: ['/sites/mySite/home'],             // show only under these paths
  hideForPaths: ['^/sites/((?!/).)+/Drafts/?$'],   // hide under these paths (regex)

  // Other
  hideOnExternal: true,                             // hide if the node is an external link
});
```

---

## GraphQL data fetching

### The golden rule: never use axios

In a jcontent UI extension, **all GraphQL calls must go through the Apollo client — never axios, fetch, or any custom HTTP helper.**

`@apollo/client` is declared as a **shared Module Federation singleton** by `@jahia/webpack-config`. This means your extension resolves the exact same Apollo client instance that jcontent itself uses. That client is already configured with:
- Endpoint: `/modules/graphql`
- Auth: session-cookie (the editor's existing jcontent session — no credentials needed)
- Cache and error policies pre-configured

### Two contexts, two patterns

#### 1. Inside an adminRoute panel (most common)

Components rendered via `registry.add('adminRoute', ...)` are mounted **inside** jcontent's React tree. Apollo's context is already provided by jcontent's `ApolloProvider`. Use hooks directly — no setup required:

```javascript
import {gql} from '@apollo/client';
import {useQuery, useLazyQuery, useApolloClient} from '@apollo/client';

// Define queries as static gql tags (not functions — Apollo needs static AST nodes)
const MY_QUERY = gql`
    query MyQuery($siteKey: String!) {
        jcr(workspace: LIVE) {
            nodesByCriteria(criteria: {
                nodeType: "my:type"
                paths: ["/sites/$siteKey"]
                pathType: ANCESTOR
            }) {
                nodes { uuid path displayName(language: "en") }
            }
        }
    }
`;

// ✅ Correct — useQuery resolves against jcontent's shared Apollo client
const MyPanel = () => {
    const siteKey = window.contextJsParameters?.siteKey || '';

    const {data, loading, error} = useQuery(MY_QUERY, {
        variables: {siteKey},
        skip: !siteKey
    });

    const nodes = data?.jcr?.nodesByCriteria?.nodes || [];
    // ...
};
```

For one-shot imperative calls (e.g. export, confirm-then-fetch), use `useApolloClient`:

```javascript
const client = useApolloClient();

const handleExport = async () => {
    const result = await client.query({
        query: MY_QUERY,
        variables: {siteKey, limit: 9999, offset: 0},
        fetchPolicy: 'network-only'   // bypass cache for fresh export data
    });
    const nodes = result.data?.jcr?.nodesByCriteria?.nodes || [];
    // ... generate CSV/JSON blob
};
```

#### 2. Inside a dialog rendered in a portal (outside jcontent's tree)

Dialog managers use `ReactDOM.createRoot` on a detached DOM node — **outside** jcontent's React tree — so the Apollo context is not inherited. You must wrap with `ApolloProvider` and pass the client explicitly:

```javascript
import {ApolloProvider} from '@apollo/client';

// The apolloClient is received from the action's context (passed by jcontent)
open({path, language, apolloClient}) {
    this.root.render(
        <ApolloProvider client={apolloClient}>
            <I18nextProvider i18n={i18next}>
                <MyDialog path={path} language={language} onClose={() => this.close()} />
            </I18nextProvider>
        </ApolloProvider>
    );
}
```

Inside `MyDialog`, `useQuery` / `useApolloClient` work normally because `ApolloProvider` is now in the tree.

### Query authoring rules

- Always use **static `gql` tagged templates** — never build query strings dynamically or as functions. Apollo's cache keys on the AST document, not a string.
- Use **parameterized variables** (`$paths: [String]`) instead of interpolating values into the query string. This enables static `gql` tags and Apollo caching.
- For LIVE workspace data (UGC — survey responses, comments, etc.), use `jcr(workspace: LIVE)`.
- For editorial content (pages, components), use `jcr` (defaults to `default` workspace).
- Use `nodesByCriteria` with `$paths` over `nodesByQuery` with interpolated SQL2 — it's safer and properly parameterized.

### Anti-patterns — never do these

```javascript
// ❌ Never — axios has no session auth and is not the shared client
import axios from 'axios';
const data = await axios.post('/modules/graphql', {query, variables});

// ❌ Never — fetch bypasses Apollo cache and CSRF guard
const res = await fetch('/modules/graphql', {method: 'POST', body: JSON.stringify({query})});

// ❌ Never — dynamic query strings break Apollo caching
const buildQuery = (siteKey) => `query { jcr { nodesByQuery(query: "... WHERE ... '${siteKey}'") { ... } } }`;

// ❌ Never — useQuery inside a portal without ApolloProvider (context missing)
// DialogManager.open() → renders outside jcontent tree → useQuery will throw
```

---

## Dialog pattern

When an action opens a dialog, use a portal manager — the dialog must be rendered outside the jcontent component tree to avoid focus-trap and z-index issues.

```javascript
// dialogManager.js
import React from 'react';
import ReactDOM from 'react-dom/client';
import { ApolloProvider } from '@apollo/client';
import { I18nextProvider } from 'react-i18next';
import i18next from 'i18next';
import { MyDialog } from './MyDialog';

class DialogManager {
    _init() {
        if (!this.root) {
            const container = document.createElement('div');
            container.id = 'my-module-dialog-root';
            document.body.appendChild(container);
            this.root = ReactDOM.createRoot(container);
        }
    }

    open({ path, language, apolloClient }) {
        this._init();
        this.root.render(
            <ApolloProvider client={apolloClient}>
                <I18nextProvider i18n={i18next}>
                    <MyDialog path={path} language={language} onClose={() => this.close()} />
                </I18nextProvider>
            </ApolloProvider>
        );
    }

    close() {
        this.root?.render(null);
    }
}

export default new DialogManager();
```

> ⚠️ **Always use `<Dialog disableEnforceFocus>`** when rendering in a portal. Without it, MUI's FocusTrap
> fights with jcontent's own focus management and causes an infinite loop.

```jsx
// MyDialog.jsx
import { Dialog, DialogTitle, DialogContent, DialogActions, Button } from '@mui/material';

export const MyDialog = ({ path, language, onClose }) => (
    <Dialog open fullWidth maxWidth="sm" disableEnforceFocus onClose={onClose}>
        <DialogTitle>...</DialogTitle>
        <DialogContent>...</DialogContent>
        <DialogActions>
            <Button onClick={onClose}>Cancel</Button>
            <Button variant="contained" onClick={handleAction}>Confirm</Button>
        </DialogActions>
    </Dialog>
);
```

---

## Runtime APIs (window.jahia.*)

These are injected by jcontent at runtime. Always check for existence before calling.

```javascript
// Toast notification
if (window.jahia?.toastDispatcher) {
    window.jahia.toastDispatcher.add({
        message: t('myMessage'),
        variant: 'success'   // 'success' | 'error' | 'warning' | 'info'
    });
}

// JCR node/folder picker (opens jcontent file picker)
if (window.CE_API?.openPicker) {
    window.CE_API.openPicker({
        type: 'folder',           // 'folder' | 'image' | 'file' | 'page' | 'content'
        isMultiple: false,
        site: window.contextJsParameters?.siteKey,
        lang: window.contextJsParameters?.uilang,
        initialSelectedItem: [],
        setValue: ([selected]) => {
            if (selected?.path) setPath(selected.path);
        }
    });
}

// Runtime context (current user, site, language)
const { siteKey, uilang, currentUser } = window.contextJsParameters ?? {};
```

---

## i18n conventions

Locale files live at `src/main/resources/javascript/locales/<lang>.json`. The top-level key is the module namespace. Always load the namespace before registering UI:

```json
// en.json
{
  "my-module": {
    "label": "My Module"
  },
  "action": {
    "myAction": {
      "label": "Do Something"
    }
  },
  "dialog": {
    "title": "...",
    "button": {
      "cancel": "Cancel",
      "confirm": "Confirm"
    }
  }
}
```

```javascript
// In init.js — always await before registering UI
await i18next.loadNamespaces('my-module');
```

Use `useTranslation('my-module')` (or `useTranslation()` if namespace is already loaded) in components.

---

## Java Action pattern

```java
@Component(service = Action.class)
public class MyAction extends Action {

    @Reference
    private RenderService renderService;       // if you need to render page HTML

    @Override
    public String getName() {
        return "myActionName";                 // matches CSRF whitelist key
    }

    @Override
    public ActionResult doExecute(
            HttpServletRequest request,
            RenderContext renderContext,
            Resource resource,
            JCRSessionWrapper session,
            Map<String, List<String>> parameters,
            URLResolver urlResolver) throws Exception {

        // 1. Read parameters
        String param = readParameter(parameters, "paramName", null);

        // 2. Business logic (run as the calling user — no privilege escalation)

        // 3. Stream a response (binary) or return JSON
        HttpServletResponse response = renderContext.getResponse();
        response.setStatus(HttpServletResponse.SC_OK);
        response.setContentType("application/pdf");
        response.getOutputStream().write(bytes);
        return ActionResult.OK;

        // OR return JSON to the client:
        // JSONObject result = new JSONObject();
        // result.put("key", "value");
        // return new ActionResult(HttpServletResponse.SC_OK, null, result);
    }
}
```

Action endpoint URL pattern:
```
POST /cms/render/default/{language}{nodePath}.{actionName}.do
```

Example: `POST /cms/render/default/en/sites/mySite/home.exportPagePdf.do`

The client calls this with `credentials: 'same-origin'` and `X-Requested-With: XMLHttpRequest`.

### CSRF guard configuration

Every Action endpoint must be whitelisted in the Jahia CSRF Guard, otherwise POST requests are rejected:

```properties
# src/main/resources/META-INF/configurations/org.jahia.modules.jahiacsrfguard-<moduleName>.cfg
whitelist = *.myActionName.do
```

---

## Share election traps (white jcontent after a restart or on a new origin)

Every remote registers its shared packages into one webpack share scope. Among **equal versions** webpack keeps
the entry with the higher `uniqueName` (the `from:` string in remoteEntry), unless one is already loaded. Two
consequences, both proven on 8.2.3.2:

- **`@apollo/client`**: never register a version above the host's (jahia-ui-root and jcontent 3.7 provide
  3.14.0). A bundle at 3.14.1 gets elected while the shell's cache stays on the host copy: white page,
  `Invariant Violation: 2` from jcontent code. Pin the host's exact version in `package.json`.
- **`@apollo/react-hooks` / `react-apollo` (legacy 3.1.x)**: `@apollo/react-common` 3.1.4 keeps its React context in a
  module-local variable. A module that shares `react-hooks` but not `react-common` (robots 3.0.0, llms 1.0.0,
  jahia-page-composer 2.1.0) carries a private context; when its copy wins the election, every legacy `useQuery`
  or `useApolloClient` at boot throws `Invariant Violation: 1` or `2` (see `invariant-packages`) and the shell is
  white. It surfaces on a cold origin (restart, or switching from `localhost` to a site host), because only then
  do all remotes register before first use. If you share `@apollo/react-hooks` or `react-apollo`, share
  `@apollo/react-common` too. Do not share them at all in new code: use `@apollo/client` hooks.

Diagnose without logging in: fetch `/jahia/jcontent` as root, collect the `javascript/apps/` script URLs, and in
each file read provides `("pkg","x.y.z"`, consumes `"pkg"(,!1)?,[`, and the `uniqueName`. The stack trace's chunk
URL (`/modules/<culprit>/javascript/apps/...`) names the elected provider directly. Fix by stopping that bundle
(`POST /modules/api/bundles/<group>/<id>/<version>/_stop`, form encoding) and reloading.

---

## Page Builder frame tokens: `--moon-*` only since jcontent 3.7.0

Anything you hand to jcontent for rendering **inside the Page Builder iframe** (`pageBuilderBoxConfig`
`borderColor` / `backgroundColors`, custom `Bar` components, injected CSS) must reference Moonstone tokens by
their `--moon-*` names. Proven on jcontent 3.7.1 / 3.8.0-SNAPSHOT with jExperience 3.9.0:

- Moonstone 2.19+ renamed every token to `--moon-*`. The un-prefixed `--color-*` names survive only as aliases in
  `dist/legacy-global-bundle.css`, which the package entry imports, so the jcontent **shell** still resolves both.
- jcontent 3.6.x cloned every `style[styleloader]` from the shell into the iframe, so the frame inherited the
  aliases. jcontent 3.7.0 (`30e59e00`, css modules for the editframe) injects only `editframe-styles/scoped.css`:
  94 `--moon-color-*`, zero `--color-*`. `Box.jsx` copies your `backgroundColors.*` strings verbatim into
  `--jcontent-backgroundColorBase|Hovered|Selected`, so `var(--color-purple_plain20)` resolves to nothing and the
  box loses its colour. Downgrading jcontent to 3.7.1 does not help; 3.6.2 is the last release with the aliases.
- jExperience 3.9.0 (Moonstone 2.13) still registers `var(--color-purple)` / `var(--color-purple_plain20)` for
  `personalizedContent`, `ABTest` and `personalizedList`: purple borders vanish in the Page Builder.

- The same commit removed the cloning of shell `style[styleloader]` tags into the frame. A custom `Bar` component
  styled with CSS modules (jExperience `Perso-experience-variants-bar`) renders in the iframe with none of its rules:
  flex row gone, chip and arrows misaligned. In 3.7+ a Bar can only rely on inline styles, Moonstone components
  whose CSS `editframe-styles` already ships, or CSS it injects into `ownerDocument` itself.

Rules: register `borderColor: 'var(--moon-color-purple)'`, `backgroundColors: {base: 'var(--moon-color-purple_plain20)', ...}`.
Verify in the iframe document, not the shell: `getComputedStyle(document.documentElement).getPropertyValue('--moon-color-purple_plain20')`.
Until third-party modules catch up, the shim `0.Modules/moonstone-legacy-tokens` (system Java bundle, one edit-mode
`RenderFilter` appending the 126 aliases as `--x: var(--moon-x, <literal>)` plus a frame script that clones the shell's style-loader tags scoped under `#jahia-portal-root`, before `</head>`) restores both; the
real fix belongs to the extension or to jcontent's `editframe-styles`.

---

## Whiteboard servlet alternative (drawer → server round-trip without a node context)

When the back-office feature is not tied to one node render (page-audit's AI review, geo-readiness'
crawler check), register a plain servlet instead of an `Action`:

```java
@Component(service = {HttpServlet.class, Servlet.class},
        property = {"alias=/my-module/my-endpoint", "allow-api-token=true"}, immediate = true)
public class MyServlet extends HttpServlet { ... }
// reachable at /modules/my-module/my-endpoint ; client: fetch(ENDPOINT, {credentials:'same-origin', headers:{'Content-Type':'application/json'}})
```

Hardening that every such servlet keeps: reject guests, require `application/json` (a cross-site form
post cannot set it), per-user sliding-window rate limit, generic error bodies.

- The guest constant is `JahiaUserManagerService.GUEST_USERNAME`. `JahiaUser.GUEST_USERNAME` does not exist
  and fails compilation.

### Public URL of a node from Java — never guess the shape

`/<lang><site-relative-path>.html` is a 404 on every non-default site. Ask Jahia:

```java
JCRSessionWrapper live = JCRSessionFactory.getInstance().getCurrentUserSession("live", Locale.forLanguageTag(lang));
JCRNodeWrapper node = live.getNode(path);                 // PathNotFoundException = never published
String url = node.getUrl();                               // /cms/render/live/<lang>/sites/<key>/...html
UrlRewriteService rw = (UrlRewriteService) SpringContextSingleton.getBean("UrlRewriteService");
url = rw.rewriteOutbound(url, request, response);         // what the rendered page prints: vanity URL,
                                                          // cms prefix and site key dropped per server-name rules
```

> ⚠️ **OSGi servlet requests report `/modules` as `getContextPath()`**, and the rewriter prepends it
> faithfully: `/modules/sites/x/home.html`. Swap that prefix for `Jahia.getContextPath()` before use.
> Verified on 8.2.3.2 (geo-readiness, 2026-09-09): digitall home → `/sites/digitall/home.html`, 200.

Vanity URLs are host-dependent by design: the rewriter emits one only when the request's server name
resolves to the page's site. On a local box where many sites share `localhost` you get the
`/sites/<key>/...` form, which is the one that actually works there. Not a bug.

---

## RenderContext setup (rendering page HTML from Java)

When an Action needs to render a page to HTML, the `RenderContext` fields must be set in this exact order:

```java
Resource htmlResource = new Resource(node, "html", null, Resource.CONFIGURATION_PAGE);
RenderContext ctx = new RenderContext(request, response, renderContext.getUser());
ctx.setSite(renderContext.getSite());          // 1. site first
ctx.setWorkspace("live");                      // 2. then workspace
ctx.setServletPath("/live");                   // 3. then servlet path (must match workspace)
ctx.setMainResource(htmlResource);             // 4. main resource last
String html = renderService.render(htmlResource, ctx);
```

> ⚠️ Order matters. Setting workspace before site or mainResource before workspace causes silent rendering errors.

---

## OSGi ManagedService (runtime configuration)

For services that need runtime-configurable properties (timeouts, URLs, feature flags):

```java
@Component(
    service = { MyService.class, ManagedService.class },
    property = { "service.pid=org.jahia.modules.<name>.myService" },
    immediate = true
)
public class MyServiceImpl implements MyService, ManagedService {

    private volatile int timeoutMs = 30_000;

    @Override
    public void updated(Dictionary<String, ?> properties) throws ConfigurationException {
        if (properties != null) {
            Object v = properties.get("MY_TIMEOUT_MS");
            if (v != null) timeoutMs = Integer.parseInt(v.toString());
        }
    }
}
```

Config file at `src/main/resources/META-INF/configurations/org.jahia.modules.<name>.myService.cfg`:

```properties
# default configuration - won't be overriden
MY_TIMEOUT_MS=30000
```

> ⚠️ **The first line must be `# default configuration - won't be overriden` (exact string).** Jahia reads this marker and does NOT overwrite the file in `digital-factory-data/karaf/etc/` when the module is redeployed. Without it, every redeploy resets any operator-edited values back to the shipped defaults.

Operators can override at runtime by editing `<jahia-data-dir>/karaf/etc/org.jahia.modules.<name>.myService.cfg`.

---

## Embedding third-party libraries in the bundle

When a library is not provided by Jahia at runtime, embed it:

```xml
<!-- pom.xml -->
<dependency>
    <groupId>org.jsoup</groupId>
    <artifactId>jsoup</artifactId>
    <version>1.17.2</version>
    <!-- No scope — will be embedded -->
</dependency>

<plugin>
    <groupId>org.apache.felix</groupId>
    <artifactId>maven-bundle-plugin</artifactId>
    <configuration>
        <instructions>
            <Embed-Dependency>jsoup;inline=false</Embed-Dependency>
            <DynamicImport-Package>*</DynamicImport-Package>
        </instructions>
    </configuration>
</plugin>
```

> ⚠️ When embedding libraries that use the Java `ImageIO` / `ServiceLoader` SPI (e.g. TwelveMonkeys ImageIO),
> you must instantiate their `ImageReaderSpi` classes directly using the **bundle's own classloader** — not
> via `IIORegistry.getDefaultInstance()`, which uses a global registry that becomes stale after bundle refresh.

```java
// Per-call classloader pattern — safe across bundle restarts
private BufferedImage decodeWebP(byte[] raw) throws Exception {
    ClassLoader cl = getClass().getClassLoader();
    // Instantiate directly — bypasses the stale global IIORegistry
    Class<ImageReaderSpi> spiClass =
        (Class<ImageReaderSpi>) cl.loadClass("com.twelvemonkeys.imageio.plugins.webp.WebPImageReaderSpi");
    ImageReaderSpi spi = spiClass.getDeclaredConstructor().newInstance();
    ImageReader reader = spi.createReaderInstance();
    try (ImageInputStream iis = new MemoryCacheImageInputStream(new ByteArrayInputStream(raw))) {
        reader.setInput(iis);
        return reader.read(0);
    } finally {
        reader.dispose();
    }
}
```

Additionally, switch the Thread Context ClassLoader (TCCL) for any library that uses `Thread.currentThread().getContextClassLoader()` internally:

```java
ClassLoader original = Thread.currentThread().getContextClassLoader();
Thread.currentThread().setContextClassLoader(getClass().getClassLoader());
try {
    // ... call to embedded library
} finally {
    Thread.currentThread().setContextClassLoader(original);
}
```

---

## GraphQL file upload from React

To upload a binary (e.g. a PDF blob) to JCR via GraphQL:

```graphql
mutation uploadFile(
    $name: String!
    $path: String!
    $mimeType: String!
    $fileHandle: String!
) {
    jcr {
        addNode(name: $name, parentPathOrId: $path, primaryNodeType: "jnt:file") {
            addChild(name: "jcr:content", primaryNodeType: "jnt:resource") {
                content: mutateProperty(name: "jcr:data") {
                    setValue(type: BINARY, value: $fileHandle)
                }
                contentType: mutateProperty(name: "jcr:mimeType") {
                    setValue(value: $mimeType)
                }
            }
            uuid
            node { path }
        }
    }
}
```

The Apollo client must be configured with a `createUploadLink` (or multipart link) for `File` variables to be serialized correctly. The `fileHandle` variable receives a `File` or `Blob` object from the client.

---

## Validation checklist

### JavaScript side
- [ ] `package.json` lists React 18, not 19
- [ ] `@jahia/webpack-config` used for Module Federation
- [ ] Entry point registers at `jahiaApp-init:N` via `registry.add('callback', ...)`
- [ ] i18n namespace loaded (awaited) before registering UI
- [ ] Action component uses `useNodeChecks` for visibility
- [ ] Dialog rendered via portal manager (outside jcontent tree)
- [ ] `<Dialog disableEnforceFocus>` on all MUI dialogs in portals
- [ ] `window.jahia.*` APIs guarded with optional chaining (`?.`)
- [ ] Webpack output goes to `src/main/resources/javascript/apps/`
- [ ] Jar contains `javascript/apps/remoteEntry.js` **and** `javascript/apps/package.json` (CopyWebpackPlugin)
- [ ] `react-redux` / `redux` / `@apollo/client` in the MF `shared` block as `{singleton, import:false}`
- [ ] `frontend-maven-plugin` declared in the pom, Node 22, `yarn.lock` committed, `node/` ignored
- [ ] `yarn dev` / `webpack --watch` never started from an agent
- [ ] `pageBuilderBoxConfig` colours and any CSS meant for the Page Builder iframe use `--moon-*` token names (jcontent >= 3.7.0 injects no `--color-*` aliases into the frame)

### Java side
- [ ] Action class: `@Component(service = Action.class)`, `getName()` matches CSRF whitelist key
- [ ] CSRF Guard config file present and correctly named
- [ ] RenderContext set in order: site → workspace → servletPath → mainResource
- [ ] All JCR access runs as the calling user (no system session escalation)
- [ ] Public URLs come from `node.getUrl()` + `UrlRewriteService.rewriteOutbound()`, with the `/modules` context path swapped out
- [ ] Guest check uses `JahiaUserManagerService.GUEST_USERNAME`
- [ ] Embedded libraries use per-call classloader, not global SPI registries
- [ ] TCCL switched for libraries that use `Thread.currentThread().getContextClassLoader()`
- [ ] OSGi config `.cfg` file present for every `ManagedService`
- [ ] `Embed-Dependency` declared in BND config for every embedded lib

---

## References

- jcontent UI extension API: https://academy.jahia.com/documentation/developer/jahia/8
- @jahia/ui-extender: https://github.com/Jahia/ui-extender
- @jahia/moonstone component library: https://moonstone.jahia.com
- @jahia/data-helper: https://github.com/Jahia/data-helper
- Module Federation docs: https://webpack.js.org/concepts/module-federation/
