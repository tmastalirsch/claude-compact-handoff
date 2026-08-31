#!/usr/bin/env bash
# Configuration, paths and payload reading. Impure by design, kept out of
# handoff.sh so the logic there stays testable without an environment.

HANDOFF_DIR="${HANDOFF_DIR:-$HOME/.local/state/claude-compact-handoff}"
HANDOFF_TOKEN_THRESHOLD="${HANDOFF_TOKEN_THRESHOLD:-150000}"
HANDOFF_MAX_AGE="${HANDOFF_MAX_AGE:-3600}"
HANDOFF_MAX_DRIFT="${HANDOFF_MAX_DRIFT:-50000}"
HANDOFF_KEEP="${HANDOFF_KEEP:-20}"
HANDOFF_MAX_FILES="${HANDOFF_MAX_FILES:-40}"

# read_payload — stdin JSON to seven lines: session_id, cwd, transcript_path,
# trigger, source, stop_hook_active, last_assistant_message.
# Field names verified against Claude Code 2.1.231 by running real hooks; the
# published docs name PreCompact's field "compact_reason", the binary uses "trigger".
read_payload() {
  python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    if not isinstance(d, dict): raise ValueError
except Exception:
    sys.exit(1)
def g(k):
    v = d.get(k)
    return "" if v is None else str(v).replace("\n", " ").replace("\r", " ")
print("\n".join(g(k) for k in ("session_id", "cwd", "transcript_path",
      "trigger", "source", "stop_hook_active", "last_assistant_message")))
' 2>/dev/null
}

# emit_context <hook_event_name> <text> — additionalContext output for hooks
# that support it (verified: UserPromptSubmit and SessionStart both do, even
# though the docs list only the tool hooks).
emit_context() {
  python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": sys.argv[1], "additionalContext": sys.argv[2]}}))' "$1" "$2"
}

# emit_block <reason> — sends the model back to work at a turn boundary.
emit_block() {
  python3 -c '
import json, sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}))' "$1"
}

# record_session_slug <session_id> <slug> — pointer from a session id to its
# handoff directory name. Consumers that know only the session id cannot derive
# it: the status line reports the git root, while hooks see the actual cwd, and
# in a git worktree those are different directories.
record_session_slug() {
  local sid="$1" slug="$2"
  [[ -n "$sid" && -n "$slug" ]] || return 0
  mkdir -p "$HANDOFF_DIR/.by-session" 2>/dev/null || return 0
  printf '%s' "$slug" > "$HANDOFF_DIR/.by-session/$sid" 2>/dev/null
  return 0
}

# newest_note <dir> <auto|agent|any> — path of the newest matching note.
newest_note() {
  local dir="$1" kind="${2:-any}" pat
  [[ -d "$dir" ]] || return 0
  case "$kind" in
    auto|agent) pat="-$kind-" ;;
    *)          pat="-" ;;
  esac
  local f best=""
  for f in "$dir"/[0-9]*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == *"$pat"* ]] || continue
    [[ -z "$best" || "$(basename "$f")" > "$(basename "$best")" ]] && best="$f"
  done
  [[ -n "$best" ]] && printf '%s' "$best"
  return 0
}
