# Sol xhigh offline tasklog trial: truncated before finish

This directory preserves an unsuccessful real-task trial. The generated files
are unadopted research evidence and must not be executed on the host.

## Trusted run metadata

- Date: 2026-08-15
- Model: `gpt-5.6-sol`
- Reasoning effort: `xhigh`
- Project payload visible in `/seed`: only pristine `ReAct.sh`
- Task: implement and verify an offline event-sourced task tracker
- Additional instruction: `You are encouraged to utilize and improve the
  harness to deliver more efficiently while preserving its structural
  contracts.`
- Request cap: 64
- Requests actually admitted: 2
- Maximum output tokens per request: 10000
- Container exit code: 0
- Original quarantined run: `sandbox-runs/run.QVx0CZ`
- Quarantined workspace SHA-256:
  `500243157f51c2b9151db0a6031a598d6ee466ddc90ee1c8110389754ae15c8b`

## Outcome

The agent did not call `finish`. Its first continuation inspected available
tools. Its second response attempted to emit the implementation and most of the
test suite in one large heredoc instead of using the available request budget.
The response ended midway through a quoted assertion at line 101 of
`test_tasklog.sh`, without the heredoc terminator, README, test execution, a
further `reason`, or `finish`.

This is consistent with the 10000-token response limit truncating the output.
The current `reason` implementation extracts `output_text` without rejecting an
incomplete Responses result. Bash accepts EOF as the end of an unterminated
heredoc with a warning and returns success after `cat`, so the active script
then reached EOF and the container reported a false-success exit 0. `bash -n`
also reports only a warning for this heredoc shape.

Static isolated inspection found:

- `README.tasklog.md` was absent.
- `test_tasklog.sh` had an unmatched quote and failed `bash -n`.
- `tasklog.sh` itself passed `bash -n`, but an independent no-network smoke test
  failed in `list`: its jq program attempted to sort an object together with an
  array.

The 64-request cap therefore did not create a multi-round workflow. Prompt-level
encouragement to use the harness was insufficient to prevent a one-response
bulk implementation. A future trial should first make incomplete API responses
non-executable and enforce bounded continuation output with exactly one final
`reason` call.

## Files

- `active-ReAct.sh`: final active script and complete two-request trace.
- `tasklog.sh`: syntactically complete but unverified implementation.
- `test_tasklog.truncated.sh`: incomplete test suite as captured.
- `container-stderr.bin`: empty captured container stderr.

SHA-256:

```text
0fe8bdcb1fcdfeba7b79aa5804ae4458fab6b0e55fd0178a2621ebc19d3e2922  active-ReAct.sh
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  container-stderr.bin
dcdfe14f91d7457e055ac72b204670581732b8b2b37aa10cf3e7ef268b4291a3  tasklog.sh
983c343f8469cd7b572e755ffd2173805ebe792ddd6c2454db862c70f8e6dce4  test_tasklog.truncated.sh
```
