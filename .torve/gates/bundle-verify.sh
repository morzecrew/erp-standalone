#!/usr/bin/env bash
# torve's `bundle-verify` gate (`.torve/gates.yaml`): the bundle builds and
# verifies, templates rendered against morzer's synthetic context. It is CI's
# build step without the signature or the component pins, on a copy, because
# `release build` writes SHA256SUMS and the version into the tree it builds.
#
#   bash .torve/gates/bundle-verify.sh
set -euo pipefail

if [ ! -f bundle/manifest.yaml ]; then
	echo "bundle-verify: no bundle/manifest.yaml yet; S-0001's first phase arms this gate"
	exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# Tracked and new files only: never a packed images/ or an archive left behind.
git ls-files -z --cached --others --exclude-standard -- bundle | xargs -0 cp --parents -t "${work}"
rm -f "${work}/bundle/SHA256SUMS" "${work}/bundle/SHA256SUMS.minisig"

morzer release build "${work}/bundle" --version 0.0.1-gate.1
morzer release verify "${work}/bundle" --render-check
