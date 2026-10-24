#!/usr/bin/env bash
#
# Stands in for the `docker` CLI under tests/pin/run.sh, placed on PATH as
# `docker`. It answers the two `buildx imagetools inspect` templates
# `scripts/resolve.sh` asks, from the reference alone: no registry and no
# daemon. Nothing else is implemented, so a resolver that invents a third call
# fails the test run rather than quietly passing.
#
#   docker buildx imagetools inspect <repo:tag> --format <template>
set -euo pipefail

# docker buildx imagetools inspect <ref> --format <template>
ref=${4:?usage: docker buildx imagetools inspect <ref> --format <template>}
template=${6:?usage: docker buildx imagetools inspect <ref> --format <template>}

case "$template" in
	'{{.Manifest.Digest}}')
		printf 'sha256:%s\n' "$(printf '%s' "$ref" | sha256sum | awk '{print $1}')"
		;;
	'{{json .Image.Config.Labels}}')
		case "$ref" in
			*/erp-migrations:*) printf '{"tech.morze.erp.schema":"0007"}\n' ;;
			*) printf 'null\n' ;;
		esac
		;;
	*)
		echo "docker-fixture: unexpected template '${template}'" >&2
		exit 1
		;;
esac