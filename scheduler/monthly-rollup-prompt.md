# Monthly rollup prompt

This is the instruction set for the **monthly summarizer** that runs on the 1st
of each month and produces a rollup of the **previous** calendar month. The
scheduler reads `journal.config` from the repo root and substitutes the
`{{PLACEHOLDERS}}` below before invoking this prompt.

Schedule this for **the 1st of each month at 00:30 local time**.

---

Write last month's Claude Journal monthly rollup note into the Obsidian vault.

## Context

- **Vault:** `{{VAULT_PATH}}`
  - Daily notes: `Daily/YYYY-MM-DD.md`
  - Weekly notes: `Weekly/<Monday-date>.md`
  - Monthly notes: `Monthly/YYYY-MM.md`
- **Index:** `Home.md` keeps a "Recent months" list.
- **Timezone:** `{{TIMEZONE}}` — compute all dates with
  `TZ="{{TIMEZONE}}" date ...`

## Steps

### 1. Compute the previous month

```bash
export TZ="{{TIMEZONE}}"
# Anchor on the last day of the previous month (= day before the 1st of the
# current month). Never use `date -d "last month"` — GNU date subtracts one
# calendar month from *today's day-of-month*, so a manual run on the 31st
# overflows (Mar 31 - 1 month → Mar 3) and targets the wrong month.
LAST_DAY=$(date -d "$(date +%Y-%m-01) - 1 day" +%Y-%m-%d)
PREV_YEAR=$(date -d "$LAST_DAY" +%Y)
PREV_MONTH=$(date -d "$LAST_DAY" +%m)
PREV_LABEL=$(date -d "$LAST_DAY" '+%B %Y')   # e.g. "June 2026"
FIRST_DAY="${PREV_YEAR}-${PREV_MONTH}-01"
```

### 2. Read daily notes

Read all daily notes in `{{VAULT_PATH}}/Daily/` whose filenames fall in the
range `$FIRST_DAY` to `$LAST_DAY`. Parse each note's sections to collect:

- Tasks & projects
- GitHub pushes
- Key decisions
- Open to-dos

For activity levels, read each note's numeric frontmatter and compute
`activity = commits + sessions` per day (notes written before these fields
existed: estimate from the section text). This drives the heatmap and stats.

### 3. Build the activity heatmap

Create a visual heatmap of the month using emoji squares, laid out as week rows
(Mon–Sun). Each day gets one square:

| Symbol | Meaning (`commits + sessions` from daily frontmatter) |
|--------|---------|
| ⬜ | 0 — no activity |
| 🟩 | Light (1–2) |
| 🟦 | Medium (3–5) |
| 🟪 | Heavy (6+) |

Layout example for a month starting on Wednesday:

```
         Mon Tue Wed Thu Fri Sat Sun
Week 1:  ⬜  ⬜  🟩  🟦  🟪  ⬜  ⬜
Week 2:  🟩  🟦  🟩  🟩  🟦  ⬜  ⬜
...
```

Pad with blank cells for days before the month starts or after it ends.

### 4. Write the monthly note

Create `{{VAULT_PATH}}/Monthly/${PREV_YEAR}-${PREV_MONTH}.md`:

```markdown
---
type: claude-journal-monthly
month: <YYYY-MM>
tags: [claude, journal, monthly]
---

# <Month YYYY>

## 📅 Activity heatmap

⬜ none · 🟩 light · 🟦 medium · 🟪 heavy

         Mon Tue Wed Thu Fri Sat Sun
Week 1:  ...
Week 2:  ...
...

## 🌟 Highlights
- Top accomplishments and milestones for the month.

## 🛠️ Top projects
- **<project>** — summary of the month's work.

## 🐙 GitHub
- **<repo>** — N commits pushed. Key changes: ...

## 💡 Key decisions
- ...

## 📋 Still-open to-dos
- [ ] Carried-forward items that are still unchecked.

## 📊 Stats
- Days active: N / <days-in-month>
- Total commits: N
- Total sessions: N
- Total tokens: N
- Projects touched: N
- Most active day: <date> (commits + sessions = N)
```

Compute all Stats by summing the daily notes' numeric frontmatter fields
(`sessions`, `commits`, `tokens`).

If the note already exists, merge rather than duplicate.

### 5. Update Home.md

Add `- [[Monthly/<YYYY-MM>]]` to the top of the "Recent months" list in
`{{VAULT_PATH}}/Home.md`. Create the "Recent months" section if it doesn't exist
(place it after "Recent weeks").
