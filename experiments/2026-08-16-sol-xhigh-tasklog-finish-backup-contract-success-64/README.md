# Sol xhigh tasklog terminal-backup success trial

This directory preserves the successful repeat of the tasklog terminal-backup
experiment. The complete worktree is model-controlled research data and must
not be executed on the host.

## Configuration

- Seed payload: the current `ReAct.sh` only, including the mandatory terminal
  backup FINISH CONTRACT
- Task: build and verify the offline event-sourced task tracker represented by
  `extracted/deliverables/`; the full INPUT is retained in the round trajectory
- Model: `gpt-5.6-sol`
- Reasoning effort: `xhigh`
- Trusted request limit: 64
- Requests admitted: 64
- Request `max_output_tokens`: omitted (`model-default`)
- Trusted upstream socket timeout: 600 seconds
- Host/container wall-clock limit: 3600 seconds
- Container exit: 0

The GitHub dataset contains only README files and the relevant shell sources:
the complete round trajectory, terminal image, final canonical image, task
implementation, and test suite. See `extracted/README.md`.

## Outcome

This run demonstrates the requested backup behavior:

- The agent completed `tasklog.sh`, `test_tasklog.sh`, and
  `README.tasklog.md`; their syntax checks and complete isolated test suite
  pass.
- Before finishing, it called `edit_context` with a complete terminal image.
  The prior 286,195-byte trajectory was archived as `.react.round.dFmdnp`.
- The replacement `.react.image.FEAytq` is clean, contains one set of structural
  markers, contains no INPUT or OBS lines, and invokes `finish` after TAPE.
- `finish` installed a 10,244-byte / 270-line canonical `ReAct.sh` with SHA-256
  `333106bc7b9c80a3243d33e97e3fcb8650121af6da8f5fdda0cbec84b20e4c74`.
- The canonical image passes `bash -n` and the repository's complete `test.sh`
  in a separate no-network container.

The meaningful durable change guards the bootstrap: only a fresh canonical
entry records INPUT and calls `reason`; replacement images execute their
prepared TAPE body directly. This prevents a terminal `edit_context` from
spending an unnecessary API request before its `finish` call. Minor redirection
spacing changes were also retained.

## Trajectory behavior

This is a deliberately stressful E2E contract run rather than an efficient
self-improvement trace. The agent implemented a nontrivial product, repeatedly
tested valid and invalid task histories, audited byte-preserving failures, and
eventually produced a 50-test suite. The deliverables are complete and pass in
an independent no-network container.

The cost is visible in `rounds/react.round.dFmdnp.sh`: the append-only tape grew
to 286,195 bytes / 7,911 lines and used all 64 relay requests. Repeated and
non-tail `reason` calls created an execution backlog, so several terminal
candidate heredocs and verification blocks appear physically in the round even
though only the first reached `exec`. The agent never compressed context during
the work; it deferred its sole effective `edit_context` until publication.

At the terminal boundary it followed the revised contract correctly. It built
a complete clean image, moved the one durable harness improvement above TAPE,
placed `finish` after TAPE, switched with `edit_context`, and let `finish`
discard the task input and 286 KB trajectory.

## Evaluation

This run is strong evidence for lifecycle correctness under a large real-task
backlog. It proves that task artifacts, durable harness evolution, context
switching, and atomic canonicalization can all complete in one Bash lifetime.
The bootstrap guard is small but useful and directly enables terminal images to
finish without an extra model call.

Its weakness is efficiency: the agent reached the outer request ceiling, made
no mid-round compression, and repeated final work because of queued reasoning.
Compared with the context-efficiency trajectory, it is more conservative in
what it publishes but substantially worse at managing its working context.
