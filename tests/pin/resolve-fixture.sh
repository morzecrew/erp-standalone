#!/usr/bin/env bash
#
# Stands in for `scripts/resolve.sh` under tests/pin/run.sh, with the same
# contract -- line 1 the digest a tag resolves to, `schema=<value>` on line 2
# when the image carries the `tech.morze.erp.schema` label -- answered from
# the reference itself, so a test run reaches no registry.
#
#   tests/pin/resolve-fixture.sh ghcr.io/morzecrew/erp-migrations:main
#   sha256:9f2c...
#   schema=0007
#
# The label is zero-padded, as the migrations image's is, so a caller that
# records it as an integer is tested doing so.
set -euo pipefail

if [ $# -ne 1 ]; then
	echo "usage: resolve-fixture.sh <repo:tag>" >&2
	exit 2
fi

ref=$1
printf 'sha256:%s\n' "$(printf '%s' "$ref" | sha256sum | awk '{print $1}')"

case "$ref" in
	*/erp-migrations:*) printf 'schema=0007\n' ;;
esac