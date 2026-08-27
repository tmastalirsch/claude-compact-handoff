#!/usr/bin/env bash
# Tests for the pure logic. No hooks, no Claude, no network.
cd "$(dirname "$0")"; source ./lib/handoff.sh
fail=0

t() { # t <description> <expected> <command...>
  local desc="$1" want="$2"; shift 2
  local got; got=$("$@")
  if [[ "$got" == "$want" ]]; then echo "ok   $desc"
  else echo "FAIL $desc"; echo "       want '$want'"; echo "        got '$got'"; fail=1; fi
}

# needs_note <used> <threshold> <note_ts> <note_used> <now> <max_age> <max_drift>
NOW=1000000; THR=150000; AGE=3600; DRIFT=50000
echo "── needs_note: below the threshold nothing is needed"
t "far below"                "no"  needs_note 40000  $THR ""      ""     $NOW $AGE $DRIFT
t "just below"               "no"  needs_note 149999 $THR ""      ""     $NOW $AGE $DRIFT

echo "── needs_note: above the threshold without a note"
t "at the threshold"         "yes" needs_note 150000 $THR ""      ""     $NOW $AGE $DRIFT
t "well above"               "yes" needs_note 400000 $THR ""      ""     $NOW $AGE $DRIFT

echo "── needs_note: an existing note can be good enough"
t "recent, little drift"     "no"  needs_note 160000 $THR 999000 155000 $NOW $AGE $DRIFT
t "same second, no drift"    "no"  needs_note 150000 $THR 1000000 150000 $NOW $AGE $DRIFT
t "age exactly at the cap"   "no"  needs_note 160000 $THR 996400 155000 $NOW $AGE $DRIFT
t "one second too old"       "yes" needs_note 160000 $THR 996399 155000 $NOW $AGE $DRIFT
t "drift exactly at the cap" "no"  needs_note 205000 $THR 999000 155000 $NOW $AGE $DRIFT
t "one token too much drift" "yes" needs_note 205001 $THR 999000 155000 $NOW $AGE $DRIFT
t "note from the future"     "no"  needs_note 160000 $THR 1000500 155000 $NOW $AGE $DRIFT

echo "── needs_note: rubbish never triggers action"
t "used is text"             "no"  needs_note abc    $THR ""      ""     $NOW $AGE $DRIFT
t "used is empty"            "no"  needs_note ""     $THR ""      ""     $NOW $AGE $DRIFT
t "note_ts is text"          "yes" needs_note 400000 $THR xyz     155000 $NOW $AGE $DRIFT

echo "── used_tokens_from_transcript: the last usage record wins"
t "sums the four fields"     "81596" used_tokens_from_transcript fixtures/transcript.jsonl
t "broken file"              ""      used_tokens_from_transcript fixtures/transcript-broken.jsonl
t "no usage record"          ""      used_tokens_from_transcript fixtures/transcript-no-usage.jsonl
t "missing file"             ""      used_tokens_from_transcript fixtures/does-not-exist.jsonl

echo "── fmt_duration"
t "zero"                     "0s"      fmt_duration 0
t "seconds"                  "45s"     fmt_duration 45
t "one minute"               "1m"      fmt_duration 90
t "minutes"                  "59m"     fmt_duration 3599
t "exactly one hour"         "1h"      fmt_duration 3600
t "hours and minutes"        "2h 13m"  fmt_duration 8000
t "whole hours"              "2h"      fmt_duration 7200
t "rubbish"                  ""        fmt_duration abc

echo "── fmt_tokens"
t "below 1k"                 "820"   fmt_tokens 820
t "thousands"                "82k"   fmt_tokens 81596
t "millions"                 "1.2M"  fmt_tokens 1234000
t "rubbish"                  ""      fmt_tokens abc

echo "── slug_for: basename plus a path hash, so equal names don't collide"
t "project directory"        "demo-app-b08912"  slug_for /Users/dev/projects/demo-app
t "trailing slash ignored"   "demo-app-b08912"  slug_for /Users/dev/projects/demo-app/
t "root"                     "root-42099b"      slug_for /
t "empty"                    "unknown"          slug_for ""

echo "── parse_note_name: epoch and token count live in the file name"
t "auto note"        "1787762345 81596"  parse_note_name 1787762345-auto-81596.md
t "agent note"       "1787762345 83000"  parse_note_name 1787762345-agent-83000.md
t "zero tokens"      "1787762345 0"      parse_note_name 1787762345-agent-0.md
t "full path works"  "1787762345 81596"  parse_note_name /a/b/1787762345-auto-81596.md
t "latest.md"        ""                  parse_note_name latest.md
t "unknown kind"     ""                  parse_note_name 1787762345-other-5.md
t "not a note"       ""                  parse_note_name garbage
t "empty"            ""                  parse_note_name ""

echo "── cap_lines <max>: truncates and says how much was dropped"
cap() { printf '%s' "$1" | cap_lines "$2"; }   # same shell, so the function is in scope
t "under the cap"  "$(printf 'a\nb')"                 cap "$(printf 'a\nb\n')" 3
t "at the cap"     "$(printf 'a\nb\nc')"              cap "$(printf 'a\nb\nc\n')" 3
t "over the cap"   "$(printf 'a\nb\nc\n… (2 more)')"  cap "$(printf 'a\nb\nc\nd\ne\n')" 3
t "empty input"    ""                                  cap "" 3

if (( fail )); then echo; echo "FAILED"; else echo; echo "all tests green"; fi
exit $fail
