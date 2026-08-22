#!/usr/bin/env bash
# bootstrap.sh — seed a freshly created worktree from its main checkout.
#
# Invoked by herdr on the worktree.created event. The event payload
# (HERDR_PLUGIN_EVENT_JSON) carries both sides we need:
#
#   .data.worktree.path                    -> the new worktree (destination)
#   .data.workspace.worktree.repo_root     -> the main checkout (source)
#
# Herdr's event envelope has a `data` wrapper. The unwrapped paths remain as
# fallbacks for older/dev payload shapes.
#
# Everything is best-effort and non-fatal: a hook failure must never make the
# worktree look broken. Diagnostics go to $HERDR_PLUGIN_STATE_DIR/log.

set -uo pipefail

state="${HERDR_PLUGIN_STATE_DIR:-/tmp/herdr-worktree-bootstrap}"
config="${HERDR_PLUGIN_CONFIG_DIR:-}"
mkdir -p "$state"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$state/log"; }

json="${HERDR_PLUGIN_EVENT_JSON:-}"
if [ -z "$json" ] || ! command -v jq >/dev/null 2>&1; then
  log "skip: need HERDR_PLUGIN_EVENT_JSON and jq"
  exit 0
fi
printf '%s\n' "$json" > "$state/last-event.json"

dest="$(jq -r '.data.worktree.path // .worktree.path // empty' <<<"$json")"
src="$(jq -r '.data.workspace.worktree.repo_root // .workspace.worktree.repo_root // empty' <<<"$json")"
branch="$(jq -r '.data.worktree.branch // .worktree.branch // "?"' <<<"$json")"

if [ -z "$dest" ]; then
  log "skip: no worktree path in payload"
  exit 0
fi
# Fall back to the workspace's own checkout path, then to git itself.
[ -n "$src" ] || src="$(jq -r '.data.workspace.worktree.checkout_path // .workspace.worktree.checkout_path // empty' <<<"$json")"
if [ -z "$src" ] && git -C "$dest" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  common="$(git -C "$dest" rev-parse --path-format=absolute --git-common-dir)"
  src="$(dirname "$common")"
fi
if [ -z "$src" ] || [ ! -d "$src" ] || [ "$src" = "$dest" ]; then
  log "skip: no usable source for $dest"
  exit 0
fi

# Defaults; a config file in HERDR_PLUGIN_CONFIG_DIR overrides them.
files=".env .env.local .env.*.local"
dirs="node_modules"
mode="hardlink"   # hardlink | copy | skip
if [ -n "$config" ] && [ -f "$config/bootstrap.conf" ]; then
  # shellcheck disable=SC1091
  . "$config/bootstrap.conf"
fi

copied=0; skipped=0
note() { log "[$branch] $*"; }

for f in $files; do
  # Glob may not match anything; test the literal too so ".env" always works.
  for path in "$src"/$f "$src/$f"; do
    [ -f "$path" ] || continue
    name="$(basename "$path")"
    if [ -e "$dest/$name" ]; then
      note "keep existing $name"
      skipped=$((skipped + 1))
    else
      cp "$path" "$dest/$name" && note "copied $name" || note "FAILED to copy $name"
      copied=$((copied + 1))
    fi
    break  # first match per pattern is enough
  done
done

case "$mode" in
  skip) note "dirs mode=skip, left $dirs alone" ;;
  copy|hardlink)
    for d in $dirs; do
      for path in "$src"/$d "$src/$d"; do
        [ -d "$path" ] || continue
        name="$(basename "$path")"
        if [ -e "$dest/$name" ]; then
          note "keep existing $name/"
          skipped=$((skipped + 1))
        elif [ "$mode" = hardlink ]; then
          cp -al "$path" "$dest/$name" \
            && note "hardlinked $name/" || note "FAILED to hardlink $name/ (try mode=copy)"
          copied=$((copied + 1))
        else
          cp -R "$path" "$dest/$name" \
            && note "copied $name/" || note "FAILED to copy $name/"
          copied=$((copied + 1))
        fi
        break
      done
    done
    ;;
esac

note "done: src=$src dest=$dest copied=$copied kept=$skipped"
