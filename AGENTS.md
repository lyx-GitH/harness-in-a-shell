# Project Notes

- `ReAct.sh` is the entire agent runtime and canonical image. Keep it small and
  preserve the append-only execution semantics.
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
- Cost-conscious sandbox defaults are 8 upstream attempts and 4096 output
  tokens per attempt. The relay's trusted `/tmp/openai-request-count` is copied
  into each non-test run directory for audit without trusting agent output.
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
