---
name: jahia-debug
description: Debug a Jahia error. Describe the error and this command will diagnose the layer (build/deploy/OSGi/render/GraphQL) and apply a targeted fix. Delegates to jahia-debug-agent.
argument-hint: [error message or description]
---

# /jahia-debug

You are orchestrating Jahia error diagnosis and resolution.

## Step 1 — Capture the error

If `$ARGUMENTS` is provided, use it as the error description.

If `$ARGUMENTS` is empty, ask:

Use AskUserQuestion with:
- Question: "Where are you seeing the error?"
- Options:
  - Build failure (`yarn build` or `mvn clean install`)
  - Deploy/bundle activation failure
  - Runtime rendering error (blank component, missing view)
  - GraphQL error (403, schema error, null field)
  - i18n issue (keys showing as raw strings)

## Step 2 — Collect Docker logs if runtime error

If the error is a runtime or deploy error:

```bash
docker ps --format "{{.Names}}" | grep -i "jahia\|dx"
```

Then stream the last 50 lines of Jahia container logs:
```bash
docker logs <container> --tail 50
```

## Step 3 — Delegate to jahia-debug-agent

Invoke the `jahia-debug-agent` agent with this prompt:

```
Debug the following Jahia error:

Error: <description from Step 1>
Layer: <build|deploy|OSGi|render|GraphQL — from Step 1 selection>
Docker logs: <last 50 lines if captured, or "not available">

Follow the jahia-dev-debug skill to:
1. Identify the root cause.
2. Apply the targeted fix.
3. Rebuild and redeploy.
4. Verify the fix in Jahia.
```
