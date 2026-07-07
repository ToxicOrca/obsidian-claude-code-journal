# Project pages prompt

This is the instruction set for the **project page builder** that (re)generates
one note per project under the vault's `Projects/` folder. The scheduler reads
`journal.config` from the repo root and substitutes the `{{PLACEHOLDERS}}` below
before invoking this prompt.

Schedule this **daily, shortly after the daily summarizer** (e.g. 23:30 or
00:20) or weekly — it is idempotent and safe to run at any cadence.

> **Note:** this is a separate scheduled task. Add a thin wrapper on your side
> (same pattern as daily/weekly/monthly: read `journal.config`, substitute
> placeholders, run this prompt).

---

Rebuild the per-project pages in the Obsidian vault.

## Context

- **Vault:** `{{VAULT_PATH}}`
  - Daily notes: `Daily/YYYY-MM-DD.md` (frontmatter has `tags:` including
    `project/<slug>` entries).
  - Project pages: `Projects/<slug>.md`
- **Index:** `Home.md` keeps a "Projects" section linking to each project page.
- **Timezone:** `{{TIMEZONE}}`

### Slug convention

Project slugs are lowercase, non-alphanumeric characters replaced with hyphens,
consecutive hyphens collapsed. Example: `My Cool_App` → `my-cool-app`.

## Steps

### 1. Discover projects

Scan all daily notes in `{{VAULT_PATH}}/Daily/`. For each note, read the
frontmatter `tags:` array and collect every tag matching `project/<slug>`. Build
a deduplicated set of all project slugs seen across all daily notes.

### 2. Build each project page

For each discovered `<slug>`, create or **regenerate**
`{{VAULT_PATH}}/Projects/<slug>.md`.

**Important:** this step is idempotent. Always rebuild the page from scratch by
re-reading the daily notes — never append to an existing page, as that would
create duplicates.

For the project page, gather from every daily note tagged `project/<slug>`:
- The date and a one-line summary of what was done on that project (from the
  "Tasks & projects worked on" section).
- Any GitHub commits for that project (from the "GitHub" section).
- Any open to-dos mentioning the project (unchecked `- [ ]` items).

Write the page with this structure:

```markdown
---
type: claude-project
project: <slug>
tags: [claude, project, project/<slug>]
---

# <slug>

## 📝 Description
A brief auto-generated description based on the most common themes across
the timeline entries.

## 📅 Timeline
*Reverse chronological. Each entry links back to the daily note.*

- [[YYYY-MM-DD]] — One-line summary of the day's work on this project.
- [[YYYY-MM-DD]] — ...
- ...

## 🐙 Commits
- `<short>` — <subject> (<date>, pushed/local-only)
- ...

## 📊 Stats
- First seen: <earliest date>
- Last active: <most recent date>
- Days active: N
- Total commits: N

## ✅ Open to-dos
- [ ] Carried-forward items from daily notes that are still unchecked.
```

### 3. Update Home.md

Ensure `{{VAULT_PATH}}/Home.md` has a "Projects" section. List every project
page as `- [[Projects/<slug>]]`, sorted alphabetically. If the section already
exists, replace its contents (don't duplicate links).
