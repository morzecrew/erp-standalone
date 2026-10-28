#!/usr/bin/env bash
#
# Rehearse on a workstation what bundle.yml's smoke-install and smoke-update
# prove on the runner: install the published bundle, back up and restore,
# rotate the database password and read through PgBouncer, update to the
# working tree's bundle/, roll back, probing between each.
#
#   scripts/rehearse.sh [--from <oci ref>] [--keep]
#
# Everything runs in a privileged docker:dind container, `erp-rehearsal`, with
# a volume of the same name for its /var/lib/docker, which
# .github/workflows/scripts/rig.sh starts, enters and removes as CI's smoke
# jobs do; a second run refuses while either exists. The container gets copies
# of install-tools.sh and smoke.sh, and of the working tree's bundle/ as git
# sees it, never a mount of the checkout. No credential enters it: the
# workstation's `oras`, with its existing login, pulls the published bundle and
# copies every image either manifest pins into an OCI layout, which the
# container's daemon loads.
#
# Environment:
#   REHEARSE_PUBKEY  the minisign public key that signed the --from bundle
#                    (the repository's MINISIGN_DEV_PUBKEY for :main)
set -euo pipefail

self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "${self_dir}/.." && pwd)
scripts=${root}/.github/workflows/scripts

name=erp-rehearsal
rig=${scripts}/rig.sh
from=ghcr.io/morzecrew/erp-standalone:main
keep=false

usage() {
	cat <<EOF
Usage: scripts/rehearse.sh [--from <oci ref>] [--keep]

Rehearse a bundle's install, backup, restore, password rotation, update and
rollback in a privileged docker:29.7.2-dind container named ${name}, as CI's
smoke jobs do. .github/workflows/scripts/rig.sh starts it, enters it and
removes it.
It installs the --from bundle, updates it to the working tree's bundle/
built as 0.0.0-rehearsal.<unix time>, and rolls back.

Options:
  --from <oci ref>  the published bundle to start from (default: ${from})
  --keep            leave the container and its volume for inspection
  -h, --help        print this help

The workstation needs:
  docker            to run the container
  oras              logged in to ghcr.io; it pulls the bundle and its images
  yq                mikefarah's yq v4, to read each manifest's images

REHEARSE_PUBKEY must hold the minisign public key that signed the --from
bundle: the repository's MINISIGN_DEV_PUBKEY for :main, its
MINISIGN_RELEASE_PUBKEY for :stable.
EOF
}

die() {
	echo "rehearse.sh: $*" >&2
	exit 1
}

while [ $# -gt 0 ]; do
	case "$1" in
	--from)
		[ $# -ge 2 ] || die "--from needs an OCI reference"
		from=$2
		shift 2
		;;
	--keep)
		keep=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage >&2
		exit 2
		;;
	esac
done

for tool in docker oras yq git tar bash; do
	command -v "${tool}" >/dev/null || die "${tool} is not on PATH; see --help"
done
[ -f "${rig}" ] || die "${rig} is missing; see --help"
yq --version 2>/dev/null | grep -q mikefarah || die "yq on PATH is not mikefarah's yq v4; see --help"
from_pubkey=${REHEARSE_PUBKEY:-}
[ -n "${from_pubkey}" ] || die "set REHEARSE_PUBKEY to the public key that signed ${from}; see --help"

if docker container inspect "${name}" >/dev/null 2>&1; then
	die "container ${name} exists: another rehearsal is up, or a --keep one was left; docker rm -f ${name}"
fi
if docker volume inspect "${name}" >/dev/null 2>&1; then
	die "volume ${name} exists: another rehearsal is up, or a --keep one was left; docker volume rm ${name}"
fi

work=$(mktemp -d)
started=false
cleanup() {
	rm -rf "${work}"
	"${started}" || return 0
	if "${keep}"; then
		echo "rehearse.sh: kept; remove with: bash ${rig} stop ${name}"
	else
		bash "${rig}" stop "${name}" || true
	fi
}
trap cleanup EXIT

in_box() {
	bash "${rig}" exec "${name}" "$@"
}

# The published bundle, before anything is started.
echo "rehearse.sh: pulling ${from}"
oras pull "${from}" -o "${work}/published" >/dev/null
published=$(find "${work}/published" -maxdepth 1 -name '*.tar.zst' -print -quit)
[ -n "${published}" ] || die "${from} holds no bundle archive"

# rig.sh's start refuses a name already taken, and removes the container and
# its volume itself when the daemon never answers or its packages fail.
echo "rehearse.sh: starting ${name}"
bash "${rig}" start "${name}"
started=true

in_box mkdir -p /rehearsal/dist /rehearsal/published
bash "${rig}" cp "${name}" "${scripts}/install-tools.sh" /rehearsal/install-tools.sh
bash "${rig}" cp "${name}" "${scripts}/smoke.sh" /rehearsal/smoke.sh
in_box bash /rehearsal/install-tools.sh morzer sops age

# The tree as git sees it, so nothing it ignores enters the container.
git -C "${root}" ls-files -z --cached --others --exclude-standard -- bundle \
	| tar -C "${root}" --null -T - -cf - \
	| bash "${rig}" cp "${name}" - /rehearsal

version=0.0.0-rehearsal.$(date +%s)
echo "rehearse.sh: building ${version}"
# shellcheck disable=SC2016 # expanded by the container's bash
in_box bash -c '
	set -euo pipefail
	cd /rehearsal
	if ! out=$(morzer release build bundle --version "$1" --json); then
		printf "%s\n" "${out}" >&2
		exit 1
	fi
	umask 077
	minisign -G -W -p rehearsal.pub -s rehearsal.key >/dev/null
	minisign -S -s rehearsal.key -m bundle/SHA256SUMS >/dev/null
	morzer release verify bundle --signing-key "$(sed -n 2p rehearsal.pub)"
	if ! out=$(morzer release archive bundle -o "dist/erp-$1.tar.zst" --json); then
		printf "%s\n" "${out}" >&2
		exit 1
	fi
' rehearse "${version}"
archive=/rehearsal/dist/erp-${version}.tar.zst
pubkey=$(in_box sed -n 2p /rehearsal/rehearsal.pub)

box_published=/rehearsal/published/$(basename "${published}")
bash "${rig}" cp "${name}" "${published}" "${box_published}"
# shellcheck disable=SC2016 # expanded by the container's bash
in_box bash -c '
	manifest=$(tar -I zstd -tf "$1" | grep -E "(^|/)manifest\.yaml$" | awk "{ print length, \$0 }" \
		| sort -n | sed -n "1s/^[0-9]* //p")
	[ -n "${manifest}" ] || { echo "$1 holds no manifest.yaml" >&2; exit 1; }
	tar -I zstd -xOf "$1" "${manifest}"
' rehearse "${box_published}" >"${work}/published-manifest.yaml"

# smoke.sh's own pin of morzer's volume helper.
helper=$(sed -n 's/^volume_helper=//p' "${scripts}/smoke.sh")
[ -n "${helper}" ] || die "smoke.sh names no volume_helper"

# Load one pinned image into the container's daemon under the name a pull by
# its pin would give it: `repo:tag`, or `repo@digest` when it has no tag.
load_image() {
	local pin=$1 ref digest first source image layout
	case "${pin}" in
	*@sha256:*) ;;
	*) die "${pin} is not pinned by digest" ;;
	esac
	ref=${pin%@*}
	digest=${pin##*@}
	first=${ref%%/*}
	if [[ ${ref} != */* ]]; then
		ref=docker.io/library/${ref}
	elif [[ ${first} != *.* && ${first} != *:* && ${first} != localhost ]]; then
		ref=docker.io/${ref}
	fi
	[[ ${ref##*/} != *:* ]] || ref=${ref%:*}
	# By digest, never by tag: the published bundle and the working tree can
	# pin two digests under one tag, and a second load under the tag would
	# leave the first unnamed and its pin unresolvable.
	image=${ref}@${digest}
	# Docker Hub's registry answers at registry-1.docker.io, not docker.io.
	source=${ref/#docker.io\//registry-1.docker.io/}@${digest}

	echo "rehearse.sh: loading ${image}"
	layout=$(mktemp -d "${work}/layout.XXXXXX")
	oras copy --to-oci-layout "${source}" "${layout}:rehearsal" >/dev/null
	# oras lists the platform and attestation manifests it copied beside the
	# tagged index; named too, the last would take the name from it.
	IMAGE=${image} yq -i -p json -o json '
		.manifests |= map(select(.annotations."org.opencontainers.image.ref.name" == "rehearsal")) |
		.manifests[0].annotations."io.containerd.image.name" = strenv(IMAGE)' "${layout}/index.json"
	tar -C "${layout}" -cf - oci-layout index.json blobs | in_box docker load >/dev/null
	rm -rf "${layout}"
}

{
	yq -r '.images[]' "${root}/bundle/manifest.yaml"
	yq -r '.images[]' "${work}/published-manifest.yaml"
	printf '%s\n' "${helper}"
} | sort -u >"${work}/images"
while read -r pin; do
	load_image "${pin}"
done <"${work}/images"

smoke() {
	echo "rehearse.sh: smoke.sh $1"
	if ! in_box bash /rehearsal/smoke.sh "$@"; then
		in_box bash /rehearsal/smoke.sh diagnose || true
		die "smoke.sh $1 failed"
	fi
}

smoke install "${box_published}" "${from_pubkey}" "${pubkey}"
smoke probe
smoke backup-restore
smoke rotate-db-password
smoke probe
smoke update "${archive}"
smoke probe
smoke rollback "${box_published}" "${archive}"
smoke probe
echo "rehearse.sh: ${from} -> ${version} rehearsed"
