# ccsync 0.4.0

Transfer the current project alongside its Claude Code session with:

```
/ccsync:push -r mac-mini:/home/hinaser/projects/aaa
```

On the receiving machine, import the waiting bundle with:

```
/ccsync:pull /home/hinaser/projects/aaa
```

For existing destinations, the session-start hook also runs pull automatically.
Pull imports bundles already delivered by Taildrop; it cannot fetch from a
remote `host:/path`. No SSH server is needed.

## Breaking command changes

- Push destinations use `host:/path`; `--to` is removed.
- `-r` includes the whole current project; `--include` and individual path
  selection are removed. Omit `-r` for session and rewind history only.
- Pull takes a positional local destination; `--into` is removed.
- Remembered destinations still work: `push -r host`, or `push -r` when only one
  host is mapped. Plain `pull` uses the recorded or sender-specified destination.

## Project transfer behavior

- Includes nested directories, hidden files, empty directories and executable
  files. Nothing is filtered: `.git`, ignored files, dependencies and `.env`
  are included too.
- Adds missing files and keeps identical contents. Differing files, symlinks
  and file/directory collisions set the bundle aside before applying it.
  `--force` only overrides transcript conflicts; it never overwrites project
  conflicts. Project files are not deleted.
- Explicit `pull /new/local/path` can create a destination for project bundles.
- Project files can arrive with an unchanged transcript. Stale or diverged
  transcripts retain their existing protections.
- Bundles are limited to 64 MB compressed and 256 MB unpacked. Symlinks and
  special files are unsupported; archive paths and entry types are checked
  before extraction.

Update ccsync on both machines for project transfer. Older receivers import
only the session. Existing session-only bundles remain supported.

Run in a terminal on each machine, then restart Claude Code:

```sh
claude plugin marketplace update hinaser
claude plugin update ccsync@hinaser
claude plugin list
```

Confirm version 0.4.0 is listed. Existing sessions and mappings are preserved.

## Validation

Local sender/receiver integration tests use isolated Claude configurations and
a Tailscale stub. They cover recursive transfer, conflicts, unchanged and stale
transcripts, new destinations, remembered destinations, removed syntax, and
symlink rejection. Real cross-machine and macOS/Windows validation remains to
be performed.
