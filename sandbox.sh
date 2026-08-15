#!/usr/bin/env bash

set -euo pipefail
umask 077
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
: "${SANDBOX_AGENT_IMAGE:=harness-in-a-shell-agent:local}"
: "${SANDBOX_AGENT_DOCKERFILE:=sandbox/Dockerfile.agent}"
AGENT_IMAGE="$SANDBOX_AGENT_IMAGE"
RELAY_IMAGE=harness-in-a-shell-relay:local

: "${OPENAI_MODEL:=gpt-5.6-sol}"
: "${OPENAI_REASONING_EFFORT:=}"
: "${SANDBOX_TIMEOUT_SECONDS:=300}"
: "${SANDBOX_MEMORY:=512m}"
: "${SANDBOX_WORK_SIZE:=256m}"
: "${OPENAI_MAX_REQUESTS:=8}"
: "${OPENAI_MAX_OUTPUT_TOKENS:=4096}"
: "${OPENAI_CHECKPOINT_AFTER_REQUESTS:=}"

build_args=()
if [[ -n "${SANDBOX_BASE_IMAGE-}" ]]; then
    build_args+=(--build-arg "BASE_IMAGE=$SANDBOX_BASE_IMAGE")
fi
if [[ -n "${SANDBOX_BUILD_PROXY-}" ]]; then
    build_args+=(
        --build-arg "http_proxy=$SANDBOX_BUILD_PROXY"
        --build-arg "https_proxy=$SANDBOX_BUILD_PROXY"
    )
fi

usage() {
    cat <<'USAGE'
Usage:
  bash sandbox.sh test
  bash sandbox.sh verify
  OPENAI_API_KEY=... bash sandbox.sh run '<prompt>'

test    Runs test.sh with no network and no API key.
verify  Checks DNS, public-IP, and relay-route isolation with a fake key.
run     Runs the live agent through the key-holding OpenAI-only relay.
USAGE
}

die() {
    printf 'sandbox: %s\n' "$1" >&2
    exit 2
}

case "${1-}" in
    test|verify|run)
        MODE="$1"
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

PROMPT="${2-}"
if [[ "$MODE" == run && -z "$PROMPT" ]]; then
    die "run requires a non-empty prompt"
fi
if [[ "$MODE" == run && "$#" -ne 2 ]]; then
    die "run accepts exactly one prompt argument"
fi
if [[ "$MODE" != run && "$#" -ne 1 ]]; then
    die "$MODE does not accept additional arguments"
fi

normalize_positive_int() {
    local name="$1"
    local value="$2"
    local normalized

    case "$value" in
        ''|*[!0-9]*) die "$name must be a positive integer" ;;
    esac
    normalized=$((10#$value))
    if ((normalized <= 0)); then
        die "$name must be a positive integer"
    fi
    printf -v "$name" '%d' "$normalized"
}

normalize_positive_int SANDBOX_TIMEOUT_SECONDS "$SANDBOX_TIMEOUT_SECONDS"
normalize_positive_int OPENAI_MAX_REQUESTS "$OPENAI_MAX_REQUESTS"
normalize_positive_int OPENAI_MAX_OUTPUT_TOKENS "$OPENAI_MAX_OUTPUT_TOKENS"
if [[ -n "$OPENAI_CHECKPOINT_AFTER_REQUESTS" ]]; then
    normalize_positive_int \
        OPENAI_CHECKPOINT_AFTER_REQUESTS "$OPENAI_CHECKPOINT_AFTER_REQUESTS"
    if [[ "$MODE" != run ]]; then
        die "OPENAI_CHECKPOINT_AFTER_REQUESTS is only valid for run"
    fi
    if ((OPENAI_CHECKPOINT_AFTER_REQUESTS >= OPENAI_MAX_REQUESTS)); then
        die "OPENAI_CHECKPOINT_AFTER_REQUESTS must be less than OPENAI_MAX_REQUESTS"
    fi
fi

case "$OPENAI_REASONING_EFFORT" in
    ''|none|low|medium|high|xhigh|max) ;;
    *)
        die "OPENAI_REASONING_EFFORT must be one of: none, low, medium, high, xhigh, max"
        ;;
esac

command -v docker >/dev/null 2>&1 || die "docker is not installed"
docker info >/dev/null 2>&1 ||
    die "the Docker daemon is not running (start Docker Desktop or run inside a disposable Linux VM)"

if [[ "$MODE" == run && -z "${OPENAI_API_KEY-}" ]]; then
    die "OPENAI_API_KEY is required by the relay"
fi

if [[ "$MODE" == run && "${ALLOW_LEGACY_DOCKER_SANDBOX-}" != 1 ]] \
    && command -v sw_vers >/dev/null 2>&1; then
    MACOS_MAJOR="$(sw_vers -productVersion | sed 's/\..*//')"
    if ((MACOS_MAJOR < 14)); then
        die "live runs are disabled on this unsupported legacy macOS/Docker stack; use a disposable UTM Linux VM, upgrade to macOS 14+ and use sbx, or explicitly set ALLOW_LEGACY_DOCKER_SANDBOX=1"
    fi
fi

RUN_TOKEN="$(date +%Y%m%d%H%M%S)-$$"
AGENT_CONTAINER="react-agent-$RUN_TOKEN"
RELAY_CONTAINER="react-relay-$RUN_TOKEN"
EGRESS_NETWORK="react-egress-$RUN_TOKEN"
SOCKET_VOLUME="react-socket-$RUN_TOKEN"
RUN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/react-sandbox.XXXXXX")"
CREATED_AGENT=
CREATED_RELAY=
CREATED_EGRESS=
CREATED_SOCKET=

cleanup() {
    set +e
    if [[ -n "$CREATED_AGENT" ]]; then
        docker rm -f "$AGENT_CONTAINER" >/dev/null 2>&1
    fi
    if [[ -n "$CREATED_RELAY" ]]; then
        docker rm -f "$RELAY_CONTAINER" >/dev/null 2>&1
    fi
    if [[ -n "$CREATED_EGRESS" ]]; then
        docker network rm "$EGRESS_NETWORK" >/dev/null 2>&1
    fi
    if [[ -n "$CREATED_SOCKET" ]]; then
        docker volume rm "$SOCKET_VOLUME" >/dev/null 2>&1
    fi
    rm -rf "$RUN_TMP"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "${SANDBOX_SKIP_BUILD-}" == 1 ]]; then
    docker image inspect "$AGENT_IMAGE" >/dev/null 2>&1 ||
        die "SANDBOX_SKIP_BUILD=1 but the agent image is absent"
else
    docker build \
        "${build_args[@]}" \
        --file "$ROOT/$SANDBOX_AGENT_DOCKERFILE" \
        --tag "$AGENT_IMAGE" \
        "$ROOT"
fi

if [[ "$MODE" != test ]]; then
    if [[ "${SANDBOX_SKIP_BUILD-}" == 1 ]]; then
        docker image inspect "$RELAY_IMAGE" >/dev/null 2>&1 ||
            die "SANDBOX_SKIP_BUILD=1 but the relay image is absent"
    else
        docker build \
            "${build_args[@]}" \
            --file "$ROOT/sandbox/Dockerfile.relay" \
            --tag "$RELAY_IMAGE" \
            "$ROOT"
    fi

    docker network create "$EGRESS_NETWORK" >/dev/null
    CREATED_EGRESS=1
    docker volume create "$SOCKET_VOLUME" >/dev/null
    CREATED_SOCKET=1

    docker run --rm \
        --network none \
        --read-only \
        --cap-drop ALL \
        --security-opt no-new-privileges=true \
        --user 0:0 \
        --mount "type=volume,source=$SOCKET_VOLUME,target=/run/openai-relay" \
        --entrypoint /bin/sh \
        "$RELAY_IMAGE" \
        -c 'chmod 0777 /run/openai-relay'

    if [[ "$MODE" == verify ]]; then
        OPENAI_API_KEY=verification-key
        export OPENAI_API_KEY
    fi

    docker create \
        --name "$RELAY_CONTAINER" \
        --hostname openai-relay \
        --network "$EGRESS_NETWORK" \
        --read-only \
        --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m \
        --mount "type=volume,source=$SOCKET_VOLUME,target=/run/openai-relay" \
        --cap-drop ALL \
        --security-opt no-new-privileges=true \
        --user 65532:65532 \
        --pids-limit 32 \
        --memory 128m \
        --memory-swap 128m \
        --cpus 0.5 \
        --ulimit nofile=128:128 \
        --ulimit core=0:0 \
        --shm-size 8m \
        --restart no \
        --log-driver local \
        --log-opt max-size=8m \
        --log-opt max-file=1 \
        --log-opt compress=false \
        -e OPENAI_API_KEY \
        -e OPENAI_ALLOWED_MODEL="$OPENAI_MODEL" \
        -e OPENAI_REASONING_EFFORT="$OPENAI_REASONING_EFFORT" \
        -e OPENAI_PAUSE_AFTER_REQUESTS="$OPENAI_CHECKPOINT_AFTER_REQUESTS" \
        -e OPENAI_MAX_REQUESTS="$OPENAI_MAX_REQUESTS" \
        -e OPENAI_MAX_OUTPUT_TOKENS="$OPENAI_MAX_OUTPUT_TOKENS" \
        "$RELAY_IMAGE" >/dev/null
    CREATED_RELAY=1
    docker start "$RELAY_CONTAINER" >/dev/null

    relay_ready=
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        if docker exec "$RELAY_CONTAINER" \
            python3 -c 'import socket; s=socket.socket(socket.AF_UNIX); s.settimeout(1); s.connect("/run/openai-relay/openai.sock"); s.sendall(b"GET /healthz HTTP/1.0\r\nHost: relay\r\n\r\n"); assert b"200 OK" in s.recv(256)' \
            >/dev/null 2>&1; then
            relay_ready=1
            break
        fi
        sleep 0.25
    done
    [[ -n "$relay_ready" ]] || die "the OpenAI relay did not become ready"

fi

agent_args=(
    docker create
    --name "$AGENT_CONTAINER"
    --hostname react-agent
    --read-only
    --tmpfs "/work:rw,nosuid,nodev,noexec,size=$SANDBOX_WORK_SIZE,uid=65532,gid=65532,mode=0700"
    --tmpfs /tmp:rw,nosuid,nodev,exec,size=16m,uid=65532,gid=65532,mode=0700
    --cap-drop ALL
    --security-opt no-new-privileges=true
    --user 65532:65532
    --pids-limit 64
    --memory "$SANDBOX_MEMORY"
    --memory-swap "$SANDBOX_MEMORY"
    --cpus 1
    --ulimit nofile=256:256
    --ulimit core=0:0
    --ulimit fsize=268435456:268435456
    --shm-size 8m
    --init
    --restart no
    --log-driver local
    --log-opt max-size=300m
    --log-opt max-file=1
    --log-opt compress=false
    -e SANDBOX_MODE="$MODE"
    -e SANDBOX_TIMEOUT_SECONDS="$SANDBOX_TIMEOUT_SECONDS"
    -e OPENAI_MODEL="$OPENAI_MODEL"
)

if [[ "$MODE" == test ]]; then
    agent_args+=(--network none)
else
    agent_args+=(
        --network none
        --mount "type=volume,source=$SOCKET_VOLUME,target=/run/openai-relay,readonly"
        -e OPENAI_UNIX_SOCKET=/run/openai-relay/openai.sock
        -e OPENAI_RESPONSES_URL=http://relay/v1/responses
        -e SANDBOX_RELAY_ORIGIN=http://relay
        -e SANDBOX_RELAY_HEALTH_URL=http://relay/healthz
    )
fi
if [[ "$MODE" == run ]]; then
    agent_args+=(-e SANDBOX_PROMPT="$PROMPT")
fi
agent_args+=("$AGENT_IMAGE")

"${agent_args[@]}" >/dev/null
CREATED_AGENT=1

agent_inspect() {
    docker inspect --format "$1" "$AGENT_CONTAINER"
}

[[ "$(agent_inspect '{{.Config.User}}')" == 65532:65532 ]] ||
    die "agent policy check failed: unexpected user"
[[ "$(agent_inspect '{{.HostConfig.ReadonlyRootfs}}')" == true ]] ||
    die "agent policy check failed: root filesystem is not read-only"
[[ "$(agent_inspect '{{.HostConfig.Privileged}}')" == false ]] ||
    die "agent policy check failed: privileged mode is enabled"
[[ "$(agent_inspect '{{json .HostConfig.CapDrop}}')" == '["ALL"]' ]] ||
    die "agent policy check failed: capabilities were not dropped"
[[ "$(agent_inspect '{{.HostConfig.NetworkMode}}')" == none ]] ||
    die "agent policy check failed: network mode is not none"
[[ -z "$(agent_inspect '{{range .Mounts}}{{if eq .Type "bind"}}bind{{end}}{{end}}')" ]] ||
    die "agent policy check failed: a host bind mount is present"
if agent_inspect '{{range .Config.Env}}{{println .}}{{end}}' |
    grep -q '^OPENAI_API_KEY='; then
    die "agent policy check failed: an API key variable is present"
fi
if [[ "$MODE" != test ]]; then
    [[ "$(agent_inspect '{{range .Mounts}}{{if eq .Destination "/run/openai-relay"}}{{.Type}}:{{.RW}}{{end}}{{end}}')" == volume:false ]] ||
        die "agent policy check failed: relay socket mount is not a read-only volume"
fi

ARCHIVE="$RUN_TMP/workspace.tar.gz"
STDERR_CAPTURE="$RUN_TMP/container-stderr.bin"
CHECKPOINT_ACTIVE_IMAGE="$RUN_TMP/checkpoint-active-image.bin"
CHECKPOINT_PROCESSES="$RUN_TMP/checkpoint-processes.bin"
CHECKPOINT_INPUT_SHA256="$RUN_TMP/checkpoint-input-sha256"
checkpoint_captured=
docker start "$AGENT_CONTAINER" >/dev/null

# The command inside the container is untrusted and runs as the same user as
# its in-container timeout. Enforce an independent host deadline as the actual
# boundary; the inner timeout remains useful for graceful termination.
host_deadline=$((SECONDS + SANDBOX_TIMEOUT_SECONDS + 10))
host_timed_out=
while [[ "$(agent_inspect '{{.State.Running}}')" == true ]]; do
    if ((SECONDS >= host_deadline)); then
        host_timed_out=1
        docker kill "$AGENT_CONTAINER" >/dev/null 2>&1 || true
        break
    fi
    if [[ -n "$OPENAI_CHECKPOINT_AFTER_REQUESTS" && -z "$checkpoint_captured" ]]; then
        pause_ready="$(
            docker exec "$RELAY_CONTAINER" \
                python3 -c 'from pathlib import Path; path=Path("/tmp/openai-pause-ready"); print(path.read_text(encoding="ascii").strip() if path.exists() else "")' \
                2>/dev/null || true
        )"
        if [[ "$pause_ready" == "$OPENAI_CHECKPOINT_AFTER_REQUESTS" ]]; then
            docker exec "$RELAY_CONTAINER" \
                python3 -c 'import sys; sys.stdout.buffer.write(open("/tmp/openai-pause-input", "rb").read())' \
                > "$CHECKPOINT_ACTIVE_IMAGE" ||
                die "could not capture the checkpoint active image"
            docker exec "$RELAY_CONTAINER" \
                python3 -c 'print(open("/tmp/openai-pause-input-sha256", encoding="ascii").read().strip())' \
                > "$CHECKPOINT_INPUT_SHA256" ||
                die "could not capture the checkpoint input hash"
            if ! docker top "$AGENT_CONTAINER" -eo pid,ppid,user,stat,args \
                > "$CHECKPOINT_PROCESSES" 2>&1; then
                die "could not capture the checkpoint process table"
            fi
            docker exec "$RELAY_CONTAINER" \
                python3 -c 'open("/tmp/openai-pause-release", "wb").close()' ||
                die "could not release the checkpoint barrier"
            checkpoint_captured=1
            printf 'sandbox: captured checkpoint after %s requests; continuing\n' \
                "$OPENAI_CHECKPOINT_AFTER_REQUESTS"
        fi
    fi
    sleep 1
done
container_status="$(docker inspect --format '{{.State.ExitCode}}' "$AGENT_CONTAINER")"

if [[ -n "$host_timed_out" ]]; then
    die "the host watchdog killed the agent after $((SANDBOX_TIMEOUT_SECONDS + 10)) seconds"
fi

relay_request_count=
if [[ "$MODE" != test ]]; then
    relay_request_count="$(
        docker exec "$RELAY_CONTAINER" \
            python3 -c 'print(open("/tmp/openai-request-count", encoding="ascii").read().strip())'
    )" || die "could not read the trusted relay request count"
    case "$relay_request_count" in
        ''|*[!0-9]*) die "the trusted relay returned an invalid request count" ;;
    esac
    if [[ "$MODE" == verify && "$relay_request_count" != 0 ]]; then
        die "verification unexpectedly made $relay_request_count upstream requests"
    fi
fi

# Container stdout is capped by the local logging driver. It is still fully
# untrusted: retain it as inert bytes and do not invoke a host archive parser.
docker logs "$AGENT_CONTAINER" > "$ARCHIVE" 2> "$STDERR_CAPTURE"

mkdir -p "$ROOT/sandbox-runs"
RUN_DIR="$(mktemp -d "$ROOT/sandbox-runs/run.XXXXXX")"
mv "$ARCHIVE" "$RUN_DIR/untrusted-output.bin"
mv "$STDERR_CAPTURE" "$RUN_DIR/untrusted-stderr.bin"
printf '%s\n' "$container_status" > "$RUN_DIR/container-exit-code"
if [[ -n "$relay_request_count" ]]; then
    printf '%s\n' "$relay_request_count" > "$RUN_DIR/openai-request-count"
fi
printf '%s\n' "$OPENAI_MODEL" > "$RUN_DIR/model"
printf '%s\n' "${OPENAI_REASONING_EFFORT:-default}" > "$RUN_DIR/reasoning-effort"
printf '%s\n' "$SANDBOX_AGENT_IMAGE" > "$RUN_DIR/agent-image"
printf '%s\n' "$SANDBOX_AGENT_DOCKERFILE" > "$RUN_DIR/agent-dockerfile"
if [[ -n "$OPENAI_CHECKPOINT_AFTER_REQUESTS" ]]; then
    printf '%s\n' "$OPENAI_CHECKPOINT_AFTER_REQUESTS" \
        > "$RUN_DIR/checkpoint-after-request"
    if [[ -n "$checkpoint_captured" ]]; then
        mv "$CHECKPOINT_ACTIVE_IMAGE" "$RUN_DIR/checkpoint-active-image.bin"
        mv "$CHECKPOINT_PROCESSES" "$RUN_DIR/checkpoint-processes.bin"
        mv "$CHECKPOINT_INPUT_SHA256" "$RUN_DIR/checkpoint-input-sha256"
        printf 'yes\n' > "$RUN_DIR/checkpoint-captured"
    else
        printf 'no\n' > "$RUN_DIR/checkpoint-captured"
    fi
fi

if [[ "$container_status" == 0 ]]; then
    printf 'sandbox: %s completed successfully\n' "$MODE"
else
    printf 'sandbox: %s exited with status %s\n' "$MODE" "$container_status"
fi
if [[ "$MODE" == run ]]; then
    printf 'sandbox: OpenAI requests attempted: %s (limit %s)\n' \
        "$relay_request_count" "$OPENAI_MAX_REQUESTS"
    printf 'sandbox: model %s; reasoning effort %s\n' \
        "$OPENAI_MODEL" "${OPENAI_REASONING_EFFORT:-default}"
    if [[ -n "$OPENAI_CHECKPOINT_AFTER_REQUESTS" ]]; then
        checkpoint_summary="not reached"
        if [[ -n "$checkpoint_captured" ]]; then
            checkpoint_summary="captured"
        fi
        printf 'sandbox: checkpoint after request %s: %s\n' \
            "$OPENAI_CHECKPOINT_AFTER_REQUESTS" \
            "$checkpoint_summary"
    fi
fi
printf 'sandbox: container exit %s; quarantined artifacts: %s\n' \
    "$container_status" "$RUN_DIR"

exit "$container_status"
