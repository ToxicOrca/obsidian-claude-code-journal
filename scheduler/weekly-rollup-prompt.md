# Weekly rollup prompt

This is the instruction set for the **weekly summarizer** that runs once a week
(Monday, shortly after midnight) and produces a rollup of the previous Mon–Sun
week. The scheduler reads `journal.config` from the repo root and substitutes
the `{{PLACEHOLDERS}}` below before invoking this prompt.

Schedule this for **Monday 00:15 local time** so the previous week is fully
closed out.

---

Write this week's Claude Journal weekly rollup note into the Obsidian vault.

## Context

- **Vault:** `{{VAULT_PATH}}`
  - Daily notes: `Daily/YYYY-MM-DD.md`
  - Weekly notes: `Weekly/<Monday-date>.md` (named after the Monday that starts
    the week)
- **Index:** `Home.md` keeps a "Recent weeks" list.
- **Timezone:** `{{TIMEZONE}}` — compute all dates with
  `TZ="{{TIMEZONE}}" date ...`

## Steps

### 1. Compute the week range (robustly)

This may run just after midnight into Monday. Always roll back to the **most
recently completed** Mon–Sun week:

```bash
export TZ="{{TIMEZONE}}"
# Today's day-of-week (1=Mon … 7=Sun)
DOW=$(date +%u)
# If it's Monday (1), the week that just ended started 7 days ago.
# Otherwise, the most recent Monday is (DOW - 1) days ago; the week
# before that started 7 more days back.
if [ "$DOW" -eq 1 ]; then
  MONDAY=$(date -d '7 days ago' +%Y-%m-%d)
else
  MONDAY=$(date -d "$((DOW - 1 + 7)) days ago" +%Y-%m-%d)
fi
SUNDAY=$(date -d "$MONDAY + 6 days" +%Y-%m-%d)
```

The output note covers **$MONDAY through $SUNDAY** inclusive.

### 2. Read daily notes

Read all daily notes in `{{VAULT_PATH}}/Daily/` whose filenames fall in the
range `$MONDAY` to `$SUNDAY` (string comparison works since they are
`YYYY-MM-DD.md`). Parse each note's sections to collect:

- Tasks & projects worked on
- Files created or changed
- GitHub pushes (repos and commits)
- Key decisions & takeaways
- Open to-dos / follow-ups

### 3. Write the weekly note

Create `{{VAULT_PATH}}/Weekly/${MONDAY}.md`:

```markdown
---
type: claude-journal-weekly
week_start: <MONDAY>
week_end: <SUNDAY>
tags: [claude, journal, weekly]
---

# Week of <Month D> – <Month D, YYYY>

## 🌟 Highlights
- Top 3–5 accomplishments or milestones for the week.

## 🛠️ Projects
- **<project>** — summary of the week's work on this project.

## 🐙 GitHub
- **<repo>** — N commits pushed. Key changes: ...

## 💡 Key decisions
- ...

## 📋 Still-open to-dos
- [ ] Carried-forward items from daily notes that are still unchecked.

## 📊 Stats
- Days active: N / 7
- Total commits pushed: N
- Projects touched: N
```

If the note already exists, merge rather than duplicate.

### 4. Update Home.md

Add `- [[Weekly/<MONDAY>]]` to the top of the "Recent weeks" list in
`{{VAULT_PATH}}/Home.md`. Create the "Recent weeks" section if it doesn't exist
(place it after "Recent days").
