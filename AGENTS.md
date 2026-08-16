# Project Notes

- `ReAct.sh` is the entire agent runtime and canonical image. Keep it small and
  preserve the append-only execution semantics.
- `act.sh` is the split-runtime variant: it preserves the same append-only,
  context-editing, and finish semantics under `.act.*` paths, while `reason.py`
  uses the official OpenAI Python SDK. `MODEL` intentionally lives directly in
  `reason.py`; that file is ordinary agent-modifiable source rather than shell
  environment configuration.
- Keep `observe()` co-located with its FUNCTION AS TOOL contract inside
  `<SYSTEM>`; executable function source is itself part of the model's
  instructions.
- Keep `ROOT`/`SELF`/`CANONICAL` in EXECUTION MODEL and the `OPENAI_MODEL`
  default in CONTROL FLOW so runtime configuration stays beside its semantics.
- Exact comments parsed as harness structure are immutable syntax. In each
  complete image, preserve the operative `# <SYSTEM>`, `# </SYSTEM>`, and
  `# <TAPE>` lines exactly and in order; apply the same rule to future parsed
  tags/comments. `test.sh` locks the clean-image marker counts and ordering.
- `test.sh` is the only test harness. It must not call the real API; it injects
  `curl`/`jq` stubs and local Python/OpenAI SDK stubs, and covers both repeated
  `edit_context` calls and terminal canonicalization through `finish`.
- Run syntax checks with `/bin/bash -n ReAct.sh`, `/bin/bash -n act.sh`, and
  `/bin/bash -n test.sh`; compile-check `reason.py` with Python 3.
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
- `bash sandbox.sh test` runs the stub in a no-network, no-key container;
  `bash sandbox.sh verify` exercises the container and relay boundaries with a
  fake key. Runtime containers never bind-mount host paths.
- For live fallback runs, the agent has `network=none` and no API key. It reaches
  `sandbox/openai_relay.py` only through a Unix socket located on a Docker volume
  mounted read-only into the agent; the relay alone has egress and fixes the
  upstream to OpenAI Responses. Results under `sandbox-runs/` are quarantined
  and must not be executed on the host.
- The host watchdog is authoritative; the same-UID in-container `timeout` is
  only a graceful first stage. Agent stdout/stderr are capped by Docker's local
  log driver and retained as `untrusted-{output,stderr}.bin`; never parse those
  streams or render agent-controlled logs automatically on the host.
- `.env` and `.env.*` must remain excluded from Git and Docker build contexts.
  A live key is passed only to the trusted relay container, never to the agent.
- The sandbox defaults to 8 upstream attempts and no explicit
  `max_output_tokens`; the selected model's intrinsic maximum applies. Set
  `OPENAI_MAX_OUTPUT_TOKENS` explicitly for a smaller cost/output bound. The
  relay's trusted request count and configured output limit are copied into
  each non-test run directory without trusting agent output.
- For a self-contained run whose only project payload is the harness, use
  `sandbox/Dockerfile.agent-react-only` with a distinct
  `SANDBOX_AGENT_IMAGE`; it copies only `ReAct.sh` into `/seed`. Runtime tools,
  the entrypoint, generated Git metadata, `.home`, and `.sandbox.log` remain
  infrastructure rather than project context.
- `OPENAI_CHECKPOINT_AFTER_REQUESTS=N` blocks the next valid request before
  count increment or upstream forwarding. The relay atomically retains that
  request's exact `input` and SHA-256; the host saves them plus a process table
  and releases the same request, preserving one Bash lifetime. Treat this as an
  API-response boundary: model output containing multiple non-tail `reason`
  calls can still make request count diverge from clean action-round count.
- `OPENAI_REASONING_EFFORT` is an optional trusted relay-side experiment knob;
  the agent cannot supply or override it. An empty value preserves the model
  default. Each run records trusted `model` and `reasoning-effort` metadata.
- A 2026-08-15 live terra trial was sandbox validation only. Its syntactically
  valid candidate omitted the closing `# </SYSTEM>` marker and was not adopted;
  model-produced candidates must remain test artifacts unless the user asks to
  merge them.
- A later 2026-08-15 terra `xhigh` trial with `improve this harness step by step`
  used all 8 requests and did perform incremental audits, but its canonical
  candidate removed the prompt/bootstrap `reason` call and leaked `# OBS:`
  lines before `# <TAPE>`. It failed `test.sh` and was not adopted.
- The controlled Sol `xhigh` comparison used the same seed, prompt, and 8-request
  cap. Sol reached a continuing image rather than `finish`; its next `reason`
  was rejected by the exhausted local cap. It showed better clean-fixture and
  publication awareness but remained incomplete and retained 207 raw
  observations. Both trials are preserved under `experiments/`; neither was
  adopted.
- A separate ReAct-only Sol `xhigh` run used 16 admitted requests and a
  10000-token output cap. It incrementally fixed `observe` framing, tested image
  validation, hardened `edit_context`/`finish`, and sanitized child Bash
  startup. It never switched context or finished, so all changes remained
  after `<TAPE>` and none were adopted. Its duplicate/non-tail `reason` calls
  also demonstrate that an API request cap is not necessarily a clean agent
  round count. The trace is preserved under `experiments/`.
- In the offline tasklog trial, raising the request cap to 64 did not induce a
  multi-round workflow: Sol used two requests and its second 10000-token output
  ended inside a test heredoc. Bash warns but can return success when EOF closes
  an unterminated heredoc, and `bash -n` does not make that warning fatal. Since
  `reason` currently extracts text without rejecting an incomplete Responses
  result, the container falsely exited 0 without `finish`. Prompt-level
  encouragement to use the harness was insufficient; preserve the trace under
  `experiments/` and address incomplete-response admission before retrying.
- The 2026-08-16 follow-up tasklog trial omitted request-level
  `max_output_tokens`, used Sol `xhigh`, and completed through `finish` after 50
  of 64 admitted requests. The live tape grew from 9,666 to an observed 248,681
  bytes, then the final canonical `ReAct.sh` became byte-identical to the seed;
  the harness stayed structurally valid and passed `test.sh`. No
  `edit_context` occurred, so this validates round completion and trajectory
  cleanup, not durable harness evolution. Repeated/non-tail continuations
  produced a sizable execution backlog and duplicate final verification.
- A successful `finish` removes the live tape needed for behavioral analysis.
  For future research trials, use a trusted pre-finish/checkpoint snapshot if
  the exact action/request trajectory matters; the final worktree alone proves
  the canonical outcome but cannot reconstruct the discarded round.
- The FINISH CONTRACT intentionally requires a terminal `edit_context` before
  every `finish`: preserve all important cross-round information before the
  first `# <TAPE>` boundary, and let only the clean replacement image call
  `finish`.
- The immediate identical tasklog repeat used all 64 requests, then correctly
  called terminal `edit_context`, preserved a canonical-only bootstrap guard
  above TAPE, and finished. Its task suite and the repository `test.sh` pass;
  preserve it under
  `experiments/2026-08-16-sol-xhigh-tasklog-finish-backup-contract-success-64/`.
- The context-efficiency experiment recorded its exact prompt in
  `experiments/2026-08-16-sol-xhigh-context-efficiency-16-reason-17-relay/README.md`, a
  16-call agent-visible limit, and a 17-request trusted relay limit. Sol used 5
  requests and durably added prompt deduplication, bounded call accounting,
  `retape`, validated image switching, and guarded finalization. The candidate
  passes `test.sh` and cuts the clean logical request payload by about 52%.
  Selected images and the final canonical file were explicitly extracted as
  read-only research data under that experiment's `extracted/` directory; the
  candidate remains unadopted.
- This host's legacy macOS 12.5.1 / Docker Desktop 4.9.1 stack is acceptable only
  for stub/verification convenience, not as the sole boundary for live arbitrary
  Bash. Use a no-sharing disposable UTM Linux VM now, or Docker Sandboxes clone
  mode after upgrading to macOS 14+.
- On this host, Docker Hub token fetches currently time out. The tested local
  build fallback retags the cached Ubuntu 24.04 amd64 image as
  `react-sandbox-base:cached`, disables old BuildKit with
  `DOCKER_BUILDKIT=0`, and sets `SANDBOX_BASE_IMAGE=react-sandbox-base:cached`
  plus `SANDBOX_BUILD_PROXY=http://host.docker.internal:1087`; these are
  build-only inputs and runtime remains isolated.
- After those images exist, `SANDBOX_SKIP_BUILD=1 bash sandbox.sh test` or
  `verify` reuses them without any build-time network. Rebuild after source
  changes rather than testing stale images.
