#!/usr/bin/env bash
# Lists today's commits across all git repos under a root, marking each as
# pushed (contained in a remote-tracking branch) or local-only.
#
# Usage:  TZ="America/New_York" ./scan-git-pushes.sh /path/to/repos/root
#
# Output lines look like:  <repo> [pushed] <shorthash> <subject>
set -euo pipefail

ROOT="${1:-.}"
D="$(date +%Y-%m-%d)"

while IFS= read -r g; do
  r="$(dirname "$g")"
  name="$(basename "$r")"
  # --all: walk every branch, not just the checked-out one — otherwise commits
  # made on a feature branch disappear from the scan after switching back.
  commits="$(git -C "$r" log --all --since="$D 00:00:00" --until="$D 23:59:59" \
              --pretty='%H|%h|%s' 2>/dev/null || true)"
  [ -z "$commits" ] && continue
  while IFS='|' read -r full short subj; do
    [ -z "$full" ] && continue
    if git -C "$r" branch -r --contains "$full" 2>/dev/null | grep -q .; then
      status="pushed"
    else
      status="local-only"
    fi
    echo "$name [$status] $short $subj"
  done <<< "$commits"
done < <(find "$ROOT" -maxdepth 3 -type d -name .git 2>/dev/null)
