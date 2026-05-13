---
name: jahia-review
description: Run a CTO-level code review on the current git diff or a specific file. Checks React version, CSRF, session safety, i18n, Javadoc, GraphQL design, and more. Use before any PR.
argument-hint: [file or directory path, or leave empty for git diff]
---

# /jahia-review

You are orchestrating a CTO-level Jahia code review.

## Step 1 — Determine review scope

If `$ARGUMENTS` is provided, review that specific file or directory.

If `$ARGUMENTS` is empty:
1. Run `git diff HEAD` to get the current changes.
2. If the diff is empty, run `git diff main...HEAD` to get all changes on this branch.
3. If still empty, tell the user: "No changes found. Provide a file path or make some changes first."

## Step 2 — Delegate to jahia-review-agent

Invoke the `jahia-review-agent` agent with this prompt:

```
Perform a CTO-level Jahia code review on the following changes.

Review scope: <file path OR git diff output>

Apply all checks from the jahia-dev-review skill:
- CRITICAL: React version violations, missing CSRF, thread-unsafe session storage, missing save/publish
- WARNING: Missing i18n EN+FR, missing null guards, OSGi field state, missing authorization, missing Javadoc
- SUGGESTIONS: CSS variable fallbacks, server vs client component choice, scale-of-thumbs

Output each finding as: [CRITICAL|WARNING|SUGGESTION] File:line — Description
End with: ✅ Approved / ⚠️ Approved with warnings / ❌ Blocked — N critical issues
```
