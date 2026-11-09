#!/usr/bin/env bash
# torve's `edge-smoke` gate (`.torve/gates.yaml`): the bundle's Compose project
# on the task's nested Docker daemon, with the real infrastructure images and
# the edge, and stand-ins for the private component images an agent cannot pull
# (`tests/compose/stub.yaml`). It proves the edge's routes and its body limit;
# the real components, migrations and sign-in are CI's smoke test, on the
# runner, with `morzer init` and `apply`.
#
# The stand-ins' contract, which this script holds them to: every service built
# from the backend image reads a request's whole body and answers 200 with the
# body `backend`, and the frontend likewise with `frontend`, each with a health
# check that passes. Rehearsed on 2026-10-23 against a fixture bundle with
# Python stand-ins: green, and red when `/mcp` left the backend's routes.
#
#   bash .torve/gates/edge-smoke.sh
set -euo pipefail

compose=bundle/compose/compose.yaml
stub=tests/compose/stub.yaml

if [ ! -f "${compose}" ] || [ ! -f "${stub}" ]; then
	echo "edge-smoke: no ${compose} or ${stub} yet; S-0001's first phase arms this gate"
	exit 0
fi

# shellcheck source=.torve/gates/erp-env.sh
. .torve/gates/erp-env.sh
export COMPOSE_PROJECT_NAME=erp-edge-smoke

tmp="${PWD}/.torve/tmp/erp"
rm -rf "${tmp}"
mkdir -p "${ERP_SECRETS_DIR}" "${ERP_DATA_DIR}"

# Every secret the schema declares, with a value of its generator's shape. The
# sandbox runs as the host's user and cannot give a file to the users the
# containers run as, so the files are world-readable here; morzer renders 0400.
while IFS=$'\t' read -r name kind; do
	case "${kind}" in
	base64) head -c 32 /dev/urandom | base64 -w0 >"${ERP_SECRETS_DIR}/${name}" ;;
	*) head -c 24 /dev/urandom | base64 -w0 | tr -d '+/=' >"${ERP_SECRETS_DIR}/${name}" ;;
	esac
	chmod 0444 "${ERP_SECRETS_DIR}/${name}"
done < <(yq -r '.secrets // [] | .[] | [(.file // .name), (.generator.kind // "password")] | @tsv' bundle/secrets.schema.yaml)

dc() { docker compose -f "${compose}" -f "${stub}" "$@"; }
cleanup() {
	status=$?
	if [ "${status}" -ne 0 ]; then
		dc ps -a || true
		dc logs --no-color --tail 80 || true
	fi
	dc down -v --remove-orphans >/dev/null 2>&1 || true
	rm -rf "${tmp}"
	exit "${status}"
}
trap cleanup EXIT

dc up -d --wait --wait-timeout 300

health="http://127.0.0.1:${ERP_PARAM_HEALTH_PORT:?bundle/manifest.yaml declares no health_port}"

expect() { # <path> <body>
	local got
	got="$(curl -fsS --max-time 10 "${health}$1")"
	[ "${got}" = "$2" ] || { echo "edge-smoke: $1 answered '${got}', not '$2'" >&2; exit 1; }
	echo "edge-smoke: $1 -> $2"
}

curl -fsS --max-time 10 -o /dev/null "${health}/__platform_healthz"
echo "edge-smoke: /__platform_healthz answers"
for path in /health /v1/openapi.json /v1/docs /mcp /.well-known/oauth-protected-resource; do
	expect "${path}" backend
done
for path in / /plans /assets/index.js; do
	expect "${path}" frontend
done

# The backend's Prometheus scrape answers on the loopback health listener only;
# on the public port /metrics is the frontend's.
expect /metrics backend
got="$(curl -fsS --max-time 10 "http://127.0.0.1:${ERP_PARAM_HTTP_PORT:?}/metrics")"
[ "${got}" = frontend ] || { echo "edge-smoke: public /metrics answered '${got}', not 'frontend'" >&2; exit 1; }
echo "edge-smoke: public /metrics -> frontend"

# A 50 MiB attachment reaches the backend; one past 51 MiB is refused at the
# edge. Sent as a multipart upload, as the frontend sends attachments, and with
# no `Expect: 100-continue`, which curl sends past 1 MiB and CRS refuses.
upload() { # <bytes> -> HTTP status
	head -c "$1" /dev/zero >"${tmp}/body"
	curl -sS --max-time 120 -o /dev/null -w '%{http_code}' -H 'Expect:' \
		-F "file=@${tmp}/body;type=application/octet-stream" \
		"${health}/v1/attachments/probe"
}
code="$(upload 52428800)"
[ "${code}" = 200 ] || { echo "edge-smoke: a 50 MiB body got ${code}, not 200" >&2; exit 1; }
echo "edge-smoke: 50 MiB -> 200"
code="$(upload 53477377)"
[ "${code}" = 413 ] || { echo "edge-smoke: a body past 51 MiB got ${code}, not 413" >&2; exit 1; }
echo "edge-smoke: past 51 MiB -> 413"
