# Sol xhigh context-efficiency run: 16-call prompt, 17-call relay

This directory preserves a successful ReAct-only self-improvement experiment.
The model-generated artifacts are research data, not adopted project sources.
Do not execute them on the host without a separate review.

## Configuration

- Seed payload: the current `ReAct.sh` only
- Model: `gpt-5.6-sol`
- Reasoning effort: `xhigh`
- Prompt: `imporve this harness to improve context efficiency, at most 16
  reason() call is permited due to budget constrain`
- Agent-visible limit: at most 16 `reason()` calls
- Trusted relay limit: 17 upstream requests
- Requests actually admitted: 5
- Request `max_output_tokens`: omitted (`model-default`)
- Trusted upstream socket timeout: 600 seconds
- Host/container wall-clock limit: 3600 seconds
- Container exit: 0

The GitHub dataset contains only the README files and the relevant shell
images under `extracted/`. The final canonical image, three active images, and
the round archive were selectively copied through a no-network container and
made non-executable and read-only. See `extracted/README.md`.

## Trajectory behavior

This trajectory is short, deliberate, and genuinely iterative:

1. The first two requests audited the harness, identified duplicated SYSTEM
   context and wasted reasoning calls around image switches, and produced the
   first structural replacement.
2. Request 3 built a more ambitious replacement plus a self-test. That test
   failed with status 1 instead of being ignored.
3. Request 4 ran a traced diagnostic, corrected the candidate, and switched to
   a smaller validated context.
4. Request 5 measured the saving, checked marker integrity and budget state,
   then called `finalize`. The clean terminal image called `finish` without a
   sixth API request.

The agent therefore used failures as observations, moved durable work above
TAPE early, and avoided a long append-only backlog. It consumed only 5 of the
17 relay requests and respected its stricter agent-visible 16-call budget.

## Durable result

The agent used structural context switching and finished successfully. The
canonical `ReAct.sh` changed from 10,041 bytes / 267 lines to 7,162 bytes / 206
lines and has SHA-256
`3956242e57be0c3a569e1db97d13dface4c168abc2752d947c8d1ae1cedd08a6`.
It retains exactly one opening SYSTEM marker, one closing SYSTEM marker, and
one TAPE marker, contains no task INPUT or OBS lines, passes `bash -n`, and
passes the repository's complete `test.sh` in a separate no-network container.

The durable changes are:

- a shorter governing prompt and reusable prefix;
- `prompt_image`, which omits the SYSTEM body from API `input` because the same
  content is already sent as `instructions`;
- a 16-call `REACT_REASON_LIMIT` and an exported call counter that survives
  sibling-image `exec` transitions;
- no automatic `reason` call when a sibling image starts, avoiding a wasted
  request during context switching;
- `retape`, which preserves the reusable prefix and replaces only disposable
  trajectory;
- syntax validation and temporary-file cleanup in `edit_context`;
- `finalize` plus a terminal-state guard in `finish`, allowing a clean terminal
  image to publish without another model request.

For a clean image, the approximate logical `instructions + input` payload fell
from 14,777 bytes for the seed to 7,095 bytes for the candidate, a reduction of
about 52%. The canonical file alone shrank by 2,879 bytes, or 28.67%.

The fifth response completed self-tests and called `finalize`; the resulting
clean image called `finish` without a sixth request. This is a successful,
meaningful experiment, but the candidate remains unadopted pending explicit
review and merge direction.

## Evaluation

The strongest improvement is not merely shorter prose: `prompt_image` removes
a systematic duplicate copy of SYSTEM on every request, while `retape` gives
the runtime a cheap path for future trajectory compression. Budget state also
survives `exec`, so context optimization no longer silently resets accounting.

The tradeoff is scope. The agent replaced a large portion of the control plane,
hard-coded the prompt's 16-call policy into the canonical image, and introduced
new lifecycle tools. Passing the existing suite is strong evidence of backward
compatibility, but this candidate is riskier to adopt than the narrow tasklog
change and deserves targeted tests for `retape`, failed upstream requests, and
counter integrity before merge.
