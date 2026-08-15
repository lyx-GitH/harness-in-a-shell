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
