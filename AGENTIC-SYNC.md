# Sync with `@jahia/agentic` (upstream Jahia reference harness)

This repo's Jahia JS-module skills track the official reference harness
[`Jahia/agentic`](https://github.com/Jahia/agentic) (`@jahia/agentic` on npm).
It is an **ongoing-improvement** repo — re-check periodically.

- **Last synced:** v0.6.0 (2026-09-03)
- **Re-sync command:** `./.agents/agentic-sync.sh` (clones upstream, prints
  missing / changed / identical / local-only). Update this file afterward.
  ⚠ The script only diffs `SKILL.md` — also `diff -rq` the `references/` and
  `scripts/` dirs of shared skills before concluding "identical".
- **Mirror invariant:** `.agents/skills/` and `.claude/skills/` must stay
  identical (`diff -rq .agents/skills .claude/skills`). Every skill edit goes
  to BOTH. The v0.5.1 pass repaired 11 drifted files where commits had patched
  only one side.

## Incorporated at v0.6.0 (2026-09-03)

Upstream delta v0.5.1 → v0.6.0 is a single new skill (plus its AGENTS.md row). Every other
shared skill, `references/` dir and `check-cnd.mjs` is byte-identical to what we already
diffed at v0.5.1, so the CHANGED table below is unchanged.

| Skill | Notes |
|---|---|
| **`jahia-dev-migrate-jsp`** (new) | added verbatim (SKILL.md + `references/{gotchas,not-portable,tag-mapping}.md`) to `.agents/skills/` and `.claude/skills/`. JSP/Java template set → JS module: audit into 3 portability tiers weighted by a real content export, ask the operator 3 scope questions (CSS as-is vs CSS Modules, keep jQuery vs islands, keep vs rewrite the Java remainder), port tag-by-tag with a mechanical naming rule, keep a stripped companion Java bundle for skins / `moduleMap` views / choicelist initializers / filters / rules, and close with an every-file accounting (registered / imported / tier-3 / dead). Complements our `automated-migration` harness (distant-site → Jahia) with the in-Jahia legacy path. |

Local-convention notes for that skill (kept verbatim, so future syncs stay IDENTICAL —
apply these when following it here): it says `yarn deploy` where our scaffolds use
`yarn jahia-deploy`; its Step 8 hands `yarn dev` to the *human* developer, which is fine —
the agent-side rule "never run `yarn dev` from an agent" still applies; its `root:root1234`
curl matches upstream's default, our local Jahia is `root:root`. Its `gotchas.md` independently
confirms our root-`icons/` ZipException and `module-priority` traps.

## Incorporated at v0.5.1 (2026-07-15)

Upstream restructured its review suite; we adopted the new names so future
syncs match by directory name:

| Change | Notes |
|---|---|
| `jahia-dev-review` → **`jahia-review-code`** | rename only — **our content kept** (upstream lacks our C9–C12 critical checks and W10 locale-sync check; its W3 wrongly recommends `jmix:hiddenType` on all structural containers, which breaks Page Builder child selection). Adopted upstream's closing pointer to `jahia-cnd-author`. |
| `jahia-dev-site-review` → **`jahia-review-site`** | adopted upstream v0.5.1 wholesale: full axe ruleset (any violation fails), **Lighthouse SEO audits** (replaces hand-rolled title/meta/h1/alt checks), gate semantics — reads `pages-to-review.json`, writes `pages.json` only on pass. Local fix: upstream's Step-1 install omits the `lighthouse` package its own script imports — we install it (candidate upstream issue). |
| **`jahia-review`** (new) | umbrella skill running `/jahia-review-code` + `/jahia-review-site` in parallel via subagents, consolidated PASS/FAIL. Our old `/jahia-review` CTO diff-review **command** renamed to `/jahia-cto-review` to free the name. |
| `jahia-dev-properties` | adopted upstream's portable grep (`find .claude .agents -name all-properties.md`) over our hardcoded `~/.claude/...` path. |
| `cnd-authoring-experience.md` (in `jahia-cnd-author/references/`) | added upstream's rule: replace special characters (e.g. `:`) with `_` in `.properties` keys. |
| `jahia-jcr-sql2` | adopted upstream's `jahia-cnd-author` pointer; fixed our dangling `/jahia-java-jcr` → `/jahia-dev-java`. |

Not applicable (CLI/installer features, we don't consume their CLI):
v0.5.0 Antigravity + Kiro agent adapters, MCP-server registration on install.

Upstream also **removed** its content-management and Java skills ("until we
have a test") — ours stay as intentional local extensions.

## Incorporated at v0.4.0 (2026-06-29)

Added verbatim (skill + its `references/` and `scripts/`), to `.agents/skills/`
and mirrored to `.claude/skills/`:

| Skill | Notes |
|---|---|
| `jahia-cnd-author` | `context: fork` CND modeling agent + **10 `references/cnd-*.md`** docs (incl. `cnd-jahia-mixins.md`). The v0.4.x flagship. Prefer over `jahia-dev-define-content-type` for non-trivial modeling. |
| `jahia-dev-review-cnd` | deterministic CND linter (`scripts/check-cnd.mjs`, pure-node, PASS/FAIL + file:line). **Ours is now ahead**: ignore directive + name-scoped missingI18n (218 vs 198 lines) — candidate upstream PR. |
| `jahia-review-site` (was `jahia-dev-site-review`) | see v0.5.1 above. |
| `jahia-jcr-sql2` | focused JCR-SQL2 reference. |

Adopted 4 conventions into `.claude/rules/jahia.md` + `CLAUDE.md` skill map:
load CND refs before writing CND · TypeScript LSP for API discovery (not grep
node_modules) · MCP-first for all Jahia ops · run `/jahia-review-site` after
each deploy.

## CHANGED skills — diverged, keep ours (re-check each pass)

Present in both but content differs. Ours lead everywhere as of v0.6.0 (re-verified 2026-09-03, incl. `references/` + `scripts/`);
reconcile field-by-field only if upstream grows something we lack:

| Skill | agentic / local (lines) | Lead |
|---|---|---|
| `jahia-dev-accessibility` | 11 / 271 | **ours** (upstream is a stub) — keep |
| `jahia-dev-query-content` | 204 / 433 | **ours** (richer) — keep |
| `jahia-dev-import-from` | 244 / 383 | **ours** (+ migration rules section) — keep |
| `jahia-dev-create-view` | 896 / 926 | **ours** (+ island i18n namespace trap) — keep |
| `jahia-review-code` | 228 / 272 | **ours** (C9–C12 + W10) — keep |
| `jahia-dev-debug` | 176 / 213 | **ours** (+ visual layout section) — keep |
| `jahia-dev-create-page-template` | 341 / 303 | **agentic** larger — pull improvements next pass |
| `jahia-dev-create-template-set` | 205 / 249 | **ours** (+ inactive-languages post-creation step) |
| `jahia-dev-build-component` | 133 / 140 | diff next pass |
| `jahia-dev-start-local` | 121 / 129 | diff next pass |
| `jahia-dev-define-content-type` | — / — | **ours** (deepened 89f17df; upstream delegates to cnd-author) |

## Intentional divergences (LOCAL-ONLY — keep; not in upstream)

Our value-add beyond the JS-only reference harness:
- **OSGi / Java:** `jahia-dev-java`, `jahia-dev-osgi-module`, `jahia-osgi-module`,
  `jahia-dev-ui-extension`, `jahia-osgi-ui-extension`
- **Content management:** `jahia-content`, `jahia-content-create-content`,
  `jahia-content-explore-structure`, `jahia-content-move-content`,
  `jahia-content-query-content`, `jahia-content-translate-content`
- **Other:** `jahia-dev-cypress`, `jahia-dev-apis`, `jahia-dev-define-content-type`,
  `jahia-unomi-profile`, `jahia-dev-jexperience`, `jahia-dev-ops`,
  `jahia-dev-properties`, and the GPS entry-point skills `jahia` / `jahia-dev`.

## Candidate upstream contributions

- `check-cnd.mjs`: ignore directive + name-scoped missingI18n (from our datatable session).
- `jahia-review-site` Step 1: missing `lighthouse` in the install command (script imports it).
- `jahia-review-code`: our C9–C12 critical checks + W10 locale-sync check; W3 correction
  (`jmix:hiddenType` only on singleton absolute-area types, never on orderable-list children).

## Convergence to watch

Upstream's `docs/superpowers/plans/` is building the same thing as our
migration orchestration (now `automated-migration`, branch `v3`): a lean
orchestrator running a developer/reviewer loop via file-based comms, and a
self-validating CND sub-agent. Cross-check their plans when evolving our
`llm-orchestration-loop` + probe gates.
