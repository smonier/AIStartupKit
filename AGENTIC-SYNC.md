# Sync with `@jahia/agentic` (upstream Jahia reference harness)

This repo's Jahia JS-module skills track the official reference harness
[`Jahia/agentic`](https://github.com/Jahia/agentic) (`@jahia/agentic` on npm).
It is an **ongoing-improvement** repo — re-check periodically.

- **Last synced:** v0.4.0 (2026-06-29)
- **Re-sync command:** `./.agents/agentic-sync.sh` (clones upstream, prints
  missing / changed / identical / local-only). Update this file afterward.

## Incorporated at v0.4.0

Added verbatim (skill + its `references/` and `scripts/`), to `.agents/skills/`
and mirrored to `.claude/skills/`:

| Skill | Notes |
|---|---|
| `jahia-cnd-author` | `context: fork` CND modeling agent + **9 `references/cnd-*.md`** docs. The v0.4.0 flagship. Prefer over `jahia-dev-define-content-type` for non-trivial modeling. |
| `jahia-dev-review-cnd` | deterministic CND linter (`scripts/check-cnd.mjs`, pure-node, PASS/FAIL + file:line). Verified working. |
| `jahia-dev-site-review` | axe-core a11y + SEO scoring per page (`scripts/review-pages.mjs`). Pairs with the migration harness's `render-truth` gate. |
| `jahia-jcr-sql2` | focused JCR-SQL2 reference. |

Adopted 4 conventions into `.claude/rules/jahia.md` + `CLAUDE.md` skill map:
load CND refs before writing CND · TypeScript LSP for API discovery (not grep
node_modules) · MCP-first for all Jahia ops · run `/jahia-dev-site-review` after
each deploy.

## CHANGED skills — diverged, to reconcile next pass

Present in both but content differs. Direction noted; reconcile by taking the
better version field-by-field (don't blindly overwrite our enhancements):

| Skill | agentic / local (lines) | Lead |
|---|---|---|
| `jahia-dev-accessibility` | 11 / 271 | **ours** (upstream is a stub) — keep |
| `jahia-dev-query-content` | 204 / 433 | **ours** (richer) — keep |
| `jahia-dev-import-from` | 244 / 383 | **ours** — keep |
| `jahia-dev-create-view` | 896 / 924 | both large — field-by-field diff |
| `jahia-dev-review` | 228 / 272 | both — diff |
| `jahia-dev-debug` | 176 / 213 | **ours** larger — diff |
| `jahia-dev-create-page-template` | 341 / 303 | **agentic** larger — pull improvements |
| `jahia-dev-create-template-set` | 205 / 232 | diff |
| `jahia-dev-build-component` | 133 / 140 | diff |
| `jahia-dev-start-local` | 121 / 129 | diff |

## Intentional divergences (LOCAL-ONLY — keep; not in upstream)

Our value-add beyond the JS-only reference harness:
- **OSGi / Java:** `jahia-dev-java`, `jahia-dev-osgi-module`, `jahia-osgi-module`,
  `jahia-dev-ui-extension`, `jahia-osgi-ui-extension`
- **Content management:** `jahia-content`, `jahia-content-create-content`,
  `jahia-content-explore-structure`, `jahia-content-move-content`,
  `jahia-content-query-content`, `jahia-content-translate-content`
- **Other:** `jahia-dev-cypress`, `jahia-dev-apis`, `jahia-dev-define-content-type`,
  and the GPS entry-point skills `jahia` / `jahia-dev`.

## Convergence to watch

Upstream's `docs/superpowers/plans/` is building the same thing as our
`jahiaMigration` orchestration: a lean orchestrator running a developer/reviewer
loop via file-based comms, and a self-validating CND sub-agent. Cross-check their
plans when evolving our `llm-orchestration-loop` + probe gates.
