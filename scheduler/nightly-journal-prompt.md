# Nightly journal prompt (OneNote)

This is the instruction set for the **summarizer** that runs once a day and
publishes the daily note into OneNote. It is designed to be run headless via
`claude -p` from a scheduled task (see `Register-JournalTask.ps1` on Windows),
but you can paste it into any Claude Code session to publish on demand.

Replace the `{{PLACEHOLDERS}}` with your own paths/values, then use it as the
task prompt. Times are easiest if you schedule the run for **23:59 in your local
timezone** so each note covers the day that is ending.

---

Write today's Claude Code journal entry and publish it to OneNote.

CONTEXT
- Output target: OneNote notebook **"{{NOTEBOOK_NAME}}"** (default "Claude
  Journal"), one section per month (named `yyyy-MM`), one page per day (titled
  `yyyy-MM-dd`). The notebook and section are created automatically if missing.
- Publisher script (handles all OneNote/Graph work, non-interactive):
  `{{REPO_PATH}}\onenote\Publish-JournalToOneNote.ps1`
- Claude Code session transcripts are mirrored to: `{{SESSIONS_DIR}}`
  (files named `YYYY-MM-DD__<sessionId>.jsonl`, each with an optional
  `<...>.cwd.txt` sidecar holding the project path).
- Git repositories root (optional commit scan): `{{REPOS_PATH}}`
- Timezone: `{{TIMEZONE}}` (e.g. America/New_York). The runner's clock may
  differ, so compute "today" explicitly for that timezone.
- Body shape reference: `{{REPO_PATH}}\onenote\page-body-example.html` shows the
  exact HTML the publisher expects (sections only; no `<html>`/`<head>` wrapper
  — the publisher adds those and the date heading).

STEPS
1. Compute today's local date D (`yyyy-MM-dd`) in the timezone above.
2. Claude Code activity: in the sessions dir, find files named `D__*.jsonl`.
   For each, read the JSONL (one JSON object per line; user/assistant messages
   are under `.message.content[]`; the `.cwd.txt` sidecar names the project).
   Summarize what was worked on. For large transcripts, sample the user prompts
   and the assistant's final messages rather than every line.
3. Git pushes (optional): for each git repo under the repos root, list commits
   authored today (local tz) and whether each is in a remote-tracking branch
   (= pushed). Report each PUSHED commit once per repo as a bullet:
   `<repo> — <brief description>. (commit <short>, pushed)`. If none, write
   "No pushes today." (See `scan-git-pushes.sh` for a ready-made scanner.)
4. Compose the page **body as HTML** (sections only) with these five sections,
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
5. Publish it. Prefer passing the HTML inline so no temp file is needed:
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
6. Report the OneNote page URL the publisher prints, then stop.

AUTH NOTE
The publisher uses a DELEGATED token (the OneNote API no longer accepts app-only
tokens). It reads a stored refresh token and refreshes silently — no prompt. If
publishing fails with an expired/revoked-token error, the one-time sign-in must
be redone: run `{{REPO_PATH}}\onenote\Initialize-OneNoteAuth.ps1` interactively.
Do NOT attempt an interactive sign-in from a headless run; just report the
failure so it can be re-bootstrapped.
