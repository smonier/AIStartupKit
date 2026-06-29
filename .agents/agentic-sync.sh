#!/usr/bin/env bash
# agentic-sync.sh — diff the local Jahia skills against the upstream
# @jahia/agentic reference harness (https://github.com/Jahia/agentic).
#
# Run this "from time to time" to stay in sync: it clones the upstream, then
# prints which skills are MISSING locally, CHANGED (content differs), IDENTICAL
# (already synced), and LOCAL-ONLY (our intentional extensions). Update
# AGENTIC-SYNC.md with the new version + decisions after reviewing.
#
# Usage: .agents/agentic-sync.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LOC="$HERE/skills"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

gh repo clone Jahia/agentic "$TMP/a" -- --depth 1 >/dev/null 2>&1 || { echo "clone failed (need gh auth)"; exit 1; }
AG="$TMP/a/src/harness/skills"
ver="$(node -e "console.log(require('$TMP/a/package.json').version)" 2>/dev/null || echo '?')"

echo "Upstream @jahia/agentic: v$ver   (local skills: ${LOC/$HOME/\~})"
echo
echo "## MISSING locally (in agentic, not here) — candidates to add"
for d in "$AG"/*/; do n=$(basename "$d"); [ -d "$LOC/$n" ] || echo "  + $n"; done
echo
echo "## CHANGED (in both, content differs) — review which is better"
for d in "$AG"/*/; do n=$(basename "$d"); f="$LOC/$n/SKILL.md"
  [ -f "$f" ] && ! diff -q "$d/SKILL.md" "$f" >/dev/null 2>&1 && \
    printf "  ~ %-30s agentic=%s local=%s lines\n" "$n" "$(wc -l <"$d/SKILL.md"|tr -d ' ')" "$(wc -l <"$f"|tr -d ' ')"
done
echo
echo "## IDENTICAL (already synced)"
for d in "$AG"/*/; do n=$(basename "$d"); f="$LOC/$n/SKILL.md"
  [ -f "$f" ] && diff -q "$d/SKILL.md" "$f" >/dev/null 2>&1 && echo "  = $n"; done
echo
echo "## LOCAL-ONLY (our extensions — keep; agentic has none)"
for d in "$LOC"/*/; do n=$(basename "$d"); [ -d "$AG/$n" ] || echo "  * $n"; done
echo
echo "Next: copy any '+' skills (with references/ + scripts/), reconcile '~' skills,"
echo "and record the version + decisions in AGENTIC-SYNC.md."
