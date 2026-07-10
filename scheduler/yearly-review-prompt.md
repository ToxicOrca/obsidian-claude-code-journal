# Year in Review prompt

This is the instruction set for the **yearly summarizer** that runs early on
January 1st and produces a "Year in Review" note for the year that just ended.
The scheduler reads `journal.config` from the repo root and substitutes the
`{{PLACEHOLDERS}}` below before invoking this prompt.

Schedule this for **January 1 at 01:30 local time** (after the monthly rollup
at 00:30 has written December's note).

---

Write last year's Claude Journal "Year in Review" note into the Obsidian vault.

## Context

- **Vault:** `{{VAULT_PATH}}`
  - Daily notes: `Daily/YYYY-MM-DD.md` (numeric frontmatter: `sessions`,
    `commits`, `tokens`)
  - Monthly notes: `Monthly/YYYY-MM.md`
  - Yearly notes: `Yearly/YYYY.md`
- **Index:** `Home.md` keeps a "Recent years" list.
- **Timezone:** `{{TIMEZONE}}` — compute all dates with
  `TZ="{{TIMEZONE}}" date ...`

## Steps

### 1. Compute the target year

```bash
export TZ="{{TIMEZONE}}"
# Anchor on yesterday so a run in the first days of January still targets the
# year that just ended.
YEAR=$(date -d "yesterday" +%Y)
```

### 2. Gather data

- **Narrative:** read all twelve `Monthly/${YEAR}-*.md` notes (highlights, top
  projects, key decisions). Fall back to daily notes for months without a
  rollup.
- **Numbers:** read every `Daily/${YEAR}-*.md` note's numeric frontmatter
  (`sessions`, `commits`, `tokens`) and `project/<slug>` tags. Daily activity
  level = `commits + sessions`.

### 3. Build the year heatmap

One row per month, one emoji square per day, using the same scale as the
monthly rollup (`commits + sessions`):

⬜ 0 · 🟩 1–2 · 🟦 3–5 · 🟪 6+

```
Jan  🟩🟩⬜🟦...
Feb  ⬜🟪🟩⬜...
...
Dec  🟦🟩⬜⬜...
```

Days with no daily note count as ⬜. Do not pad rows — each row has exactly as
many squares as the month has days.

### 4. Write the yearly note

Create `{{VAULT_PATH}}/Yearly/${YEAR}.md`:

```markdown
---
type: claude-journal-yearly
year: <YYYY>
tags: [claude, journal, yearly]
sessions: <total>
commits: <total>
tokens: <total>
---

# <YYYY> — Year in Review

## 📅 Year heatmap

⬜ none · 🟩 light · 🟦 medium · 🟪 heavy

Jan  ...
Feb  ...
...
Dec  ...

## 🌟 Highlights of the year
- The 5–10 biggest accomplishments, launches, or milestones.

## 🛠️ Top projects
- **<project>** — one-paragraph summary of the year's arc on this project.
  (Order by days active; include a `[[Projects/<slug>]]` link.)

## 📈 By the numbers
- Days active: N / 365
- Longest streak: N days (<start> → <end>)
- Total sessions: N
- Total commits: N
- Total tokens: N
- Busiest month: <Month> (N active days)
- Busiest day: <date> (commits + sessions = N)
- Projects touched: N

## 🏷️ Topic mix
- topic/feature ██████░░░░ 60%
- topic/bug-fix ███░░░░░░░ 30%
- (share of daily notes carrying each topic tag; omit unused topics)

## 💡 Decisions that shaped the year
- The handful of key decisions with lasting impact (from monthly notes).

## 📋 Carried into <YYYY+1>
- [ ] Still-open to-dos worth keeping (dedupe; drop stale ones).
```

If the note already exists, regenerate it from scratch (idempotent — same rule
as project pages).

### 5. Update Home.md

Add `- [[Yearly/<YYYY>]]` to the top of the "Recent years" list in
`{{VAULT_PATH}}/Home.md`. Create the "Recent years" section if it doesn't
exist (place it after "Recent months").
