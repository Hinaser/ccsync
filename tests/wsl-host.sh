#!/bin/sh
# Optional real integration test: WSL -> Windows Git Bash -> WSL on host storage.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WIN_BASH=${CCSYNC_TEST_WINDOWS_BASH:-'/mnt/c/Program Files/Git/bin/bash.exe'}
if [ ! -x "$WIN_BASH" ] || ! command -v wslpath >/dev/null 2>&1; then
    printf 'SKIP: WSL with Windows Git Bash is required\n'
    exit 0
fi
WIN_TEMP=$("$WIN_BASH" --noprofile --norc -c 'cygpath -m /tmp' | tr -d '\r')
WORK=$(mktemp -d "$(wslpath -u "$WIN_TEMP")/ccsync-test.XXXXXXXXXX")
LOCAL_WORK=$(mktemp -d)
trap 'rm -rf "$WORK" "$LOCAL_WORK"' EXIT HUP INT TERM
WIN_ROOT=$(wslpath -m "$WORK")
mkdir -p "$WORK/tool/bin" "$WORK/tool/.claude-plugin" "$WORK/share space" "$WORK/windows-project" "$LOCAL_WORK/project"
cp "$ROOT/bin/ccsync" "$WORK/tool/bin/ccsync"
cp "$ROOT/.claude-plugin/plugin.json" "$WORK/tool/.claude-plugin/plugin.json"
unset CCSYNC_TRANSPORT CCSYNC_SHARE CCSYNC_HOST
wslpeer() (cd "$LOCAL_WORK/project"; CLAUDE_CONFIG_DIR="$LOCAL_WORK/config" "$ROOT/bin/ccsync" "$@")
winpeer() {
    "$WIN_BASH" --noprofile --norc -c '
        root=$1; shift
        unset CCSYNC_TRANSPORT CCSYNC_SHARE CCSYNC_HOST
        export CLAUDE_CONFIG_DIR="$root/windows-config"
        cd "$root/windows-project" || exit 1
        "$root/tool/bin/ccsync" "$@"
    ' -- "$WIN_ROOT" "$@"
}
wslpeer setup --share "$WORK/share space" --host wsl-test
winpeer setup --share "$WIN_ROOT/share space" --host windows-test
# Send a native Windows destination, including its backslashes.
wslpeer init windows-test "$(wslpath -w "$WORK/windows-project")"
winpeer pull
wslpeer pull
printf '{"uuid":"one","cwd":"%s"}\n' "$LOCAL_WORK/project" > "$LOCAL_WORK/session.jsonl"
printf 'round trip\n' > "$LOCAL_WORK/project/a file"
wslpeer push -r windows-test --session "$LOCAL_WORK/session.jsonl" --no-history
winpeer pull
cmp "$LOCAL_WORK/project/a file" "$WORK/windows-project/a file"
# Windows must find the returned session and reverse mapping without --session.
winpeer push wsl-test --no-history
wslpeer pull
key=$(printf '%s' "$LOCAL_WORK/project" | sed 's/[^A-Za-z0-9]/-/g')
test -f "$LOCAL_WORK/config/projects/$key/session.jsonl"
# Inspect the Windows transcript to confirm its cwd really uses escaped native
# backslashes rather than only passing the format-independent UUID comparison.
cat > "$WORK/check-windows.sh" <<'CHECK'
#!/bin/sh
set -eu
root=$1
key=$(printf '%s' "$root/windows-project" | sed 's/[^A-Za-z0-9]/-/g')
native=$(cygpath -aw "$root/windows-project")
EXPECTED_CWD=$native awk '
    BEGIN {
        raw=ENVIRON["EXPECTED_CWD"]
        for(i=1;i<=length(raw);i++) {
            c=substr(raw,i,1); if(c=="\\") expected=expected "\\"; expected=expected c
        }
    }
    index($0,expected) {found=1} END {exit !found}
' "$root/windows-config/projects/$key/session.jsonl"
CHECK
"$WIN_BASH" --noprofile --norc "$WIN_ROOT/check-windows.sh" "$WIN_ROOT"
printf 'real WSL/Windows host filesystem round trip passed\n'
