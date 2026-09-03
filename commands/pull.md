---
description: Receive Claude Code sessions waiting for this machine
argument-hint: [--into <local-dir>] [--force] [--source <dir>]
allowed-tools: Bash
---

!`"${CLAUDE_PLUGIN_ROOT}/bin/ccsync" pull $ARGUMENTS`

Report the command output above verbatim. Do nothing else — do not run further
commands, do not summarize, do not suggest follow-ups.
