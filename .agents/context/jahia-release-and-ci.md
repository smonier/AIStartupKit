# Releasing Jahia JS modules, and reading their CI

How a JavaScript module actually reaches a release, what the CI jobs mean, and how to read the
SonarQube gate. Two kinds of repos, two release paths: check which one a repo uses (look at the
previous release's assets and the workflows) before cutting anything.

---

## Jahia org repos (Jahia standard CI, chachalog)

The path, in order:

1. Every change that users notice carries a `.chachalog/<id>.md` fragment (`<module>: patch|minor|major`,
   one neutral line). A push to `main` makes the `Chachalog - Prepare Changelog` workflow open or
   update a bot PR "chore: release <module> @ vX.Y.Z" on branch `release`. That PR consumes the
   fragments into `CHANGELOG.md` and `.chachalog/.version`.
2. Merge the release PR. Chachalog creates **no** GitHub release by itself.
3. Create a **prerelease** on `main` by hand, tag in Jahia format `X_Y_Z` (dots become
   underscores: `0_1_0`), title `<module> vX.Y.Z`, notes = the `CHANGELOG.md` section.
   `gh release create 0_1_0 --target <merge sha> --title "<module> v0.1.0" --notes-file <section> --prerelease`
4. The prerelease fires `on-release.yml` (shared `reusable-release-module.yml`): it deletes and
   recreates the tag, runs `mvn release:prepare/perform` (Nexus staging), pushes the next
   `-SNAPSHOT` version to `main`, and updates the signature.

Traps:

- **A new repo is not writable by the release CI.** The release job pushes over SSH as the org CI
  account; a repo created by hand has no team grant or deploy key for it, so the first step fails
  with `Permission to Jahia/<repo>.git denied` and nothing is pushed (prerelease and tag stay
  intact). Granting access is a repo-admin decision: report it, never change permissions yourself.
  After the grant, `gh run rerun <run id> --failed` finishes the same release.
- **The release builds `main` HEAD**, not the merge commit you tagged (`git pull origin main` in the
  action). Commits pushed after the release PR ship in that version while their fragments go to the
  next release PR. Push fixes before cutting, or accept the mismatch knowingly.
- **Two jobs are red on every push to `main` of a JS module, by design of the shared actions:**
  `Publish module` (the snapshot `.tgz` does upload to Nexus, then a step greps the Maven log for
  an uploaded `.jar` and exits 1) and `SBOM processing` (the CycloneDX tool crashes). Build and
  integration tests are the jobs that matter. Do not "fix" these in the module.
- **Bot PRs.** A PR the chachalog bot opens or updates runs its checks normally on Jahia repos;
  on the very first release PR they may sit at `action_required` until a maintainer approves.

### Manual release when the release workflow cannot run

When the release job is blocked (no CI write access yet) and a release is needed now, cut it by
hand from a CI-built package, never a local build:

1. Commit `chore: release <module> X.Y.Z` on `main`: `package.json` and `pom.xml` version
   `X.Y.Z`, `.chachalog/.version`, and rename the pending `## ` section of `CHANGELOG.md`.
2. The `On merge to main` run uploads `build-artifacts`; the package is
   `target/<module>-X.Y.Z.tgz` (download via `gh api repos/<o>/<r>/actions/artifacts/<id>/zip`,
   available as soon as `Build Module` has finished). Check its `package.json` and grep it for
   `/Users/`.
3. Point the release tag at that commit (`git tag -f X_Y_Z <sha> && git push -f origin refs/tags/X_Y_Z`),
   attach the package, write the notes.
4. **Immediately** commit `X.Y.(Z+1)-SNAPSHOT` back on `main`.
5. Update the README's "Latest release" line (link to the new release) in the same follow-up
   commit: a status line written before the first release ("in development, not released yet")
   otherwise survives every release.

**`main` must always carry a `-SNAPSHOT` version.** The shared `@jahia/cypress` provisioning
installs only `*-SNAPSHOT.jar` / `*-SNAPSHOT.tgz` from `artifacts/`, so on a release version the
module is never installed in the CI Jahia and every integration test fails (pages answer 400,
GraphQL `data` is undefined), which also skips `Publish module`. The release workflow avoids this
by releasing from its own commits; a hand release must restore the SNAPSHOT itself.

Nothing reaches Nexus on this path. Once the CI account has access, the next release goes through
the normal prerelease path again.

## Personal add-on repos (scaffold CI)

Repos such as `smonier/jsfaq` have no chachalog and no Nexus. The release is a GitHub release whose
asset is the package **built by CI**, never a local build (a local Module Federation build embeds
absolute paths in its source maps).

- `build.yml` must pack, not just build: `yarn build` then `yarn package`
  (`yarn pack --out dist/package.tgz`) before `upload-artifact`. A workflow that only builds
  uploads nothing ("No files were found") and nobody notices until release day. Pin
  `actions/setup-node` to `node-version: 22`.
- Sequence: bump `package.json` + prepend the `CHANGELOG.md` section in one commit, push, wait for
  CI green, merge, download the artifact of the **merge** commit
  (`gh run download <id> -D <dir>`; the file is `<dir>/package.tgz/package.tgz`), check
  `package/package.json` (version, `snapshot: false`, `module-dependencies`) and grep the package
  for `/Users/`, then `gh release create` with that file renamed to the repo's asset convention.
- Every repo carries `CHANGELOG.md` (newest first, `## X.Y.Z (YYYY-MM-DD)`), a root `LICENSE`
  (MIT: "Copyright (c) <first year> to present Jahia") and `"license"` in `package.json`; GitHub
  release notes alone are not a changelog. A `release.sh` takes its notes from the CHANGELOG
  section and fails when the section is missing.
- Keep the docs to what is true: README (features, requirements, install, editor usage, content
  model, accessibility, theming variables, i18n, development, changelog, license) and at most one
  architecture document. Delete scaffold READMEs and implementation diaries; they drift and
  contradict the code within weeks.

## Installing a released package locally

Same-version `yarn deploy` is skipped by provisioning. Install the release file itself:

```bash
curl -s -u root:root1234 -H "Origin: http://localhost:8080" -X POST \
  http://localhost:8080/modules/api/bundles/ -F bundle=@<module>-vX.Y.Z.tgz -F start=true
curl -s -u root:root1234 -H "Origin: http://localhost:8080" \
  "http://localhost:8080/modules/api/bundles/*/<module>/*/_info"
```

Then uninstall the older, now inactive version. `_uninstall` must be **form-encoded**
(`-H "Content-Type: application/x-www-form-urlencoded" --data ""`), otherwise it answers 500
("@FormParam ..."). Never uninstall the last version of a module: that purges content of its types.

## SonarQube gate

- Sonar runs on pull requests (`on-code-change.yml`) and on a schedule (`schedule-sonar.yml`), not
  on pushes to `main`. A repo whose `main` was never analysed has no baseline, so its first PR
  counts the **whole project** as new code: a changelog-only release PR showed 29 issues and a D
  reliability rating.
- The check-run summary names the failing conditions; annotations are empty. The API is closed to
  anonymous calls. Fastest way to the issue list: the user opens sonarqube.jahia.com in Chrome
  (SSO), then from a tab on that origin
  `fetch("/api/issues/search?components=org.jahia.modules.javascript:<module>&pullRequest=<n>&resolved=false&ps=100",{credentials:"include"})`.
- `npx eslint` with `eslint-plugin-sonarjs` + `eslint-plugin-unicorn` reproduces most TypeScript
  rules locally (27 of 29 here; not S2871, which needs type information).

Write TypeScript that passes the rules met on template sets from the start:

| Rule | Write |
|---|---|
| S2871 (reliability, high) | `sort` always with a compare function: `(a, b) => a - b` |
| S7781 (reliability) | `replaceAll` (a regex argument needs the `g` flag) |
| S7758 (reliability) | `codePointAt`; check astral characters still pass the same tests |
| S3776 | functions at cognitive complexity 15 or less: split parsers into named steps |
| S3358 | no nested ternaries: named constants first |
| S4624 | no template literal inside a template literal: compute the inner string first |
| S7780 | `String.raw` for strings with backslashes |
| S7755 | `.at(-1)` instead of `[x.length - 1]` |
| S7763 | `export { x } from "./y.js"` to re-export |
| S7778 | one `push(a, b)` instead of two pushes |
| S5852 (hotspot) | no two adjacent quantified groups that can match the same characters: `<([a-z][a-z0-9]*)([^<>]*)>` is quadratic on an unclosed tag (186 ms at 20 KB); add `(?![a-z0-9])` after the name, which changes no match |

Hotspots do not fail the gate but wait for a review in SonarQube. Test fixtures that feed
`javascript:` or `http:` URLs to a filter (S1523, S5332) are expected there; mark them reviewed as
Safe in SonarQube (the user does it, it is their account) rather than editing the tests.

A refactor done for the gate must not change output: compare the rendered `<main>` and JSON-LD of
every demo page before and after deploying (byte-identical), plus unit tests and Cypress.

Reference: classic-templates (Jahia org path), jsfaq / js-media-gallery / js-store-locator
(add-on path), 2026-10-01.

## Replicating sites to another instance

Exported sites keep `siteservername=localhost`. On Jahia Cloud the instance then builds absolute
URLs with its own host and resolves pages from the `/sites/<key>/` path; a made-up server name
(`<site>.demo`) leaks into canonical and sitemap URLs. Several sites on `localhost` make
`renderContext.getSite()` return the same site for all of them, so views must read the page's own
site (see CLAUDE.md). `importSite` takes the inner `<sitekey>.zip`, never the container zip of an
Administration export; leave `roles.zip` and `mounts.zip` out on shared instances, and recreate the
`systemsite` categories the site refers to before importing (references are by path).
Reference kit: 0.Modules/demo-replication (`replicate.sh --site <key>`).
