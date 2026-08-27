#!/usr/bin/env bash
# PreCompact: the floor. Writes a mechanical handoff at the exact moment of
# compaction, from facts already on disk — no model involved, so it cannot be
# wrong, slow, or skipped. Exits 0 under all circumstances: a hook that blocks
# compaction would be worse than no handoff at all.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/lib/handoff.sh" 2>/dev/null || exit 0
source "$HERE/lib/env.sh" 2>/dev/null || exit 0

parsed="$(read_payload)" || exit 0
[[ -n "$parsed" ]] || exit 0
{ read -r SID; read -r CWD; read -r TRANSCRIPT; read -r TRIGGER; } <<< "$parsed"
[[ -n "$CWD" ]] || exit 0

used="$(used_tokens_from_transcript "$TRANSCRIPT")"
[[ -n "$used" ]] || used=0
now="$(date +%s)"
dir="$HANDOFF_DIR/$(slug_for "$CWD")"
mkdir -p "$dir" 2>/dev/null || exit 0
file="$dir/$now-auto-$used.md"

branch="$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null)"
[[ -n "$branch" ]] || branch="(not a git repository)"
status="$(git -C "$CWD" status --porcelain 2>/dev/null | cap_lines "$HANDOFF_MAX_FILES")"
diffstat="$(git -C "$CWD" diff --stat 2>/dev/null | cap_lines "$HANDOFF_MAX_FILES")"

{
  printf '# Handoff (mechanical)\n\n'
  printf -- '- When: %s\n' "$(date -u '+%Y-%m-%d %H:%M:%SZ')"
  printf -- '- Compaction trigger: %s\n' "${TRIGGER:-unknown}"
  printf -- '- Session: %s\n' "${SID:-unknown}"
  printf -- '- Directory: %s\n' "$CWD"
  printf -- '- Branch: %s\n' "$branch"
  printf -- '- Tokens in context: %s (%s)\n' "$used" "$(fmt_tokens "$used")"
  printf -- '- Transcript: %s\n' "${TRANSCRIPT:-unknown}"
  printf '\n## Working tree\n\n'
  if [[ -n "$status" ]]; then printf '```\n%s\n```\n' "$status"; else printf 'clean\n'; fi
  printf '\n## Diff stat\n\n'
  if [[ -n "$diffstat" ]]; then printf '```\n%s\n```\n' "$diffstat"; else printf 'no unstaged changes\n'; fi
  printf '\n---\n\nWritten automatically before compaction. It records the situation, not the\nreasoning — for decisions and rationale see the newest `-agent-` note, if one exists.\n'
} > "$file" 2>/dev/null || exit 0

cp -f "$file" "$dir/latest.md" 2>/dev/null

# Prune: keep the newest HANDOFF_KEEP notes, drop the rest.
if [[ "$HANDOFF_KEEP" =~ ^[0-9]+$ ]] && (( HANDOFF_KEEP > 0 )); then
  ls -1 "$dir"/[0-9]*.md 2>/dev/null | sort -r | tail -n +$(( HANDOFF_KEEP + 1 )) \
    | while IFS= read -r old; do rm -f "$old" 2>/dev/null; done
fi
exit 0
