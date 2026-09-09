# ccsync

A Claude Code plugin that moves session transcripts between machines over
Tailscale (Taildrop) or a shared filesystem. `bin/ccsync` is the whole implementation.

Push sends to `host:/path`; `-r` includes the whole current project. Pull runs
on the receiving machine and accepts only an optional local destination.
It imports waiting bundles; it does not fetch from a remote host.

## Constraints that are easy to break

**Dependencies are POSIX utilities (sh, awk, tar, etc.) and, for Taildrop only, the Tailscale CLI.** No
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
an explicit local destination, a recorded mapping, or the `target_cwd` the sender named with `host:/path`
— in that order. Scanning `$HOME` for a plausible directory was tried and
removed.

**Tailnet peers and shared-directory writers are trusted; manifests still get checked.** A device that
Tailscale has approved into the tailnet is one of your own machines, so ccsync
does not authenticate `origin_host` or verify that an incoming transcript's
history is unmodified — a peer can assert both. What it does check is that
`session_id` and `origin_host` are single path components (`safe_component`),
because those become filenames, map keys and the argument to `rm -rf`. That is
not defence against a hostile peer so much as against a buggy or older one: an
unvalidated `session_id` was a `rm -rf` outside the project, running unattended
from the SessionStart hook. Any new manifest field that reaches a path needs
the same check.

## Naming

| | |
|---|---|
| install id | `ccsync@hinaser` |
| marketplace name | `hinaser`, from `.claude-plugin/marketplace.json` |
| slash commands | `/ccsync:push`, `/ccsync:pull`, `/ccsync:status`, `/ccsync:list`, `/ccsync:setup`, `/ccsync:init`, `/ccsync:unmap` — one file per subcommand in `commands/`, since plugin commands are namespaced as `<plugin>:<command>` |
| state directory | `~/.claude/ccsync/` — no `claude-` prefix inside `~/.claude` |

## Releasing

1. bump `version` in `.claude-plugin/plugin.json` — the only place a version
   lives; it decides the install cache path and `bin/ccsync` reads it for
   `tool_version`
2. update `RELEASE_NOTES.md`, run every `tests/*.sh` script and
   `sh -n bin/ccsync`, then commit using the GitHub noreply identity
3. create an annotated tag using the GitHub noreply identity, then push the
   release commit to `main` and the tag to origin (the marketplace follows `main`)
4. `gh release create vX.Y.Z --notes-file RELEASE_NOTES.md`
5. refresh this machine's own install: `claude plugin marketplace update hinaser`
   then `claude plugin update ccsync@hinaser`, then restart

Check release files and commit/tag metadata for private information before
publishing. Keep account handles, but use generic example paths, hostnames and
addresses. Do not rewrite published history as part of an ordinary release.

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

`push -r host:/path` adds the whole current project as a `project/` tree with
`project_files\t1` in the manifest. Project restore preflights every path and
refuses differing contents or type collisions, even with `--force`. No project
files are deleted. Archives accept only regular files and directories and are
checked for traversal before extraction. Run `sh tests/project-transfer.sh` for
the isolated sender/receiver integration tests.

## WSL

Tailscale runs on the Windows side and is driven through interop, so bundles
are staged under `%LOCALAPPDATA%\Temp\ccsync` — the Windows binary cannot read
WSL paths. Do not install Tailscale inside WSL.

## Transport configuration

`setup --share <dir> --host <name>` persists configuration as tab-separated
`local` and `share` records in the existing map. `host` records store per-peer
transport and share paths. Flags override environment, which overrides saved
peer routes, then local defaults. `CCSYNC_*` variables remain supported.
Both endpoints register their own inbox before sending; never silently create a
peer inbox. Keep stable endpoint identities, peer validation and atomic bundle
publication intact. Pull checks all configured routes with isolated contexts and
suppresses unavailable transports in automatic hooks. Incoming paths and
transcripts use platform-aware normalization; preserve native Windows cwd values.

Run `sh tests/project-transfer.sh`, `sh tests/filesystem-transport.sh`,
`sh tests/configuration.sh`, `sh tests/paths-and-pairing.sh`, and `sh -n bin/ccsync`.
The path tests cover Windows representations without pretending to exercise SMB.
`sh tests/wsl-host.sh` additionally exercises a real WSL/Windows round trip when
Windows Git Bash is available, and skips elsewhere.
