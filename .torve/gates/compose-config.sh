#!/usr/bin/env bash
# torve's `compose-config` gate (`.torve/gates.yaml`): Compose reads the
# bundle's file with every `ERP_*` variable morzer would set, and nothing else,
# since morzer filters the rest out of the environment.
#
#   bash .torve/gates/compose-config.sh
set -euo pipefail

compose=bundle/compose/compose.yaml

if [ ! -f "${compose}" ]; then
	echo "compose-config: no ${compose} yet; S-0001's first phase arms this gate"
	exit 0
fi

# shellcheck source=.torve/gates/erp-env.sh
. .torve/gates/erp-env.sh
mapfile -t erp < <(env | grep '^ERP_')
env -i PATH="${PATH}" HOME="${HOME}" "${erp[@]}" docker compose -f "${compose}" config -q
