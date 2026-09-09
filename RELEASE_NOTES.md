# ccsync 0.5.0

Transfer Claude Code sessions and projects through Windows file shares, mounted
SMB shares, or WSL host storage, alongside the existing Tailscale transport.

## Set up a shared filesystem once

Create a dedicated directory that both endpoints can access, then register each
endpoint using its own local path:

```text
# WSL
/ccsync:setup --share /mnt/c/Users/you/ccsync-share --host wsl

# Windows
/ccsync:setup --share C:/Users/you/ccsync-share --host windows
```

Discover the receiver and transfer a project:

```text
/ccsync:status
/ccsync:push -r windows:C:/Users/you/projects/example
```

On Windows, run `/ccsync:pull`, or start Claude Code in an existing destination
and let the session-start hook import it automatically. Configuration is saved;
no shell exports are required for future launches.

## Changes

- Filesystem bundles are queued in separate endpoint inboxes and published only
  after copying finishes. Incomplete copies are ignored.
- Transports are remembered per peer. Add a Taildrop peer with
  `init <peer> <remote-dir> --transport tailscale`, or select a share with
  `--share <dir>` on init or push.
- Manual and automatic pulls check all configured inboxes. An unavailable share
  does not block other transports; automatic hooks suppress missing-mount errors.
- Status shows configuration, discovered peers, routes, queue counts and
  availability. Unknown filesystem peers are rejected with setup guidance.
- Pairing confirms receiver names and directory mappings. Windows path spellings
  are normalized for mappings, while transcripts retain native Windows paths.
- Existing Taildrop mappings, environment overrides, and older bundles remain
  supported. Fast-forward and project-conflict protections are unchanged.
- Machine-specific network examples were replaced with generic values. Public
  account handles remain; new release metadata uses the GitHub noreply identity.

## Update

Run on each endpoint, then restart Claude Code:

```sh
claude plugin marketplace update hinaser
claude plugin update ccsync@hinaser
claude plugin list
```

Confirm version **0.5.0**. Existing sessions and directory mappings are preserved.
Tailscale remains the default; filesystem delivery requires setup on both ends.

## Validation

All five test scripts pass: project transfer, filesystem delivery, configuration
and mixed transports, Windows path handling and pairing, and a real
WSL → Windows Git Bash → WSL round trip using host storage. Shell syntax and
whitespace checks pass. Live SMB-server and macOS testing remain outstanding.
