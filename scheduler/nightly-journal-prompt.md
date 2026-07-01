# Daily journal prompt

This is the instruction set for the **daily summarizer** that runs once a day
and writes the daily note. The scheduler reads `journal.config` from the repo
root and substitutes the `{{PLACEHOLDERS}}` below before invoking this prompt.

Schedule this for **23:59 in your local timezone** so each note covers the day
that is ending.

---

Write today's Claude Journal daily note into the Obsidian vault.

## Context

- **Vault:** `{{VAULT_PATH}}` — daily notes go in `Daily/`, named `YYYY-MM-DD.md`.
- **Template:** match the structure in `Templates/Daily Note Template.md`.
- **Index:** `Home.md` keeps a "Recent days" list of `[[YYYY-MM-DD]]` links.
- **Git repos:** `{{REPOS_PATH}}` — scan all repos under this root.
- **Session transcripts:** `{{SESSIONS_DIR}}` — files named
  `YYYY-MM-DD__<sessionId>.jsonl`, each with an optional `.cwd.txt` sidecar
  holding the project path.
- **Timezone:** `{{TIMEZONE}}` — always compute the local date with
  `TZ="{{TIMEZONE}}" date +%Y-%m-%d` if the runner's clock may be UTC.

## Steps

### 1. Compute the target date

```bash
# Dispatch jitter can push a 23:59 run past midnight — target yesterday if before noon.
D_TODAY="$(TZ="{{TIMEZONE}}" date +%Y-%m-%d)"
HOUR="$(TZ="{{TIMEZONE}}" date +%H)"
if [ "$HOUR" -lt 12 ]; then
  D="$(TZ="{{TIMEZONE}}" date -d 'yesterday' +%Y-%m-%d)"
else
  D="$D_TODAY"
fi
WEEKDAY="$(TZ="{{TIMEZONE}}" date -d "$D" '+%A, %B %-d, %Y')"
```

### 2. Read Claude Code session transcripts

In `{{SESSIONS_DIR}}`, find all files matching `${D}__*.jsonl`.

For each transcript:
- Read the `.cwd.txt` sidecar (if present) to identify the project.
- Parse the JSONL: each line is a JSON object. User and assistant messages are
  under `.message.content[]`. Tool calls appear under `.tool_use` / `.tool_result`.
- For large transcripts, sample the user prompts and the assistant's final
  messages rather than reading every line.
- Extract: what was worked on, key files touched, decisions made, and any
  explicit to-do items or follow-ups the user mentioned.

### 3. Scan Git repos for today's commits

For every Git repository under `{{REPOS_PATH}}` (find directories containing
`.git`, up to 3 levels deep):

```bash
git -C "$repo" log --since="$D 00:00:00" --until="$D 23:59:59" \
    --pretty='%H|%h|%s'
```

If `git log` fails for a repo (permissions, corruption, etc.), do not silently
skip it — include it in the output as:
`- _<repo>: git repo unreadable, skipped._`

For each commit, determine pushed vs. local-only:

```bash
git -C "$repo" branch -r --contains "$FULL_SHA" 2>/dev/null | grep -q .
```

- **Skip** the sessions mirror directory (it is not a meaningful project repo).
- **Include** this journal repo itself — commits to it are real work.
- Report pushed commits as:
  `- **<repo>** — <brief description>. (commit \`<short>\`, pushed)`
- List local-only commits separately.
- If no commits at all: `- _No pushes today._`

The GitHub section is sourced **only** from this git scan so pushes are never
double-counted regardless of how the work was done.

### 4. Write the daily note

Create or update `{{VAULT_PATH}}/Daily/${D}.md` with this exact structure:

```markdown
---
type: claude-journal
date: <D>
tags: [claude, journal]
---

# <Weekday, Month D, YYYY>

## 🛠️ Tasks & projects worked on
- ...

## 📄 Files created or changed
- ...

## 🐙 GitHub
- ...

## 💡 Key decisions & takeaways
- ...

## ✅ To-dos / follow-ups
- [ ] ...
```

If the note already exists, **merge** new content into the existing sections
rather than duplicating entries.

### 5. Update Home.md

Add `- [[<D>]]` to the top of the "Recent days" list in
`{{VAULT_PATH}}/Home.md` if not already present.

### 6. No-activity fallback

If there was no Claude Code activity and no Git commits today, still create the
note with each section showing `- _Nothing logged today._` so the daily cadence
is unbroken.

---

**Optional (Anthropic Cowork only):** If — and only if — this prompt runs
inside Anthropic's Cowork desktop app, it can also enumerate desktop Claude
app sessions via the internal `session-info` tools and fold them into the
sections above. These tools do not exist in a normal Claude Code / CLI
environment, so **everywhere else this step is silently skipped and can be
ignored** — it requires no setup and its absence is expected, not an error.
