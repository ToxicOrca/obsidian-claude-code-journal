<div align="center">

# obsidian-claude-code-journal

**Automatically keep a daily journal of everything you build with Claude Code — in Obsidian, OneNote, or both.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Made for Claude Code](https://img.shields.io/badge/made%20for-Claude%20Code-blueviolet)](https://claude.com/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#contributing)

</div>

---

Each night a summarizer reads that day's Claude Code sessions and your Git
pushes, then writes a tidy dated note — without you lifting a finger. You choose
where it lands:

- **Obsidian** (default) — plain Markdown files in your vault, with weekly/monthly
  rollups, per-project pages, auto-tagging, and graph links.
- **OneNote** — HTML pages published to a OneNote notebook via Microsoft Graph,
  organized by month, with native OneNote checkboxes.
- **Both** — run both backends on every nightly run.

```markdown
# Monday, June 29, 2026

## Tasks & projects worked on
- **my-api** — Added rate limiting middleware and tests.
- **notes-app** — Debugged the sync conflict on startup.

## GitHub
- **my-api** — Add rate limiting middleware. (commit `a1b2c3d`, pushed)

## Key decisions & takeaways
- Chose a token-bucket limiter over fixed-window to smooth bursts.

## To-dos / follow-ups
- [ ] Wire the limiter config to env vars.
```

Because Obsidian notes are plain Markdown, any sync tool (Syncthing, Obsidian
Sync, Git, Dropbox) carries them to your phone and other machines. OneNote syncs
automatically to every device where you're signed in.

---

## Table of Contents

- [Architecture](#architecture)
- [Features](#features)
- [Quick Start (Obsidian)](#quick-start-obsidian)
- [Quick Start (OneNote)](#quick-start-onenote)
- [Setup (detailed)](#setup-detailed)
- [Configuration Reference](#configuration-reference)
- [Privacy](#privacy)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [Credits](#credits)
- [License](#license)

---

## Architecture

```
┌──────────────────────┐
│    Claude Code       │
│   (your sessions)    │
└──────┬───────────────┘
       │ Stop / SessionEnd hook
       ▼
┌──────────────────────┐     ┌──────────────────────┐
│  exporter/           │     │  Git repos            │
│  export-session.js   │     │  (today's commits)    │
│                      │     │                       │
│  ➜ sessions/*.jsonl  │     │  ➜ scan-git-pushes.sh │
└──────┬───────────────┘     └──────┬───────────────┘
       │                            │
       └──────────┬─────────────────┘
                  ▼
       ┌──────────────────────┐
       │  Scheduled agents    │
       │  (read prompt files  │
       │   + journal.config)  │
       └──────┬───────────────┘
              │
     ┌────────┴────────┐
     ▼                 ▼
┌─────────────┐  ┌──────────────────────────────┐
│  Obsidian   │  │  Publish-JournalToOneNote.ps1│
│  vault      │  │  (Microsoft Graph, delegated)│
│  Daily/     │  └──────┬───────────────────────┘
│  Weekly/    │         ▼
│  Monthly/   │  ┌──────────────────────────────┐
│  Projects/  │  │  OneNote notebook            │
│  Home.md    │  │   └ yyyy-MM section          │
└─────────────┘  │      └ yyyy-MM-dd page       │
                 └──────────────────────────────┘
```

## Features

- **Zero-effort journaling** — notes appear automatically; you never have to
  write them.
- **Dual-backend support** — publish to Obsidian, OneNote, or both. Set
  `BACKEND` in `journal.config` and go.
- **Session export hook** — mirrors Claude Code transcripts to a plain folder
  in real-time (fires on every response, not just clean exits).
- **Git push scanner** — finds today's pushed commits across all your repos
  and groups them by project.
- **Daily summarizer** — an agent prompt that synthesizes sessions + pushes
  into a structured daily note with tasks, files changed, decisions, and
  to-dos. *(Cowork bonus: when run inside Anthropic's Cowork app, the daily
  summarizer can also capture desktop Claude app conversations. This activates
  automatically in that environment and is safely ignored everywhere else — no
  configuration, and not required for the core workflow.)*
- **Weekly & monthly rollups** *(Obsidian only)* — scheduled prompts that
  aggregate daily notes into weekly highlights and monthly summaries with an
  emoji activity heatmap.
- **Auto-tagging** *(Obsidian only)* — daily notes are tagged with
  `project/<slug>` per repo touched and `topic/*` tags from a controlled
  vocabulary (feature, bug-fix, refactor, docs, test, devops, design). Inline
  `#project/<slug>` references in project bullets make the Obsidian graph
  light up.
- **Streaks & stats** *(Obsidian only)* — every daily note carries
  Dataview-queryable numeric frontmatter (`sessions`, `commits`, `tokens`),
  and `Home.md` shows your current and longest daily streak, updated nightly.
- **Year in Review** *(Obsidian only)* — each January 1st, a `Yearly/YYYY.md`
  note with a full-year emoji heatmap, top projects, topic mix, and
  by-the-numbers totals for the year.
- **Per-project pages** *(Obsidian only)* — a scheduled prompt rebuilds
  `Projects/<slug>.md` for every project seen in your daily notes:
  reverse-chronological timeline, commit history, stats, and open to-dos — all
  cross-linked with backlinks.
- **OneNote publishing** — daily pages published via Microsoft Graph with
  native OneNote checkboxes for to-dos. Organized by month section,
  idempotent (re-runs update in place, never duplicate).
- **Sync-friendly** — Obsidian: plain Markdown works with Syncthing, Obsidian
  Sync, Git, Dropbox. OneNote: syncs automatically to all signed-in devices.
- **Privacy-first** — raw transcripts are git-ignored and never leave your
  machine; only the summary lands in your vault or notebook.

## Quick Start (Obsidian)

```bash
# 1. Clone the repo
git clone https://github.com/ToxicOrca/obsidian-claude-code-journal.git

# 2. Create your local config
cp journal.config.example journal.config
#    Edit journal.config — set VAULT_PATH, REPOS_PATH, SESSIONS_DIR, TIMEZONE.
#    Leave BACKEND=obsidian (the default).

# 3. Register the exporter hook
#    Add the hooks from hooks/settings.example.json into
#    ~/.claude/settings.json, replacing the path with the
#    absolute path to exporter/export-session.js on your machine.

# 4. Set up the vault
#    Copy obsidian-template/ files into your Obsidian vault.
#    Enable the core "Daily notes" and "Templates" plugins.

# 5. Schedule the summarizers
#    Each scheduled task is a thin wrapper that reads journal.config
#    and a prompt file from scheduler/, substitutes placeholders,
#    and runs the prompt. See "Scheduling" below.
```

## Quick Start (OneNote)

```powershell
# 1. Clone the repo
git clone https://github.com/ToxicOrca/obsidian-claude-code-journal.git

# 2. Create your local config
cp journal.config.example journal.config
#    Edit journal.config — set BACKEND=onenote, REPO_PATH, REPOS_PATH,
#    SESSIONS_DIR, TIMEZONE, and optionally NOTEBOOK_NAME.

# 3. (Optional) Configure tenant/notebook name
cp config.example.json config.json
#    Edit config.json if you need to pin a specific Azure AD tenant
#    or change the notebook name (default: "Claude Journal").

# 4. Register the exporter hook (same as Obsidian — captures transcripts)
#    Add the hooks from hooks/settings.example.json into
#    ~/.claude/settings.json.

# 5. Authorize OneNote (one-time interactive sign-in)
pwsh .\onenote\Initialize-OneNoteAuth.ps1

# 6. Schedule the nightly run
pwsh .\scheduler\Register-JournalTask.ps1
```

> **Requirements for OneNote:** Windows with PowerShell 7+, the
> `Microsoft.Graph` PowerShell module (`Install-Module Microsoft.Graph`),
> Node.js (for the capture hook), and a Microsoft 365 / work-school or personal
> Microsoft account with OneNote. No Azure app registration is required.

## Setup (detailed)

### 1. Clone

```bash
git clone https://github.com/ToxicOrca/obsidian-claude-code-journal.git
```

### 2. Add the export hook to Claude Code

Open your Claude Code settings at `~/.claude/settings.json` and merge in the
hooks from [`hooks/settings.example.json`](hooks/settings.example.json). Point
the `command` at the absolute path of `exporter/export-session.js` on your
machine.

> **Merging:** if you already have a `hooks` block or existing `Stop` /
> `SessionEnd` hooks, add the node command as **another entry** in the existing
> `hooks` array — don't replace what's there.

The exporter is wired to both `Stop` (fires after every response) and
`SessionEnd`. `Stop` keeps the mirror continuously up to date, so you never need
to exit a session cleanly — closing the terminal is fine.

By default transcripts mirror to `<repo>/sessions/`. To send them elsewhere, set
`CLAUDE_JOURNAL_SESSIONS_DIR` to an absolute path in the hook's environment.

### 3. Create your local config

```bash
cp journal.config.example journal.config
```

Edit `journal.config` with your real paths and timezone. Set `BACKEND` to
`obsidian` (default), `onenote`, or `both`. This file is git-ignored — it stays
on your machine. The prompt files read these values at runtime through
`{{PLACEHOLDERS}}`, so **what you run == what you push**.

### 4a. Set up the Obsidian vault *(BACKEND=obsidian or both)*

Copy the files in [`obsidian-template/`](obsidian-template/) into a vault:
`Daily Note Template.md` into a `Templates/` folder and `Home.md` at the root.
Enable the core **Daily notes** and **Templates** plugins.

### 4b. Authorize OneNote *(BACKEND=onenote or both)*

> **Why interactive?** Microsoft retired **app-only** (certificate) access to the
> OneNote API on March 31 2025 — the endpoint only accepts **delegated**
> (app + user) tokens now. You sign in **once** and the publisher reuses a stored
> refresh token thereafter.

```powershell
pwsh .\onenote\Initialize-OneNoteAuth.ps1
```

Follow the device-code prompt (open the URL, enter the code, sign in). This
stores a DPAPI-encrypted refresh token at
`%LOCALAPPDATA%\OneNoteClaudeJournal\onenote-refresh.dat` and verifies access by
listing your notebooks. Re-run only if publishing later reports an
expired/revoked token (e.g. the job didn't run for >90 days).

Optionally, copy `config.example.json` to `config.json` to set a custom
`tenantId` or `notebookName` (defaults: `common` and `Claude Journal`).

> **First-time visibility:** a notebook created via the Graph API does **not**
> auto-appear in the OneNote app or OneNote.com right away. Open it once from
> **OneDrive > Documents > Notebooks > (notebook)** (or the page URL the
> publisher prints). After that it stays in your notebook list.

### 5. Schedule the summarizers

Each scheduled task is a thin wrapper: it reads `journal.config`, substitutes
the `{{PLACEHOLDER}}` tokens in the corresponding prompt file, and runs the
result via `claude -p`. You never edit the prompt files for local config — just
update `journal.config`.

**Obsidian scheduled tasks** (when `BACKEND=obsidian` or `both`):

| Task | Prompt file | Schedule |
|------|-------------|----------|
| Daily | `scheduler/nightly-journal-prompt.md` | 23:59 daily |
| Projects | `scheduler/project-pages-prompt.md` | 01:00 daily (after daily) |
| Weekly | `scheduler/weekly-rollup-prompt.md` | Mon 00:15 |
| Monthly | `scheduler/monthly-rollup-prompt.md` | 1st of month 00:30 |
| Yearly | `scheduler/yearly-review-prompt.md` | Jan 1 01:30 |

**OneNote scheduled task** (when `BACKEND=onenote` or `both`):

| Task | Prompt file | Schedule |
|------|-------------|----------|
| Daily (OneNote) | `scheduler/nightly-journal-onenote-prompt.md` | 23:59 daily |

On Windows, you can register the OneNote task with:

```powershell
pwsh .\scheduler\Register-JournalTask.ps1
```

It starts as soon as possible after a missed start, so a sleeping/off PC just
runs at next wake. Change the time with `-Time "22:30"`; remove with
`-Unregister`.

> **Note:** The weekly, monthly, and per-project rollups are **Obsidian-only** —
> they parse the daily Markdown notes in the vault. OneNote daily pages do not
> feed into rollups. If you use `BACKEND=both`, the rollups will work from the
> Obsidian daily notes as usual.

### Rollups *(Obsidian only)*

**Weekly** notes summarize Mon-Sun into `Weekly/<Monday-date>.md` with
highlights, projects, GitHub activity, decisions, and carried-forward to-dos.

**Monthly** notes summarize an entire calendar month into `Monthly/YYYY-MM.md`
and include an emoji activity heatmap (the squares: none, light, medium, heavy)
plus stats.

**Yearly** notes ("Year in Review") land in `Yearly/YYYY.md` each January 1st:
a full-year emoji heatmap, highlights, top projects, topic mix, and totals
(sessions, commits, tokens, longest streak).

All roll-ups read from the daily notes already in your vault — they don't
re-scan transcripts or git repos.

### Per-project pages *(Obsidian only)*

The project-pages prompt discovers every `project/<slug>` tag across your daily
notes and (re)builds `Projects/<slug>.md` for each one — a timeline, commit
history, stats, and open to-dos. It is fully idempotent: each run regenerates
from the daily notes rather than appending, so it's safe to run at any cadence.

### Auto-tagging *(Obsidian only)*

The daily summarizer automatically tags each note with `project/<slug>` for
every repo touched and `topic/*` tags from a controlled vocabulary. Inline
`#project/<slug>` references on each project bullet make the Obsidian graph
link daily notes to project pages.

### Testing OneNote

```powershell
# Create today's page immediately from the example body
pwsh .\onenote\Publish-JournalToOneNote.ps1 -BodyHtmlPath .\onenote\page-body-example.html

# ...or trigger the full scheduled run:
Start-ScheduledTask -TaskName "Claude OneNote Journal"
```

## Configuration Reference

| What | Where | Default |
|------|-------|---------|
| Backend selection | `BACKEND` in `journal.config` | `obsidian` |
| All paths & timezone | `journal.config` (repo root) | see `.example` |
| Transcript mirror dir | `CLAUDE_JOURNAL_SESSIONS_DIR` env var | `<repo>/sessions/` |
| Note locations (Obsidian) | `Daily/`, `Weekly/`, `Monthly/`, `Yearly/`, `Projects/` in vault | -- |
| Sign-in tenant (OneNote) | `tenantId` in `config.json` | `common` |
| Notebook name (OneNote) | `NOTEBOOK_NAME` in `journal.config` or `config.json` | `Claude Journal` |
| Section naming (OneNote) | (fixed) one per month | `yyyy-MM` |
| Page title (OneNote) | (fixed) ISO date | `yyyy-MM-dd` |
| Refresh-token store (OneNote) | DPAPI file (per-user) | `%LOCALAPPDATA%\OneNoteClaudeJournal\onenote-refresh.dat` |
| Run time (OneNote task) | `-Time` on `Register-JournalTask.ps1` | `23:59` |

## Privacy

Mirrored transcripts (`sessions/*.jsonl`) contain **your** conversations and
code. They are git-ignored by default — **never commit them**. The journal notes
themselves live in your Obsidian vault (or OneNote notebook), not in this repo.
The OneNote refresh token is encrypted at rest (DPAPI, CurrentUser scope) and
stored outside the repo.

## File structure

```
obsidian-claude-code-journal/
├── journal.config.example        # Template config — copy to journal.config
├── journal.config                 # Your local config (git-ignored)
├── config.example.json            # OneNote-specific config template
├── config.json                    # OneNote local config (git-ignored)
├── exporter/
│   └── export-session.js          # Hook: mirrors transcripts to sessions/
├── hooks/
│   └── settings.example.json      # Claude Code hook registration
├── scheduler/
│   ├── nightly-journal-prompt.md         # Daily summarizer prompt — Obsidian
│   ├── nightly-journal-onenote-prompt.md # Daily summarizer prompt — OneNote
│   ├── project-pages-prompt.md           # Per-project page builder (Obsidian)
│   ├── weekly-rollup-prompt.md           # Weekly rollup (Obsidian)
│   ├── monthly-rollup-prompt.md          # Monthly rollup (Obsidian)
│   ├── yearly-review-prompt.md           # Year in Review (Obsidian)
│   ├── scan-git-pushes.sh               # Helper: scan repos for today's commits
│   └── Register-JournalTask.ps1         # Windows Task Scheduler (OneNote)
├── onenote/
│   ├── Initialize-OneNoteAuth.ps1  # One-time device-code sign-in
│   ├── OneNoteAuth.ps1             # Shared auth helpers (token refresh)
│   ├── Publish-JournalToOneNote.ps1# Graph API publisher
│   └── page-body-example.html      # Example HTML body fragment
├── obsidian-template/
│   ├── Daily Note Template.md
│   ├── Weekly Note Template.md
│   ├── Monthly Note Template.md
│   ├── Yearly Note Template.md
│   ├── Project Page Template.md
│   └── Home.md
├── docs/
│   └── how-it-works.md
└── sessions/                      # Mirrored transcripts (git-ignored)
```

## Roadmap

- [ ] `SessionEnd`-only mode (skip per-response mirroring for lower overhead)
- [ ] Native summarizer that doesn't need an agent
- [ ] Kanban-board output (group to-dos across days)
- [ ] Weekly/monthly rollups for OneNote
- [x] ~~Support for other note apps (Notion, Logseq, Bear)~~ OneNote support added!
- [ ] Support for Notion, Logseq, Bear

## Contributing

Issues and PRs welcome! If you have an idea — session filters, alternative
output formats, new note-app targets — open an issue or send a PR.

## Credits

- **OneNote integration** contributed by
  [@Bartak-the-Dev](https://github.com/Bartak-the-Dev) — the full OneNote
  publishing pipeline (Graph API publisher, device-code auth, Windows Task
  Scheduler registration) was originally developed in
  [PR #1](https://github.com/ToxicOrca/obsidian-claude-code-journal/pull/1).

## License

MIT — see [LICENSE](LICENSE).
