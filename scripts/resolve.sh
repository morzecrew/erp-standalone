#!/usr/bin/env bash
#
# Resolve an image reference to the digest its tag points at, and report the
# schema label the image carries.
#
#   scripts/resolve.sh ghcr.io/morzecrew/erp-backend:main
#   sha256:6f1c...
#
#   scripts/resolve.sh ghcr.io/morzecrew/erp-migrations:main
#   sha256:9b0d...
#   schema=0007
#
# Line one is always the digest of the tag, read from the registry with
# `docker buildx imagetools inspect`. Line two appears only when the image
# carries the `tech.morze.erp.schema` label -- the migrations image does -- so
# a reader learns which schema a release produces without running it.
#
# This reaches the registry, so it needs the network and a logged-in Docker;
# tests/pin/run.sh drives its caller with this script replaced by a fixture.
set -euo pipefail

schema_label=tech.morze.erp.schema

if [ $# -ne 1 ]; then
	echo "usage: resolve.sh <repo:tag>" >&2
	exit 2
fi

ref=$1
case "$ref" in
	*:*) ;;
	*)
		echo "resolve.sh: '${ref}' names no tag; pass a repo:tag" >&2
		exit 2
		;;
esac

digest=$(docker buildx imagetools inspect "$ref" --format '{{.Manifest.Digest}}')
case "$digest" in
	sha256:*) ;;
	*)
		echo "resolve.sh: '${ref}' resolved to '${digest}', which is not a digest" >&2
		exit 1
		;;
esac
printf '%s\n' "$digest"

# A multi-platform index has no single image config to read labels from. The
# migrations image is published single-platform -- the manifest requires
# amd64 -- so its config is the one asked for below, and an image without one
# simply reports no label.
labels=$(docker buildx imagetools inspect "$ref" \
	--format '{{json .Image.Config.Labels}}' 2>/dev/null || true)
schema=$(printf '%s' "$labels" \
	| jq -r --arg key "$schema_label" 'if type == "object" then (.[$key] // empty) else empty end' 2>/dev/null || true)
if [ -n "$schema" ]; then
	printf 'schema=%s\n' "$schema"
fi