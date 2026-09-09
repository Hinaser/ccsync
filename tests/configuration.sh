#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
unset CCSYNC_TRANSPORT CCSYNC_SHARE CCSYNC_HOST
mkdir -p "$WORK/share one" "$WORK/share two" "$WORK/drop" "$WORK/hub" "$WORK/windows" "$WORK/wsl" "$WORK/tail"
cat > "$WORK/tailscale" <<'STUB'
#!/bin/sh
printf '%s %s\n' "$TS_SELF" "$*" >> "$TS_LOG"
case $1 in
    status)
        printf '100.64.0.1 %s user linux -\n' "$TS_SELF"
        for p in hub-tail tail; do [ "$p" = "$TS_SELF" ] || printf '100.64.0.2 %s user linux -\n' "$p"; done ;;
    file)
        case $2 in
            cp) peer=${4%:}; mkdir -p "$TS_DROP/$peer"; cp "$3" "$TS_DROP/$peer/" ;;
            get) mkdir -p "$4"; for b in "$TS_DROP/$TS_SELF/"*.tar.gz; do [ ! -f "$b" ] || mv "$b" "$4/"; done ;;
        esac ;;
esac
exit 0
STUB
chmod +x "$WORK/tailscale"
export CCSYNC_TAILSCALE="$WORK/tailscale" TS_LOG="$WORK/ts-log" TS_DROP="$WORK/drop"
hub() (cd "$WORK/hub"; TS_SELF=hub-tail CLAUDE_CONFIG_DIR="$WORK/hub-config" "$ROOT/bin/ccsync" "$@")
windows() (cd "$WORK/windows"; TS_SELF=windows CLAUDE_CONFIG_DIR="$WORK/windows-config" "$ROOT/bin/ccsync" "$@")
wsl() (cd "$WORK/wsl"; TS_SELF=wsl CLAUDE_CONFIG_DIR="$WORK/wsl-config" "$ROOT/bin/ccsync" "$@")
tailpeer() (cd "$WORK/tail"; TS_SELF=tail CLAUDE_CONFIG_DIR="$WORK/tail-config" "$ROOT/bin/ccsync" "$@")
# Saved setup is sufficient for every later process, without exported config.
hub setup --share "$WORK/share one" --host hub
windows setup --share "$WORK/share one" --host Windows
hub setup --share "$WORK/share one" --host hub
if CLAUDE_CONFIG_DIR="$WORK/duplicate" "$ROOT/bin/ccsync" setup --share "$WORK/share one" --host hub; then exit 1; fi
hub status > "$WORK/status"
awk '/discovered: Windows/ {found=1} END {exit !found}' "$WORK/status"
if hub init wondows "$WORK/windows"; then exit 1; fi
test ! -e "$WORK/share one/wondows"
# Case spelling is resolved from the receiver, instead of creating an alias inbox.
hub init windows "$WORK/windows"
windows pull
hub pull
awk -F '\t' '$1=="host" && $2=="Windows" && $3=="verified" {found=1} END {exit !found}' "$WORK/hub-config/ccsync/map"
test ! -e "$TS_LOG"
# Add another share. Existing peer routing keeps using the first share.
hub setup --share "$WORK/share two" --host hub
wsl setup --share "$WORK/share two" --host wsl
hub init wsl "$WORK/wsl"
wsl pull
hub pull
printf '{"uuid":"one","cwd":"%s"}\n' "$WORK/hub" > "$WORK/hub.jsonl"
hub push windows --session "$WORK/hub.jsonl" --no-history
windows pull
test ! -e "$TS_LOG"
# Add a Taildrop peer without changing either filesystem peer's transport.
hub init tail "$WORK/tail" --transport tailscale
tailpeer pull
hub pull
# Return bundles on all three routes and drain them in one automatic pull.
for peer in windows wsl tail; do
    printf '{"uuid":"%s-one","cwd":"%s"}\n' "$peer" "$WORK/$peer" > "$WORK/$peer.jsonl"
done
windows push hub --session "$WORK/windows.jsonl" --no-history
wsl push hub --session "$WORK/wsl.jsonl" --no-history
tailpeer push hub-tail --session "$WORK/tail.jsonl" --no-history
hub status > "$WORK/status"
awk '/inbox: 1 waiting for hub/ {found=1} END {exit !found}' "$WORK/status"
hub pull --auto
key=$(printf '%s' "$WORK/hub" | sed 's/[^A-Za-z0-9]/-/g')
for peer in windows wsl tail; do test -f "$WORK/hub-config/projects/$key/$peer.jsonl"; done
# An offline share is quiet in hooks; other routes continue importing.
mv "$WORK/share one" "$WORK/share offline"
printf '{"uuid":"wsl-two","cwd":"%s"}\n' "$WORK/wsl" >> "$WORK/wsl.jsonl"
wsl push hub --session "$WORK/wsl.jsonl" --no-history
hub pull --auto > "$WORK/auto-output" 2> "$WORK/auto-error"
test ! -s "$WORK/auto-error"
test "$(wc -l < "$WORK/hub-config/projects/$key/wsl.jsonl" | tr -d ' ')" = 2
if hub pull > "$WORK/manual-output" 2> "$WORK/manual-error"; then exit 1; fi
awk '/shared directory unavailable/ {found=1} END {exit !found}' "$WORK/manual-error"
hub status > "$WORK/status"
awk '/unavailable; mount the share/ {found=1} END {exit !found}' "$WORK/status"
mv "$WORK/share offline" "$WORK/share one"
# Removal is explicit, prevents dangling peer routes, and preserves share files.
if hub setup --remove-share "$WORK/share one"; then exit 1; fi
hub unmap Windows
hub setup --remove-share "$WORK/share one"
test -d "$WORK/share one/Windows"
# Environment overrides are temporary; explicit flags persist the chosen route.
tailpeer setup --share "$WORK/share two" --host tail
CCSYNC_TRANSPORT=filesystem CCSYNC_SHARE="$WORK/share two" hub push tail --session "$WORK/hub.jsonl" --no-history
awk -F '\t' '$1=="host" && $2=="tail" && $3=="transport" && $4=="tailscale" {found=1} END {exit !found}' "$WORK/hub-config/ccsync/map"
tailpeer pull
CCSYNC_TRANSPORT=tailscale hub push tail --share "$WORK/share two" --session "$WORK/hub.jsonl" --no-history
awk -F '\t' '$1=="host" && $2=="tail" && $3=="transport" && $4=="filesystem" {found=1} END {exit !found}' "$WORK/hub-config/ccsync/map"
tailpeer pull
# Setup must preserve the routing of old Taildrop maps with no transport field.
mkdir -p "$WORK/legacy-config/ccsync"
printf 'path\ttail\t%s\t%s\n' "$WORK/hub" "$WORK/tail" > "$WORK/legacy-config/ccsync/map"
CLAUDE_CONFIG_DIR="$WORK/legacy-config" "$ROOT/bin/ccsync" setup --share "$WORK/share two" --host legacy
awk -F '\t' '$1=="host" && $2=="tail" && $3=="transport" && $4=="tailscale" {found=1} END {exit !found}' "$WORK/legacy-config/ccsync/map"
# The earlier environment-only filesystem release can adopt its existing inbox.
mkdir -p "$WORK/env-config/ccsync" "$WORK/share two/old-fs"
printf 'path\twsl\t%s\t%s\n' "$WORK/hub" "$WORK/wsl" > "$WORK/env-config/ccsync/map"
CCSYNC_TRANSPORT=filesystem CCSYNC_SHARE="$WORK/share two" CCSYNC_HOST=old-fs CLAUDE_CONFIG_DIR="$WORK/env-config" "$ROOT/bin/ccsync" setup
awk -F '\t' '$1=="host" && $2=="wsl" && $3=="transport" && $4=="filesystem" {found=1} END {exit !found}' "$WORK/env-config/ccsync/map"
# Missing option values produce useful errors rather than shell crashes.
for args in 'setup --share' 'setup --host' 'init --transport' 'push --share' 'pull --source'; do
    if hub $args > "$WORK/error" 2>&1; then exit 1; fi
    awk '/requires a value/ {found=1} END {exit !found}' "$WORK/error"
done
printf 'configuration and mixed transport tests passed\n'
