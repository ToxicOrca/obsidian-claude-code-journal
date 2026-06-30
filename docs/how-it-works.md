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
