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
PREV_YEAR=$(date -d "last month" +%Y)
PREV_MONTH=$(date -d "last month" +%m)
PREV_LABEL=$(date -d "last month" '+%B %Y')   # e.g. "June 2026"
FIRST_DAY="${PREV_YEAR}-${PREV_MONTH}-01"
# Last day of the previous month = day 0 of this month
LAST_DAY=$(date -d "$(date +%Y-%m-01) - 1 day" +%Y-%m-%d)
```

### 2. Read daily notes

Read all daily notes in `{{VAULT_PATH}}/Daily/` whose filenames fall in the
range `$FIRST_DAY` to `$LAST_DAY`. Parse each note's sections to collect:

- Tasks & projects
- GitHub pushes
- Key decisions
- Open to-dos

Also note which dates had activity (any non-empty section) vs. no activity, for
the heatmap.

### 3. Build the activity heatmap

Create a visual heatmap of the month using emoji squares, laid out as week rows
(Mon–Sun). Each day gets one square:

| Symbol | Meaning |
|--------|---------|
| ⬜ | No activity |
| 🟩 | Light (1–2 commits or sessions) |
| 🟦 | Medium (3–5 commits or sessions) |
| 🟪 | Heavy (6+ commits or sessions) |

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
- Total commits pushed: N
- Projects touched: N
- Most active day: <date> (N commits)
```

If the note already exists, merge rather than duplicate.

### 5. Update Home.md

Add `- [[Monthly/<YYYY-MM>]]` to the top of the "Recent months" list in
`{{VAULT_PATH}}/Home.md`. Create the "Recent months" section if it doesn't exist
(place it after "Recent weeks").
