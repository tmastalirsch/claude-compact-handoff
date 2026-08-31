#!/usr/bin/env bash
# UserPromptSubmit: the cheap check before work starts. Reads only files, makes
# no model call, and stays silent unless a handoff is actually missing or stale.
# Advisory wording on purpose — get-shit-done removed its imperative phrasing
# after issue #884 because hook orders override what the user wanted.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/lib/handoff.sh" 2>/dev/null || exit 0
source "$HERE/lib/env.sh" 2>/dev/null || exit 0

parsed="$(read_payload)" || exit 0
[[ -n "$parsed" ]] || exit 0
{ read -r SID; read -r CWD; read -r TRANSCRIPT; } <<< "$parsed"

SLUG="$(slug_for "$CWD")"
record_session_slug "$SID" "$SLUG"

used="$(used_tokens_from_transcript "$TRANSCRIPT")"
[[ -n "$used" ]] || exit 0
dir="$HANDOFF_DIR/$SLUG"
note="$(newest_note "$dir" agent)"
note_ts=""; note_used=""
[[ -n "$note" ]] && read -r note_ts note_used <<< "$(parse_note_name "$note")"

now="$(date +%s)"
[[ "$(needs_note "$used" "$HANDOFF_TOKEN_THRESHOLD" "$note_ts" "$note_used" \
      "$now" "$HANDOFF_MAX_AGE" "$HANDOFF_MAX_DRIFT")" == yes ]] || exit 0

age=""
[[ "$note_ts" =~ ^[0-9]+$ ]] && age=" The newest one is $(fmt_duration $(( now - note_ts ))) old."
emit_context UserPromptSubmit \
  "Context handoff: $(fmt_tokens "$used") in context and no fresh handoff on disk.$age Consider writing one with the compact-handoff skill before starting large work, so a compaction cannot lose the reasoning."
exit 0
