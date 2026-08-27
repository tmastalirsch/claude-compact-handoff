#!/usr/bin/env bash
# Stop: the write moment. The turn is finished, nothing is in flight — the one
# safe point to ask for a note. Respects stop_hook_active, Claude Code's own
# loop guard, so this can never spin.
# Note: an interrupted turn fires no Stop hook at all (verified), which is why
# nothing here records state. The next UserPromptSubmit catches up instead.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/lib/handoff.sh" 2>/dev/null || exit 0
source "$HERE/lib/env.sh" 2>/dev/null || exit 0

parsed="$(read_payload)" || exit 0
[[ -n "$parsed" ]] || exit 0
{ read -r SID; read -r CWD; read -r TRANSCRIPT; read -r TRIGGER; read -r SOURCE; read -r STOP_ACTIVE; } <<< "$parsed"

shopt -s nocasematch
[[ "$STOP_ACTIVE" == true ]] && exit 0
shopt -u nocasematch

used="$(used_tokens_from_transcript "$TRANSCRIPT")"
[[ -n "$used" ]] || exit 0
dir="$HANDOFF_DIR/$(slug_for "$CWD")"
note="$(newest_note "$dir" agent)"
note_ts=""; note_used=""
[[ -n "$note" ]] && read -r note_ts note_used <<< "$(parse_note_name "$note")"

now="$(date +%s)"
[[ "$(needs_note "$used" "$HANDOFF_TOKEN_THRESHOLD" "$note_ts" "$note_used" \
      "$now" "$HANDOFF_MAX_AGE" "$HANDOFF_MAX_DRIFT")" == yes ]] || exit 0

emit_block "Context is at $(fmt_tokens "$used") with no fresh handoff on disk. Before finishing, write one to $dir/$now-agent-$used.md — use the compact-handoff skill for the structure. Keep the file name exactly as given: the timestamp and token count in it are how the plugin knows the note is current."
exit 0
