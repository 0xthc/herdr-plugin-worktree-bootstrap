# herdr-plugin-worktree-bootstrap

Seed new herdr worktrees with the files git does not carry: `.env` files,
`node_modules`, and other untracked local state.

A `worktree.created` event hook runs the moment a worktree workspace opens,
copies the configured files from the main checkout into it, and exits. The
worktree is usable immediately — no manual copying, no first-run failures
because an API key is missing.

## What it does

On every `herdr worktree create`:

- Copies `.env`, `.env.local`, and `.env.*.local` from the repo root.
- Hardlinks `node_modules` (`cp -al`): instant, near-zero extra disk, and safe
  in practice because package managers replace rather than edit files in place.
- Never overwrites anything already present in the destination.
- Logs every decision to `$HERDR_PLUGIN_STATE_DIR/log`.

## Actions

| Action | What it does |
| --- | --- |
| `herdr-plugin-worktree-bootstrap.rerun` | Re-seed the current workspace's worktree (e.g. after editing the config) |

## Configuration

Defaults live in `bin/bootstrap.sh`. To override them, create a config file —
it is plain shell that is sourced:

```bash
mkdir -p "$(herdr plugin config-dir herdr-plugin-worktree-bootstrap)"
cat > "$(herdr plugin config-dir herdr-plugin-worktree-bootstrap)/bootstrap.conf" <<'EOF'
files=".env .env.local"
dirs="node_modules vendor"
mode="hardlink"   # hardlink | copy | skip
EOF
```

- `files` — glob patterns copied as plain files.
- `dirs` — directories handled according to `mode`.
- `mode` — `hardlink` (default), `copy`, or `skip`.

## Safety

The hook only ever writes into the freshly created worktree path taken from
the event payload, only copies from the recorded `repo_root`, and refuses to
overwrite existing files. It never deletes anything anywhere. A failure to
copy is logged and otherwise ignored: a bootstrap hook must never make the
worktree look broken.

Hardlinked `node_modules` shares inodes with the source checkout. That is fine
for normal package-manager workflows; if you have tooling that rewrites files
inside `node_modules` in place, set `mode="copy"`.

## Notes on herdr

- The event payload carries both endpoints:
  `.worktree.path` (destination) and `.workspace.worktree.repo_root`
  (source). If either is missing the script falls back to deriving the main
  checkout from `git rev-parse --git-common-dir`.
- Event hooks receive no shell expansion; all logic lives in this script.
- Startup hooks do not re-run when a plugin is installed or enabled, so there
  is deliberately no startup hook — the event alone covers every new worktree.

## Install

```bash
herdr plugin install 0xthc/herdr-plugin-worktree-bootstrap
```

Or link a local checkout while hacking on it:

```bash
herdr plugin link /path/to/herdr-plugin-worktree-bootstrap --enabled
```

Requires herdr >= 0.8.2, plus `jq` and `cp` with `-l` (GNU coreutils or macOS).

## Debugging

Everything the hook did is in the plugin log:

```bash
herdr plugin log herdr-plugin-worktree-bootstrap   # herdr's own command log
cat ~/.local/share/herdr/plugins/state/herdr-plugin-worktree-bootstrap/log
```

The last raw event payload is kept next to it as `last-event.json`.
