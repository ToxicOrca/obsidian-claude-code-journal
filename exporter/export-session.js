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

function localDate() {
  // Uses the machine's local timezone. To pin a timezone, set TZ in the
  // environment that runs the hook.
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
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
    const sid = (data.session_id || path.basename(src, ".jsonl") || "session")
      .toString()
      .replace(/[^A-Za-z0-9_-]/g, "");
    const dest = path.join(outDir, `${localDate()}__${sid}.jsonl`);
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
