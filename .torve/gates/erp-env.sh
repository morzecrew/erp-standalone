# shellcheck shell=bash
# Sourced by the compose gates: the `ERP_*` variables morzer gives Compose
# (pages/docs/reference/variables.md), from bundle/manifest.yaml where it has
# them and invented where an installation would supply them. Secrets go under
# .torve/tmp, inside the checkout, because the nested daemon shares the
# checkout's mount and not the sandbox's /tmp.
manifest=bundle/manifest.yaml

while IFS=$'\t' read -r name value; do
	export "ERP_IMAGE_${name}=${value}"
done < <(yq -r '.images // {} | to_entries[] | [(.key | upcase | sub("[-.]"; "_")), .value] | @tsv' "${manifest}")

while IFS=$'\t' read -r name value; do
	export "ERP_PARAM_${name}=${value}"
done < <(yq -r '.parameters // {} | to_entries[] | [(.key | upcase | sub("[-.]"; "_")), (.value.default // "")] | @tsv' "${manifest}")

export ERP_SECRETS_DIR="${PWD}/.torve/tmp/erp/secrets"
export ERP_RELEASE_DIR="${PWD}/bundle"
export ERP_DATA_DIR="${PWD}/.torve/tmp/erp/data"
export ERP_VERSION=0.0.1-gate.1
