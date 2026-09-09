#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
# Exercise path handling without requiring a Windows runner. cygpath itself is
# a platform dependency, not emulated here; these cases cover the map and JSON
# formats that Windows produces.
awk '/^# ---.* main$/ {exit} {print}' "$ROOT/bin/ccsync" > "$WORK/library"
(
    export CLAUDE_CONFIG_DIR="$WORK/config"
    . "$WORK/library"
    load_config || exit 1
    test "$(abs_path .)" = "$PWD"
    test "$(normalize_path 'c:\Users\A Project\')" = 'C:/Users/A Project'
    test "$(normalize_path '\\server\share\folder')" = '//server/share/folder'
    test "$(normalize_path C:/)" = 'C:/'
    test "$(normalize_path /)" = '/'
    IS_WINDOWS=1
    mkdir -p "$STATE"
    # Read old Git Bash local keys and native remote keys, preserving spaces.
    printf 'path\tpeer\t/c/Users/A Project\tD:\\Work\\Remote\n' > "$MAP"
    test "$(map_remote_for peer 'C:\Users\A Project')" = 'D:\Work\Remote'
    test "$(map_local_for peer 'd:/work/remote/')" = '/c/Users/A Project'
    map_set path peer 'C:/Users/A Project' 'D:/Work/Updated'
    test "$(map_remote_for peer '/c/Users/A Project')" = 'D:/Work/Updated'
    test "$(wc -l < "$MAP" | tr -d ' ')" = 1
    cmd_unmap peer 'C:/Users/A Project'
    test -z "$(map_remote_for peer 'C:/Users/A Project')"
    IS_WINDOWS=0
    map_set path peer /tmp/Project /remote/Project
    test -z "$(map_remote_for peer /tmp/project)"
    test "$(map_remote_for peer /tmp/Project)" = /remote/Project
    # Native and forward-slash cwd fields, whitespace, JSON quoting, and tool
    # text: only matching cwd fields change, other text remains untouched.
    cat > "$WORK/windows.jsonl" <<'JSON'
{"uuid":"one","cwd":"C:\\Users\\A Project","text":"C:\\Users\\A Project"}
{"uuid":"two", "cwd" : "c:/Users/A Project"}
{"uuid":"three","cwd":"/c/Users/A Project"}
{"uuid":"four","cwd":"D:/Other"}
JSON
    rewrite_jsonl "$WORK/windows.jsonl" "$WORK/linux.jsonl" 'C:/Users/A Project' '/home/a/Project' 0 > "$WORK/counts"
    test "$(cat "$WORK/counts")" = '4 3'
    cat > "$WORK/expected.jsonl" <<'JSON'
{"uuid":"one","cwd":"/home/a/Project","text":"C:\\Users\\A Project"}
{"uuid":"two", "cwd" : "/home/a/Project"}
{"uuid":"three","cwd":"/home/a/Project"}
{"uuid":"four","cwd":"D:/Other"}
JSON
    cmp "$WORK/linux.jsonl" "$WORK/expected.jsonl"
    rewrite_jsonl "$WORK/linux.jsonl" "$WORK/returned.jsonl" '/home/a/Project' 'C:\Users\A Project' 0 > /dev/null
    awk 'NR<=3 && index($0,"C:\\\\Users\\\\A Project")==0 {exit 1}' "$WORK/returned.jsonl"
    printf '{"cwd":"/home/a/quoted","text":"/home/a/quoted"}\n' > "$WORK/quoted.jsonl"
    rewrite_jsonl "$WORK/quoted.jsonl" "$WORK/quoted-out.jsonl" '/home/a/quoted' '/home/a/"quoted"' 1 > /dev/null
    printf '{"cwd":"/home/a/\\"quoted\\"","text":"/home/a/\\"quoted\\""}\n' > "$WORK/quoted-expected.jsonl"
    cmp "$WORK/quoted-out.jsonl" "$WORK/quoted-expected.jsonl"
    # Only a correlated probe reply may change a saved peer name.
    map_set path old-name /tmp/local /tmp/remote
    map_set host old-name transport filesystem
    map_set host old-name share '/some share'
    map_set host old-name probe_id expected-probe
    {
        mf_put origin_host registered-name
        mf_put requested_host old-name
        mf_put probe_id wrong-probe
        mf_put path_exists yes
    } > "$WORK/ack"
    RECEIVE_ROUTE=0
    handle_ack "$WORK/ack"
    test "$(map_remote_for old-name /tmp/local)" = /tmp/remote
    sed 's/wrong-probe/expected-probe/' "$WORK/ack" > "$WORK/correct-ack"
    handle_ack "$WORK/correct-ack"
    test -z "$(map_remote_for old-name /tmp/local)"
    test "$(map_remote_for registered-name /tmp/local)" = /tmp/remote
    test "$(map_get host registered-name share)" = '/some share'
    test -n "$(map_get host registered-name verified)"
    # Old receivers can still acknowledge without the new optional fields.
    printf 'origin_host\tlegacy\npath_exists\tyes\n' > "$WORK/legacy-ack"
    handle_ack "$WORK/legacy-ack"
    test -n "$(map_get host legacy verified)"
)
printf 'Windows path and pairing tests passed\n'
