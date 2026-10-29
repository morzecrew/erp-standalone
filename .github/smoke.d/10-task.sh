#!/usr/bin/env bash
#
# A task: a one-shot backend container, through the entrypoint that reads its
# secrets. `repair` changes nothing on a fresh install.
set -euo pipefail
# shellcheck source=/dev/null
. /rig/smoke-lib.sh

sudo morzer task list
sudo morzer --verbose task run repair
