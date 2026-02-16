#!/usr/bin/env bash
set -euo pipefail

ref="$1" # e.g. ghcr.io/org/repo:v1.2.3

# outputs: sha256:....
docker buildx imagetools inspect "$ref" --format '{{json .Manifest.Digest}}' | tr -d '"'
