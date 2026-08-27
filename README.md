# Compact Handoff

A Claude Code plugin that makes sure a context compaction never takes your state
with it.

When the context window fills up, Claude summarises its own history to make room.
The summary keeps roughly what was said and reliably loses **why** things were
decided and **what was already ruled out**. Afterwards you see Claude re-reading
files it had already read, or proposing an approach it had itself rejected.

This plugin does three things at three different moments:

| Moment | Hook | What happens |
|---|---|---|
| Before work starts | `UserPromptSubmit` | If the context is large and no fresh handoff exists, a short advisory line goes into the prompt. Reads files only, no model call. |
| End of a turn | `Stop` | The one safe point to ask for a reasoned note — the turn is done, nothing is in flight. Asks once, never loops. |
| The instant of compaction | `PreCompact` | Writes a mechanical handoff from facts already on disk. No model involved, so it cannot be wrong, slow, or skipped. |
| Right after compaction | `SessionStart` (`source=compact`) | Tells the agent where its notes are, so you do not have to. |

The floor is `PreCompact`. Everything else can fail — you interrupt a turn, the
agent ignores the advisory, a compaction arrives unannounced — and you still have
the situation on disk.

## Two kinds of note

```
~/.local/state/claude-compact-handoff/<project>/
  1787817162-agent-37847.md     written by the agent: decisions, dead ends, next action
  1787817236-auto-43301.md      written by the hook:  branch, working tree, diff, tokens
  latest.md                     copy of the newest
```

The epoch and the token count live in the **file name**. Nothing has to maintain a
metadata file that way — which matters, because an interrupted turn fires no hook
that could have updated one.

`-auto-` notes tell you the situation. `-agent-` notes tell you the reasoning. The
mechanical note points at the reasoned one when it exists.

## Installation

```bash
git clone https://github.com/tmastalirsch/claude-compact-handoff.git
```

Add it as a plugin (the plugin registers its own hooks — no editing of
`settings.json` required), or point Claude Code at the clone during development.
Verify the manifest at any time with:

```bash
claude plugin validate /path/to/claude-compact-handoff
```

**Before you enable it, set `HANDOFF_TOKEN_THRESHOLD` for your context window.** The
default of 150000 tokens suits a 200k window. On a 1M window it fires within the first
hour of work and will keep asking for handoffs — set it to around `750000` instead. See
[Configuration](#configuration).

## Configuration

Environment variables, e.g. in the `env` block of `~/.claude/settings.json`.

| Variable | Default | Meaning |
|---|---|---|
| `HANDOFF_TOKEN_THRESHOLD` | `150000` | Tokens in context above which a note is wanted |
| `HANDOFF_MAX_AGE` | `3600` | A note older than this many seconds is stale |
| `HANDOFF_MAX_DRIFT` | `50000` | A note is stale once the context has grown this many tokens since |
| `HANDOFF_DIR` | `~/.local/state/claude-compact-handoff` | Where notes are kept |
| `HANDOFF_KEEP` | `20` | Notes retained per project |
| `HANDOFF_MAX_FILES` | `40` | Cap on file-list length inside a note |

**Set the threshold to match your context window.** The default suits a 200k
window (150k ≈ 75%). On a 1M window leave it far higher — around `750000` — or the
plugin will ask for handoffs from the first hour of work onwards.

The threshold is in tokens rather than percent on purpose: hooks are never given
context metrics, so the plugin reads the token count from the transcript. A
percentage would need a window size it cannot know, and would be quietly wrong.

## Layout

| File | Purpose |
|---|---|
| `lib/handoff.sh` | pure logic, no IO — `needs_note`, `parse_note_name`, `slug_for`, `cap_lines`, `fmt_duration`, `fmt_tokens` |
| `lib/env.sh` | configuration, payload reading, output helpers |
| `hooks/pre-compact.sh` | the mechanical note |
| `hooks/prompt-check.sh` | the advisory before work |
| `hooks/turn-end.sh` | the request at a turn boundary |
| `hooks/after-compact.sh` | the pointer afterwards |
| `skills/write-handoff/SKILL.md` | the structure the agent fills in |

## Tests

```bash
bash test.sh          # every suite
bash test-lib.sh      # pure logic, no hooks, no Claude
bash test-hooks.sh    # synthetic payloads -> stdout JSON + files, in a throwaway git repo
```

78 assertions. The suites are portable: no absolute home paths in fixtures.

## Hook facts, measured rather than read

These were established by registering real hooks and running real sessions against
Claude Code 2.1.231. Two of them contradict the published documentation, and both
would have caused silent bugs.

- **`PreCompact` names its field `trigger`, not `compact_reason`.** The documented
  name appears nowhere in the binary. Values are `manual` and `auto`.
- **An interrupted turn fires no completion hook at all.** Not `Stop`, not
  `StopFailure`, not `Notification`. A control run in the same pane confirmed `Stop`
  fires normally when a turn completes. Consequence: never store "we already asked"
  — derive state from the artifact instead.
- **`UserPromptSubmit` and `SessionStart` do support `additionalContext`**, though
  the docs list only the tool hooks. Verified by injection: the model answered from
  injected text it could not otherwise have known.
- **`Stop` can return `{"decision":"block","reason":...}`** and the model acts on the
  reason. `stop_hook_active` is Claude Code's own loop guard — this plugin respects
  it rather than inventing its own.
- **`SessionStart` reports `source` as `startup`, `resume`, `clear` or `compact`.**
  The `compact` value is what closes the loop after a compaction.

## Worktrees

A git worktree gets its own note directory, keyed by its own path. That is
deliberate: parallel worktrees are parallel work, and pooling their handoffs would
let a note from one line of work make another look freshly handed off. The
mechanical note records `Worktree of: <main repo>` so a note is still identifiable
once the worktree is gone.

Consequence worth knowing: a session running inside `<repo>/.worktrees/feature-x`
writes to `.../feature-x-<hash>/`, not to a directory named after the repo.

## Limitations

- The token count comes from the newest `usage` record in the transcript. Very early
  in a session there may be none yet, in which case the context-gated hooks stay
  quiet — the next turn catches up.
- `PreCompact` cannot preserve context, only record it. Nothing can: the hook runs
  before the summary is built and has no way to influence it.
- The reasoned note depends on the agent cooperating. That is why the mechanical one
  exists.
- Blocking a turn costs tokens, because the model keeps working to write the note.
  It happens once per fill, above the threshold only.

## Prior art

The idea of warning the agent rather than the user comes from
[get-shit-done](https://github.com/gsd-build/get-shit-done), whose context monitor
makes the point plainly: the status line shows usage to the user, while the agent has
no awareness of its own limits. Its handoff structure — decisions with rationale,
anti-patterns discovered through actual failure rather than predicted — shaped the
skill in this plugin.

Where this plugin differs: it hooks the moment of compaction rather than only
warning ahead of it, so an unattended or unannounced compaction still leaves a
record; and it needs no project methodology to be useful.

## License

MIT — see [LICENSE](LICENSE).
