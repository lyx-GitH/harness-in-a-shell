#!/usr/bin/env bash

set -euo pipefail
umask 077

: "${SANDBOX_MODE:?SANDBOX_MODE is required}"
: "${SANDBOX_TIMEOUT_SECONDS:=300}"

cp -R /seed/. /work/
chmod -R u+rwX /work
mkdir -p "$HOME"
cd /work || exit 1

git init -q
git config user.name sandbox
git config user.email sandbox@invalid
git add -A
git commit -qm 'sandbox seed'

log=/work/.sandbox.log
: > "$log"

# The task status is data that must be captured below, not an initialization
# failure that should trigger errexit.
set +e

case "$SANDBOX_MODE" in
    test)
        timeout --signal=TERM --kill-after=5s \
            "${SANDBOX_TIMEOUT_SECONDS}s" bash test.sh > "$log" 2>&1
        status=$?
        ;;
    verify)
        status=0
        {
            if timeout 3 getent ahostsv4 example.com >/dev/null 2>&1; then
                printf 'FAIL: arbitrary DNS resolution is available\n'
                status=1
            else
                printf 'PASS: arbitrary DNS resolution is blocked\n'
            fi

            if curl -fsS --max-time 3 http://1.1.1.1/ >/dev/null 2>&1; then
                printf 'FAIL: direct public-IP access is available\n'
                status=1
            else
                printf 'PASS: direct public-IP access is blocked\n'
            fi

            if curl --unix-socket "$OPENAI_UNIX_SOCKET" --noproxy '*' \
                -fsS --max-time 3 "$SANDBOX_RELAY_HEALTH_URL" >/dev/null; then
                printf 'PASS: the internal OpenAI relay is reachable\n'
            else
                printf 'FAIL: the internal OpenAI relay is unreachable\n'
                status=1
            fi

            if [[ -n "${OPENAI_API_KEY-}" ]]; then
                printf 'FAIL: an API key variable is visible to the agent\n'
                status=1
            else
                printf 'PASS: no API key variable is visible to the agent\n'
            fi

            if [[ -S /var/run/docker.sock || -S /run/docker.sock ]]; then
                printf 'FAIL: a Docker control socket is visible\n'
                status=1
            else
                printf 'PASS: no Docker control socket is visible\n'
            fi

            if touch /etc/react-sandbox-write-probe >/dev/null 2>&1; then
                printf 'FAIL: the root filesystem is writable\n'
                status=1
            else
                printf 'PASS: the root filesystem is read-only\n'
            fi

            if touch /run/openai-relay/write-probe >/dev/null 2>&1; then
                printf 'FAIL: the relay socket volume is writable\n'
                status=1
            else
                printf 'PASS: the relay socket volume is read-only\n'
            fi

            if grep -q '^CapEff:[[:space:]]*0000000000000000$' /proc/self/status \
                && grep -q '^NoNewPrivs:[[:space:]]*1$' /proc/self/status; then
                printf 'PASS: capabilities are empty and no-new-privileges is set\n'
            else
                printf 'FAIL: process privilege controls do not match policy\n'
                status=1
            fi

            denied_status="$(
                curl -sS --max-time 3 \
                    --unix-socket "$OPENAI_UNIX_SOCKET" \
                    --noproxy '*' \
                    -o /tmp/react-relay-denied \
                    -w '%{http_code}' \
                    -X POST \
                    -H 'Content-Type: application/json' \
                    --data '{}' \
                    "$SANDBOX_RELAY_ORIGIN/v1/models"
            )"
            if [[ "$denied_status" == 404 ]]; then
                printf 'PASS: non-Responses relay paths are rejected\n'
            else
                printf 'FAIL: relay returned HTTP %s for a forbidden path\n' \
                    "$denied_status"
                status=1
            fi

            wrong_model_status="$(
                curl -sS --max-time 3 \
                    --unix-socket "$OPENAI_UNIX_SOCKET" \
                    --noproxy '*' \
                    -o /tmp/react-relay-wrong-model \
                    -w '%{http_code}' \
                    -X POST \
                    -H 'Content-Type: application/json' \
                    --data '{"model":"not-allowed","instructions":"x","input":"x"}' \
                    "$OPENAI_RESPONSES_URL"
            )"
            if [[ "$wrong_model_status" == 403 ]]; then
                printf 'PASS: model substitution is rejected\n'
            else
                printf 'FAIL: relay returned HTTP %s for a substituted model\n' \
                    "$wrong_model_status"
                status=1
            fi

            extra_field_status="$(
                curl -sS --max-time 3 \
                    --unix-socket "$OPENAI_UNIX_SOCKET" \
                    --noproxy '*' \
                    -o /tmp/react-relay-extra-field \
                    -w '%{http_code}' \
                    -X POST \
                    -H 'Content-Type: application/json' \
                    --data "{\"model\":\"$OPENAI_MODEL\",\"instructions\":\"x\",\"input\":\"x\",\"tools\":[]}" \
                    "$OPENAI_RESPONSES_URL"
            )"
            if [[ "$extra_field_status" == 400 ]]; then
                printf 'PASS: extra API fields and hosted tools are rejected\n'
            else
                printf 'FAIL: relay returned HTTP %s for an extra API field\n' \
                    "$extra_field_status"
                status=1
            fi

            connect_status="$(
                curl -sS --max-time 3 \
                    --unix-socket "$OPENAI_UNIX_SOCKET" \
                    --noproxy '*' \
                    -o /tmp/react-relay-connect \
                    -w '%{http_code}' \
                    -X CONNECT \
                    "$OPENAI_RESPONSES_URL"
            )"
            if [[ "$connect_status" == 405 ]]; then
                printf 'PASS: CONNECT tunneling is rejected\n'
            else
                printf 'FAIL: relay returned HTTP %s for CONNECT\n' \
                    "$connect_status"
                status=1
            fi
        } > "$log" 2>&1
        ;;
    run)
        printf 'Running the agent with a %ss wall-clock limit.\n' \
            "$SANDBOX_TIMEOUT_SECONDS" >> "$log"
        timeout --signal=TERM --kill-after=5s \
            "${SANDBOX_TIMEOUT_SECONDS}s" \
            bash ReAct.sh "${SANDBOX_PROMPT-}" >> ReAct.sh 2>> "$log"
        status=$?
        ;;
    *)
        printf 'unknown SANDBOX_MODE: %s\n' "$SANDBOX_MODE" > "$log"
        status=2
        ;;
esac

printf '%s\n' "$status" > /work/.sandbox-exit-code

# Normal command stdout and stderr are redirected into the bounded tmpfs.
# Container stdout is reserved for the workspace archive; the host keeps both
# output streams as inert, unparsed bytes because arbitrary Bash can forge them.
tar -C /work -czf - .
archive_status=$?
if ((status == 0 && archive_status != 0)); then
    status=$archive_status
fi
exit "$status"
