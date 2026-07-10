#!/usr/bin/env node
/*
 * obsidian-claude-code-journal — session exporter
 * --------------------------------------------------
 * A Claude Code hook that mirrors the current session's transcript into a
 * plain folder, so a downstream summarizer (e.g. a scheduled task) can read it
 * and write a daily journal note in Obsidian.
 *
 * Claude Code pipes a JSON object to this script on stdin. We only need
 * `transcript_path` (the .jsonl for the active session) and optionally
 * `session_id` and `cwd`.
 *
 * Wire it to BOTH the `Stop` and `SessionEnd` hooks. `Stop` fires after every
 * assistant response, so the mirror stays current and you never have to exit
 * cleanly; `SessionEnd` catches the final state. See hooks/settings.example.json.
 *
 * Output location (first match wins):
 *   1. $CLAUDE_JOURNAL_SESSIONS_DIR  (recommended — set it to an absolute path)
 *   2. <this repo>/sessions          (default; git-ignored)
 *
 * This script NEVER throws to the caller and always exits 0 — a logging hook
 * must not be able to disrupt Claude Code.
 */
const fs = require("fs");
const path = require("path");

function sessionsDir() {
  if (process.env.CLAUDE_JOURNAL_SESSIONS_DIR) {
    return process.env.CLAUDE_JOURNAL_SESSIONS_DIR;
  }
  // Default: a `sessions` folder at the repo root (one level up from /exporter).
  return path.join(__dirname, "..", "sessions");
}

function fmtLocalDate(d) {
  // Formats a Date in the machine's local timezone. To pin a timezone, set TZ
  // in the environment that runs the hook.
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function sessionStartDate(src) {
  // Date the mirror file by the session's FIRST entry timestamp — not the
  // copy time. This keeps one stable filename for a session that runs past
  // midnight, instead of creating a second next-day copy whose full contents
  // would be re-summarized (double-counted) by the next day's journal run.
  // Falls back to "now" if no timestamp can be found.
  try {
    const fd = fs.openSync(src, "r");
    const buf = Buffer.alloc(65536);
    const n = fs.readSync(fd, buf, 0, buf.length, 0);
    fs.closeSync(fd);
    for (const line of buf.toString("utf8", 0, n).split("\n")) {
      if (!line.trim()) continue;
      let obj;
      try { obj = JSON.parse(line); } catch { continue; }
      if (obj && obj.timestamp) {
        const d = new Date(obj.timestamp);
        if (!isNaN(d)) return fmtLocalDate(d);
      }
    }
  } catch {
    // fall through
  }
  return fmtLocalDate(new Date());
}

function readStdin() {
  try {
    return fs.readFileSync(0, "utf8");
  } catch {
    return "";
  }
}

try {
  const raw = readStdin();
  const data = raw ? JSON.parse(raw) : {};
  const src = data.transcript_path;
  if (src && fs.existsSync(src)) {
    const outDir = sessionsDir();
    fs.mkdirSync(outDir, { recursive: true });
    // Sanitize FIRST, then fall back — so an id made entirely of invalid
    // characters still yields a usable filename instead of `<date>__.jsonl`.
    let sid = (data.session_id || path.basename(src, ".jsonl") || "")
      .toString()
      .replace(/[^A-Za-z0-9_-]/g, "");
    if (!sid) sid = "session";
    const dest = path.join(outDir, `${sessionStartDate(src)}__${sid}.jsonl`);
    fs.copyFileSync(src, dest);
    // Sidecar with the working directory, so the summarizer can name the project.
    if (data.cwd) {
      fs.writeFileSync(dest.replace(/\.jsonl$/, ".cwd.txt"), String(data.cwd), "utf8");
    }
  }
} catch {
  // swallow — never block the session
}
process.exit(0);
