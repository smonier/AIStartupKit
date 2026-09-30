#!/usr/bin/env bash
# agentic-sync.sh — diff the local Jahia skills against the upstream
# @jahia/agentic reference harness (https://github.com/Jahia/agentic).
#
# Run this "from time to time" to stay in sync: it clones the upstream, then
# prints the upstream commits since our last sync, which skills are MISSING
# locally, CHANGED (anything in the skill dir differs: SKILL.md, references/,
# scripts/), IDENTICAL (already synced), and LOCAL-ONLY (our intentional
# extensions), and checks the .agents/.claude mirror. Update AGENTIC-SYNC.md
# with the new version + decisions after reviewing.
#
# Usage: .agents/agentic-sync.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
LOC="$HERE/skills"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Full history (blobs fetched lazily): a --depth 1 clone cannot show what changed since the last sync.
gh repo clone Jahia/agentic "$TMP/a" -- --filter=blob:none >/dev/null 2>&1 || { echo "clone failed (need gh auth)"; exit 1; }
AG="$TMP/a/src/harness/skills"
ver="$(node -e "console.log(require('$TMP/a/package.json').version)" 2>/dev/null || echo '?')"
last="$(grep -m1 -oE '\*\*Last synced:\*\* v[0-9.]+' "$ROOT/AGENTIC-SYNC.md" 2>/dev/null | grep -oE '[0-9.]+$' || true)"

echo "Upstream @jahia/agentic: v$ver   last synced: v${last:-?}   (local skills: ${LOC/#$HOME/~})"
echo
echo "## UPSTREAM COMMITS since v${last:-?}"
tag="@jahia/agentic@$last"
if [ -n "$last" ] && git -C "$TMP/a" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  log="$(git -C "$TMP/a" log --format='  %h %ad %s' --date=short "$tag..HEAD")"
  echo "${log:-  (none)}"
  echo
  echo "## FILES changed upstream since v$last"
  files="$(git -C "$TMP/a" diff --stat=100 "$tag..HEAD" -- src/harness | sed 's/^/  /')"
  echo "${files:-  (none)}"
else
  echo "  tag '$tag' not found - compare by hand (git -C <clone> tag -l)"
fi
echo
echo "## MISSING locally (in agentic, not here) — candidates to add"
for d in "$AG"/*/; do n=$(basename "$d"); [ -d "$LOC/$n" ] || echo "  + $n"; done
echo
echo "## CHANGED (in both, content differs) — review which is better"
for d in "$AG"/*/; do n=$(basename "$d"); l="$LOC/$n"
  [ -d "$l" ] || continue
  diffs="$(diff -rq "$d" "$l" 2>/dev/null | sed -E \
    -e "s|^Files $AG/([^ ]+) and .* differ\$|differs:       \1|" \
    -e "s|^Only in $AG/|only upstream: |" -e "s|^Only in $LOC/|only local:    |")"
  [ -n "$diffs" ] && { echo "  ~ $n"; echo "$diffs" | sed 's/^/      /'; }
done
echo
echo "## IDENTICAL (already synced, whole skill dir)"
for d in "$AG"/*/; do n=$(basename "$d"); l="$LOC/$n"
  [ -d "$l" ] && diff -rq "$d" "$l" >/dev/null 2>&1 && echo "  = $n"; done
echo
echo "## LOCAL-ONLY (our extensions — keep; agentic has none)"
for d in "$LOC"/*/; do n=$(basename "$d"); [ -d "$AG/$n" ] || echo "  * $n"; done
echo
echo "## MIRROR (.agents/skills vs .claude/skills)"
mirror="$(diff -rq "$LOC" "$ROOT/.claude/skills" 2>&1)"
echo "${mirror:-  identical}"
echo
echo "Next: copy any '+' skills (with references/ + scripts/), reconcile '~' skills"
echo "against the intentional divergences in AGENTIC-SYNC.md, edit BOTH mirrors,"
echo "and record the version + decisions in AGENTIC-SYNC.md."
