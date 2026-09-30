# CND Content Modeling Decisions

## Scale of thumbs

A well-scoped module has: **1–4 page templates, 5–10 content types, 2–5 mixins, 1–4 views per type.**
If a request exceeds this, flag it and split work into sessions.

---

## Semantic vs generic types

| Use semantic types for… | Use generic types for… |
|---|---|
| Business entities: articles, team members, events | Visual composition: banners, feature rows |
| Items that appear in listings/collections | One-off sections, layout containers |
| Content with business logic or user restrictions | Reusable UI blocks without meaning |
| Content that needs a detail page (`jmix:mainResource`) | |

When in doubt, prefer semantic — its evolutions are easier to design.

---

## Weakreference vs children

| Use children when… | Use weakreference when… |
|---|---|
| Parent is a visual container (CTAs inside a hero) | Internal links (call to action targets, page links) |
| Children have no life outside the parent | Many-to-many relationships (author ↔ blog post) |
| Always created together | Content managed/reused elsewhere |
| Each child has multiple properties (label + link) | Each item is just a reference to an existing node |

- Many-to-many = MUST use `weakreference multiple`
- One-to-many = prefer children when parent is the container

---

## Mixin vs child node vs inheritance

| Use mixin when… | Use child nodes when… | Use inheritance when… |
|---|---|---|
| Reusing properties across unrelated types | Multiple instances needed (multiple CTAs) | Retaining original views + adding fields in new views |
| At most one instance per component | | |

**Avoid inheritance in general** — it duplicates types in the editor picker.

Never extend anything other than `jnt:content` (or your base mixin). To add fields to a type you don't control, use a mixin with `extends`:

```cnd
[nsmix:morePageFields] mixin extends=jnt:page
 - myField (string) i18n
```

---

## Pages vs jmix:mainResource

| Use pages when… | Use jmix:mainResource when… |
|---|---|
| Content is a standalone page with no structured data | Content needs both a listing card AND a detail page |
| No programmatic listing/filtering needed | Content collections (blog posts, events, team members) |

---

## Common reusable mixin patterns

| Mixin name | Properties | When to use |
|---|---|---|
| `nsmix:cta` | `label (string) i18n`, `j:linkType (string, choicelist[linkTypeInitializer])` | Any type with a button/link |
| `nsmix:media` | `image (weakreference, picker[type='image']) < jmix:image` | Any type with an image |
| `nsmix:seo` | `metaTitle (string) i18n`, `metaDescription (string, textarea) i18n` | Any `jmix:mainResource` type |
| `nsmix:badge` | `badgeText (string) i18n`, `badgeColor (string, color)` | Cards, teasers |

Always extract to a mixin when the same set of properties appears on 2+ types.

**One mixin, two ways to reuse it (the call to action).** Declare the property group once and:

- put it in the **supertypes** of the types whose layout places it (a hero banner puts its button
  under the heading);
- make it **optional everywhere else** with `extends=` on the mixin the section types already share,
  so editors switch it on per node ("Call to action" toggle in the edit form) and every future
  section gets it with no CND change:

```cnd
[nsmix:cta] > nsmix:linkTo mixin
 extends = nsmix:sectionStyle
 - ctaLabel (string) i18n
```

A type that already has the mixin as a supertype shows no second toggle (verified with
`forms { editForm(uuidOrPath, uiLocale, locale) }` on 8.2.3.2: `dynamic: true` fieldset on a rich
text, `dynamic: false` on the image-and-text that inherits it). The view renders it with one helper
that returns nothing when the mixin is off, and every section view ends with that helper. No
separate "CTA banner" type: a text section on the accent surface with the call to action on is one.
Pick the `extends=` target carefully: extending the base component mixin would also offer the
button on link lists, headers and footers. Reference: classic-templates `ctplmix:cta`, `lib/Cta.tsx`.

---

## Spec template (interactive mode)

```
Component: [PascalCase name]
Description: [what editors create with this]
Fields:
  - name: data type, i18n?, mandatory?, multiple?
Views: [default / card / fullPage / small]
Used where: [page area / content folder / child of <Parent>]
Repeatable children: [no / yes: describe]
```
