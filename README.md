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
       │  Nightly summarizer  │
       │  (scheduled agent /  │
       │   cron + claude -p)  │
       └──────┬───────────────┘
              ▼
       ┌──────────────────────┐
       │  Obsidian vault      │
       │  Daily/YYYY-MM-DD.md │
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
- **Nightly summarizer** — an agent prompt that synthesizes sessions + pushes
  into a structured daily note with tasks, files changed, decisions, and
  to-dos.
- **Obsidian-native** — ships with a daily-note template and a `Home.md` index
  that updates itself.
- **Sync-friendly** — plain Markdown files work with Syncthing, Obsidian Sync,
  Git, Dropbox, or anything else.
- **Privacy-first** — raw transcripts are git-ignored and never leave your
  machine; only the summary lands in your vault.

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/<your-user>/obsidian-claude-code-journal.git

# 2. Register the exporter hook
#    Add the hooks from hooks/settings.example.json into
#    ~/.claude/settings.json, replacing the path with the
#    absolute path to exporter/export-session.js on your machine.

# 3. Set up the vault
#    Copy obsidian-template/ files into your Obsidian vault.
#    Enable the core "Daily notes" and "Templates" plugins.

# 4. Schedule the summarizer
#    Fill in the {{PLACEHOLDERS}} in scheduler/nightly-journal-prompt.md
#    and run it daily at 23:59 local time (e.g. as a Claude scheduled
#    task or via cron: claude -p "$(cat prompt.md)").
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

### 4. Schedule the summarizer

Take [`scheduler/nightly-journal-prompt.md`](scheduler/nightly-journal-prompt.md),
fill in the `{{PLACEHOLDERS}}` (vault path, repos path, sessions dir, timezone),
and run it once a day — schedule it for **23:59 local time** so each note covers
the day that's ending.

## Configuration Reference

| What | Where | Default |
|------|-------|---------|
| Transcript mirror dir | `CLAUDE_JOURNAL_SESSIONS_DIR` env var | `<repo>/sessions/` |
| Timezone | `TZ` in the summarizer's environment | machine local |
| Note location | `{{VAULT_PATH}}/Daily/` | — |

## Privacy

Mirrored transcripts (`sessions/*.jsonl`) contain **your** conversations and
code. They are git-ignored by default — **never commit them**. The journal notes
themselves live in your Obsidian vault, not in this repo.

## Roadmap

- [ ] `SessionEnd`-only mode (skip per-response mirroring for lower overhead)
- [ ] Native summarizer that doesn't need an agent
- [ ] Kanban-board output (group to-dos across days)
- [ ] Support for other note apps (Notion, Logseq, Bear)
- [ ] Weekly/monthly roll-up notes

## Contributing

Issues and PRs welcome! If you have an idea — session filters, alternative
output formats, new note-app targets — open an issue or send a PR.

## License

MIT — see [LICENSE](LICENSE).
