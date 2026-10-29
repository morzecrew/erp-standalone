#!/usr/bin/env bash
#
# Drives scripts/pin.sh over throwaway copies of the tree, with the resolver
# `pin.sh` would call replaced by tests/pin/resolve-fixture.sh and a stand-in
# `oras` for scripts/resolve.sh's own check, so nothing here reaches the
# network and the committed bundle/manifest.yaml is never written.
#
#   bash tests/pin/run.sh
#
# It checks what D-15 asks for: a dev pin is `main`, a release keeps the
# digests the dev pin committed under `bundle-X.Y.Z` and refuses a placeholder
# or pruned digest and a version that is not X.Y.Z, the migrations label lands
# in all three compatibility fields, pinning twice changes nothing, and no
# other value in the manifest moves -- plus what D-4 asks for: release mode
# writes `compatibility.rollback_safe` true only when both components.yaml
# entries are, and refuses a value that is not a boolean, while a plain pin
# leaves the committed value alone.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "${here}/../.." && pwd)

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

# The fixtures are copied out and made executable, so a test run does not
# depend on the modes of the files it reads.
mkdir -p "${work}/bin"
cp "${here}/resolve-fixture.sh" "${work}/resolve.sh"
cp "${here}/oras-fixture.sh" "${work}/bin/oras"
chmod +x "${work}/resolve.sh" "${work}/bin/oras"
resolve_fixture=${work}/resolve.sh

# The manifest as committed, to compare a pinned copy against.
original=${work}/original.yaml
cp "${repo}/bundle/manifest.yaml" "${original}"

failures=0
ok() { echo "ok - $*"; }
fail() { echo "not ok - $*" >&2; failures=$((failures + 1)); }

expect() { # expect <what> <expected> <actual>
	if [ "$2" = "$3" ]; then
		ok "$1"
	else
		fail "$1: expected '$2', got '$3'"
	fi
}

expect_lines() { # expect_lines <what> <expected> <actual>
	expect "$1" "$2" "$(printf '%s\n' "$3" | wc -l | tr -d ' ')"
}

refuse() { # refuse <what> <message substring> <command...>
	local what=$1 want=$2 out
	shift 2
	if out=$("$@" 2>&1); then
		fail "$what: the command succeeded"
	elif printf '%s' "${out}" | grep -qF -- "${want}"; then
		ok "$what"
	else
		fail "$what: refused, but not for '${want}': ${out}"
	fi
}

# A tree to pin: a copy of the committed manifest and a components.yaml.
new_tree() { # new_tree <name>
	local dir=${work}/$1
	mkdir -p "${dir}/bundle"
	cp "${original}" "${dir}/bundle/manifest.yaml"
	printf '%s' "${dir}"
}

write_components() { # write_components <tree> <backend safe> <frontend safe>
	cat >"$1/components.yaml" <<-EOF
		backend:
		  rollback_safe: $2
		frontend:
		  rollback_safe: $3
	EOF
}

pin() { # pin <tree> [args...]
	local tree=$1
	shift
	PIN_ROOT="${tree}" RESOLVE="${resolve_fixture}" bash "${repo}/scripts/pin.sh" "$@"
}

yaml_get() { yq -r "$2" "$1/bundle/manifest.yaml"; }

hash() { sha256sum "$1" | cut -d' ' -f1; }

# What the fixture answers for a reference; the expectations below are built
# from it rather than from digests written down here.
fixture_digest() { "${resolve_fixture}" "$1" | sed -n '1p'; }

# Everything pin.sh is allowed to write, removed: what is left must be the
# manifest it was given.
strip() {
	yq -o=json 'del(
		.images.backend, .images.migrations, .images.frontend,
		.compatibility.database_schema_produces,
		.compatibility.database_schema_min,
		.compatibility.database_schema_max)' "$1"
}

echo "# the dev channel pins main"
dev=$(new_tree dev)
# components.yaml disagrees with the manifest about rollback_safe, so a plain
# pin that touched the field would be caught below.
write_components "${dev}" false false
pin "${dev}" >/dev/null

expect "pins the backend to main" \
	"ghcr.io/morzecrew/erp-backend:main@$(fixture_digest ghcr.io/morzecrew/erp-backend:main)" \
	"$(yaml_get "${dev}" '.images.backend')"
expect "pins the migrations to main" \
	"ghcr.io/morzecrew/erp-migrations:main@$(fixture_digest ghcr.io/morzecrew/erp-migrations:main)" \
	"$(yaml_get "${dev}" '.images.migrations')"
expect "pins the frontend to main" \
	"ghcr.io/morzecrew/erp-frontend:main@$(fixture_digest ghcr.io/morzecrew/erp-frontend:main)" \
	"$(yaml_get "${dev}" '.images.frontend')"

# The fixture's label is zero-padded -- `0007`, as the migrations image's is --
# and the manifest's fields are integers, so the number it names lands there.
echo "# the migrations label reaches all three schema fields"
expect "database_schema_produces" 7 "$(yaml_get "${dev}" '.compatibility.database_schema_produces')"
expect "database_schema_min" 7 "$(yaml_get "${dev}" '.compatibility.database_schema_min')"
expect "database_schema_max" 7 "$(yaml_get "${dev}" '.compatibility.database_schema_max')"

# D-4: plain pinning writes no rollback_safe, so the committed value survives
# even though components.yaml says otherwise.
echo "# plain pinning leaves rollback_safe as committed"
expect "rollback_safe keeps the committed true" true "$(yaml_get "${dev}" '.compatibility.rollback_safe')"

echo "# nothing else in the manifest moves"
if diff <(strip "${original}") <(strip "${dev}/bundle/manifest.yaml") >/dev/null; then
	ok "every other key holds its value"
else
	fail "every other key holds its value"
	diff <(strip "${original}") <(strip "${dev}/bundle/manifest.yaml") | sed 's/^/    /' || true
fi
if diff <(grep -E '^[[:space:]]*#' "${original}") \
	<(grep -E '^[[:space:]]*#' "${dev}/bundle/manifest.yaml") >/dev/null; then
	ok "the manifest's comments survive"
else
	fail "the manifest's comments survive"
fi

echo "# pinning twice changes nothing"
pinned=$(hash "${dev}/bundle/manifest.yaml")
pin "${dev}" >/dev/null
expect "a second pin writes the same bytes" "${pinned}" "$(hash "${dev}/bundle/manifest.yaml")"

# A release ships what the dev channel pinned, not what `main` points at by the
# time it is cut: the committed digests below are not the ones the fixture
# resolves `main` to, so a release that resolved a tag again would be caught.
echo "# release mode promotes the committed pins under bundle-X.Y.Z"
release=$(new_tree release)
write_components "${release}" true true
committed_backend=sha256:$(printf 'a%.0s' {1..64})
committed_migrations=sha256:$(printf 'b%.0s' {1..64})
committed_frontend=sha256:$(printf 'c%.0s' {1..64})
yq -i "
	.images.backend = \"ghcr.io/morzecrew/erp-backend:main@${committed_backend}\" |
	.images.migrations = \"ghcr.io/morzecrew/erp-migrations:main@${committed_migrations}\" |
	.images.frontend = \"ghcr.io/morzecrew/erp-frontend:main@${committed_frontend}\"" \
	"${release}/bundle/manifest.yaml"
pin "${release}" --release 1.2.3 >/dev/null

expect "keeps the backend's digest" \
	"ghcr.io/morzecrew/erp-backend:bundle-1.2.3@${committed_backend}" \
	"$(yaml_get "${release}" '.images.backend')"
expect "keeps the migrations' digest" \
	"ghcr.io/morzecrew/erp-migrations:bundle-1.2.3@${committed_migrations}" \
	"$(yaml_get "${release}" '.images.migrations')"
expect "keeps the frontend's digest" \
	"ghcr.io/morzecrew/erp-frontend:bundle-1.2.3@${committed_frontend}" \
	"$(yaml_get "${release}" '.images.frontend')"
expect "records the migrations label too" 7 "$(yaml_get "${release}" '.compatibility.database_schema_produces')"

promoted=$(hash "${release}/bundle/manifest.yaml")
pin "${release}" --release 1.2.3 >/dev/null
expect "a second promotion writes the same bytes" "${promoted}" "$(hash "${release}/bundle/manifest.yaml")"

# D-4: a rollback is safe only when both components are, and release mode is
# the only writer of the field.
echo "# release mode writes rollback_safe as the conjunction of both components"
expect "both true gives true" true "$(yaml_get "${release}" '.compatibility.rollback_safe')"

safe_backend=$(new_tree safe-backend)
write_components "${safe_backend}" false true
pin "${safe_backend}" --release 1.2.3 >/dev/null
expect "a false backend gives false" false \
	"$(yaml_get "${safe_backend}" '.compatibility.rollback_safe')"

safe_frontend=$(new_tree safe-frontend)
write_components "${safe_frontend}" true false
pin "${safe_frontend}" --release 1.2.3 >/dev/null
expect "a false frontend gives false" false \
	"$(yaml_get "${safe_frontend}" '.compatibility.rollback_safe')"

echo "# release mode refuses what it cannot promote"
refuses() { # refuses <what> <substring> <yq update or ''> <pin.sh args...>
	local what=$1 want=$2 update=$3 tree before
	shift 3
	tree=$(new_tree "refuse-${what// /-}")
	write_components "${tree}" true true
	[ -z "${update}" ] || yq -i "${update}" "${tree}/bundle/manifest.yaml"
	before=$(hash "${tree}/bundle/manifest.yaml")
	refuse "${what}" "${want}" pin "${tree}" "$@"
	expect "${what}: the manifest is left alone" "${before}" "$(hash "${tree}/bundle/manifest.yaml")"
}

zero=sha256:$(printf '0%.0s' {1..64})
pruned=sha256:deadbeef$(printf 'e%.0s' {1..56})
refuses "a release with no version" "takes the release's version" '' --release
refuses "a version that is not X.Y.Z" "not '1.2'" '' --release 1.2
refuses "a v-prefixed version" "not 'v1.2.3'" '' --release v1.2.3
refuses "the placeholder digest" "holds the placeholder digest" \
	".images.backend = \"ghcr.io/morzecrew/erp-backend:main@${zero}\"" --release 1.2.3
refuses "a digest the registry pruned" "release a newer commit of main" \
	".images.frontend = \"ghcr.io/morzecrew/erp-frontend:main@${pruned}\"" --release 1.2.3

# D-4: only a boolean is a release input. A word that is neither, and a quoted
# boolean -- a string that spells `true` -- are both refused.
refuses_safe() { # refuses_safe <what> <backend safe> <frontend safe> <substring>
	local what=$1 tree before
	shift
	tree=$(new_tree "refuse-${what// /-}")
	write_components "${tree}" "$1" "$2"
	before=$(hash "${tree}/bundle/manifest.yaml")
	refuse "${what}" "$3" pin "${tree}" --release 1.2.3
	expect "${what}: the manifest is left alone" "${before}" "$(hash "${tree}/bundle/manifest.yaml")"
}

refuses_safe "a rollback_safe that is neither true nor false" maybe false "is not true or false"
refuses_safe "a quoted 'true', which is a string, not a boolean" '"true"' false "is not true or false"
refuses_safe "a missing frontend rollback_safe" true null "is not true or false"

echo "# resolve.sh"
stub_path="${work}/bin:${PATH}"
migrations_out=$(PATH="${stub_path}" bash "${repo}/scripts/resolve.sh" ghcr.io/morzecrew/erp-migrations:main)
expect "the digest is line one" "$(fixture_digest ghcr.io/morzecrew/erp-migrations:main)" \
	"$(printf '%s\n' "${migrations_out}" | sed -n '1p')"
expect "the schema label is line two" "schema=0007" \
	"$(printf '%s\n' "${migrations_out}" | sed -n '2p')"

backend_out=$(PATH="${stub_path}" bash "${repo}/scripts/resolve.sh" ghcr.io/morzecrew/erp-backend:main)
expect_lines "an image without the label prints the digest alone" 1 "${backend_out}"

refuse "a reference with no tag" "names no tag" \
	env PATH="${stub_path}" bash "${repo}/scripts/resolve.sh" ghcr.io/morzecrew/erp-backend

by_digest=$(fixture_digest ghcr.io/morzecrew/erp-migrations:main)
digest_out=$(PATH="${stub_path}" bash "${repo}/scripts/resolve.sh" "ghcr.io/morzecrew/erp-migrations@${by_digest}")
expect "a digest resolves to itself" "${by_digest}" "$(printf '%s\n' "${digest_out}" | sed -n '1p')"
expect "a digest's schema label is read too" "schema=0007" "$(printf '%s\n' "${digest_out}" | sed -n '2p')"

echo "# the scripts as a release calls them"
# No PIN_ROOT and no RESOLVE: pin.sh finds the committed components.yaml and
# the manifest where it lives, which is how a workflow calls it. The tree is a
# copy, so this asserts the committed files too.
tree=${work}/tree
mkdir -p "${tree}/scripts" "${tree}/bundle"
cp "${repo}/scripts/pin.sh" "${tree}/scripts/pin.sh"
cp "${here}/resolve-fixture.sh" "${tree}/scripts/resolve.sh"
cp "${original}" "${tree}/bundle/manifest.yaml"
cp "${repo}/components.yaml" "${tree}/components.yaml"
chmod +x "${tree}/scripts/resolve.sh"

release_out=''
# Release mode refuses a components.yaml entry without a boolean, and a
# placeholder digest, so this passing says the committed files are releasable.
if release_out=$(bash "${tree}/scripts/pin.sh" --release 0.1.0 2>&1); then
	ok "the committed components.yaml and manifest are what a release reads"
else
	fail "the committed components.yaml and manifest are what a release reads: ${release_out}"
fi

committed=$(yq -r '.images.backend' "${original}")
expect "promotes the digest the committed manifest pins" \
	"ghcr.io/morzecrew/erp-backend:bundle-0.1.0@${committed##*@}" \
	"$(yq -r '.images.backend' "${tree}/bundle/manifest.yaml")"
if printf '%s' "${release_out}" | grep -qF 'erp-backend:bundle-0.1.0@'; then
	ok "reports the pin it wrote"
else
	fail "reports the pin it wrote: ${release_out}"
fi
expect "the committed bundle/manifest.yaml is never written" \
	"$(hash "${original}")" "$(hash "${repo}/bundle/manifest.yaml")"

if [ "${failures}" -ne 0 ]; then
	echo "${failures} check(s) failed" >&2
	exit 1
fi
echo "all checks passed"