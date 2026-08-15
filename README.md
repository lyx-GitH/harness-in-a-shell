# Harness in a Shell

```bash
bash ReAct.sh '<prompt>' >> ReAct.sh
```

[中文版](./README.zh-CN.md)

That one shell command is the ReAct loop. In generic form it is
`bash agent.sh '<prompt>' >> agent.sh`: model output goes to stdout, stdout is
appended to the running script, and the same Bash process continues reading and
executing the appended source. There is no explicit `while` loop.

This repository is a research prototype built around three ideas.

## 1. Script as Context

The active Bash script is the agent's complete context. It contains the
governing prompt, runtime identity, tool definitions, user input, observations,
execution tape, continuation, and its own context-editing machinery.

`reason` sends the complete current script to the model. The response is not a
separate chat message: it is future Bash source appended to that script.

```text
# INPUT: user instructions
# OBS:   tool observations
# EXIT:  observed exit status
# <TAPE> live trajectory begins here
```

Because the script is context, changing the SYSTEM prompt, reorganizing memory,
or replacing the reasoning machinery are all ordinary script edits.
`edit_context` performs a structural edit by switching to a complete new script.

## 2. Function as Tool

A Bash function is a tool. The agent may call or redefine an existing function,
author a new one, compose tools from other tools, refine old tools, or derive new
tools through any recursive combination of authoring, composition, and
refinement.

`observe` runs a command or function once in the current shell and records its
output and exit status as inert Bash comments. State changes made by a function,
such as variables or `cd`, remain live. A state-only function may also be called
directly when it produces no unsafe stdout.

The harness itself follows the same rule: `observe`, `reason`, `edit_context`,
and `finish` are functions rather than privileged operations outside the script.

## 3. File as Round

A round is the file-backed lifecycle of one task, not one API call. It begins
when a prompt is appended to the canonical `ReAct.sh` and ends when `finish`
installs the next canonical `ReAct.sh`. A round may migrate through any number
of active image files.

```text
ReAct.sh (clean canonical; previous round complete)
  └─ append prompt → ReAct.sh becomes the active, task-bearing file
       └─ first edit_context → exec .react.image.* as the new active context
            └─ new image startup archives old ReAct.sh as .react.round.*
                 └─ canonical pathname remains intentionally absent
                      └─ zero or more edit_context transitions
                           └─ finish
                                └─ install the active prefix through the first
                                   exact # <TAPE> as ReAct.sh (round complete)
```

After the first successful context switch, the newly active image immediately
de-canonicalizes the old, task-bearing `ReAct.sh`. Later switches do not repeat
that step because the canonical pathname is already absent. At rest,
`ReAct.sh` contains the durable state produced by the completed round and serves
as the next round's entry. It may be the active file before the first switch,
but it never remains as a stale active image after execution has migrated
elsewhere.

Before calling `finish`, the agent uses `edit_context` when necessary to promote
reusable improvements above the first exact `# <TAPE>` boundary. `finish` then
validates that prefix, atomically installs it as `ReAct.sh`, and exits. The new
canonical image therefore omits the tape and the `finish` call. `finish` does not
decide what knowledge is durable; that semantic edit remains the agent's
responsibility.

The first exact line `# <TAPE>` is therefore a format invariant. Reusable source
before the real boundary must not contain another identical whole line.

## Run

Requirements:

- Bash
- `curl`
- `jq`
- `OPENAI_API_KEY`

The default model is `gpt-5.6-sol`; override it with `OPENAI_MODEL`.

```bash
export OPENAI_API_KEY='...'
bash ReAct.sh 'Find and fix the failing tests.' >> ReAct.sh
```

The command intentionally modifies `ReAct.sh`, and the canonical pathname may
temporarily disappear after the first context switch. This prototype assumes
one active round per directory. Git provides the simplest experiment log and
reset point.

## Test without an API key

```bash
bash test.sh
```

The test injects local `curl` and `jq` stubs. It verifies append execution,
function evolution and shell-state persistence, repeated context edits,
de-canonicalization after the first switch, PID continuity across `exec`, and
automatic canonicalization through `finish` on Bash 3.2 and Bash 5.1.

This is deliberately a research artifact, not a hardened executor or sandbox.
