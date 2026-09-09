#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
mkdir -p "$WORK/shared folder" "$WORK/source" "$WORK/dest"
export CCSYNC_TRANSPORT=filesystem CCSYNC_SHARE="$WORK/shared folder"
# Any accidental Tailscale invocation fails the test, even on an installed host.
cat > "$WORK/tailscale" <<'STUB'
#!/bin/sh
echo invoked >> "$TS_CALLS"
exit 1
STUB
chmod +x "$WORK/tailscale"
export CCSYNC_TAILSCALE="$WORK/tailscale" TS_CALLS="$WORK/ts-calls"
sender() (cd "$WORK/source"; CCSYNC_HOST=wsl CLAUDE_CONFIG_DIR="$WORK/send" "$ROOT/bin/ccsync" "$@")
receiver() (cd "$WORK/dest"; CCSYNC_HOST=windows CLAUDE_CONFIG_DIR="$WORK/receive" "$ROOT/bin/ccsync" "$@")
printf '{"uuid":"one","cwd":"%s"}\n' "$WORK/source" > "$WORK/session.jsonl"
printf 'project contents\n' > "$WORK/source/a file"
sender setup --share "$CCSYNC_SHARE" --host wsl
receiver setup --share "$CCSYNC_SHARE" --host windows
sender init windows "$WORK/dest"
receiver pull
sender pull
sender status > "$WORK/status"
! test -e "$TS_CALLS"
# Check acknowledgement updated the sender's mapping.
awk -F '\t' '$1=="host" && $2=="windows" && $3=="verified" { found=1 } END {exit !found}' "$WORK/send/ccsync/map"
sender push -r --session "$WORK/session.jsonl" --no-history
# Repeated sends in the same second must retain both bundles.
sender push -r --session "$WORK/session.jsonl" --no-history
test "$(find "$CCSYNC_SHARE/windows" -name 'sess_*.tar.gz' | wc -l | tr -d ' ')" = 2
printf 'incomplete' > "$CCSYNC_SHARE/windows/.ccsync.partial"
receiver pull --auto
cmp "$WORK/source/a file" "$WORK/dest/a file"
key=$(printf '%s' "$WORK/dest" | sed 's/[^A-Za-z0-9]/-/g')
transcript=$WORK/receive/projects/$key/session.jsonl
test -f "$transcript"
test -f "$CCSYNC_SHARE/windows/.ccsync.partial"
# Reverse mapping and transport also work for a return transfer.
printf '{"uuid":"two","cwd":"%s"}\n' "$WORK/dest" >> "$transcript"
receiver push wsl --session "$transcript" --no-history
sender pull
key=$(printf '%s' "$WORK/source" | sed 's/[^A-Za-z0-9]/-/g')
test "$(wc -l < "$WORK/send/projects/$key/session.jsonl" | tr -d ' ')" = 2
! test -e "$TS_CALLS"
if CCSYNC_HOST=../escape CLAUDE_CONFIG_DIR="$WORK/bad" "$ROOT/bin/ccsync" status; then exit 1; fi
if CCSYNC_SHARE="$WORK/missing" sender push windows --session "$WORK/session.jsonl"; then exit 1; fi
if sender push '../escape:/tmp/project' --session "$WORK/session.jsonl"; then exit 1; fi
if CCSYNC_TRANSPORT=unknown sender status; then exit 1; fi
test ! -e "$WORK/missing"
printf 'filesystem transport tests passed\n'
