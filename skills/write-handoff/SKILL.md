---
name: write-handoff
description: Write a reasoned handoff note before the context window is compacted, so the decisions and dead ends survive what a summary would drop. Use when a hook reports that no fresh handoff exists, when the user asks for a handoff or to pause work, or before deliberately running /compact or /clear during unfinished work.
---

# Write a handoff note

A compaction replaces the conversation with a summary. The summary keeps roughly
what was said; it reliably loses **why** things were decided and **what was already
ruled out**. This note is the part worth keeping.

A companion hook already writes the mechanical facts — branch, diff, changed files,
token count — at the moment of compaction. Do not repeat them. Write the reasoning.

## Where to write it

The hook that asked for this note names the exact path, in the form:

```
<state dir>/<project>/<epoch>-agent-<tokens>.md
```

**Use that name unchanged.** The timestamp and token count in the file name are how
the plugin knows whether the note is still current — a renamed file is invisible to it.

If you are writing without being asked, get the values yourself: `date +%s` for the
epoch, and the token count from the newest `-auto-` note in the same directory (or `0`
if there is none).

## What to write

Fill in only the sections you can answer honestly. An empty section is information; a
guessed one is a trap for whoever reads this next.

```markdown
# Handoff (reasoned)

## Task
What is being worked on, in two or three sentences. Enough for a reader with no
memory of the conversation.

## Done
What is actually finished and verified. Say how it was verified.

## Remaining
What is left, in the order it should be done.

## Decisions
- Chose X over Y because Z.
Each entry needs the reason. A decision without its rationale gets re-litigated.

## Ruled out
- Tried A, it failed because B.
Only things actually attempted and observed to fail. Not predictions, not concerns —
those belong in Risks. This section is what stops the next attempt repeating your work.

## Blockers
Anything stuck, and what it is waiting for. Mark whichever need a human.

## Environment
Running servers, watchers, background tasks, external state that is not in git.

## Read first
Files and documents the next reader must open, in order, each with one line on why.

## Next action
The single concrete first step on resuming. Not a goal — an action.
```

## Rules

- **Be specific enough for a reader with no memory.** "Fixed the bug" is worthless;
  "fixed the off-by-one in `render_bar` that dropped the last segment" survives.
- **Never invent.** If you do not know whether something was verified, say it was not.
- **Do not touch the `-auto-` notes.** They are the mechanical record; overwriting one
  destroys evidence of what the situation was.
- **Keep it short enough to be read.** Aim for something a person scans in a minute.
