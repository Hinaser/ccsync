---
description: Send this Claude Code session and optional project files to another machine using the configured transport
argument-hint: [-r] [host[:/remote-dir]] [--session <id>] [--no-history] [--transport tailscale|filesystem] [--share <dir>]
allowed-tools: Bash
---

!`"${CLAUDE_PLUGIN_ROOT}/bin/ccsync" push $ARGUMENTS`

Report the command output above verbatim. Do nothing else — do not run further
commands, do not summarize, do not suggest follow-ups.
