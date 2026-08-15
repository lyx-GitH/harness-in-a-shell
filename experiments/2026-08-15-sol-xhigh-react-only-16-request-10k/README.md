# Sol xhigh ReAct-only 16-request trace

This directory preserves one unadopted harness self-improvement trace. The
model-generated shell files are research evidence, not executable project
sources. Do not run them on the host.

## Trusted run metadata

- Date: 2026-08-15
- Model: `gpt-5.6-sol`
- Reasoning effort: `xhigh`
- User prompt: `improve the harness step by step`
- Project payload visible in `/seed`: only `ReAct.sh`
- Seed `ReAct.sh` SHA-256:
  `e2e29f8e335d6ff6e25af048e04669e587f2e86dd0807793eed23c5a412462d8`
- OpenAI requests admitted: 16 of 16 allowed
- Maximum output tokens per request: 10000
- Checkpoint: immediately before request 9 was counted or sent upstream
- Container exit code: 4
- Starting repository commit: `84776ccc06359ca8252069cc729b55cbe3e0f66c`
- Original quarantined run: `sandbox-runs/run.rZRi7q`
- Base image ID:
  `sha256:a04dc4851cbcbb42b54d1f52a41f5f9eca6a5fd03748c3f6eb2cbeb238ca99bd`
- Agent image ID:
  `sha256:c47ee43bda6d2bbd30d4547d148c95257a961d0eb11348f21de8a2c0799d7ebc`
- Relay image ID:
  `sha256:41af87fd2423d38f3db8570a21339c77cadf6c99e494f658a02aa24153d8642a`

The checkpoint image is the exact request-9 `input` retained by the trusted
relay, before that request was released. Its recorded relay hash matches the
archived file. It is a byte-for-byte prefix of the final image. Because some
model responses emitted more than one `reason` call, “request” here means an
API response boundary, not a guarantee of one cleanly serialized action block.

Exit 4 is the controlled local request boundary. The active script contained
18 queued `reason` call sites; the relay admitted 16 upstream requests and
returned HTTP 429 to the remaining two. The final `jq -e` pipeline returned 4.

## Evolution observed

By the checkpoint, the agent had reproduced and fixed `observe` framing when a
command omits its trailing newline. It also added and tested `validate_image`,
which checks the Bash shebang, exact SYSTEM/TAPE marker cardinality and order,
and Bash syntax.

During requests 9–16 it wired validation into `edit_context`, rejected a bad
replacement without switching, strengthened `finish` staging and cleanup, and
introduced clean child-Bash launchers that remove `BASH_ENV`, `ENV`,
`SHELLOPTS`, and `BASHOPTS` before validation or context execution. Its
failure-injection tests reported success.

The emergent design pattern was to treat the harness as a self-hosting compiler:
validate executable structure at lifecycle boundaries, test failure paths
before integration, and use staging plus atomic installation. However, marker
and syntax validation still did not prove that required bindings, functions,
or the next-task bootstrap survived.

No context switch or `finish` occurred. Every candidate change remained after
the first `# <TAPE>` marker, so none became a clean reusable prefix. The final
file is syntactically valid working state, not an adopted or completed harness.

## Files

- `step-08-active-image.sh`: exact active script passed as request 9 input.
- `step-08-processes.txt`: trusted host process table at that boundary.
- `step-16-active-image.sh`: final active `ReAct.sh`, including the full trace.

SHA-256:

```text
7f0d69e21401929b07d7d1679b77e2dfe26ba580ac616a2af94f3311160f1503  step-08-active-image.sh
79606ec7f9c5a24c5c488477e661ec31c62b706dcd129aa4aa4c4eaadd4c9345  step-08-processes.txt
1d8b93bca21eb0b60ae0fa03d08ef011fff7b631984ecd447e68c07e693d7ed6  step-16-active-image.sh
```
