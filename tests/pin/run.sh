#!/usr/bin/env bash
#
# Drives scripts/pin.sh over throwaway copies of the tree, with the resolver
# `pin.sh` would call replaced by tests/pin/resolve-fixture.sh and a stand-in
# `docker` for scripts/resolve.sh's own check, so nothing here reaches the
# network and the committed bundle/manifest.yaml is never written.
#
#   bash tests/pin/run.sh
#
# It checks what D-15 asks for: a dev pin is `main`, a release pin is the
# versions components.yaml names, release mode refuses `main` and `sha-*`, the
# migrations label lands in all three compatibility fields, pinning twice
# changes nothing, and no other value in the manifest moves.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "${here}/../.." && pwd)

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

# The fixtures are copied out and made executable, so a test run does not
# depend on the modes of the files it reads.
mkdir -p "${work}/bin"
cp "${here}/resolve-fixture.sh" "${work}/resolve.sh"
cp "${here}/docker-fixture.sh" "${work}/bin/docker"
chmod +x "${work}/resolve.sh" "${work}/bin/docker"
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

write_components() { # write_components <tree> <backend version> <frontend version>
	cat >"$1/components.yaml" <<-EOF
		backend:
		  image: ghcr.io/morzecrew/erp-backend
		  version: $2
		  rollback_safe: false
		  notes: Test backend.
		frontend:
		  image: ghcr.io/morzecrew/erp-frontend
		  version: $3
		  rollback_safe: false
		  notes: Test frontend.
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
write_components "${dev}" 0.0.0 0.0.0
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

echo "# release mode pins the versions components.yaml names"
release=$(new_tree release)
write_components "${release}" 1.2.3 4.5.6
pin "${release}" --release >/dev/null

expect "pins the backend to its version" \
	"ghcr.io/morzecrew/erp-backend:1.2.3@$(fixture_digest ghcr.io/morzecrew/erp-backend:1.2.3)" \
	"$(yaml_get "${release}" '.images.backend')"
expect "pins the migrations to the backend's version" \
	"ghcr.io/morzecrew/erp-migrations:1.2.3@$(fixture_digest ghcr.io/morzecrew/erp-migrations:1.2.3)" \
	"$(yaml_get "${release}" '.images.migrations')"
expect "pins the frontend to its own version" \
	"ghcr.io/morzecrew/erp-frontend:4.5.6@$(fixture_digest ghcr.io/morzecrew/erp-frontend:4.5.6)" \
	"$(yaml_get "${release}" '.images.frontend')"
expect "records the migrations label too" 7 "$(yaml_get "${release}" '.compatibility.database_schema_produces')"

echo "# release mode refuses what a release is not made of"
refuses() { # refuses <what> <backend version> <frontend version> <substring>
	local what=$1 tree before
	shift
	tree=$(new_tree "refuse-${what// /-}")
	write_components "${tree}" "$1" "$2"
	before=$(hash "${tree}/bundle/manifest.yaml")
	refuse "${what}" "$3" pin "${tree}" --release
	expect "${what}: the manifest is left alone" "${before}" "$(hash "${tree}/bundle/manifest.yaml")"
}

refuses "the branch tag main" main 4.5.6 "is 'main'"
refuses "a main frontend" 1.2.3 main "is 'main'"
refuses "a commit tag sha-*" sha-1a2b3c4 4.5.6 "not a commit"
refuses "a version that is not X.Y.Z" 1.2 4.5.6 "is not X.Y.Z"

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
# Release mode refuses a component entry that is missing a field, so this
# passing says the committed components.yaml carries all of them.
if release_out=$(bash "${tree}/scripts/pin.sh" --release 2>&1); then
	ok "the committed components.yaml carries every field a release reads"
else
	fail "the committed components.yaml carries every field a release reads: ${release_out}"
fi

expect "pins the version the committed components.yaml names" \
	"ghcr.io/morzecrew/erp-backend:0.0.0@$(fixture_digest ghcr.io/morzecrew/erp-backend:0.0.0)" \
	"$(yq -r '.images.backend' "${tree}/bundle/manifest.yaml")"
if printf '%s' "${release_out}" | grep -qF 'erp-backend:0.0.0@'; then
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