<div align="center">

# onenote-claude-code-journal

**Automatically keep a daily OneNote journal of everything you build with Claude Code.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Made for Claude Code](https://img.shields.io/badge/made%20for-Claude%20Code-blueviolet)](https://claude.com/claude-code)

</div>

---

Each night a summarizer reads that day's Claude Code sessions and your Git
pushes, then publishes a tidy dated page into a **OneNote** notebook — without
you lifting a finger. The page lands in a notebook (default "Claude Journal"),
in a section for the current month, titled with the date:

> **# Friday, June 30, 2026**
>
> **🛠️ Tasks & projects worked on**
> - **my-api** — Added rate-limiting middleware and tests.
> - **notes-app** — Debugged the sync conflict on startup.
>
> **🐙 GitHub / GitLab**
> - **my-api** — Add rate-limiting middleware. (commit `a1b2c3d`, pushed)
>
> **💡 Key decisions & takeaways**
> - Chose a token-bucket limiter over fixed-window to smooth bursts.
>
> **✅ To-dos / follow-ups**
> - ☐ Wire the limiter config to env vars.

Because the page lives in OneNote, it syncs to every device where you're signed
in — phone, tablet, other machines — automatically.

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
│  ➜ sessions/*.jsonl  │     │  ➜ scan-git-pushes.sh │
└──────┬───────────────┘     └──────┬───────────────┘
       │                            │
       └──────────┬─────────────────┘
                  ▼
       ┌──────────────────────┐
       │  Nightly summarizer  │
       │  (scheduler +        │
       │   claude -p)         │
       └──────┬───────────────┘
              ▼
       ┌──────────────────────────────┐
       │  Publish-JournalToOneNote.ps1│
       │  (Microsoft Graph, delegated)│
       └──────┬───────────────────────┘
              ▼
       ┌──────────────────────────────┐
       │  OneNote                     │
       │  notebook                    │
       │   └ yyyy-MM section          │
       │      └ yyyy-MM-dd page       │
       └──────────────────────────────┘
```

## How the pieces map

| Stage | File | What it does |
|-------|------|--------------|
| Capture | `exporter/export-session.js` | Claude Code hook; mirrors each session transcript to `sessions/`. |
| Git scan | `scheduler/scan-git-pushes.sh` | Lists today's commits per repo, marked pushed / local-only. |
| Authorize | `onenote/Initialize-OneNoteAuth.ps1` | One-time device-code sign-in; stores a refresh token (`OneNoteAuth.ps1` reuses it silently). |
| Summarize | `scheduler/nightly-journal-prompt.md` | The `claude -p` prompt: read sessions + git, compose the day's HTML, call the publisher. |
| Publish | `onenote/Publish-JournalToOneNote.ps1` | Delegated Graph: find-or-create notebook → month section → daily page; create or idempotently update. |
| Schedule | `scheduler/Register-JournalTask.ps1` | Registers the nightly Windows Task Scheduler job. |

## Requirements

- **Windows** with **PowerShell 7+** (for the publisher and scheduler script).
- The **Microsoft.Graph** PowerShell module (`Install-Module Microsoft.Graph`).
- **Node.js** (for the capture hook).
- A **Microsoft 365 / work-school or personal Microsoft account** with OneNote.
  No Azure app registration is required — the tool uses Microsoft's public Graph
  CLI client for a delegated sign-in.

## Setup

### 1. Configure (optional)

Copy `config.example.json` to `config.json` and set your `tenantId` if you want
to pin sign-in to a specific tenant (default `common` works for any account).
You can also set a custom `notebookName`.

### 2. Authorize OneNote (one-time sign-in)

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

### 3. Register the capture hook

Merge the hooks from [`hooks/settings.example.json`](hooks/settings.example.json)
into your Claude Code settings (`~/.claude/settings.json`; on Windows
`C:\Users\<you>\.claude\settings.json`), pointing the `command` at the absolute
path of `exporter/export-session.js`. It's wired to both `Stop` and `SessionEnd`,
mirroring transcripts to `sessions/`. To send transcripts elsewhere, set
`CLAUDE_JOURNAL_SESSIONS_DIR` to an absolute path in the hook's environment.

### 4. Schedule the nightly run

Fill in the `{{PLACEHOLDERS}}` in
[`scheduler/nightly-journal-prompt.md`](scheduler/nightly-journal-prompt.md)
(repo path, sessions dir, repos path, timezone, notebook name). Then register
the daily 23:59 task:

```powershell
pwsh .\scheduler\Register-JournalTask.ps1
```

It starts as soon as possible after a missed start, so a sleeping/off PC just
runs at next wake. Change the time with `-Time "22:30"`; remove with
`-Unregister`. (Not on Windows? Run `claude -p "$(cat scheduler/nightly-journal-prompt.md)"`
from cron at 23:59 local instead.)

### 5. Test it

```powershell
# Create today's page immediately from the example body
pwsh .\onenote\Publish-JournalToOneNote.ps1 -BodyHtmlPath .\onenote\page-body-example.html
# ...or trigger the full scheduled run:
Start-ScheduledTask -TaskName "Claude OneNote Journal"
```

The first run creates the notebook and the current month's section automatically.

> **First-time visibility:** a notebook created via the Graph API does **not**
> auto-appear in the OneNote app or OneNote.com right away. Open it once from
> **OneDrive → Documents → Notebooks → (notebook)** (or the page URL the
> publisher prints). After that it stays in your notebook list and the nightly
> page updates show up on their own.

## Configuration Reference

| What | Where | Default |
|------|-------|---------|
| Transcript mirror dir | `CLAUDE_JOURNAL_SESSIONS_DIR` env var | `<repo>/sessions/` |
| Sign-in tenant | `tenantId` in `config.json` | `common` |
| Notebook name | `notebookName` in `config.json` / `-NotebookName` | `Claude Journal` |
| Section naming | (fixed) one per month | `yyyy-MM` |
| Page title | (fixed) ISO date | `yyyy-MM-dd` |
| Refresh-token store | DPAPI file (per-user) | `%LOCALAPPDATA%\OneNoteClaudeJournal\onenote-refresh.dat` |
| Run time | `-Time` on `Register-JournalTask.ps1` | `23:59` |

## Privacy

Mirrored transcripts (`sessions/*.jsonl`) contain **your** conversations and
code. They are git-ignored by default — **never commit them**. The refresh token
is encrypted at rest and stored outside the repo. Only the daily summary is
published to OneNote.

## License

MIT — see [LICENSE](LICENSE).
