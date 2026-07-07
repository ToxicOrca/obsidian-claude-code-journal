# Nightly journal prompt (OneNote)

This is the instruction set for the **OneNote daily summarizer** that runs once
a day and publishes the daily note into OneNote. The scheduler reads
`journal.config` from the repo root and substitutes the `{{PLACEHOLDERS}}`
below before invoking this prompt.

Schedule this for **23:59 in your local timezone** so each note covers the day
that is ending.

---

Write today's Claude Code journal entry and publish it to OneNote.

## Context

- **Output target:** OneNote notebook **"{{NOTEBOOK_NAME}}"** (default "Claude
  Journal"), one section per month (named `yyyy-MM`), one page per day (titled
  `yyyy-MM-dd`). The notebook and section are created automatically if missing.
- **Publisher script** (handles all OneNote/Graph work, non-interactive):
  `{{REPO_PATH}}/onenote/Publish-JournalToOneNote.ps1`
- **Session transcripts:** `{{SESSIONS_DIR}}` — files named
  `YYYY-MM-DD__<sessionId>.jsonl`, each with an optional `.cwd.txt` sidecar
  holding the project path.
- **Git repos:** `{{REPOS_PATH}}` — scan all repos under this root.
- **Timezone:** `{{TIMEZONE}}` — always compute the local date in this timezone
  since the runner's clock may be UTC.
- **Body shape reference:** `{{REPO_PATH}}/onenote/page-body-example.html` shows
  the exact HTML the publisher expects (sections only; no `<html>`/`<head>`
  wrapper — the publisher adds those and the date heading).

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

For each commit, determine pushed vs. local-only:

```bash
git -C "$repo" branch -r --contains "$FULL_SHA" 2>/dev/null | grep -q .
```

- **Skip** the sessions mirror directory (it is not a meaningful project repo).
- **Include** this journal repo itself — commits to it are real work.
- Report pushed commits as bullets; list local-only commits separately.
- If no commits at all: `No pushes today.`

The GitHub section is sourced **only** from this git scan so pushes are never
double-counted.

### 4. Compose the page body as HTML

Produce the five journal sections as HTML (sections only, no `<html>` wrapper),
in this order, matching `page-body-example.html`:

- `<h2>&#128296; Tasks &amp; projects worked on</h2>`
- `<h2>&#128196; Files created or changed</h2>`
- `<h2>&#128011; GitHub / GitLab</h2>`
- `<h2>&#128161; Key decisions &amp; takeaways</h2>`
- `<h2>&#9989; To-dos / follow-ups</h2>`

Use `<ul>/<li>` for lists and `<code>` for file/command names. Render every
to-do as `<p data-tag="to-do">...</p>` so it becomes a OneNote checkbox.

If there was no activity today, still produce all five sections with a single
`<li>Nothing logged today.</li>` so the daily cadence is unbroken.

### 5. Publish

Prefer passing the HTML inline so no temp file is needed:

```powershell
$body = @'
<h2>...</h2>
...your composed sections...
'@
& "{{REPO_PATH}}\onenote\Publish-JournalToOneNote.ps1" -BodyHtml $body -Date $D
```

(You may also write the fragment to a file and pass `-BodyHtmlPath` instead.)
The publisher is idempotent: if today's page already exists it replaces the
body in place rather than creating a duplicate, so re-running is safe.

### 6. Report

Report the OneNote page URL the publisher prints, then stop.

---

**Auth note:** The publisher uses a DELEGATED token (the OneNote API no longer
accepts app-only tokens). It reads a stored refresh token and refreshes
silently — no prompt. If publishing fails with an expired/revoked-token error,
the one-time sign-in must be redone: run
`{{REPO_PATH}}/onenote/Initialize-OneNoteAuth.ps1` interactively. Do NOT
attempt an interactive sign-in from a headless run; just report the failure so
it can be re-bootstrapped.
