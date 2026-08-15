# Harness self-improvement experiments

These directories preserve model-generated research artifacts. They are not
adopted project sources and must not be executed on the host.

## Controlled 2026-08-15 comparison

The Terra and Sol trials used the same byte-identical agent seed, trusted
relay, user prompt, reasoning effort, timeout, request cap, and output-token
cap. The only intended independent variable was the model:

| Condition | Terra | Sol |
| --- | --- | --- |
| Model | `gpt-5.6-terra` | `gpt-5.6-sol` |
| Prompt | `improve this harness step by step` | same |
| Reasoning effort | `xhigh` | `xhigh` |
| Successful upstream requests | 8 | 8 |
| Max output tokens per request | 4096 | 4096 |
| Wall-clock limit | 300 seconds | 300 seconds |
| State at cutoff | Prematurely canonicalized | Continuing image, not canonicalized |

Terra progressed more quickly from audit to implementation and used its eighth
request to call `finish`, but its canonical result removed the next-task
bootstrap and failed the semantic test. Sol spent more of the fixed budget
inspecting the repository and tests. It independently chose structural image
validation, recognized that testing the dirty live script as a clean fixture
caused a misleading failure, and used its eighth response to switch into a
continuing image with an explicit plan to test a clean candidate before
publication. The new image's initial continuation was rejected locally because
the eight-request cap had already been reached.

At this fixed cutoff, Sol was more cautious about publication and showed better
awareness of repository-level semantics, but it did not complete or prove an
improvement. It also wasted work on one invalid subshell inspection and one
duplicated source inspection, and its continuing image retained 207 raw
observation lines. The evidence supports a behavioral difference, not adoption
of either candidate.

## ReAct-only 16-request trace

`2026-08-15-sol-xhigh-react-only-16-request-10k/` preserves a separate Sol
`xhigh` run whose only project payload was `ReAct.sh`. It used the prompt
`improve the harness step by step`, a 16-request cap, a 10000-token per-response
cap, and an exact active-image checkpoint before request 9 was released.

The model found and fixed observation framing, developed structural image
validation, integrated it into context switching and finalization, and tested a
sanitized child-Bash boundary. All changes remained live trajectory after
`# <TAPE>`; no context switch or `finish` made them durable. The artifacts are
therefore evidence of incremental design behavior, not an adopted candidate.

## Offline tasklog trial

`2026-08-15-sol-xhigh-tasklog-64-cap-10k-truncated/` preserves a real-task trial
with a 64-request cap. Despite being encouraged to use and improve the harness,
Sol used only two requests and attempted to generate the implementation and
tests in one 10000-token response. The response ended inside a test heredoc;
Bash treated EOF as its terminator and the run falsely exited 0 without tests,
documentation, or `finish`. An independent isolated smoke test also found a
functional `list` bug. Nothing was adopted.

## Offline tasklog finish trial without an explicit output cap

`2026-08-16-sol-xhigh-tasklog-model-default-finish/` preserves the follow-up
real-task run from the same pristine ReAct-only seed. The trusted relay omitted
`max_output_tokens`, retained a 64-request safety bound, and admitted 50 Sol
`xhigh` requests before the agent finished successfully.

The active tape grew from 9,666 to an observed 248,681 bytes and accumulated a
continuation backlog, then `finish` reduced the canonical image to a file
byte-identical to the seed. This proves the round lifecycle and canonical
cleanup on a substantive task. It does not show durable self-improvement: the
agent never used `edit_context`, and no temporary tool or harness change
survived the TAPE boundary. The full final worktree is retained as a
quarantined binary artifact; because `finish` discards the tape, the exact live
trajectory is not recoverable from the final archive.
