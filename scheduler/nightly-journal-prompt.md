# Nightly journal prompt (template)

This is the instruction set for the **summarizer** that runs once a day and
writes the daily note. Run it however you like — a Claude scheduled task, a
cron job that calls `claude -p`, or any agent that can read files and write
markdown.

Replace the `{{PLACEHOLDERS}}` with your own paths, then paste it as the task
prompt. Times are easiest if you schedule the run for **23:59 in your local
timezone** so each note covers the day that is ending.

---

Write today's Claude Journal daily note into the Obsidian vault.

CONTEXT
- Vault: `{{VAULT_PATH}}` (daily notes go in its `Daily/` subfolder, named `YYYY-MM-DD.md`).
- A template exists at `Templates/Daily Note Template.md` — match its structure.
- An index note `Home.md` keeps a "Recent days" list of links.
- Git repositories live under: `{{REPOS_PATH}}`
- Claude Code session transcripts are mirrored to: `{{SESSIONS_DIR}}`
  (files named `YYYY-MM-DD__<sessionId>.jsonl`, each with an optional
  `<...>.cwd.txt` sidecar holding the project path).
- Local timezone: `{{TIMEZONE}}` (e.g. America/New_York). If your runner's
  clock is UTC, always compute the local date with `TZ="{{TIMEZONE}}" date +%Y-%m-%d`.

STEPS
1. Compute today's local date D using the timezone above.
2. Claude Code activity: in `{{SESSIONS_DIR}}`, find files named `D__*.jsonl`.
   For each, read the JSONL (one JSON object per line; user/assistant messages
   are under `.message.content[]`; the `.cwd.txt` sidecar names the project).
   Summarize what was worked on. For large transcripts, sample the user prompts
   and the assistant's final messages rather than every line.
3. GitHub pushes: for each git repo under `{{REPOS_PATH}}`, list commits authored
   today (in the local timezone) and whether each is contained in a remote-tracking
   branch (= pushed). Report each PUSHED commit once, per repo, as:
   `- **<repo>** — <brief description>. (commit \`<short>\`, pushed)`.
   List local-only commits separately if you like. If none: `- _No pushes today._`.
   The GitHub section is sourced ONLY from this git scan, so pushes are never
   double-counted regardless of how the work was done.
4. Write `Daily/D.md` with this frontmatter at the very top, then a
   `# <Weekday, Month D, YYYY>` heading, then the sections in this order:
   🛠️ Tasks & projects worked on · 📄 Files created or changed · 🐙 GitHub ·
   💡 Key decisions & takeaways · ✅ To-dos / follow-ups (as `- [ ]`).
   ```
   ---
   type: claude-journal
   date: D
   tags: [claude, journal]
   ---
   ```
   If the note already exists, update/merge rather than duplicating.
5. Update `Home.md`: add `- [[D]]` to the top of the "Recent days" list if not
   already present.
6. If there was no activity today, still create the note with sections marked
   "- _Nothing logged today._" so the daily cadence is unbroken.

OPTIONAL — Anthropic Cowork users only: you can additionally enumerate desktop
Claude app sessions via the session-info tools and fold them into the same
sections. This is specific to that environment and not required.
