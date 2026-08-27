#!/usr/bin/env bash
# Pure logic for the handoff plugin: no hooks, no network, no Claude.
# Everything here is deterministic given its arguments, so it can be tested
# without a running session.

# needs_note <used_tokens> <threshold> <note_ts> <note_used> <now> <max_age> <max_drift>
# Prints "yes" when a fresh handoff should be written, otherwise "no".
#
# State is derived from the artifact, never from whether we asked before: a user
# who interrupts a turn leaves no Stop hook behind, so any "we already asked"
# marker would stick forever with nothing on disk to show for it.
needs_note() {
  local used="$1" thr="$2" note_ts="$3" note_used="$4" now="$5" max_age="$6" max_drift="$7"
  [[ "$used" =~ ^[0-9]+$ && "$thr" =~ ^[0-9]+$ ]] || { printf 'no'; return; }
  (( used < thr )) && { printf 'no'; return; }
  # No readable note metadata at all -> one is needed.
  [[ "$note_ts" =~ ^[0-9]+$ && "$note_used" =~ ^[0-9]+$ ]] || { printf 'yes'; return; }
  local age=$(( now - note_ts ))
  (( age < 0 )) && age=0                  # clock skew: treat as brand new
  (( age > max_age )) && { printf 'yes'; return; }
  local drift=$(( used - note_used ))
  (( drift < 0 )) && drift=0              # context shrank (compaction) — not stale
  (( drift > max_drift )) && { printf 'yes'; return; }
  printf 'no'
}

# used_tokens_from_transcript <path> — tokens held by the newest usage record.
# Hooks never receive context metrics, but they do receive transcript_path.
used_tokens_from_transcript() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  python3 - "$f" 2>/dev/null <<'PY'
import json, sys
last = None
try:
    with open(sys.argv[1]) as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except Exception:
                continue
            u = (d.get("message") or {}).get("usage")
            if isinstance(u, dict):
                last = u
except Exception:
    pass
if last:
    print(sum(int(last.get(k) or 0) for k in (
        "input_tokens", "cache_creation_input_tokens",
        "cache_read_input_tokens", "output_tokens")))
PY
}

# fmt_duration <seconds> — 45s | 1m | 2h | 2h 13m
fmt_duration() {
  local s="$1"
  [[ "$s" =~ ^[0-9]+$ ]] || return 0
  if   (( s < 60 ));   then printf '%ds' "$s"
  elif (( s < 3600 )); then printf '%dm' $(( s / 60 ))
  else
    local h=$(( s / 3600 )) m=$(( (s % 3600) / 60 ))
    if (( m )); then printf '%dh %dm' "$h" "$m"; else printf '%dh' "$h"; fi
  fi
}

# fmt_tokens <tokens> — 820 | 82k | 1.2M
fmt_tokens() {
  local n="$1"
  [[ "$n" =~ ^[0-9]+$ ]] || return 0
  awk -v n="$n" 'BEGIN {
    if      (n >= 1000000) printf "%.1fM", n / 1000000
    else if (n >= 1000)    printf "%dk", int(n / 1000 + 0.5)
    else                   printf "%d", n
  }'
}

# slug_for <path> — basename plus a short path hash, so two projects called
# "api" never share a handoff directory.
slug_for() {
  local p="$1"
  [[ -n "$p" ]] || { printf 'unknown'; return; }
  local clean="${p%/}"
  [[ -z "$clean" ]] && clean="/"
  local base
  if [[ "$clean" == "/" ]]; then base="root"; else base="$(basename "$clean")"; fi
  printf '%s-%s' "$base" "$(printf '%s' "$clean" | shasum | cut -c1-6)"
}

# cap_lines <max> — filter: keep at most <max> lines, then say what was dropped.
# Silent truncation would read as "that was everything".
cap_lines() {
  local max="${1:-10}" n=0 extra=0 line
  local -a keep=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    if (( n < max )); then keep+=("$line"); else (( extra++ )); fi
    (( n++ ))
  done
  (( ${#keep[@]} == 0 )) && return 0
  printf '%s\n' "${keep[@]}"
  (( extra )) && printf '… (%d more)\n' "$extra"
  return 0
}

# parse_note_name <file|basename> — prints "<epoch> <tokens>" for a note file.
# Both facts live in the name so nothing has to maintain a metadata file after
# the agent writes its note; an interrupted turn fires no hook that could.
parse_note_name() {
  local n="${1##*/}"
  [[ "$n" =~ ^([0-9]{9,})-(auto|agent)-([0-9]+)\.md$ ]] || return 0
  printf '%s %s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}"
}
