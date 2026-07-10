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

### Slug convention

Whenever a project/repo name is used as a tag or identifier, normalize it to a
**slug**: lowercase, replace any non-alphanumeric character with a hyphen, and
collapse consecutive hyphens. For example: `My Cool_App` → `my-cool-app`.

### Controlled topic vocabulary

When auto-tagging (Step 7), use **only** these topic tags:

| Tag | When to apply |
|-----|---------------|
| `topic/feature` | New functionality was added |
| `topic/bug-fix` | A bug was fixed |
| `topic/refactor` | Code was restructured without behavior change |
| `topic/docs` | Documentation or comments were the primary work |
| `topic/test` | Tests were added or fixed |
| `topic/devops` | CI/CD, build, deploy, or infrastructure work |
| `topic/design` | UI/UX, styling, or layout work |

Only add a topic tag when the day's content **clearly** supports it. When in
doubt, omit — a missing tag is better than a wrong one.

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

Transcript files are named by the **session start date**. A session that runs
past midnight keeps its start-date filename, so also check the **previous
day's** files (`$(date -d "$D - 1 day" +%Y-%m-%d)__*.jsonl`) for entries whose
`timestamp` falls on `$D` — that spillover work belongs in today's note. When
summarizing a spillover file, use **only** the entries timestamped on `$D`;
everything earlier was already covered by yesterday's note.

For each transcript:
- Read the `.cwd.txt` sidecar (if present) to identify the project.
- Parse the JSONL: each line is a JSON object. User and assistant messages are
  under `.message.content[]`. Tool calls appear under `.tool_use` / `.tool_result`.
- For large transcripts, sample the user prompts and the assistant's final
  messages rather than reading every line.
- Extract: what was worked on, key files touched, decisions made, and any
  explicit to-do items or follow-ups the user mentioned.
- Count the day's **sessions** (number of distinct transcripts with entries on
  `$D`) and sum the day's **tokens**: for each assistant entry, add
  `.message.usage.input_tokens + .message.usage.output_tokens` (skip entries
  without a `usage` object; count each entry once). These feed the frontmatter
  in Step 4.

### 3. Scan Git repos for today's commits

For every Git repository under `{{REPOS_PATH}}` (find directories containing
`.git`, up to 3 levels deep):

```bash
git -C "$repo" log --all --since="$D 00:00:00" --until="$D 23:59:59" \
    --pretty='%H|%h|%s'
```

`--all` is required: plain `git log` only walks the checked-out branch, so
commits made on a feature branch would vanish from the journal after switching
back to `main`.

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
tags: [claude, journal, project/<slug>, ..., topic/<topic>, ...]
sessions: <N>
commits: <N>
tokens: <N>
---

# <Weekday, Month D, YYYY>

## 🛠️ Tasks & projects worked on
- **<project>** — what was done. #project/<slug>
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

Each project bullet in "Tasks & projects worked on" must include an inline
`#project/<slug>` tag so the Obsidian graph links resolve to the project page.

The numeric frontmatter fields are the machine-readable record of the day
(Dataview-queryable):
- `sessions` — distinct transcripts with entries on `$D` (from Step 2).
- `commits` — total commits found by the git scan (pushed + local-only).
- `tokens` — summed input+output tokens from Step 2 (`0` if none).

If the note already exists, **merge** new content into the existing sections
rather than duplicating entries (recompute the numeric fields from scratch —
don't add to the old values).

### 5. Update Home.md

Add `- [[Daily/<D>|<D>]]` to the top of the "Recent days" list in
`{{VAULT_PATH}}/Home.md` if not already present. Always use the
folder-qualified `Daily/` link: weekly notes are also named by date, so a bare
`[[<D>]]` can ambiguously resolve to `Weekly/<D>.md` when `<D>` is a Monday.

Then update the "🔥 Streak" section (create it directly under the `# 🤖 Claude
Journal` heading if missing):

1. An **active day** is a daily note whose frontmatter has `sessions > 0` or
   `commits > 0` (notes written before these fields existed count as active if
   they are not the `_Nothing logged today._` fallback).
2. Walk `Daily/*.md` filenames backwards from `$D` to find the **current
   streak** (consecutive active days ending at `$D`; `0` if today was
   inactive) and the **longest streak** ever.
3. Write:

```markdown
## 🔥 Streak
- Current: **N days** (as of <D>)
- Longest: **N days** (<start> → <end>)
```

### 6. No-activity fallback

If there was no Claude Code activity and no Git commits today, still create the
note with each section showing `- _Nothing logged today._` so the daily cadence
is unbroken. Set `sessions: 0`, `commits: 0`, `tokens: 0` in the frontmatter —
the streak and rollup logic depend on these zeros.

### 7. Auto-tag the note

After building the note content, derive tags and write them into the frontmatter
`tags:` array. The base tags `[claude, journal]` are always present. Add:

1. **Project tags** — one `project/<slug>` tag per project/repo touched today.
   Derive the slug from the repo directory name (from the git scan) and/or the
   `.cwd.txt` sidecar basename, using the slug convention above.
2. **Topic tags** — from the controlled vocabulary above. Scan the day's work
   (commit messages, session content, files changed) and add only the topics
   that clearly apply. Typical days get 1–3 topic tags; it's fine to add none.

The final frontmatter should look like:
```yaml
tags: [claude, journal, project/my-api, project/notes-app, topic/feature, topic/bug-fix]
sessions: 3
commits: 5
tokens: 184200
```

---

**Optional (Anthropic Cowork only):** If — and only if — this prompt runs
inside Anthropic's Cowork desktop app, it can also enumerate desktop Claude
app sessions via the internal `session-info` tools and fold them into the
sections above. These tools do not exist in a normal Claude Code / CLI
environment, so **everywhere else this step is silently skipped and can be
ignored** — it requires no setup and its absence is expected, not an error.
