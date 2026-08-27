#!/usr/bin/env bash
# SessionStart with source=compact: closes the loop. Verified that Claude Code
# reports source values startup|resume|clear|compact, and that SessionStart can
# inject context — so the agent learns where its own notes are without the user
# having to run anything.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/lib/handoff.sh" 2>/dev/null || exit 0
source "$HERE/lib/env.sh" 2>/dev/null || exit 0

parsed="$(read_payload)" || exit 0
[[ -n "$parsed" ]] || exit 0
{ read -r SID; read -r CWD; read -r TRANSCRIPT; read -r TRIGGER; read -r SOURCE; } <<< "$parsed"
[[ "$SOURCE" == "compact" ]] || exit 0

dir="$HANDOFF_DIR/$(slug_for "$CWD")"
newest="$(newest_note "$dir" any)"
[[ -n "$newest" ]] || exit 0

agent="$(newest_note "$dir" agent)"
extra=""
[[ -n "$agent" ]] && extra=" A note written by the agent is at $agent — prefer that one, it carries the reasoning."
emit_context SessionStart \
  "This context was just compacted, so earlier detail may be missing. A handoff written at the moment of compaction is at $dir/latest.md.$extra Read it before continuing work that depends on what happened earlier."
exit 0
