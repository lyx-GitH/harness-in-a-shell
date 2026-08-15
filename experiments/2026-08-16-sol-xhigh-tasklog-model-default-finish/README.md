# Sol xhigh real-task finish trial

This directory preserves the quarantined result of a real offline task run.
The artifact is model-controlled data: do not extract or execute it on the
host. Inspect it only inside a disposable, no-network sandbox.

## Configuration

- Seed payload: pristine `ReAct.sh` only
- Model: `gpt-5.6-sol`
- Reasoning effort: `xhigh`
- Prompt: build and verify an offline event-sourced Bash task tracker, with
  encouragement to use and improve the harness
- Successful upstream requests: 50 of a retained 64-request safety bound
- Request `max_output_tokens`: omitted (`model-default`)
- Trusted upstream socket timeout: 600 seconds
- Container exit: 0

The trusted metadata and complete final worktree archive are retained beside
this note. `untrusted-output.bin` is a gzip-compressed tar stream in this run,
but it remains untrusted. Its SHA-256 is
`e16ce0546da781a59070e228ca257681491776bfe04cf27ab16c91ee0ed691b0`.

## Harness result

The run genuinely reached `finish`:

- The active `ReAct.sh` grew from 9,666 bytes / 261 lines to an observed peak
  of 248,681 bytes / 6,685 lines while the round was live.
- Its live tail contained completed verification observations followed by
  `finish` calls.
- The agent container then exited 0.
- The archived canonical `ReAct.sh` is back to 9,666 bytes / 261 lines and is
  byte-identical to the seed. Both have SHA-256
  `e2e29f8e335d6ff6e25af048e04669e587f2e86dd0807793eed23c5a412462d8`.
- The final image has exactly one opening SYSTEM marker, one closing SYSTEM
  marker, and one TAPE marker; its Bash syntax and the repository semantic test
  pass.

This is a successful demonstration of `finish` as round commit and trajectory
garbage collection. It is not a successful harness-evolution trial. No
`edit_context` switch occurred, no task-time tool or instruction was promoted
before TAPE, and the final canonical harness is exactly the original seed.
The agent evolved a large temporary function/tool vocabulary inside the round,
but `finish` correctly discarded it.

## Research observations

- The physical tape grew roughly 25.7x before canonicalization.
- Repeated or non-tail `reason` calls formed an execution backlog, so the 50
  admitted API requests are not equivalent to 50 clean act-observe-reason
  rounds. Several final verification blocks were duplicated before the first
  queued `finish` was reached.
- Successful canonicalization destroys the expanded tape. The final archive
  proves the clean result but cannot reconstruct the complete 50-request
  trajectory. Future behavioral experiments should have the trusted runner
  checkpoint the active image immediately before canonicalization, without
  changing agent semantics.

The generated task tracker, its README, and its 50-test suite are included in
the quarantined worktree. They were independently syntax-checked and the suite
passed in another no-network container. Their product completeness was not the
primary outcome measured by this trial.
