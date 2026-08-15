# Harness in a Shell

An append-only research prototype where the Bash program is simultaneously the
agent image, context, tool registry, execution tape, and continuation.

The runtime is one file: [`ReAct.sh`](./ReAct.sh). Bash functions are tools,
comments are observations, model output is future Bash source, and Bash keeps
executing as that source is appended. There is no explicit agent loop.

## Run

Requirements:

- Bash
- `curl`
- `jq`
- `OPENAI_API_KEY`

The default model is `gpt-5.6-sol`; override it with `OPENAI_MODEL`.

```bash
export OPENAI_API_KEY="..."
bash ReAct.sh "Find and fix the failing tests." >> ReAct.sh
```

This intentionally modifies `ReAct.sh`. Commit or copy the canonical image
before an experiment if you want an easy reset.

## What happens

1. The input is appended as `# INPUT:` comments.
2. `reason` sends the full current script to the Responses API.
3. The model returns Bash source and stdout appends it to the same script.
4. The current Bash process continues into the appended source.
5. Generated code may use tools, record observations, redefine tools, and call
   `reason` as its continuation.
6. It may context-switch by creating a complete new image and using
   `exec bash "$NEXT" >> "$NEXT"`.
7. On completion it may consolidate reusable improvements back into the
   canonical `ReAct.sh` and exit.

## Test without an API key

```bash
bash test.sh
```

The test injects local `curl` and `jq` stubs. It verifies the unusual semantics
that matter here: appended source executes once, a Bash function can evolve,
state changed by an observed function remains live, observations join the tape,
and `exec` switches to a self-contained image without changing PID.
Set `BASH_UNDER_TEST` to exercise a specific interpreter, for example:

```bash
BASH_UNDER_TEST=/opt/homebrew/bin/bash bash test.sh
```

This is deliberately a research artifact, not a hardened executor or sandbox.
