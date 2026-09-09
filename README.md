# ccsync

Move Claude Code sessions and project files between machines over Tailscale or a shared filesystem.

The default transport is **Taildrop**
(`tailscale file cp` / `tailscale file get`), requiring Tailscale on both ends — no sshd, no open ports, no
firewall rules, and no need to make the working-directory paths match.

```
# on the machine you are leaving
/ccsync:push -r mac-mini:/home/you/projects/example

# on mac-mini: import the waiting bundle into this local directory
/ccsync:pull /home/you/projects/example
```

Then resume the session using the command printed by pull. For an existing
destination, starting Claude Code also runs pull automatically through the
session-start hook. Omit `-r` to transfer only the session and rewind history.

## Why this is needed

Claude Code stores a session at
`~/.claude/projects/<cwd, non-alphanumerics turned into '-'>/<session-id>.jsonl`,
and every line of that transcript also carries an absolute `cwd`. The same repo
at `/home/you/projects/foo` (WSL) and `/Users/you/projects/foo` (macOS)
therefore produces two different directory keys and two different `cwd` values.
Copying the file alone does not work.

`ccsync` figures out the local counterpart of the sender's directory and
rewrites `cwd` on arrival.

## Shared filesystem transport (Windows shares and WSL)

Create a dedicated shared directory, then run setup once on **each endpoint**.
For WSL and its Windows host, these two paths refer to the same directory:

```text
# In Claude Code on WSL
/ccsync:setup --share /mnt/c/Users/you/ccsync-share --host wsl

# In Claude Code on Windows (Git Bash paths also work)
/ccsync:setup --share C:/Users/you/ccsync-share --host windows
```

Setup saves configuration in `~/.claude/ccsync/map`. Slash commands and the
SessionStart hook read it automatically, including when Claude Code is launched
from an editor. No shell exports or Claude settings edits are needed. For terminal
use, invoke `bin/ccsync setup` from a checkout with the same arguments.

For Windows file sharing (SMB), use a mounted share on Linux/macOS or a Git Bash
path such as `//server/share/ccsync`. Both endpoints must access **the same physical
directory**, using their own local paths. Mounting and credentials are managed
outside ccsync; setup requires the shared root to exist. On Windows, drive-letter,
Git Bash `/c/...`, and quoted backslash paths are accepted and normalized.
Tailscale is not required for filesystem-only use.

Choose a stable, unique name for each endpoint, including Windows and WSL on the
same computer. If `--host` is omitted, setup uses the saved name or the hostname
(with a distribution suffix on WSL). Names allow letters, digits, dots,
underscores and hyphens, cannot start with a hyphen, and cannot be `.` or `..`.
Setup refuses a name already registered by another configuration. To create a
separate endpoint, use a separate `CLAUDE_CONFIG_DIR`. Avoid names differing only
by case; peer lookup uses the spelling published by the receiver.

Discover peers, pair directories, then transfer:

```text
/ccsync:status
/ccsync:init windows C:/Users/you/projects/example
/ccsync:push -r windows

# On Windows
/ccsync:pull
```

You can skip explicit pairing and push directly after both setups:
`/ccsync:push -r windows:C:/Users/you/projects/example`. A typo in the peer name
fails with a list of available names; push never creates an unknown peer's inbox.
The path after `host:` is the **receiver's project directory**, separate from the
share. Quote arguments containing spaces. Windows mappings recognize native
`C:\Users\...`, `C:/Users/...` and local Git Bash `/c/Users/...` spellings; imported
transcripts use native Windows `cwd` paths.

### Mixing transports and adding shares

Each peer remembers its transport. To add a Mac over Taildrop while keeping a
Windows share configured:

```text
/ccsync:init mac-mini /Users/you/projects/example --transport tailscale
/ccsync:push mac-mini
/ccsync:push windows
```

Run `setup --share <another-dir>` to register another share with the same endpoint
name. It becomes the default for new filesystem peers; existing peer routes stay
unchanged. Use `init <peer> <remote-dir> --share <dir>` or
`push <peer>:/remote-dir --share <dir>` to select a specific share and save that
route. If the same peer name appears on multiple shares, select one explicitly.
Use distinct names for endpoints that should remain independently addressable.

Both manual and automatic pull check all configured shares and Taildrop when it
is configured (the default, a saved Taildrop peer, or `setup --transport tailscale`).
An unavailable transport does not block other inboxes. Missing mounts and receive
failures are quiet during automatic hooks; manual pull reports them and returns a
failure status. `pull --source <dir>` imports only that directory for retries.

`status` shows saved configuration, environment overrides, discovered endpoints,
per-peer routes, filesystem queue counts, and unavailable shares. Taildrop queues
remain managed by Tailscale until fetched. Filesystem availability means the inbox
exists, not that the receiver is running.

To forget a peer, use `unmap <peer>`. To stop checking a share, forget peers using
it and run `setup --remove-share <dir>`; share files and registrations are retained.
If the removed share was the default, the default returns to Tailscale; other
registered shares are still checked. `setup --transport tailscale` enables
Taildrop and makes it the default without removing filesystem routes.

### Existing environment configuration

`CCSYNC_TRANSPORT`, `CCSYNC_SHARE`, and `CCSYNC_HOST` remain supported. For push
and init, precedence is command flags, environment overrides, the saved peer
route, then the local default. `--share` implies filesystem transport. Environment
route overrides are temporary for already configured peers; explicit command flags
save route changes. Pull always checks all configured inboxes, including an extra
share supplied by `CCSYNC_SHARE`. `status` reports active overrides.

For an existing environment-only installation, run
`setup --share "$CCSYNC_SHARE" --host "$CCSYNC_HOST"` once on each endpoint, then
remove the exports from your launcher or shell profile. Existing Tailscale mappings
and older bundles remain supported. Existing unregistered filesystem inboxes can
still receive bundles, but each endpoint should run setup to publish its identity.

### Delivery and access

Bundles are stored under `<share>/<host>/`. A completed copy is published by rename
inside that directory, so pull ignores partial copies. A successful push means the
bundle is queued, not that it was imported. The receiving application may be closed
as long as the share remains accessible. Import preserves the existing archive,
conflict, and fast-forward rules.

Use a directory accessible only to trusted endpoints: anyone with write access can
submit bundles, and anyone with read access can read their contents. Configure share
permissions so both endpoints can read, write and remove inbox files. Interrupted
pushes may leave hidden `.ccsync.*` temporary files; remove these only when no push
is active, and preserve the `.ccsync-peer` registration file. Keep the share outside
projects transferred with `-r`.

## Prerequisites

**For the default transport: Tailscale on both machines, signed in to the same tailnet.** Taildrop is enabled by default; nothing needs to be exposed,
forwarded or opened.

- **WSL2** — use the **Windows** Tailscale client. It is reachable from WSL
  through interop, and installing Tailscale inside WSL costs more than it
  returns ([why](#do-not-install-tailscale-inside-wsl2)).
- **macOS** — either the App Store build (its CLI lives inside
  `/Applications/Tailscale.app`, which is checked automatically) or the
  standalone build from tailscale.com.
- **Linux** — `tailscaled` running, and `sudo tailscale set --operator=$USER`
  so the CLI can be driven without sudo.
- Set `CCSYNC_TAILSCALE=/path/to/tailscale` if the binary lives somewhere
  unusual.

`ccsync` is a single POSIX shell script. Beyond the optional Tailscale CLI it uses
only `sh`, `awk`, `tar` and `sha256sum`/`shasum` — no Python, no Node, no jq.
These are present by default on macOS and Linux, and on Windows they come with
the Git Bash that Claude Code already requires.

Both machines should run the same version of Claude Code. A mismatch is
reported when a session arrives, not blocked.

## Install

In Claude Code, on each machine:

```
/plugin marketplace add Hinaser/ccsync
/plugin install ccsync@hinaser
```

To work from a local checkout instead, clone it wherever you keep repositories
and point the marketplace at that directory:

```bash
git clone https://github.com/Hinaser/ccsync
```

```
/plugin marketplace add /path/to/ccsync
/plugin install ccsync@hinaser
```

Installing the plugin also installs a `SessionStart` hook that runs `ccsync
pull` quietly whenever Claude Code starts, so the receiving side needs no
command at all. It is a no-op when nothing is waiting.

### Update an existing installation

On each machine, run these in a terminal after the new version reaches `main`:

```sh
claude plugin marketplace update hinaser
claude plugin update ccsync@hinaser
claude plugin list
```

Confirm the new version is listed, then restart Claude Code. Existing sessions
and directory mappings are preserved. Update both machines before using project
transfer. The GitHub marketplace tracks `main`; publishing a release tag alone
does not update installations. If you added a local checkout as the marketplace,
update that checkout first with `git pull --ff-only`.

## Commands

```
/ccsync:push <host>:/remote-dir         send the current session, recording where it goes
/ccsync:push -r <host>:/remote-dir      send the session and the whole current project
/ccsync:push <host>                     thereafter; the directory is remembered
/ccsync:push                            when only one host is mapped for this directory
/ccsync:pull                            receive anything waiting (the hook does this for you)
/ccsync:pull <local-dir>                receive into a specific local directory
/ccsync:pull .                          receive into the current directory
/ccsync:list                            sessions recorded for this directory
/ccsync:status                          configuration, discovered peers, queues and mappings
/ccsync:setup --share <dir> --host <name> save filesystem setup for commands and hooks
/ccsync:init <host> <remote-dir>        pair explicitly and verify the mapping
/ccsync:unmap <host> [<local-dir>]      forget a mapping, or the peer entirely
```

`/ccsync:init <host> <remote-dir>` pairs directories explicitly and also sends
a probe: the peer's next pull records the reverse mapping, checks the
directory exists there and sends an acknowledgement back, which marks the pair
verified in `status`.

## Push first, pull on the receiving machine

`push` sends a bundle to the named machine using the configured transport. After it arrives,
`pull` on that machine imports the session and any included project files.
The session-start hook runs this import automatically when Claude Code starts;
run `/ccsync:pull` manually if Claude Code is already open.

Pull receives bundles already sent to this machine. Its optional path is a
**local destination**, and applies to every session bundle waiting in the inbox.
`/ccsync:pull mac-mini:/home/you/projects/example` is not supported: it cannot
fetch a project directly from another machine. Run push on mac-mini first, then
pull on the machine where you want to continue working. `--source <dir>` selects
a local directory of bundles for import or retry, not a remote source.

### Updating from earlier command syntax

| Previous syntax | Replacement |
|---|---|
| `/ccsync:push mac-mini --to /remote/project` | `/ccsync:push mac-mini:/remote/project` |
| `/ccsync:push mac-mini --include .` | `/ccsync:push -r mac-mini` |
| `/ccsync:pull --into /local/project` | `/ccsync:pull /local/project` |

`--to`, `--include` and `--into` are removed. Project transfer uses `-r` for the
whole current project; individual path selection is not available.

## Where an arriving session is placed

There is no searching of your filesystem. The directory is resolved in this
order:

1. `<local-dir>`, if given;
2. a mapping already recorded for that peer and directory;
3. the directory the **sender** named with `host:/path`, if it exists here — this is
   what makes the receiving side configuration-free;
4. otherwise the bundle is left queued and `pull` tells you to name a directory
   with `ccsync pull <local-dir>`.

Whatever is used is recorded, so it is asked for at most once per peer and
project.

## Deciding whether to write

Transcripts are append-only, so `ccsync` treats them like a branch and
only ever fast-forwards. It compares the sequence of entry ids on both sides:

| relation | result |
|---|---|
| no local copy | written |
| local is a prefix of incoming | fast-forward, written (previous copy kept as `.bak-<epoch>`) |
| identical | reported as up to date, nothing written |
| **incoming is a prefix of local** | **kept local — this machine is ahead, nothing written** |
| diverged (both sides have entries the other lacks) | refused and set aside in `~/.claude/ccsync/conflicts/` so it is not retried on every start |

So pulling can never lose work that only exists on the receiving machine, and a
stale bundle arriving after you have carried on locally is simply ignored.

To accept a conflicting transcript anyway:

```
/ccsync:pull --source ~/.claude/ccsync/conflicts --force
```

The copy being replaced is kept alongside it as `.jsonl.bak-<epoch>`.

## What moves

| | |
|---|---|
| `~/.claude/projects/<key>/<id>.jsonl` | the transcript — always |
| `~/.claude/file-history/<id>/` | `/rewind` state — included when under 64 MB (`--no-history` to skip) |
| Project files/directories | include the whole current project with `-r` |
| `~/.claude.json`, `shell-snapshots/`, `session-env/` | never — machine-specific or account state |

Only the `cwd` field is rewritten. Absolute paths embedded in tool results are
left alone: they are plain text, resume works regardless, and rewriting them
would edit quoted file contents. Pass `--rewrite-all` to `pull` to replace every
occurrence anyway.

### Including project files

```
/ccsync:push -r mac-mini:/home/you/projects/example
```

The destination uses SSH-style `host:/path` notation. Once remembered, use
`/ccsync:push -r mac-mini`, or `/ccsync:push -r` if only one host is mapped.
`-r` includes the whole current project; omit it to send only the session and
rewind history. Quote the whole destination if its path contains spaces:
`"mac-mini:/path/my project"`.
With Taildrop, the host is a Tailscale peer name or IPv4 address. With filesystem
transport, it is the receiver’s registered endpoint name. Neither uses an SSH username or port.

Directories include their contents recursively, including hidden files and empty
directories. `-r` includes everything: `.git`, ignored files, dependencies
and secrets such as `.env` are **not filtered**. Symlinks, special files, and
names containing tabs, newlines or backslashes are unsupported.
Bundles are limited to 64 MB compressed and 256 MB unpacked, including the session
and rewind history. Both machines must run a version supporting project transfer;
older receivers only restore the session.

Pull adds missing files and keeps files with identical contents. It never deletes
project files. If an incoming path differs or collides with a symlink or directory,
the entire bundle is set aside in `~/.claude/ccsync/conflicts/` before any project
files or transcript are changed. `--force` only affects transcript conflicts; it
does not overwrite project files. Move aside or reconcile the conflicting local
paths, then retry with `pull --source ~/.claude/ccsync/conflicts`.

Project files are processed even when the transcript is already up to date. A
stale or diverged transcript keeps its project payload from being applied unless
you explicitly use `--force`. An interrupted or failed copy can leave some new
files in place; retrying keeps those if their contents match.

To receive into a directory that does not exist yet, explicitly run
`/ccsync:pull <new-local-dir>`. It creates that directory for a bundle with
project files and remembers the mapping. Automatic pulls require an existing
destination.

## Platforms

| | Tailscale binary | staging |
|---|---|---|
| WSL2 | the **Windows** client through interop | `%LOCALAPPDATA%\Temp\ccsync` |
| Windows 10/11 | `C:\Program Files\Tailscale\tailscale.exe` | `~/.claude/ccsync/outbox` |
| macOS | `/Applications/Tailscale.app/Contents/MacOS/Tailscale`, or `tailscale` on PATH | `~/.claude/ccsync/outbox` |
| Linux | `tailscale` on PATH | `~/.claude/ccsync/outbox` |

### Do not install Tailscale inside WSL2

The Windows client already works from WSL through interop. A WSL install costs a
second node to keep online, `tailscaled` started by hand or systemd on every
boot, `--tun=userspace-networking` for the missing TUN device, and route
conflicts with the Windows client under mirrored networking — in exchange for
skipping one staging hop that is handled automatically.

On Windows the script runs under the Git Bash that Claude Code already
requires, so `sh`, `awk` and `tar` are present and transcripts keep their LF
line endings.

## Notes

- Taildrop delivers directly and does not queue for an offline peer, so `push`
  to an offline machine fails immediately rather than pretending to succeed.
- If a GUI client auto-accepts Taildrop files instead of holding them, `pull`
  also scans `~/Downloads` (and the Windows profile's `Downloads` from WSL).
- On Linux, `sudo tailscale set --operator=$USER` lets you drive `tailscale`
  without sudo.
- Keep Claude Code at the same version on both machines. A mismatch is reported
  on pull, not blocked.
- State lives in `~/.claude/ccsync/`: `map` (tab-separated), `archive/`
  holding bundles that were applied, and `conflicts/` holding ones that were
  refused.
- `CCSYNC_TAILSCALE=/path/to/tailscale` overrides binary discovery.

## License

MIT
