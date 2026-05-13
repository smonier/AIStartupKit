---
name: jahia-deploy
description: Build and deploy the current Jahia module to a running local instance. Detects module type (JS template set vs Maven bundle) and runs the correct build pipeline.
---

# /jahia-deploy

You are orchestrating a Jahia module build and deploy.

## Step 1 — Detect module type

Run both checks in parallel:

```bash
# Check for JS template set
find . -name "package.json" -not -path "*/node_modules/*" | xargs grep -l "@jahia/javascript-modules-library" 2>/dev/null | head -1

# Check for Maven bundle
find . -name "pom.xml" -maxdepth 2 | head -1
```

## Step 2 — Verify Jahia is running

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/cms/login
```

If not `200`: tell the user Jahia is not running. Suggest `/jahia-dev-start-local`.

## Step 3 — Build and deploy

**JS template set found:**
```bash
yarn build && yarn jahia-deploy
```
Watch for TypeScript errors and CND parse failures. If `yarn build` fails, report the exact error.

**Maven bundle found:**
```bash
mvn clean install
```
Then hot-deploy the `.jar` from `target/` to `http://localhost:8080/modules/api/bundles`.

**Both found (monorepo):**
Use AskUserQuestion to ask which module to deploy.

## Step 4 — Verify

After deploy:
1. Check Jahia logs for bundle activation errors.
2. If JS module: open `http://localhost:8080` and verify the component renders without `No rendering set for node:` errors.
3. Report: `✅ Deployed successfully` or `❌ Deploy failed — <error>`.
