# How it works (in depth)

## The problem

Claude Code writes a full transcript of every session to disk as JSON Lines
(`.jsonl`), one event per line — your prompts, the assistant's replies, tool
calls, timestamps, the working directory, and Git branch. These live under
Claude Code's config directory (e.g. `~/.claude/projects/<encoded-cwd>/<id>.jsonl`).

That directory is treated as protected by some agent sandboxes, and the project
subfolders use a mangled encoding of the working-directory path. So rather than
reading from there directly, we mirror the transcript out to a plain folder.

## The exporter hook

`exporter/export-session.js` is registered as a Claude Code **hook**. Claude
Code runs it and pipes a small JSON object to it on stdin:

```json
{
  "session_id": "abc123",
  "transcript_path": "/home/you/.claude/projects/-home-you-proj/abc123.jsonl",
  "cwd": "/home/you/proj",
  "hook_event_name": "Stop"
}
```

The script reads `transcript_path` and copies that file into the sessions
folder as `YYYY-MM-DD__<sessionId>.jsonl`, plus a `.cwd.txt` sidecar naming the
project. It always exits 0 so it can never disrupt your session.

### Why both `Stop` and `SessionEnd`?

- **`Stop`** fires every time the assistant finishes responding. Mirroring here
  keeps the copy fresh throughout the session — so even if you just close the
  terminal, everything up to the last response is already saved.
- **`SessionEnd`** fires on a clean exit (`/exit`, logout). It's a final
  backstop.

Copying the same file repeatedly is cheap and idempotent — later runs just
overwrite that day's copy for the session.

## The summarizer

A scheduled agent reads the day's mirrored transcripts and Git history and
writes the note. Keeping the summary step separate from capture means you can
swap in any runner (a Claude scheduled task, `claude -p` from cron, etc.) without
touching the hook.

The `BACKEND` setting in `journal.config` controls where the daily summary goes:

- **`obsidian`** (default) — writes a Markdown daily note into the vault
  (`Daily/YYYY-MM-DD.md`) using `scheduler/nightly-journal-prompt.md`. The
  weekly, monthly, and per-project rollups then parse those daily notes.
- **`onenote`** — publishes an HTML page to a OneNote notebook using
  `scheduler/nightly-journal-onenote-prompt.md` and the Graph API publisher.
- **`both`** — runs both prompts, producing a vault note and a OneNote page.

## Publishing to OneNote

OneNote isn't files on disk — it's a Notebook > Section > Page tree reached
through the Microsoft Graph API. `onenote/Publish-JournalToOneNote.ps1` does the
Graph work:

1. Find-or-create the notebook (default **"Claude Journal"**).
2. Find-or-create a **month section** named `yyyy-MM` (e.g. `2026-06`).
3. Find a **page titled `yyyy-MM-dd`** for the day.
   - Absent: `POST` a new page (HTML body).
   - Present: `PATCH`-replace the page body, so re-running the same day never
     duplicates the page.

The summarizer hands the publisher only the page **body** as HTML (the five
sections); the publisher wraps it in the page document and sets the title and
date heading. OneNote pages are HTML, so to-dos use OneNote's checkbox tag
(`<p data-tag="to-do">...</p>`) rather than Markdown `- [ ]`. See
`onenote/page-body-example.html` for the exact shape.

### Authentication: why delegated, not app-only

Microsoft **retired app-only (certificate / client-credentials) access to the
OneNote API on March 31 2025** — the endpoint now returns `40001 Unauthorized`
for app-only tokens and accepts only **delegated** (app + user) tokens. So this
tool cannot run from a pure background service identity; it needs a user.

The journal handles this with a refresh-token flow (`onenote/OneNoteAuth.ps1`):

- `Initialize-OneNoteAuth.ps1` runs the OAuth **device-code** flow once. You
  sign in and consent delegated `Notes.ReadWrite`; the identity platform returns
  a refresh token, which is stored **DPAPI-encrypted** (CurrentUser scope) at
  `%LOCALAPPDATA%\OneNoteClaudeJournal\onenote-refresh.dat`.
- On each run, `Get-OneNoteAccessToken` exchanges that refresh token for a fresh
  access token (no prompt) and re-stores the rotated refresh token it gets back.
  As long as the job runs within the refresh-token lifetime (~90 days) it stays
  alive indefinitely.
- The client is Microsoft's first-party **Graph Command Line Tools** public
  client — present in every tenant, so **no app registration or secret is
  needed**.

The refresh token is encrypted at rest and readable only by the same user on the
same machine. It is stored outside the repo and never synced.

## Git push tracking

A commit counts as "pushed" if it is contained in any remote-tracking branch
(`git branch -r --contains <sha>`). The scan runs per repo and lists each commit
once, so pushes are never double-counted — regardless of whether the work came
from Claude Code, another tool, or manual commits.

## Time zones

The mirror names files by the **local** date at the moment the hook runs. The
summarizer should compute "today" in your local timezone too (set `TZ`), since
many schedulers and sandboxes run with a UTC clock. Running the summary at 23:59
local keeps each note aligned to the day it covers.
