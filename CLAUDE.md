# ccsync

A Claude Code plugin that moves session transcripts between machines over
Tailscale (Taildrop). `bin/ccsync` is the whole implementation.

## Constraints that are easy to break

**Dependencies are sh, awk, tar and the Tailscale CLI. Nothing else.** No
Python, no Node, no jq. This is deliberate: Git Bash on Windows and a stock
macOS have no Python, and the tool has to run wherever Claude Code runs. The
implementation was Python once and was rewritten for exactly this reason — do
not reintroduce an interpreter dependency for convenience.

**`plugin.json` must not declare `commands` or `hooks`.** `commands/` and
`hooks/hooks.json` are auto-discovered. Naming them in the manifest makes the
loader read `hooks/hooks.json` twice and the plugin fails with "Duplicate hooks
file detected".

**`${CLAUDE_PLUGIN_ROOT}` must be written with braces.** The loader does a
literal `${CLAUDE_PLUGIN_ROOT}` → path replacement on command bodies,
frontmatter and `hooks.json` before anything reaches a shell. Bare
`$CLAUDE_PLUGIN_ROOT` is not substituted, so the shell expands it to the empty
string and every command dies with `/bin/ccsync: no such file or directory`.

**`/plugin marketplace add Hinaser/ccsync` tracks the default branch.** There is no `@tag` or `@ref` syntax — that string is treated as a
repository name. Everyone who installs gets the tip of `main`, so `main` must
always be in a working state. Tags are version markers for humans, not install
targets.

**Receiving only ever fast-forwards.** `pull` compares the sequence of
transcript entry ids (`uuid` per line) and writes only when the local copy is a
prefix of the incoming one. Equal means skip; local longer means keep local;
divergence is set aside in `~/.claude/ccsync/conflicts/`. A pull must never be
able to discard work that exists only on the receiving machine.

**No searching of the filesystem.** An arriving session is placed using
`--into`, a recorded mapping, or the `target_cwd` the sender named with `--to`
— in that order. Scanning `$HOME` for a plausible directory was tried and
removed.

## Naming

| | |
|---|---|
| install id | `ccsync@hinaser` |
| marketplace name | `hinaser`, from `.claude-plugin/marketplace.json` |
| slash commands | `/ccsync:push`, `/ccsync:pull`, `/ccsync:status`, `/ccsync:list`, `/ccsync:init` — one file per subcommand in `commands/`, since plugin commands are namespaced as `<plugin>:<command>` |
| state directory | `~/.claude/ccsync/` — no `claude-` prefix inside `~/.claude` |

## Releasing

1. bump `version` in `.claude-plugin/plugin.json` — the only place a version
   lives; it decides the install cache path and `bin/ccsync` reads it for
   `tool_version`
2. commit
3. `git tag -a vX.Y.Z -m "ccsync X.Y.Z" && git push origin vX.Y.Z`
4. `gh release create vX.Y.Z --notes ...`
5. refresh this machine's own install: `claude plugin update ccsync@hinaser`,
   then restart

Releases carry no assets; a plugin is installed from the repository, not
downloaded. Do not force-update a tag that has been published.

## Testing without a second machine

Both sides can be exercised locally:

- `CLAUDE_CONFIG_DIR=/tmp/fake-home` isolates state and the placed transcripts
- `ccsync pull --source <dir>` reads bundles from a directory
  instead of Taildrop
- `CCSYNC_TAILSCALE=/path/to/stub` replaces the Tailscale binary; a stub only
  needs to answer `status` with the plain-text peer table and record `file cp`
  arguments

A bundle is a `.tar.gz` of a tab-separated `manifest` plus `<session-id>.jsonl`,
named `sess_*`, `probe_*` or `ack_*`.

## WSL

Tailscale runs on the Windows side and is driven through interop, so bundles
are staged under `%LOCALAPPDATA%\Temp\ccsync` — the Windows binary cannot read
WSL paths. Do not install Tailscale inside WSL.
