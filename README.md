# Harness in a Shell

```bash
bash ReAct.sh '<prompt>' >> ReAct.sh
```

[中文版](./README.zh-CN.md)

That one shell command is the ReAct loop. In generic form it is
`bash agent.sh '<prompt>' >> agent.sh`: model output goes to stdout, stdout is
appended to the running script, and the same Bash process continues reading and
executing the appended source. There is no explicit `while` loop.

The repository also includes a split Python-SDK variant:

```bash
python3 -m pip install openai
export OPENAI_API_KEY='...'
bash act.sh '<prompt>' >> act.sh
```

`act.sh` retains the append-only agent, tools, context editing, and round
lifecycle. `reason.py` extracts the SYSTEM section, calls the Responses API,
and prints the next Bash source. Its `MODEL` constant is intentionally ordinary
agent-modifiable source, so model or API evolution happens by editing the Python
tool itself instead of adding shell configuration.

This repository is a research prototype built around three ideas.

## 1. Script as Context

The active Bash script is the agent's complete context. It contains the
governing prompt, runtime identity, tool definitions, user input, observations,
execution tape, continuation, and its own context-editing machinery.

`reason` sends the complete current script to the model. The response is not a
separate chat message: it is future Bash source appended to that script.

```text
# INPUT: user instructions
# OBS:   tool observations
# EXIT:  observed exit status
# <TAPE> live trajectory begins here
```

Because the script is context, changing the SYSTEM prompt, reorganizing memory,
or replacing the reasoning machinery are all ordinary script edits.
`edit_context` performs a structural edit by switching to a complete new script.

## 2. Function as Tool

A Bash function is a tool. The agent may call or redefine an existing function,
author a new one, compose tools from other tools, refine old tools, or derive new
tools through any recursive combination of authoring, composition, and
refinement.

`observe` runs a command or function once in the current shell and records its
output and exit status as inert Bash comments. State changes made by a function,
such as variables or `cd`, remain live. A state-only function may also be called
directly when it produces no unsafe stdout.

The harness itself follows the same rule: `observe`, `reason`, `edit_context`,
and `finish` are functions rather than privileged operations outside the script.

## 3. File as Round

A round is the file-backed lifecycle of one task, not one API call. It begins
when a prompt is appended to the canonical `ReAct.sh` and ends when `finish`
installs the next canonical `ReAct.sh`. A round may migrate through any number
of active image files.

```text
ReAct.sh (clean canonical; previous round complete)
  └─ append prompt → ReAct.sh becomes the active, task-bearing file
       └─ first edit_context → exec .react.image.* as the new active context
            └─ new image startup archives old ReAct.sh as .react.round.*
                 └─ canonical pathname remains intentionally absent
                      └─ zero or more edit_context transitions
                           └─ finish
                                └─ install the active prefix through the first
                                   exact # <TAPE> as ReAct.sh (round complete)
```

After the first successful context switch, the newly active image immediately
de-canonicalizes the old, task-bearing `ReAct.sh`. Later switches do not repeat
that step because the canonical pathname is already absent. At rest,
`ReAct.sh` contains the durable state produced by the completed round and serves
as the next round's entry. It may be the active file before the first switch,
but it never remains as a stale active image after execution has migrated
elsewhere.

Before calling `finish`, the agent uses `edit_context` when necessary to promote
reusable improvements above the first exact `# <TAPE>` boundary. `finish` then
validates that prefix, atomically installs it as `ReAct.sh`, and exits. The new
canonical image therefore omits the tape and the `finish` call. `finish` does not
decide what knowledge is durable; that semantic edit remains the agent's
responsibility.

The first exact line `# <TAPE>` is therefore a format invariant. Reusable source
before the real boundary must not contain another identical whole line.

## Run

Requirements for the self-contained `ReAct.sh` variant:

- Bash
- `curl`
- `jq`
- `OPENAI_API_KEY`

The default model is `gpt-5.6-sol`; override it with `OPENAI_MODEL`.

```bash
export OPENAI_API_KEY='...'
bash ReAct.sh 'Find and fix the failing tests.' >> ReAct.sh
```

For the split variant, use Bash, Python 3, the `openai` package, and
`OPENAI_API_KEY`. Its canonical image is `act.sh`, and `reason.py` must remain
beside it:

```bash
bash act.sh 'Find and fix the failing tests.' >> act.sh
```

Each command intentionally modifies its canonical shell image (`ReAct.sh` or
`act.sh`), and that canonical pathname may temporarily disappear after the
first context switch. This prototype assumes one active round per directory.
Git provides the simplest experiment log and reset point.

## Test without an API key

```bash
bash test.sh
```

The test injects local `curl`, `jq`, Python, and OpenAI SDK stubs; it never calls
the real API. It verifies both reasoner variants, append execution, function
evolution and shell-state persistence, repeated context edits,
de-canonicalization after the first switch, PID continuity across `exec`, and
automatic canonicalization through `finish` on Bash 3.2 and Bash 5.1.

## Run in a disposable sandbox

Treat model output as arbitrary Bash, not merely as a program that might make a
mistake. In particular, do not bind-mount the real repository, home directory,
credentials, or a Docker socket into its executor.

The repository includes a container fallback for local experiments. On macOS,
start Docker Desktop first:

```bash
open -a Docker
bash sandbox.sh test
bash sandbox.sh verify
```

`test` runs the stub harness with no network or key. `verify` uses a fake key
and checks the isolation policy. The untrusted agent container has a read-only
root filesystem, bounded tmpfs, no Linux capabilities, resource limits, no host
bind mounts, no Docker socket, no API key, and `network=none`.

For a live run, the agent can only reach a narrow relay through a Unix socket on
a read-only-mounted volume. The relay holds the real key, reconstructs only a
`POST /v1/responses` request to `api.openai.com`, pins the model, rejects extra
API fields, disables hosted tools and streaming, and enforces per-run request,
body, response, output-token, and wall-clock limits. The independent host
watchdog remains authoritative even if arbitrary Bash attacks its in-container
timeout.

```text
agent (arbitrary Bash; network=none; no key)
  └─ Unix socket on read-only mount → trusted relay
                                      └─ TLS → api.openai.com/v1/responses
```

On a supported Docker installation, run it with:

```bash
export OPENAI_API_KEY='...'
bash sandbox.sh run 'Inspect the harness and finish cleanly.'
```

Tune the bounds with `SANDBOX_TIMEOUT_SECONDS`, `SANDBOX_MEMORY`,
`SANDBOX_WORK_SIZE`, `OPENAI_MAX_REQUESTS`, `OPENAI_MAX_OUTPUT_TOKENS`, and
`OPENAI_UPSTREAM_TIMEOUT_SECONDS`. For controlled model experiments,
`OPENAI_REASONING_EFFORT` can be `none`, `low`, `medium`, `high`, `xhigh`, or
`max`; when unset, the model default is preserved. This setting is injected by
the trusted relay and is not exposed to the agent. The cost-conscious defaults
allow at most 8 API attempts. `OPENAI_MAX_OUTPUT_TOKENS` is optional; when it is
unset, the relay omits `max_output_tokens` and the selected model's intrinsic
maximum applies. Set it explicitly when a smaller cost/output bound is desired.
The trusted relay records the actual attempt count, model, reasoning effort,
and configured output limit in each run directory. Container output is
disk-capped and retained under
`sandbox-runs/run.*/untrusted-{output,stderr}.bin`; the trusted host runner
deliberately does not parse it or render agent-controlled logs in the terminal.
A normal run writes a gzip tar stream to `untrusted-output.bin`, but arbitrary
Bash can corrupt or forge it. Inspect it only inside another disposable,
no-network sandbox, and never execute or source recovered files on the host.

For a longitudinal run, set `OPENAI_CHECKPOINT_AFTER_REQUESTS=N` to hold the
next valid request before it is counted or sent upstream. The host records the
exact request `input` (the current `$SELF`), its SHA-256, and a process table,
then releases the same request so the same Bash lifetime continues. The value
is valid only for `run` and must be below `OPENAI_MAX_REQUESTS`. To exclude all
other repository documents from an agent experiment, select the run-only
`sandbox/Dockerfile.agent-react-only` with `SANDBOX_AGENT_DOCKERFILE` and give
it a distinct `SANDBOX_AGENT_IMAGE` tag; that image copies only `ReAct.sh` into
`/seed`.

`SANDBOX_BASE_IMAGE` and `SANDBOX_BUILD_PROXY` are build-only escape hatches
for an offline cache or a local package proxy. They do not change the runtime
network policy and the proxy value is not baked into the resulting image. Once
both local images have been built, `SANDBOX_SKIP_BUILD=1` skips all image-build
network access; a live `run` still calls the OpenAI API through the relay. Use it
only when deliberately testing the already-built image.

This Mac currently runs macOS 12.5.1 and Docker Desktop 4.9.1. That stack is no
longer supported and is too old to be the sole boundary for a live arbitrary
Bash agent, so `sandbox.sh run` refuses by default on it. For experiments today,
run the same script inside a disposable UTM Linux VM with host directory,
clipboard, USB, and credential sharing disabled. `ALLOW_LEGACY_DOCKER_SANDBOX=1`
exists as an explicit research-risk override, not as a recommendation.

### Stronger microVM setup

After upgrading to macOS 14 or later, prefer Docker Sandboxes. Initialize its
network policy as deny-by-default, use clone mode so the working copy stays in
the microVM, scope the OpenAI secret to this sandbox, and allow exactly the API
host:

```bash
brew trust docker/tap
brew install docker/tap/sbx
sbx login
sbx policy init deny-all

sbx create shell "$PWD" --clone --no-share-skills --name react-harness --cpus 1 --memory 1g
sbx secret set react-harness openai
sbx policy allow network --sandbox react-harness api.openai.com:443
sbx policy ls --wide
sbx run --name react-harness
```

Then, inside the sandbox:

```bash
OPENAI_API_KEY=proxy-managed bash ReAct.sh '<prompt>' >> ReAct.sh
```

Use a staging Git repository containing only files the agent may read; clone
mode still exposes the source repository read-only. `--no-share-skills` also
prevents the sandbox from receiving Docker's shared host skill store. Remove
the microVM with `sbx rm react-harness` after exporting and reviewing the one
result you intend to keep.

This remains a research artifact. Canonicalization means a round completed; it
does not make the resulting Bash trustworthy.

## Experiment results and analysis

The archived runs under [`experiments/`](./experiments/) test whether the
harness can support incremental work, safe publication, and durable
self-improvement. Model-produced candidates are quarantined research artifacts;
none of the experimental harness variants below was adopted.

| Experiment | Requests / limit | Observed result | Interpretation |
| --- | ---: | --- | --- |
| [Terra `xhigh`, controlled comparison](./experiments/2026-08-15-terra-xhigh/) | 8 / 8 | Called `finish`, but published a candidate that removed the next-task bootstrap and failed the semantic test. | Faster movement from audit to implementation did not produce safe canonicalization. |
| [Sol `xhigh`, same controlled comparison](./experiments/2026-08-15-sol-xhigh-8-request-cutoff/) | 8 / 8 | Detected more repository-level invariants and switched to a continuing image, but reached the cap before retesting or finishing; the image retained 207 raw observation lines. | More cautious publication behavior than Terra at this cutoff, but no completed or proven improvement. |
| [Sol ReAct-only trace](./experiments/2026-08-15-sol-xhigh-react-only-16-request-10k/) | 16 / 16 | Improved observation framing, image validation, `edit_context`/`finish`, and child-Bash startup in the live tape. It never switched context or called `finish`. | Useful incremental design work occurred, but every change remained disposable trajectory rather than durable source. |
| [Tasklog trial with 10k output cap](./experiments/2026-08-15-sol-xhigh-tasklog-64-cap-10k-truncated/) | 2 / 64 | The second response ended inside a test heredoc. Bash accepted EOF as the terminator and the container exited 0 without completing tests, docs, or `finish`; an isolated check also found a `list` bug. | Process success and `bash -n` are insufficient evidence when a Responses result may be incomplete. |
| [Tasklog finish trial with model-default output limit](./experiments/2026-08-16-sol-xhigh-tasklog-model-default-finish/) | 50 / 64 | Completed through `finish`. The active file grew from 9,666 to an observed 248,681 bytes, then canonical `ReAct.sh` became byte-identical to the seed; no `edit_context` occurred. | Strong evidence for long-round execution and trajectory cleanup, but no durable harness evolution. |

The main conclusions are:

- An API-request limit is not a clean ReAct-round limit. A single model output
  can contain duplicated or non-tail `reason` calls, creating an execution
  backlog and making request count diverge from meaningful action rounds.
- A zero shell exit code does not prove completion. In particular, an output
  cutoff inside a heredoc can still be accepted by Bash. Future admission logic
  should reject incomplete Responses before their text becomes executable.
- `finish` proves that the file-as-round lifecycle reached canonical cleanup;
  it does not prove correctness or self-improvement. Durable evolution requires
  an explicit `edit_context` that moves selected changes above `# <TAPE>`.
- Successful `finish` discards the live tape. Behavioral studies therefore need
  a trusted pre-finish or API-boundary checkpoint if the exact trajectory must
  remain available for analysis.
- Under the controlled eight-request cutoff, Sol was more conservative about
  publication than Terra, but neither model produced an adoptable result. The
  evidence supports a behavioral difference, not a general model ranking.

See [`experiments/README.md`](./experiments/README.md) for the full provenance,
controls, and artifact-specific caveats.
