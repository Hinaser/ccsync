#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
mkdir -p "$WORK/send" "$WORK/receive" "$WORK/inbox" "$WORK/source/src/empty" "$WORK/dest"
cat > "$WORK/tailscale" <<'EOF'
#!/bin/sh
case $1 in
    status) printf '100.0.0.1 sender user linux -\n100.0.0.2 receiver user linux -\n' ;;
    file) [ "$2" != cp ] || cp "$3" "$INBOX/" ;;
esac
EOF
chmod +x "$WORK/tailscale"
export CCSYNC_TAILSCALE=$WORK/tailscale INBOX=$WORK/inbox
printf '{"uuid":"one","cwd":"%s"}\n' "$WORK/source" > "$WORK/session.jsonl"
printf 'hello\n' > "$WORK/source/src/a file"
printf 'hidden\n' > "$WORK/source/src/.hidden"
printf '#!/bin/sh\n' > "$WORK/source/run"
chmod +x "$WORK/source/run"
push() (
    cd "$WORK/source"
    CLAUDE_CONFIG_DIR=$WORK/send "$ROOT/bin/ccsync" push "receiver:$WORK/dest" \
        --session "$WORK/session.jsonl" --no-history "$@"
)
pull() {
    CLAUDE_CONFIG_DIR=$WORK/receive "$ROOT/bin/ccsync" pull --source "$INBOX" "$@"
}
key=$(printf '%s' "$WORK/dest" | sed 's/[^A-Za-z0-9]/-/g')
transcript=$WORK/receive/projects/$key/session.jsonl
push -r
pull
cmp "$WORK/source/src/a file" "$WORK/dest/src/a file"
cmp "$WORK/source/src/.hidden" "$WORK/dest/src/.hidden"
test -d "$WORK/dest/src/empty"
test -x "$WORK/dest/run"
test -f "$transcript"

# An identical transcript must still carry newly included files.
printf 'new\n' > "$WORK/source/new"
push -r
pull
cmp "$WORK/source/new" "$WORK/dest/new"

# Preflight the whole tree: no additions or transcript updates on conflict.
printf 'local work\n' > "$WORK/dest/src/a file"
printf 'addition\n' > "$WORK/source/src/aaa"
printf '{"uuid":"two","cwd":"%s"}\n' "$WORK/source" >> "$WORK/session.jsonl"
push -r
pull --force
test ! -e "$WORK/dest/src/aaa"
test "$(cat "$WORK/dest/src/a file")" = 'local work'
test "$(wc -l < "$transcript" | tr -d ' ')" = 1
test -n "$(ls "$WORK/receive/ccsync/conflicts/"sess_*.tar.gz)"

# A new directory is created only through an explicit local destination.
push -r
pull "$WORK/new project"
cmp "$WORK/source/src/a file" "$WORK/new project/src/a file"
test -d "$WORK/new project/src/empty"

# SSH-style destinations, recursive transfer, and remembered destinations.
short_push() (
    cd "$WORK/source"
    CLAUDE_CONFIG_DIR=$WORK/send "$ROOT/bin/ccsync" push \
        --session "$WORK/session.jsonl" --no-history "$@"
)
short_push -r "receiver:$WORK/short destination"
pull "$WORK/short destination"
cmp "$WORK/source/run" "$WORK/short destination/run"
printf 'remembered\n' > "$WORK/source/remembered"
short_push -r receiver
pull "$WORK/short destination"
cmp "$WORK/source/remembered" "$WORK/short destination/remembered"
short_push -r
pull "$WORK/short destination"
short_push "receiver:$WORK/dest"
pull "$WORK/dest"
if short_push receiver "$WORK/dest"; then exit 1; fi
if short_push "receiver:$WORK/dest" --to "$WORK/other"; then exit 1; fi
if short_push "receiver:"; then exit 1; fi
if short_push ":$WORK/dest"; then exit 1; fi
if short_push --to; then exit 1; fi

# Removed flags are rejected, rather than retained as aliases.
if short_push receiver --to "$WORK/dest"; then exit 1; fi
if short_push receiver --include .; then exit 1; fi

# Reject sender symlinks when recursively transferring the project.
ln -s "$WORK/source/src" "$WORK/source/link"
if push -r; then exit 1; fi
rm "$WORK/source/link"

# A receiver symlink cannot redirect project writes outside the destination.
mkdir "$WORK/linked" "$WORK/outside"
ln -s "$WORK/outside" "$WORK/linked/src"
push -r
pull "$WORK/linked"
test ! -e "$WORK/outside/aaa"

# Legacy session-only bundles still work, and stale transcripts add no files.
push
pull "$WORK/dest"
test "$(wc -l < "$transcript" | tr -d ' ')" = 2
printf '{"uuid":"three","cwd":"%s"}\n' "$WORK/dest" >> "$transcript"
printf 'stale\n' > "$WORK/source/stale"
push -r
pull "$WORK/dest"
test ! -e "$WORK/dest/stale"

# Unsupported archive links are rejected before extraction.
mkdir "$WORK/bad"
ln -s "$WORK/outside" "$WORK/bad/project"
tar -czf "$INBOX/sess_bad.tar.gz" -C "$WORK/bad" project
pull
test -f "$WORK/receive/ccsync/conflicts/sess_bad.tar.gz"
# Pull accepts one positional destination and rejects the removed flag.
if pull --into "$WORK/dest"; then exit 1; fi
if pull "$WORK/dest" "$WORK/other"; then exit 1; fi
if pull "receiver:$WORK/dest"; then exit 1; fi
printf 'project transfer tests passed\n'
