#!/usr/bin/env bash
# Tests for the four hooks: synthetic payload on stdin -> stdout JSON + files on disk.
# No live Claude session involved; a throwaway git repo stands in for the project.
cd "$(dirname "$0")"; ROOT="$PWD"
fail=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HANDOFF_DIR="$TMP/state"
export HANDOFF_TOKEN_THRESHOLD=50000 HANDOFF_MAX_AGE=3600 HANDOFF_MAX_DRIFT=50000 HANDOFF_KEEP=3

PROJ="$TMP/demo"; mkdir -p "$PROJ"
git -C "$PROJ" init -q -b main
git -C "$PROJ" config user.email t@e.st; git -C "$PROJ" config user.name Test
printf 'one\n' > "$PROJ/tracked.txt"
git -C "$PROJ" add -A && git -C "$PROJ" commit -qm "initial"
printf 'one\ntwo\n' > "$PROJ/tracked.txt"      # modified, uncommitted
printf 'new\n' > "$PROJ/untracked.txt"          # untracked
TRANSCRIPT="$ROOT/fixtures/transcript.jsonl"    # newest usage record = 81596 tokens

t() { if [[ "$3" == "$2" ]]; then echo "ok   $1"
      else echo "FAIL $1"; echo "       want '$2'"; echo "        got '$3'"; fail=1; fi; }

has() { # has <description> <needle> <haystack>
  if [[ "$3" == *"$2"* ]]; then echo "ok   $1"
  else echo "FAIL $1"; echo "       '$2' not found in: ${3:0:160}"; fail=1; fi; }

payload() { # payload <event> [extra json pairs...]
  python3 -c '
import json, sys
d = {"hook_event_name": sys.argv[1], "session_id": "sess-1",
     "cwd": sys.argv[2], "transcript_path": sys.argv[3]}
for pair in sys.argv[4:]:
    k, v = pair.split("=", 1)
    d[k] = json.loads(v) if v[:1] in "{[tf0123456789\"" else v
print(json.dumps(d))' "$1" "$PROJ" "$TRANSCRIPT" "${@:2}"
}

field() { python3 -c '
import json, sys
try: d = json.loads(sys.stdin.read())
except Exception: print(""); raise SystemExit
for k in sys.argv[1].split("."):
    d = (d or {}).get(k) if isinstance(d, dict) else None
print("" if d is None else d)' "$1"; }

echo "── PreCompact writes the mechanical note, whatever else happens"
out="$(payload PreCompact 'trigger="manual"' | bash hooks/pre-compact.sh)"; rc=$?
t "exits 0"                 "0"    "$rc"
t "prints nothing"          ""     "$out"
NOTE="$(ls "$HANDOFF_DIR"/demo-*/*.md 2>/dev/null | head -1)"
t "a note file exists"      "yes"  "$( [[ -n "$NOTE" ]] && echo yes || echo no )"
body="$(cat "$NOTE" 2>/dev/null)"
has "records the trigger"        "manual"        "$body"
has "records the branch"         "main"          "$body"
has "records the modified file"  "tracked.txt"   "$body"
has "records the untracked file" "untracked.txt" "$body"
has "records the token count"    "81596"         "$body"
has "records the transcript"     "transcript.jsonl" "$body"
t "name carries epoch and tokens" "81596" \
  "$(bash -c "source $ROOT/lib/handoff.sh; parse_note_name '$NOTE'" | cut -d' ' -f2)"
t "name marks it as auto"   "yes"    "$( [[ "$(basename "$NOTE")" == *-auto-* ]] && echo yes || echo no )"
t "latest.md points at it"  "yes"    "$( [[ -f "$(dirname "$NOTE")/latest.md" ]] && echo yes || echo no )"

echo "── PreCompact records the main repo when the cwd is a worktree"
WT="$TMP/wt"; git -C "$PROJ" worktree add -q -b side "$WT" 2>/dev/null
out="$(payload PreCompact 'trigger="auto"' | sed "s|\"cwd\": \"$PROJ\"|\"cwd\": \"$WT\"|" | bash hooks/pre-compact.sh)"
WNOTE="$(ls "$HANDOFF_DIR"/wt-*/[0-9]*.md 2>/dev/null | head -1)"
wbody="$(cat "$WNOTE" 2>/dev/null)"
has "names the worktree branch" "side"        "$wbody"
has "names the main repo"       "Worktree of" "$wbody"
has "gives the repo path"       "demo"        "$wbody"

echo "── PreCompact never breaks compaction"
t "garbage stdin exits 0"   "0"  "$(echo 'not json' | bash hooks/pre-compact.sh >/dev/null 2>&1; echo $?)"
t "empty stdin exits 0"     "0"  "$(printf '' | bash hooks/pre-compact.sh >/dev/null 2>&1; echo $?)"
t "no git repo exits 0"     "0"  "$(payload PreCompact 'trigger="auto"' | sed "s|$PROJ|$TMP|" | bash hooks/pre-compact.sh >/dev/null 2>&1; echo $?)"

echo "── PreCompact prunes old notes (HANDOFF_KEEP=3)"
for i in 1 2 3 4 5; do payload PreCompact 'trigger="auto"' | bash hooks/pre-compact.sh >/dev/null 2>&1; sleep 1; done
t "keeps only 3"  "3"  "$(ls "$HANDOFF_DIR"/demo-*/[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')"

echo "── UserPromptSubmit: the cheap check before work starts"
rm -rf "$HANDOFF_DIR"
out="$(payload UserPromptSubmit 'prompt="do a thing"' | bash hooks/prompt-check.sh)"
t "event name"  "UserPromptSubmit"  "$(printf '%s' "$out" | field hookSpecificOutput.hookEventName)"
has "mentions the missing handoff" "no fresh handoff" "$(printf '%s' "$out" | field hookSpecificOutput.additionalContext)"
has "advisory, not an order"       "Consider"         "$(printf '%s' "$out" | field hookSpecificOutput.additionalContext)"

t "quiet below the threshold" "" \
  "$(HANDOFF_TOKEN_THRESHOLD=900000 payload UserPromptSubmit | HANDOFF_TOKEN_THRESHOLD=900000 bash hooks/prompt-check.sh)"

SLUGDIR="$HANDOFF_DIR/$(bash -c "source $ROOT/lib/handoff.sh; slug_for '$PROJ'")"
mkdir -p "$SLUGDIR"
printf 'a fresh agent note\n' > "$SLUGDIR/$(date +%s)-agent-81000.md"
t "quiet when a fresh agent note exists" "" \
  "$(payload UserPromptSubmit | bash hooks/prompt-check.sh)"

echo "── Stop: ask at the turn boundary, never in a loop"
rm -rf "$HANDOFF_DIR"
out="$(payload Stop 'stop_hook_active=false' 'last_assistant_message="did the thing"' | bash hooks/turn-end.sh)"
t "blocks once"  "block"  "$(printf '%s' "$out" | field decision)"
has "names the skill"   "compact-handoff"  "$(printf '%s' "$out" | field reason)"
has "names the target"  "$HANDOFF_DIR"     "$(printf '%s' "$out" | field reason)"
has "says it is not a failure" "not a failure"  "$(printf '%s' "$out" | field reason)"

t "silent when stop_hook_active" "" \
  "$(payload Stop 'stop_hook_active=true' | bash hooks/turn-end.sh)"
t "exits 0 even when blocking"   "0" \
  "$(payload Stop 'stop_hook_active=false' | bash hooks/turn-end.sh >/dev/null 2>&1; echo $?)"

echo "── SessionStart: point at the note only after a compaction"
t "quiet on startup" "" "$(payload SessionStart 'source="startup"' | bash hooks/after-compact.sh)"
t "quiet on resume"  "" "$(payload SessionStart 'source="resume"'  | bash hooks/after-compact.sh)"
payload PreCompact 'trigger="auto"' | bash hooks/pre-compact.sh >/dev/null 2>&1
out="$(payload SessionStart 'source="compact"' | bash hooks/after-compact.sh)"
t "event name"  "SessionStart"  "$(printf '%s' "$out" | field hookSpecificOutput.hookEventName)"
has "says it was compacted" "compacted"   "$(printf '%s' "$out" | field hookSpecificOutput.additionalContext)"
has "gives the path"        "latest.md"   "$(printf '%s' "$out" | field hookSpecificOutput.additionalContext)"
t "quiet when no note exists" "" \
  "$(rm -rf "$HANDOFF_DIR"; payload SessionStart 'source="compact"' | bash hooks/after-compact.sh)"

if (( fail )); then echo; echo "FAILED"; else echo; echo "all tests green"; fi
exit $fail
