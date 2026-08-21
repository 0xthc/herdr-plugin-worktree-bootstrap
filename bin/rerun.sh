#!/usr/bin/env bash
# rerun.sh — the herdr-plugin-worktree-bootstrap.rerun action. Re-seeds the
# focused workspace's worktree by synthesizing the same payload the
# worktree.created event carries, then reusing bootstrap.sh.
#
# The action runs with HERDR_PLUGIN_CONTEXT_JSON describing the current
# workspace. The workspace record from `herdr api snapshot` carries the same
# worktree provenance the event payload does.

set -uo pipefail

ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"
if [ -z "$ctx" ] || ! command -v jq >/dev/null 2>&1; then
  echo "worktree-bootstrap: need context and jq" >&2
  exit 1
fi

ws="$(jq -r '.workspace_id // empty' <<<"$ctx")"
if [ -z "$ws" ]; then
  echo "worktree-bootstrap: no workspace in context" >&2
  exit 1
fi

record="$("${HERDR_BIN_PATH:-herdr}" api snapshot 2>/dev/null)"
payload="$(jq --arg id "$ws" '
  .result.snapshot.workspaces[]? | select(.workspace_id == $id)
  | { workspace: . }' <<<"$record" 2>/dev/null)"

if [ -z "$payload" ]; then
  echo "worktree-bootstrap: could not resolve worktree for workspace $ws" >&2
  exit 1
fi

HERDR_PLUGIN_EVENT_JSON="$payload" bash "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"
echo "worktree-bootstrap: re-ran for workspace $ws (see plugin log)"
