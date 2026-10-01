---
name: jahia-dev-create-template-set
description: Scaffolds a new Jahia JavaScript template set (React). Use this when asked to create a new Jahia module, website, or project.
---

## About Jahia JavaScript Modules

This skill only covers **JavaScript Modules** — React-based template sets for Jahia 8+. This is the recommended approach for all new Jahia projects.

### JS modules vs Java modules vs Next.js

| | Java Modules | JS Modules | Next.js (Headless) |
|---|---|---|---|
| Availability | All versions | 8.2+ | Depends on setup |
| Separate runtime | No | No | Yes |
| GraphQL required | No | No | Yes |
| CMS navigation/cache/auth | Yes | Yes | No |
| Packaging | Maven/jar | NPM/tgz | NPM/tgz |
| Templating | JSP | JSX | JSX |
| Module descriptor | pom.xml | package.json | Separate module |

Jahia recommends JS or Java modules for most projects. Next.js should only be chosen when integrating with an existing Next.js codebase.

### How JS modules run: GraalVM + GraalJS

Jahia JS modules run inside **GraalJS** (part of GraalVM) — a fully ECMAScript-2019-compliant JS engine on the JVM. GraalVM Native Image is **not** used (incompatible with OSGi). Official Jahia Docker images ship with GraalVM pre-configured.

**Build pipeline:** Yarn 4 + Vite. The `npm init @jahia/module@latest` scaffolder generates `vite.config.mjs` handling TypeScript, CSS Modules, and client-side JS bundles.

**tgz → OSGi transformation:** On install, Jahia converts the NPM tgz into an OSGi bundle. Key `package.json` → `MANIFEST.MF` mappings:

| package.json field | MANIFEST.MF clause |
|---|---|
| `jahia.module-dependencies` | `Jahia-Depends` |
| `jahia.server` | `Jahia-NPM-InitScript` |
| `jahia.required-version` | `Jahia-Required-Version` |
| `jahia.module-type` | `Jahia-Module-Type` |
| `jahia.static-resources` | `Jahia-Static-Resources` |

**Request flow:**
1. Browser request → Jahia servlet
2. `TemplateNodeFilter` resolves the template identifier
3. `ViewsRegistrar` resolves the JS script for the template
4. `GraalVMEngine` pulls a `ContextProvider` from its pool, renders via GraalJS
5. `<Area>` / `<Render>` components may call `RenderService` to render child views
6. Final HTML assembled and returned

The engine maintains a pool of polyglot contexts (one per thread). Each context runs all init scripts (`dist/server/index.js`) on creation. A version counter invalidates stale contexts when modules are added or removed.

---

## Step 1 — Check prerequisites

Before scaffolding, verify Node.js and Yarn are available:

```bash
node --version   # must be 22.14+
yarn --version   # must be 4.9+
```

Node 22.14+ is required. Yarn is managed by **Corepack** (bundled with Node) — no global install needed:

```bash
corepack enable yarn
```

If Node is missing or outdated, install it from [nodejs.org/en/download](https://nodejs.org/en/download) — select **for your platform** and **with Yarn**. Alternatively use mise:

```bash
mise use node@lts && corepack enable yarn
```

Do not proceed until both `node --version` (22.14+) and `yarn --version` (4.9+) pass.

---

## Step 2 — Scaffold the module

Run the interactive CLI and **show the user its full output**:

```bash
npm init @jahia/module@latest <project-name>
```

The CLI will prompt interactively for:

| Prompt | Guidance |
|--------|----------|
| Module name | kebab-case, e.g. `my-site` |
| Output directory | accept the default (`./<module-name>`) |
| Module type | see below |

**Module type — always choose a template set:**
- `A minimal Hello World template set` ✅ — best starting point, includes working components
- `An empty template set` — blank canvas, for experienced developers

Once the project is created, the CLI will suggest commands to start it. Run them in order — they start Docker (Jahia) and push the module.

---

### Choosing the CND namespace

The CLI derives the namespace from the module name with hyphens removed (`classic-templates` →
`classictemplates` / `classictemplatesmix`), and there is no prompt to change it. To pick a short
prefix, change the two namespace lines of `settings/definitions.cnd` **before the first deploy**
(a registered prefix cannot be renamed; see the namespace-collision trap in `jahia-dev-debug`), and
rename `settings/content-types-icons/<module>mix_component.png` to `<prefix>mix_component.png`. First
check the prefix is free on the target instance: list `jcr { nodeTypes { nodes { name } } }` and
look at the prefixes.

---

## Step 3 — After generation

1. `cd <project-name>`
2. `yarn install` — install dependencies. If Yarn complains the project "isn't part of the workspace"
   (a parent directory holds a `package.json`), create an empty `yarn.lock` in the module root: that
   marks it as a standalone project.

### Jahia-standard CI (modules built and published by Jahia)

The scaffold's `.github/workflows/build.yml` only builds and uploads the tgz. A module that follows
the Jahia standard (Cortex review, Sonar, integration tests, Nexus publish, release) copies the
layout of `luxe-jahia-demo` instead:

- a thin `pom.xml` (parent `org.jahia.modules:jahia-modules:8.2.1.0`, packaging `pom`) that runs
  `frontend-maven-plugin` (`yarn install`, `yarn build`), attaches `dist/package.tgz` with
  `build-helper-maven-plugin` and copies it to `target/` with `maven-antrun-plugin`;
- `.yarn/releases/yarn-4.x.cjs` + `yarnPath` in `.yarnrc.yml`, so the Yarn 1 that the Maven plugin
  installs hands over to Yarn 4;
- `package.json` → `jahia.maven.groupId` (`org.jahia.modules.javascript`) and
  `distributionManagement`, `jahia.module-dependencies` pinning `javascript-modules-engine=[1.1,2)`;
- `.github/workflows/`: `on-code-change`, `on-merge`, `on-release`, `schedule-sonar`, `manual-run`,
  plus the globally managed `chachalog-*` and `delivery-*` (copy, never edit), `.github/release.yml`,
  `maven.settings.xml`, `instructions/changelog.instructions.md`, and `renovate.json` with
  `"ignorePaths": ["**/node_modules/**"]` (the recommended preset silently ignores `tests/`);
- a `tests/` Cypress project (see `/jahia-dev-cypress`), a root `LICENSE`, no per-file license header.

Before the first release, read [`jahia-release-and-ci.md`](../../context/jahia-release-and-ci.md):
a repo created by hand must give the org CI account write access or the release job cannot push,
SonarQube has no baseline until the first PR (that PR counts the whole project), and `Publish
module` and `SBOM processing` are red on every push to `main` of a JS module.

> ⚠ Changing `jahia.maven.groupId` after a first deploy does **not** replace the installed bundle:
> provisioning skips a bundle with the same symbolic name and version. Uninstall the old one first
> (`POST /modules/api/bundles/<old-group>/<name>/<version>/_uninstall`, form-encoded).

To run the module locally, use the `/jahia-dev-start-local` skill next.

---

## Step 4 — Build and deploy the module

Once Jahia is running at `http://localhost:8080`, build and deploy the module:

```bash
yarn build && yarn jahia-deploy
```

`yarn jahia-deploy` (from `@jahia/vite-plugin` 1.2.0+) always uses curl and defaults to `http://localhost:8080` / `root:root1234` — no `.env` configuration is required for standard local development.

Verify the module is installed:

```
tool: content.get
args: { "path": "/modules/<module-name>" }
```

Fallback without MCP:

```bash
curl -s -u root:root1234 -H "Origin: http://localhost:8080" \
  -X POST http://localhost:8080/modules/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ jcr { nodeByPath(path:\"/modules/<module-name>\") { name } } }"}'
```

Replace `<module-name>` with the `name` from `package.json`. The response should contain `"name": "<module-name>"`.

---

## Step 5 — Create a new site in Jahia

After the module is deployed, create the site via the `jahia` MCP server (MCP first) - **do not use the UI**:

```
tool: site.create
args: {
  "siteKey": "<module-name>",
  "title": "My Site",
  "templateSet": "<module-name>",
  "defaultLanguage": "en",
  "serverName": "localhost"
}
```

Replace `<module-name>` with the `name` from `package.json`. `templateSet` must exactly match the deployed module name. Verify with `tool: site.list`: the site key must appear in the response. Then check the site's languages (`j:languages`) and add the second language (every module ships EN + FR): site creation has been seen to ignore the requested languages.

#### Fallback: the `jahia` MCP server is not connected

Use the Provisioning API instead.

> ⚠️ **CRITICAL: syntax is `- createSite: ""`** — the empty string `""` after the colon is **mandatory**. Without it, Jahia returns HTTP 200 but silently creates nothing. Using `- createSite:` with nested properties is **wrong and will fail silently**.

```bash
MODULE_NAME=<module-name>   # value of "name" in package.json

curl -u root:root1234 \
     -X POST \
     -H "Content-Type: application/yaml" \
     --data-binary "- createSite: \"\"
  siteKey: ${MODULE_NAME}
  title: \"My Site\"
  defaultLanguage: en
  serverName: localhost
  templateSet: ${MODULE_NAME}" \
     http://localhost:8080/modules/api/provisioning
```

Or write the script to a file and POST it:

```bash
MODULE_NAME=<module-name>

cat > /tmp/create-site.yaml <<EOF
- createSite: ""
  siteKey: ${MODULE_NAME}
  title: "My Site"
  defaultLanguage: en
  serverName: localhost
  templateSet: ${MODULE_NAME}
EOF

curl -u root:root1234 -X POST -H "Content-Type: application/yaml" \
  --data-binary @/tmp/create-site.yaml \
  http://localhost:8080/modules/api/provisioning
```

Verify the site was created:
```bash
curl -s -u root:root1234 \
  -H "Content-Type: application/json" -H "Origin: http://localhost:8080" \
  -X POST http://localhost:8080/modules/graphql \
  -d "{\"query\":\"{ jcr { nodeByPath(path:\\\"/sites/${MODULE_NAME}\\\") { name } } }\"}"
```

The response must contain `"name": "<module-name>"`. If the path returns `null`, the site was not created — check that `templateSet` exactly matches the deployed module name.

### Post-creation: set required language properties

After the site is created, always set `j:inactiveLanguages` and `j:inactiveLiveLanguages` on the site node. Without them, some Jahia features (language switcher, publication workflows) behave unpredictably.

```bash
curl -s -u root:root \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:8080" \
  -X POST http://localhost:8080/modules/graphql \
  -d @- <<'GRAPHQL'
{"query":"mutation { jcr { mutateNode(pathOrId: \"/sites/<siteKey>\") { p1: mutateProperty(name: \"j:inactiveLanguages\") { setValues(values: []) } p2: mutateProperty(name: \"j:inactiveLiveLanguages\") { setValues(values: []) } } } }"}
GRAPHQL
```

Both mutations must return `"setValues": true`.

---

## Generated structure (Hello World template set)

```
<module-name>/
├── .github/               # GitHub Actions (builds on push)
├── .vscode/               # VSCode config — install recommended extensions!
├── src/
│   ├── components/        # React content type components
│   └── templates/         # Page layouts
├── settings/
│   ├── content-types-icons/   # 32×32 PNG icons per content type
│   ├── definitions.cnd        # Module-level CND (mixins, base types)
│   ├── import.xml             # Content/pages provisioned on site creation
│   ├── locales/               # i18n (en.json, fr.json, ...)
│   ├── resources/             # Editor UI labels (.properties files)
│   └── template-thumbnail.png # Shown in the Jahia template picker
├── static/                # Static files (images, fonts, vendor CSS/JS)
├── docker-compose.yml     # Local Jahia instance
├── docker/provisioning.yml
├── .env                   # Environment variables for build tools
├── .node-version          # Node version pin (used by GitHub Actions)
├── package.json
├── vite.config.mjs
└── tsconfig.json
```

`static/` is served at `/modules/<name>/` — reference files there with `buildModuleFileUrl("image.png")`.

---

## References
- https://github.com/Jahia/javascript-modules (monorepo — includes the `create-module` archetype)

## Troubleshooting

If anything goes wrong during setup or scaffolding, refer to the official Jahia front-end developer setup guide:

> https://academy.jahia.com/tutorials-get-started/front-end-developer/setting-up-your-dev-environment

---

## Validation checklist
- [ ] `node --version` reports 22.14+
- [ ] `yarn --version` reports 4.9+ (via Corepack)
- [ ] Module directory created with expected structure
- [ ] `yarn install` completes without errors
- [ ] `yarn build && yarn jahia-deploy` succeeds — module appears at `/modules/<name>` in JCR
- [ ] Site created with MCP `site.create` (fallback: Provisioning API `createSite: ""`) - `site.list` confirms the site key
- [ ] Site languages checked: EN and FR both active
- [ ] `j:inactiveLanguages` and `j:inactiveLiveLanguages` set to `[]` on the site node
