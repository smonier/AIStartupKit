---
name: jahia-i18n-check
description: Verify i18n completeness for all Jahia modules in the current project. Checks that EN and FR exist for both CND labels (.properties) and UI labels (.json). Reports missing keys.
---

# /jahia-i18n-check

You are verifying i18n completeness across the Jahia project.

## Step 1 — Find all i18n files

Run in parallel:

```bash
# CND label files
find . -path "*/settings/resources/*.properties" -not -path "*/node_modules/*" | sort

# UI locale files
find . -path "*/settings/locales/*.json" -not -path "*/node_modules/*" | sort
```

## Step 2 — Check CND labels (`.properties`)

For each module that has a `settings/resources/` directory:

1. Verify both `<module>.properties` (EN) and `<module>_fr.properties` (FR) exist.
2. Extract all keys from the EN file.
3. Extract all keys from the FR file.
4. Report keys present in EN but missing in FR (untranslated).
5. Report keys present in FR but missing in EN (orphaned — EN is the source of truth).

```bash
# Compare key sets
diff <(grep -o "^[^=]*" settings/resources/<module>.properties | sort) \
     <(grep -o "^[^=]*" settings/resources/<module>_fr.properties | sort)
```

## Step 3 — Check UI locale files (`.json`)

For each module that has `settings/locales/`:

1. Verify both `en.json` and `fr.json` exist.
2. Use `jq` to extract all keys (dot-notation paths):
```bash
jq '[paths(scalars)] | map(join(".")) | .[]' settings/locales/en.json | sort > /tmp/en_keys.txt
jq '[paths(scalars)] | map(join(".")) | .[]' settings/locales/fr.json | sort > /tmp/fr_keys.txt
diff /tmp/en_keys.txt /tmp/fr_keys.txt
```
3. Report missing keys in either direction.

## Step 4 — Summary report

Output a table:

```
Module                 CND Labels        UI Labels
──────────────────     ──────────────    ──────────────
<module-name>          ✅ EN+FR complete  ⚠️ FR missing 3 keys
```

List all missing keys below the table with their EN values so translators can act immediately.
