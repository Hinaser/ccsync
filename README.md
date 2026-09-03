# ccsync

Move Claude Code sessions between machines over Tailscale.

The only requirement is Tailscale on both ends. Transport is **Taildrop**
(`tailscale file cp` / `tailscale file get`) — no sshd, no open ports, no
firewall rules, and no need to make the working-directory paths match.

```
# on the machine you are leaving
/ccsync:push mac-mini

# on the machine you are moving to: just start Claude Code in that project.
# The session is already there.
claude --resume <id>
```

## Why this is needed

Claude Code stores a session at
`~/.claude/projects/<cwd, non-alphanumerics turned into '-'>/<session-id>.jsonl`,
and every line of that transcript also carries an absolute `cwd`. The same repo
at `/home/you/projects/foo` (WSL) and `/Users/you/projects/foo` (macOS)
therefore produces two different directory keys and two different `cwd` values.
Copying the file alone does not work.

`ccsync` figures out the local counterpart of the sender's directory and
rewrites `cwd` on arrival.

## Prerequisites

**Tailscale, on both machines, signed in to the same tailnet.** That is the
whole of it. Taildrop is enabled by default; nothing needs to be exposed,
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

`ccsync` is a single POSIX shell script. Beyond the Tailscale CLI it uses
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

## Commands

```
/ccsync:push <host> --to <remote-dir>   send the current session, recording where it goes
/ccsync:push <host>                     thereafter; the directory is remembered
/ccsync:push                            when only one host is mapped for this directory
/ccsync:pull                            receive anything waiting (the hook does this for you)
/ccsync:pull --into <local-dir>         place an arriving session somewhere specific
/ccsync:list                            sessions recorded for this directory
/ccsync:status                          peers and their mappings
/ccsync:init <host> <remote-dir>        pair explicitly and verify the mapping
```

`/ccsync:init <host> <remote-dir>` is an alternative to `--to` that also sends
a probe: the peer's next pull records the reverse mapping, checks the
directory exists there and sends an acknowledgement back, which marks the pair
verified in `status`.

## Where an arriving session is placed

There is no searching of your filesystem. The directory is resolved in this
order:

1. `--into <local-dir>`, if given;
2. a mapping already recorded for that peer and directory;
3. the directory the **sender** named with `--to`, if it exists here — this is
   what makes the receiving side configuration-free;
4. otherwise the bundle is left queued and `pull` tells you to name a directory
   with `--into`.

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
| `~/.claude.json`, `shell-snapshots/`, `session-env/` | never — machine-specific or account state |

Only the `cwd` field is rewritten. Absolute paths embedded in tool results are
left alone: they are plain text, resume works regardless, and rewriting them
would edit quoted file contents. Pass `--rewrite-all` to `pull` to replace every
occurrence anyway.

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
