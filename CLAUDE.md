# CLAUDE.md

Guidance for Claude Code (and any future agent) working in this repo. **Read
this before editing** — this project is the source end of a multi-stage
pipeline, and several scheduled tasks (Routines) on this machine depend on the
exact output format described below. Changing the exporter's output or the daily
note structure without updating those tasks will silently break the journal.

## What this project is

`obsidian-claude-code-journal` automatically keeps a daily journal of work done
with Claude Code, publishing to **Obsidian**, **OneNote**, or **both**. It has
two halves:

1. **Exporter (this repo, real-time):** a Claude Code hook that mirrors the
   active session's transcript into a plain `sessions/` folder.
2. **Summarizers (scheduled tasks, nightly):** agent prompts (in `scheduler/`)
   that read those transcripts + today's Git pushes and write structured notes.
   - **Obsidian backend:** Markdown notes into the vault (`Daily/`, `Weekly/`,
     `Monthly/`, `Projects/`, plus a `Home.md` index).
   - **OneNote backend:** HTML pages into a OneNote notebook via Microsoft Graph
     (one section per month, one page per day).

The `BACKEND` setting in `journal.config` controls which backend(s) run.
Obsidian notes are plain Markdown (synced via Syncthing, Obsidian Sync, Git,
Dropbox). OneNote syncs automatically. Raw transcripts stay local and
git-ignored.

## Repo layout

- `exporter/export-session.js` — the hook. Copies the session `.jsonl` transcript
  into the sessions dir. Never throws; always exits 0 (a logging hook must never
  disrupt Claude Code).
- `scheduler/` — the **actual summarizer logic**, version-controlled here:
  - `nightly-journal-prompt.md` — Obsidian daily note builder (includes auto-tagging).
  - `nightly-journal-onenote-prompt.md` — OneNote daily page builder.
  - `weekly-rollup-prompt.md` — weekly rollup (Obsidian only).
  - `monthly-rollup-prompt.md` — monthly rollup + activity heatmap (Obsidian only).
  - `project-pages-prompt.md` — per-project page (re)builder (Obsidian only).
  - `scan-git-pushes.sh` — helper to list today's commits per repo (pushed vs local).
  - `Register-JournalTask.ps1` — registers a Windows Task Scheduler job (OneNote).
- `onenote/` — OneNote publishing pipeline:
  - `Initialize-OneNoteAuth.ps1` — one-time device-code OAuth sign-in.
  - `OneNoteAuth.ps1` — shared auth helpers (DPAPI-encrypted refresh token).
  - `Publish-JournalToOneNote.ps1` — Microsoft Graph publisher (notebook > section > page).
  - `page-body-example.html` — example HTML body fragment.
- `hooks/settings.example.json` — how to register the exporter hook.
- `obsidian-template/` — vault templates (Daily/Weekly/Monthly/Project) + `Home.md`.
- `journal.config` — local paths, timezone, backend selection (git-ignored; see below).
- `journal.config.example` — template for the above.
- `config.example.json` — OneNote-specific config template (tenantId, notebookName).
- `config.json` — OneNote local config (git-ignored).
- `sessions/` — mirrored transcripts, git-ignored. **Never commit these** — they
  contain the user's conversations and code.
- `docs/how-it-works.md` — narrative overview.

## journal.config (local, git-ignored)

KEY=VALUE lines. Current values on this machine:

```
VAULT_PATH=C:\Users\Orca\Documents\Obsidian\Claude Journal
REPOS_PATH=C:\Users\Orca\Documents\ClaudeProjects
SESSIONS_DIR=C:\Users\Orca\Documents\ClaudeProjects\obsidian-claude-code-journal\sessions
TIMEZONE=America/New_York
BACKEND=obsidian
REPO_PATH=C:\Users\Orca\Documents\ClaudeProjects\obsidian-claude-code-journal
NOTEBOOK_NAME=Claude Journal
```

The scheduled tasks read this file and substitute the matching
`{{PLACEHOLDER}}` tokens in the `scheduler/*.md` prompt files at runtime. What
you edit in the prompts is exactly what runs — keep the placeholders intact.

The `BACKEND` setting controls which summarizer prompt(s) run:
- `obsidian` (default) — only `nightly-journal-prompt.md` (writes vault notes).
- `onenote` — only `nightly-journal-onenote-prompt.md` (publishes to OneNote).
- `both` — runs both prompts.

`REPO_PATH` and `NOTEBOOK_NAME` are used only by the OneNote prompt and are
ignored when `BACKEND=obsidian`.

## The exporter: invocation and output format

**Invocation.** Registered in the user's Claude Code settings
(`~/.claude/settings.json`) as a hook on **both** the `Stop` and `SessionEnd`
events:

```
node ".../obsidian-claude-code-journal/exporter/export-session.js"
```

`Stop` fires after every assistant response (keeps the mirror continuously
current — no clean exit required); `SessionEnd` catches the final state. Claude
Code pipes a JSON object to the script on stdin; the script uses
`transcript_path`, and optionally `session_id` and `cwd`.

**Output (this is the contract the summarizers depend on — do not change
casually):**

- **Location (first match wins):** `$CLAUDE_JOURNAL_SESSIONS_DIR` if set,
  otherwise `<repo>/sessions/`.
- **Transcript file:** a copy of the session `.jsonl`, named
  **`YYYY-MM-DD__<sessionId>.jsonl`**. The date is the machine's local date
  (`localDate()`; override by setting `TZ` in the hook's environment). The
  session id is sanitized to `[A-Za-z0-9_-]`.
- **Sidecar:** if `cwd` was provided, a **`YYYY-MM-DD__<sessionId>.cwd.txt`** file
  containing the working directory path, so the summarizer can name the project.

If you change the filename pattern, the date format, or the sidecar, update
**both** `scheduler/nightly-journal-prompt.md` and
`scheduler/nightly-journal-onenote-prompt.md` (Step 2 in each) to match — they
glob `${D}__*.jsonl` and read the `.cwd.txt` sidecar.

## Scheduled tasks (Routines) that consume this data

Four scheduled tasks run on this machine. Each is a **thin wrapper**: its prompt
lives in a `SKILL.md` under `C:\Users\Orca\Claude\Scheduled\<taskId>\SKILL.md`,
and that SKILL.md does nothing but (1) read `journal.config`, (2) read the
matching `scheduler/*.md` prompt in this repo, (3) substitute placeholders, and
(4) follow it exactly. **The real logic lives here in `scheduler/`, not in the
SKILL.md files** — edit the prompts here, not the tasks.

| Task ID | Purpose | Prompt file used | Cron | Approx. time |
|---------|---------|------------------|------|--------------|
| `claude-journal-daily` | Summarize each day's Claude work into a daily note | `scheduler/nightly-journal-prompt.md` | `59 23 * * *` | ~midnight, daily |
| `claude-journal-weekly` | Summarize the week's daily notes into a weekly rollup | `scheduler/weekly-rollup-prompt.md` | `59 23 * * 0` | Sun→Mon boundary, ~12:07 AM Mon |
| `claude-journal-monthly` | Summarize the previous month into a monthly rollup w/ heatmap | `scheduler/monthly-rollup-prompt.md` | `30 0 1 * *` | Day 1 of month, ~12:30 AM |
| `claude-journal-projects` | Rebuild per-project pages from tagged daily notes | `scheduler/project-pages-prompt.md` | `0 1 * * *` | ~1:08 AM, daily |

Notes:
- The daily task's SKILL.md additionally **enables the optional Cowork
  desktop-capture step** (`mcp__session_info__list_sessions` +
  `read_transcript`) because those tools exist in its runtime. This is silently
  skipped in a plain Claude Code environment.
- These tasks call `mcp__cowork__request_cowork_directory` for `VAULT_PATH` (and
  `REPOS_PATH` for daily) to gain file access before writing.

## Dependency chain — READ BEFORE CHANGING OUTPUT

```
exporter output (sessions/*.jsonl + .cwd.txt)
        ↓  (read by)
        ├─ claude-journal-daily  →  Daily/YYYY-MM-DD.md   (structured, tagged)
        │       ↓  (daily notes read by)
        │       ├─ claude-journal-weekly    → Weekly/<Monday>.md
        │       ├─ claude-journal-monthly   → Monthly/YYYY-MM.md
        │       └─ claude-journal-projects  → Projects/<slug>.md
        │
        └─ OneNote nightly prompt  →  OneNote page (yyyy-MM-dd)
                (independent; no rollup chain)
```

The **Obsidian** weekly, monthly, and projects rollups **do not re-scan
transcripts or Git** — they parse the daily notes. So the daily note's
structure, tags, filenames, and folder layout are a hard contract. If you change
how daily notes are written, update the three downstream prompts too.

The **OneNote** daily page is a standalone output — no rollup chain reads it.
Changes to the OneNote prompt or HTML structure do not affect the Obsidian
pipeline and vice versa.

### Exact structures the rollups rely on

**Daily note** — `Daily/YYYY-MM-DD.md`, frontmatter + fixed section headings:

```markdown
---
type: claude-journal
date: <YYYY-MM-DD>
tags: [claude, journal, project/<slug>, ..., topic/<topic>, ...]
---

# <Weekday, Month D, YYYY>

## 🛠️ Tasks & projects worked on
- **<project>** — what was done. #project/<slug>
## 📄 Files created or changed
## 🐙 GitHub
## 💡 Key decisions & takeaways
## ✅ To-dos / follow-ups
- [ ] ...
```

Contract points the downstream tasks depend on:
- **Filename/date format:** `Daily/YYYY-MM-DD.md`. Weekly/monthly select notes by
  string-comparing these filenames against a date range — do not change the
  pattern.
- **Frontmatter tags:** base `[claude, journal]` always; one `project/<slug>` per
  repo touched; `topic/<t>` from the controlled vocabulary only
  (`feature, bug-fix, refactor, docs, test, devops, design`).
- **`project/<slug>` frontmatter tags are how `claude-journal-projects`
  discovers projects.** Each project bullet also carries an inline
  `#project/<slug>` tag for Obsidian graph links. Slug convention: lowercase,
  non-alphanumeric → hyphen, collapse repeats (`My Cool_App` → `my-cool-app`).
- **Section headings (with emoji) are parsed by name** — weekly/monthly/projects
  read "Tasks & projects worked on", "GitHub", "Key decisions", and the `- [ ]`
  to-do checkboxes. Renaming a heading or dropping its emoji can orphan a section.
- **GitHub section** is sourced only from the Git scan (never from session text)
  to avoid double-counting.

**Rollup outputs & their frontmatter:**
- Weekly: `Weekly/<Monday-date>.md`, `type: claude-journal-weekly`,
  `tags: [claude, journal, weekly]`.
- Monthly: `Monthly/YYYY-MM.md`, `type: claude-journal-monthly`,
  `tags: [claude, journal, monthly]`, includes an emoji heatmap
  (⬜ none · 🟩 light · 🟦 medium · 🟪 heavy).
- Projects: `Projects/<slug>.md`, `type: claude-project`,
  `tags: [claude, project, project/<slug>]`. **Idempotent** — always regenerated
  from daily notes; never appended.
- All four update `Home.md` (Recent days / Recent weeks / Recent months /
  Projects sections).

## Vault paths at a glance

```
<VAULT_PATH>/
├── Home.md                 # self-updating index
├── Daily/YYYY-MM-DD.md     # written by claude-journal-daily
├── Weekly/<Monday>.md      # written by claude-journal-weekly
├── Monthly/YYYY-MM.md      # written by claude-journal-monthly
└── Projects/<slug>.md      # rebuilt by claude-journal-projects
```

## When you edit this repo

- **Change the exporter output format** → also update both
  `scheduler/nightly-journal-prompt.md` and
  `scheduler/nightly-journal-onenote-prompt.md` (glob pattern + sidecar read).
- **Change the Obsidian daily note format** (headings, frontmatter, tags,
  filename) → also update `weekly-`, `monthly-`, and `project-pages-` prompts,
  which parse those daily notes. (The OneNote prompt is independent.)
- **Change the OneNote page HTML structure** → update
  `nightly-journal-onenote-prompt.md` and `onenote/page-body-example.html`.
  (The Obsidian prompts are independent.)
- **Change slug rules or the `project/<slug>` tag** → update every Obsidian
  prompt (they all share the slug convention; projects builder keys off the tag).
- **Don't put logic in the `Scheduled/*/SKILL.md` files** — they are intentionally
  thin. Logic belongs in `scheduler/`.
- **Never commit `sessions/`.** It's git-ignored and holds private transcripts.
- **Never commit `config.json`.** It's git-ignored and holds tenant-specific
  OneNote settings.

## Known inconsistencies to be aware of

- The README schedule table and the header comments in `project-pages-prompt.md`
  (which suggest 00:05 / 00:20 / 23:30) **do not match the actual configured
  cron times** (projects runs `0 1 * * *` ≈ 1:08 AM; daily `59 23 * * *`). The
  live cron in the scheduled tasks is authoritative; the doc comments are stale.
- `claude-journal-weekly` fires at the Sunday→Monday boundary (`59 23 * * 0`,
  Sunday 23:59) — essentially the same moment as Sunday's `claude-journal-daily`
  run (`59 23 * * *`). Because the weekly rollup reads Sunday's daily note, there
  is a potential race where the weekly rollup could run before Sunday's daily
  note is finished, causing it to miss the last day of the week. If weekly
  rollups ever look like they're dropping Sundays, this timing overlap is the
  likely cause.
