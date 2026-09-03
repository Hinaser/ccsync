---
description: Send this Claude Code session to another machine over Tailscale
argument-hint: [host] [--to <remote-dir>] [--session <id>] [--no-history]
allowed-tools: Bash
---

!`"$CLAUDE_PLUGIN_ROOT/bin/ccsync" push $ARGUMENTS`

Report the command output above verbatim. Do nothing else — do not run further
commands, do not summarize, do not suggest follow-ups.
