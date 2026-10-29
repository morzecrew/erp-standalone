#!/usr/bin/env bash
#
# Pin the three component images in `bundle/manifest.yaml` to their digests,
# and record the migrations image's `tech.morze.erp.schema` label in the three
# `compatibility.database_schema_*` fields. `--release` also writes
# `compatibility.rollback_safe`, true only when both components.yaml entries
# declare it; plain pinning leaves it as committed. No other value in the
# manifest changes, and a second run leaves the file byte-identical.
#
#   scripts/pin.sh                  pin `main` -- the dev channel
#   scripts/pin.sh --release X.Y.Z  promote the committed pins as release X.Y.Z
#
# The dev channel pins the digest each component's `main` points at right now.
# A release ships what the dev channel installed and smoke-tested, so
# `--release` resolves no tag: it keeps each digest the committed manifest
# pins and names it under the tag `bundle-X.Y.Z`, which publish.yml then puts
# on the image so the components' retention keeps it. It refuses the all-zero
# placeholder and a digest the registry no longer holds.
#
# The digests come from `scripts/resolve.sh`, which reaches the registry.
# tests/pin/run.sh drives this script with the environment below pointing at a
# fixture, so no test run touches the network.
#
# Environment:
#   PIN_ROOT  the tree to pin      (default: the repository this script is in)
#   RESOLVE   the resolver to call (default: resolve.sh beside this script)
set -euo pipefail

self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=${PIN_ROOT:-$(cd "${self_dir}/.." && pwd)}
resolve=${RESOLVE:-"${self_dir}/resolve.sh"}

manifest=${root}/bundle/manifest.yaml
components=${root}/components.yaml

die() {
	echo "pin.sh: $*" >&2
	exit 1
}

usage() {
	echo "usage: pin.sh [--release X.Y.Z]"
}

release=false
version=
while [ $# -gt 0 ]; do
	case "$1" in
		--release)
			[ $# -ge 2 ] || die "--release takes the release's version ($(usage))"
			release=true
			version=$2
			shift
			;;
		--help | -h)
			usage
			exit 0
			;;
		*) die "unknown argument '$1' ($(usage))" ;;
	esac
	shift
done
if $release; then
	[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
		|| die "--release takes the release's X.Y.Z, not '${version}'"
fi

[ -f "$manifest" ] || die "no bundle/manifest.yaml under ${root}"
[ -f "$resolve" ] || die "no resolver at ${resolve}"

# The repository an image key is pinned in, without its tag and digest:
# `ghcr.io/morzecrew/erp-backend:main@sha256:...` -> `ghcr.io/morzecrew/erp-backend`.
repo_of() {
	local value
	value=$(yq -r ".images.$1" "$manifest")
	case "$value" in
		'' | null) die "bundle/manifest.yaml names no images.$1" ;;
	esac
	printf '%s\n' "${value%@sha256:*}" | sed -E 's/:[^:/]+$//'
}

# Ask the resolver about a `repo:tag` or `repo@digest`, leaving its answer in
# RESOLVED_DIGEST and RESOLVED_SCHEMA (empty when the image carries no schema
# label).
resolve_ref() {
	local out
	out=$("$resolve" "$1") || die "the resolver failed for $1${resolve_hint}"
	RESOLVED_DIGEST=$(printf '%s\n' "$out" | sed -n '1p')
	RESOLVED_SCHEMA=$(printf '%s\n' "$out" | sed -n 's/^schema=//p' | sed -n '1p')
	[[ $RESOLVED_DIGEST =~ ^sha256:[0-9a-f]{64}$ ]] \
		|| die "the resolver printed no digest for $1: '${RESOLVED_DIGEST}'"
}

# Whether a rollback is safe, as components.yaml declares it for one
# component. Only a YAML boolean is a release input: a quoted `"true"` is a
# string, which is a wrong value, not a truthy one.
rollback_safe_of() {
	local name=$1
	yq -e ".${name}.rollback_safe | tag == \"!!bool\"" "$components" >/dev/null 2>&1 \
		|| die "components.yaml: ${name}.rollback_safe is not true or false"
	yq -r ".${name}.rollback_safe" "$components"
}

# The digest the committed manifest pins an image key to. The all-zero
# placeholder (S-0001/D-2) is no pin at all: nothing main.yml installed.
committed_digest() {
	local value digest
	value=$(yq -r ".images.$1" "$manifest")
	digest=${value##*@}
	[[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] \
		|| die "bundle/manifest.yaml pins images.$1 to no digest: '${value}'"
	if [[ $digest =~ ^sha256:0+$ ]]; then
		die "bundle/manifest.yaml's images.$1 holds the placeholder digest; a release promotes what main.yml pinned"
	fi
	printf '%s\n' "$digest"
}

# Pin one image key, leaving the pin in PINNED: the digest `main` points at on
# the dev channel, and in a release the committed digest under `bundle-X.Y.Z`.
pin_component() {
	local repo digest
	repo=$(repo_of "$1")
	if $release; then
		digest=$(committed_digest "$1")
		resolve_ref "${repo}@${digest}"
		PINNED="${repo}:bundle-${version}@${RESOLVED_DIGEST}"
	else
		resolve_ref "${repo}:main"
		PINNED="${repo}:main@${RESOLVED_DIGEST}"
	fi
}

resolve_hint=
if $release; then
	[ -f "$components" ] || die "no components.yaml under ${root}; release mode reads rollback_safe from it"
	# D-4: a rollback across the pair is safe only when both components are;
	# the conjunction is what the bundle declares.
	backend_safe=$(rollback_safe_of backend)
	frontend_safe=$(rollback_safe_of frontend)
	if [ "$backend_safe" = true ] && [ "$frontend_safe" = true ]; then
		rollback_safe=true
	else
		rollback_safe=false
	fi
	resolve_hint="; the registry no longer holds the digest main.yml pinned, which the component's retention prunes, so release a newer commit of main"
fi

pin_component backend
backend_pin=$PINNED

# D-15: main.yml pins the migrations image beside the backend.
pin_component migrations
migrations_pin=$PINNED
schema=${RESOLVED_SCHEMA}
[ -n "$schema" ] \
	|| die "${migrations_pin} carries no tech.morze.erp.schema label; the bundle cannot say which schema it produces"
[[ $schema =~ ^[0-9]+$ ]] \
	|| die "${migrations_pin}'s tech.morze.erp.schema label is '${schema}', not a number"
# The three fields are integers and a label may be zero-padded (`0007`), which
# YAML would read as octal; pin the number itself.
schema=$((10#$schema))

pin_component frontend
frontend_pin=$PINNED

# D-15: only the three component pins and the three schema fields are written;
# D-4 adds `compatibility.rollback_safe` in release mode alone, so a plain pin
# leaves the committed value alone. `yq` re-emits the document, so the manifest
# keeps its keys, values and comments and loses only the blank lines between
# its sections.
export PIN_BACKEND=$backend_pin
export PIN_MIGRATIONS=$migrations_pin
export PIN_FRONTEND=$frontend_pin
export PIN_SCHEMA=$schema
update='
	.images.backend = strenv(PIN_BACKEND) |
	.images.migrations = strenv(PIN_MIGRATIONS) |
	.images.frontend = strenv(PIN_FRONTEND) |
	.compatibility.database_schema_produces = (strenv(PIN_SCHEMA) | tonumber) |
	.compatibility.database_schema_min = (strenv(PIN_SCHEMA) | tonumber) |
	.compatibility.database_schema_max = (strenv(PIN_SCHEMA) | tonumber)'
if $release; then
	update="${update} | .compatibility.rollback_safe = ${rollback_safe}"
fi
yq -i "$update" "$manifest"

printf 'pin.sh: backend    %s\n' "$backend_pin"
printf 'pin.sh: migrations %s (schema %s)\n' "$migrations_pin" "$schema"
printf 'pin.sh: frontend   %s\n' "$frontend_pin"
if $release; then
	printf 'pin.sh: rollback_safe %s\n' "$rollback_safe"
fi