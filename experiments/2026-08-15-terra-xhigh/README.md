# Terra xhigh research artifact

This directory preserves the unadopted output of one sandboxed harness
self-improvement trial. The files are research evidence, not executable project
sources. Do not run them on the host.

## Trusted run metadata

- Date: 2026-08-15
- Model: `gpt-5.6-terra`
- Reasoning effort: `xhigh`
- User prompt: `improve this harness step by step`
- OpenAI requests attempted: 8 of 8
- Container exit code: 0
- Original quarantined run: `sandbox-runs/run.3HLHeP`

The model worked incrementally: it audited the image, introduced a
`validate_image` gate, exercised positive and negative cases, added validation
to `edit_context` and `finish`, tested rejection cleanup, and called `finish`.

The result was deliberately not adopted. Although `candidate.ReAct.sh` passes
Bash syntax and has one correctly ordered copy of each structural marker, it
fails the repository semantic test with `expected two edited context images;
got 0`. It removed the canonical prompt/bootstrap block that records `$1` and
calls `reason`, so future tasks do nothing. It also persisted task-specific
`# OBS:` lines before `# <TAPE>`. Its validator therefore enforced syntactic
shape while accepting a semantically incomplete harness.

## Files

- `candidate.ReAct.sh`: the canonical file produced by `finish`.
- `active-image.sh`: the final active image, including its post-tape trajectory.
- `round.sh`: the de-canonicalized original round with the complete pre-switch
  trajectory and replacement heredoc.

SHA-256:

```text
a0014c98e4d18f30c10036948f83370a093da63827fe42ed9a3484c6a22aedc3  candidate.ReAct.sh
230262bc5b529f7c053a517d5ca74b23367f67a146f5dda737332dac9da3de6a  active-image.sh
727c761f6e33b1c94bcea512821af2bcbe56789a793ff888e9f4789baabf297e  round.sh
```
