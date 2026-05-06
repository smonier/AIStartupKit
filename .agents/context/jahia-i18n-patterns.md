# Context — Jahia i18n Patterns

i18n in Jahia splits across two concerns and two module types. The file locations and mechanisms differ depending on whether you are in a JS template set or an OSGi module.

**Rule: every new module ships EN and FR at minimum — no English-only strings.**

---

## JS Template Set (React 19, Vite)

There are two separate i18n systems in a template set. Both are required.

### 1. CND / Editor labels — `settings/resources/`

Labels shown in the **jcontent editor** (field names, node type names, choicelist options, view names, tooltips). These are Java ResourceBundle `.properties` files picked up by Jahia at deploy time.

**File location:**
```
settings/
└── resources/
    ├── <module-name>.properties         ← default (English fallback)
    ├── <module-name>_en.properties      ← explicit English
    └── <module-name>_fr.properties      ← French (minimum required)
```

> The default `.properties` file (no locale suffix) acts as the fallback. Always keep it in sync with `_en.properties`.

**Key naming conventions:**

| Pattern | Example | Purpose |
|---|---|---|
| `ns_typeName=Label` | `ailp_heroBanner=Hero Banner` | Node type display name |
| `nsmix_mixinName=Label` | `ailpmix_component=AI Landing Page Component` | Mixin display name |
| `ns_typeName.propertyName=Label` | `ailp_heroBanner.headline=Headline` | Field label |
| `ns_typeName.propertyName.ui.tooltip=Text` | `ailp_heroBanner.headline.ui.tooltip=Main hero title` | Editor tooltip |
| `ns_typeName.propertyName.choiceValue=Label` | `ailp_gridRow.columns.2=2 columns` | Choicelist option |
| `ns_typeName.viewName=Label` | `ailp_heroBanner.default=Default View` | View display name |

**Full example:**

```properties
# ─── Node Types ───────────────────────────────────────────────────────────────
ailp_heroBanner=Hero Banner
ailpmix_component=AI Landing Page Component

# ─── HeroBanner properties ────────────────────────────────────────────────────
ailp_heroBanner.headline=Headline
ailp_heroBanner.headline.ui.tooltip=Main hero title displayed prominently
ailp_heroBanner.backgroundImage=Background Image
ailp_heroBanner.backgroundImage.ui.tooltip=Full-width background image for the hero section

# ─── Choicelist values ────────────────────────────────────────────────────────
ailp_gridRow.columns=Number of Columns
ailp_gridRow.columns.1=1 column
ailp_gridRow.columns.2=2 columns
ailp_gridRow.columns.3=3 columns
ailp_gridRow.columns.4=4 columns

# ─── Views ────────────────────────────────────────────────────────────────────
ailp_heroBanner.default=Default View
```

---

### 2. Front-end UI labels — `settings/locales/`

Labels used inside **React components** — button text, section headings, form labels, alt text, error messages, anything that is not a CND editor label. These are JSON files auto-discovered by the `@jahia/vite-plugin` and served by the module at runtime via `react-i18next`.

**File location:**
```
settings/
└── locales/
    ├── en.json      ← English (minimum required)
    └── fr.json      ← French (minimum required)
```

**No manual registration is needed.** The `@jahia/vite-plugin` in `vite.config.js` picks up all files in `settings/locales/` automatically.

**Key structure — nested JSON:**

```json
{
    "section": {
        "contact": {
            "address": "address",
            "phone": "phone",
            "btn": "make an appointment"
        }
    },
    "alt": {
        "estate": "view of the real estate: {{estate}}"
    },
    "pagination": {
        "previous": "Previous",
        "next": "Next",
        "showing": "Showing {{from}} to {{to}} of {{total}} results"
    },
    "form": {
        "contact": {
            "submit": "submit",
            "sendMessageError": "Something went wrong. Status: {{status}}."
        }
    }
}
```

**Usage in views** (`useTranslation` from `react-i18next`):

```tsx
// Works in both .server.tsx and .client.tsx
import { useTranslation } from "react-i18next";

const { t } = useTranslation();

// Simple key
<button>{t("section.contact.btn")}</button>

// With interpolation
<img alt={t("alt.estate", { estate: title })} />

// In server view alongside JCR data
const { t } = useTranslation();
const locale = currentResource.getLocale().getLanguage();
<p>{price.toLocaleString(locale)}€</p>  // locale from JCR
<span>{t("estate.bedrooms.label")}</span>  // UI label from locales
```

---

## OSGi Module (Java bundle or UI extension)

Only one i18n system — `.properties` files — used for both CND labels and UI extension labels.

**File location:**
```
src/main/resources/
└── resources/
    ├── <artifact-id>.properties         ← default (English fallback)
    ├── <artifact-id>_en.properties      ← explicit English
    └── <artifact-id>_fr.properties      ← French (minimum required)
```

> Note the path: `src/main/resources/resources/` — the double `resources/` is correct and required.

**Example (OSGi module with a UI extension):**

```properties
# efficy-ent-services.properties
efficy-ent-services.label=Efficy Enterprise service
efficy-ent-services.label.settings.title=Efficy Enterprise service settings
efficy-ent-services.label.action.title=Efficy Enterprise service
efficy-ent-services.label.appsAccordion.title=Efficy Enterprise service
```

**Loading in the UI extension JS** — must call `loadNamespaces` before registering anything:

```javascript
// registerExtensions.js (or index.js)
window.jahia.i18n.loadNamespaces('my-module-name');

window.jahia.uiExtender.registry.add('callback', 'my-module-init', {
    targets: ['jahiaApp-init:60'],
    callback: function () {
        registry.add('action', 'myAction', {
            buttonLabel: 'my-module-name:label.action.title',  // module:key
            targets: ['contentActions:50'],
            // ...
        });
    }
});
```

Labels in registry entries always use the `'module-name:key'` format — the module name as namespace, the property key as the path.

---

## Quick comparison

| | JS Template Set | OSGi Module |
|---|---|---|
| **CND / editor labels** | `settings/resources/<module>.properties` | `src/main/resources/resources/<artifact>.properties` |
| **Front-end UI labels** | `settings/locales/en.json`, `fr.json` | n/a — use `.properties` for everything |
| **React usage** | `useTranslation()` → `t("key")` | `'module:label.key'` in registry entries |
| **Loading** | Automatic (`@jahia/vite-plugin`) | `window.jahia.i18n.loadNamespaces('module')` |
| **Minimum locales** | EN + FR `.properties` + EN + FR `.json` | EN + FR `.properties` |

---

## Common pitfalls

| Pitfall | Consequence |
|---|---|
| Missing `_fr.properties` | French editors see raw property keys instead of labels |
| Using hardcoded strings in React views instead of `t()` | Untranslatable UI; breaks locale switching |
| Choicelist values without `.properties` entries | Raw values (`_self`, `Monday`) shown in editor instead of display labels |
| OSGi: missing `loadNamespaces` call | UI extension labels render as raw `module:key` strings |
| OSGi: wrong path (`src/main/resources/` instead of `src/main/resources/resources/`) | Properties file not found; all labels missing |
| JS template set: putting UI strings in `.properties` instead of `locales/*.json` | Labels work in the editor but `t()` calls return the key at runtime |
| Missing tooltips (`propertyName.ui.tooltip`) | Editors have no guidance on what fields mean |
