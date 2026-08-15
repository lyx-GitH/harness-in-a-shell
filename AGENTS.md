# Project Notes

- `ReAct.sh` is the entire agent runtime and canonical image. Keep it small and
  preserve the append-only execution semantics.
- Keep `observe()` co-located with its FUNCTION AS TOOL contract inside
  `<SYSTEM>`; executable function source is itself part of the model's
  instructions.
- Keep `ROOT`/`SELF`/`CANONICAL` in EXECUTION MODEL and the `OPENAI_MODEL`
  default in CONTROL FLOW so runtime configuration stays beside its semantics.
- `test.sh` is the only test harness. It must not call the real API; it injects
  `curl` and `jq` stubs through `PATH`, and covers both repeated `edit_context`
  calls and terminal canonicalization through `finish`.
- Run syntax checks with `/bin/bash -n ReAct.sh` and `/bin/bash -n test.sh`.
- Run the semantic test with `bash test.sh`.
- Set `BASH_UNDER_TEST=/path/to/bash` to validate the append semantics against a
  particular Bash build.
- The host macOS lacks `realpath` and currently lacks `jq`. Path initialization
  therefore uses `cd` plus `pwd -P`; live API runs require installing `jq`.
- During an active task, the running image is append-only. Context compression
  or structural self-editing passes another complete image to `edit_context`,
  which selects a unique `.react.image.*` path and switches with `exec`; only
  `finish` validates the current image's prefix through its first `# <TAPE>`,
  installs that prefix as canonical `ReAct.sh`, then exits.
- FILE AS ROUND means the first noncanonical image archives the dirty prior
  `ReAct.sh` as `.react.round.*`; the canonical pathname remains absent until
  `finish` ends the round.
- The prototype assumes one active round per directory; concurrent rounds would
  contend for the single canonical pathname and round archive transition.
