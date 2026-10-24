#!/usr/bin/env bash
#
# Pin the three component images in `bundle/manifest.yaml` to the digests
# their tags point at right now, and record the migrations image's
# `tech.morze.erp.schema` label in the three `compatibility.database_schema_*`
# fields. `--release` also writes `compatibility.rollback_safe`, true only when
# both components.yaml entries declare it; plain pinning leaves it as
# committed. No other value in the manifest changes, and a second run leaves
# the file byte-identical.
#
#   scripts/pin.sh             pin `main` -- the dev channel
#   scripts/pin.sh --release   pin the versions `components.yaml` names
#
# A release is made of component releases, so `--release` refuses a tag that
# is not `X.Y.Z` -- `main` and `sha-*` among them. The migrations image always
# ships beside the backend, so it takes the backend's version. In the dev
# channel all three carry `main`, whatever a previous release pinned.
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

# The two components components.yaml names; the migrations image follows the
# backend's version rather than having one of its own.
component_keys=(backend frontend)

die() {
	echo "pin.sh: $*" >&2
	exit 1
}

usage() {
	echo "usage: pin.sh [--release]"
}

release=false
for arg in "$@"; do
	case "$arg" in
		--release) release=true ;;
		--help | -h)
			usage
			exit 0
			;;
		*) die "unknown argument '${arg}' (usage: pin.sh [--release])" ;;
	esac
done

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

# Ask the resolver about a `repo:tag`, leaving its answer in RESOLVED_DIGEST
# and RESOLVED_SCHEMA (empty when the image carries no schema label).
resolve_ref() {
	local out
	out=$("$resolve" "$1") || die "the resolver failed for $1"
	RESOLVED_DIGEST=$(printf '%s\n' "$out" | sed -n '1p')
	RESOLVED_SCHEMA=$(printf '%s\n' "$out" | sed -n 's/^schema=//p' | sed -n '1p')
	[[ $RESOLVED_DIGEST =~ ^sha256:[0-9a-f]{64}$ ]] \
		|| die "the resolver printed no digest for $1: '${RESOLVED_DIGEST}'"
}

# The version components.yaml names for a component. A release is assembled
# from component releases, so anything but `X.Y.Z` is refused.
version_of() {
	local name=$1 version
	version=$(yq -r ".${name}.version" "$components")
	case "$version" in
		'' | null) die "components.yaml names no ${name}.version" ;;
		main) die "components.yaml: ${name}.version is 'main'; a release is made of component releases, not of the branch" ;;
		sha-*) die "components.yaml: ${name}.version is '${version}'; a release names an X.Y.Z, not a commit" ;;
	esac
	[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
		|| die "components.yaml: ${name}.version '${version}' is not X.Y.Z"
	printf '%s\n' "$version"
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

# Every field D-15 gives a component entry. A field nobody filled in is a
# release input that is missing, not a default.
require_entry() {
	local name=$1
	yq -e "has(\"${name}\") and (.${name} | has(\"image\")) and (.${name} | has(\"version\")) and (.${name} | has(\"rollback_safe\")) and (.${name} | has(\"notes\"))" "$components" >/dev/null \
		|| die "components.yaml: ${name} needs image, version, rollback_safe and notes"
}

backend_tag=main
frontend_tag=main
if $release; then
	[ -f "$components" ] || die "no components.yaml under ${root}; release mode reads the versions it names"
	for name in "${component_keys[@]}"; do
		require_entry "$name"
		[ "$(yq -r ".${name}.image" "$components")" = "$(repo_of "$name")" ] \
			|| die "components.yaml's ${name}.image and bundle/manifest.yaml's images.${name} are not the same repository"
	done
	backend_tag=$(version_of backend)
	frontend_tag=$(version_of frontend)
	# D-4: a rollback across the pair is safe only when both component
	# releases are; the conjunction is what the bundle declares.
	backend_safe=$(rollback_safe_of backend)
	frontend_safe=$(rollback_safe_of frontend)
	if [ "$backend_safe" = true ] && [ "$frontend_safe" = true ]; then
		rollback_safe=true
	else
		rollback_safe=false
	fi
fi
# D-15: the migrations image ships with the backend's commit or version.
migrations_tag=$backend_tag

backend_ref="$(repo_of backend):${backend_tag}"
resolve_ref "$backend_ref"
backend_pin="${backend_ref}@${RESOLVED_DIGEST}"

migrations_ref="$(repo_of migrations):${migrations_tag}"
resolve_ref "$migrations_ref"
migrations_pin="${migrations_ref}@${RESOLVED_DIGEST}"
schema=${RESOLVED_SCHEMA}
[ -n "$schema" ] \
	|| die "${migrations_ref} carries no tech.morze.erp.schema label; the bundle cannot say which schema it produces"
[[ $schema =~ ^[0-9]+$ ]] \
	|| die "${migrations_ref}'s tech.morze.erp.schema label is '${schema}', not a number"
# The three fields are integers and a label may be zero-padded (`0007`), which
# YAML would read as octal; pin the number itself.
schema=$((10#$schema))

frontend_ref="$(repo_of frontend):${frontend_tag}"
resolve_ref "$frontend_ref"
frontend_pin="${frontend_ref}@${RESOLVED_DIGEST}"

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