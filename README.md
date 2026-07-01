<div align="center">

# obsidian-claude-code-journal

**Automatically keep a daily Obsidian journal of everything you build with Claude Code.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Made for Claude Code](https://img.shields.io/badge/made%20for-Claude%20Code-blueviolet)](https://claude.com/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#contributing)

</div>

---

Each night a summarizer reads that day's Claude Code sessions and your Git
pushes, then writes a tidy dated note into your Obsidian vault — without you
lifting a finger.

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

Because notes are plain Markdown, any sync tool (Syncthing, Obsidian Sync, Git,
Dropbox) carries them to your phone and other machines.

---

## Table of Contents

- [Architecture](#architecture)
- [Features](#features)
- [Quick Start](#quick-start)
- [Setup (detailed)](#setup-detailed)
- [Configuration Reference](#configuration-reference)
- [Privacy](#privacy)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
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
              ▼
       ┌──────────────────────┐
       │  Obsidian vault      │
       │  Daily/YYYY-MM-DD.md │
       │  Weekly/YYYY-MM-DD.md│
       │  Monthly/YYYY-MM.md  │
       │  Home.md (index)     │
       └──────────────────────┘
```

## Features

- **Zero-effort journaling** — notes appear automatically; you never have to
  write them.
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
- **Weekly & monthly rollups** — scheduled prompts that aggregate daily notes
  into weekly highlights and monthly summaries with an emoji activity heatmap.
- **Obsidian-native** — ships with daily, weekly, and monthly note templates
  and a `Home.md` index that updates itself.
- **Sync-friendly** — plain Markdown files work with Syncthing, Obsidian Sync,
  Git, Dropbox, or anything else.
- **Privacy-first** — raw transcripts are git-ignored and never leave your
  machine; only the summary lands in your vault.

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/<your-user>/obsidian-claude-code-journal.git

# 2. Create your local config
cp journal.config.example journal.config
#    Edit journal.config with your real paths and timezone.

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

## Setup (detailed)

### 1. Clone

```bash
git clone https://github.com/<your-user>/obsidian-claude-code-journal.git
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

### 3. Set up the Obsidian vault

Copy the files in [`obsidian-template/`](obsidian-template/) into a vault:
`Daily Note Template.md` into a `Templates/` folder and `Home.md` at the root.
Enable the core **Daily notes** and **Templates** plugins.

### 4. Create your local config

```bash
cp journal.config.example journal.config
```

Edit `journal.config` with your real paths and timezone. This file is
git-ignored — it stays on your machine. The prompt files read these values at
runtime through `{{PLACEHOLDERS}}`, so **what you run == what you push**.

### 5. Schedule the summarizers

Each scheduled task is a thin wrapper: it reads `journal.config`, substitutes
the `{{PLACEHOLDER}}` tokens in the corresponding prompt file, and runs the
result via `claude -p`. You never edit the prompt files for local config — just
update `journal.config`.

| Task | Prompt file | Schedule |
|------|-------------|----------|
| Daily | `scheduler/nightly-journal-prompt.md` | 23:59 daily |
| Weekly | `scheduler/weekly-rollup-prompt.md` | Mon 00:15 |
| Monthly | `scheduler/monthly-rollup-prompt.md` | 1st of month 00:30 |

### Rollups

**Weekly** notes summarize Mon–Sun into `Weekly/<Monday-date>.md` with
highlights, projects, GitHub activity, decisions, and carried-forward to-dos.

**Monthly** notes summarize an entire calendar month into `Monthly/YYYY-MM.md`
and include an emoji activity heatmap (⬜ none · 🟩 light · 🟦 medium · 🟪
heavy) plus stats.

Both roll-ups read from the daily notes already in your vault — they don't
re-scan transcripts or git repos.

## Configuration Reference

| What | Where | Default |
|------|-------|---------|
| All paths & timezone | `journal.config` (repo root) | see `.example` |
| Transcript mirror dir | `CLAUDE_JOURNAL_SESSIONS_DIR` env var | `<repo>/sessions/` |
| Note locations | `Daily/`, `Weekly/`, `Monthly/` in vault | — |

## Privacy

Mirrored transcripts (`sessions/*.jsonl`) contain **your** conversations and
code. They are git-ignored by default — **never commit them**. The journal notes
themselves live in your Obsidian vault, not in this repo.

## File structure

```
obsidian-claude-code-journal/
├── journal.config.example   # Template config — copy to journal.config
├── journal.config            # Your local config (git-ignored)
├── exporter/
│   └── export-session.js     # Hook: mirrors transcripts to sessions/
├── hooks/
│   └── settings.example.json # Claude Code hook registration
├── scheduler/
│   ├── nightly-journal-prompt.md   # Daily summarizer prompt
│   ├── weekly-rollup-prompt.md     # Weekly rollup prompt
│   ├── monthly-rollup-prompt.md    # Monthly rollup prompt
│   └── scan-git-pushes.sh         # Helper: scan repos for today's commits
├── obsidian-template/
│   ├── Daily Note Template.md
│   ├── Weekly Note Template.md
│   ├── Monthly Note Template.md
│   └── Home.md
├── docs/
│   └── how-it-works.md
└── sessions/                 # Mirrored transcripts (git-ignored)
```

## Roadmap

- [ ] `SessionEnd`-only mode (skip per-response mirroring for lower overhead)
- [ ] Native summarizer that doesn't need an agent
- [ ] Kanban-board output (group to-dos across days)
- [ ] Support for other note apps (Notion, Logseq, Bear)

## Contributing

Issues and PRs welcome! If you have an idea — session filters, alternative
output formats, new note-app targets — open an issue or send a PR.

## License

MIT — see [LICENSE](LICENSE).
