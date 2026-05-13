---
name: jahia-new-component
description: Scaffold a complete Jahia component (CND + types.ts + React view + CSS). Asks what to build, then delegates to jahia-js-dev-agent. Use when starting a new UI component or page section.
argument-hint: [component description]
---

# /jahia-new-component

You are orchestrating the creation of a new Jahia Single Directory Component (SDC).

## Step 1 — Gather spec

If `$ARGUMENTS` is empty, ask the user:

Use the AskUserQuestion tool with:
- Question: "What component do you want to build?"
- Options covering common types: Hero section, Card/listing item, Navigation, Form, Content block, Other

If `$ARGUMENTS` is provided, use it as the component description directly.

## Step 2 — Collect details

Ask a second clarifying question:

Use the AskUserQuestion tool with:
- Question: "Does this component need client-side interactivity (e.g. tabs, carousel, form submission)?"
- Options: No — server-only (React 19 server component), Yes — needs an Island (client-side), Not sure

## Step 3 — Delegate to agent

Invoke the `jahia-js-dev-agent` agent with this prompt:

```
Build a new Jahia SDC component: <component description from Step 1>.

Client-side interactivity needed: <answer from Step 2>.

Follow the jahia-dev-build-component skill exactly:
1. Write and confirm the content spec with me before writing any code.
2. Define the CND content type and types.ts.
3. Implement the React view and CSS Module.
4. Run yarn build && yarn jahia-deploy.
5. Verify the component renders in Jahia Page Builder.
```
