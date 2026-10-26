#!/usr/bin/env bash
#
# Smoke-test a bundle archive on the runner, the way a machine installs it.
#
#   smoke.sh install <archive> <pubkey>...  fresh `sudo morzer init` and `apply`
#   smoke.sh update <archive>               `sudo morzer update` to the archive
#   smoke.sh probe                          the edge's loopback health port
#   smoke.sh backup-restore                 back up, write over it, restore, check
#   smoke.sh rotate-db-password             rotate the database password, apply, read
#   smoke.sh rollback <published> <new>     `sudo morzer rollback` from <new> to <published>
#   smoke.sh diagnose                       `morzer status` and the Compose logs
#   smoke.sh free-disk                      room for the release's disk requirement
#
# `install` trusts every key it is given and refuses an unsigned release. It
# sets `admin_password`, the one secret the operator sets, from `random`;
# `init` generates the rest, and nothing here prints a secret.
#
# `backup-restore` writes the marker `before` into Postgres and Valkey, backs
# up, writes `after`, restores, and fails unless both read `before` again.
# `rotate-db-password` writes `rotated`, rotates `postgres_password`, applies,
# and fails unless the marker reads `rotated` through PgBouncer: the rotated
# password reaches the role and every reader of it.
# `rollback` passes when the rollback succeeds, or when morzer refuses it
# (exit 9) and either the new archive declares `rollback_safe: false` or the
# two archives produce different database schemas.
# The markers are fixed words; no secret is ever read out here.
set -euo pipefail

health_port=8081
# morzer reads a volume for a backup through this image and never pulls it
# itself; `morzer doctor` names it under backup.volume-helper. 0.6.0's own.
volume_helper=busybox@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0

die() {
	echo "smoke.sh: $*" >&2
	exit 1
}

random() {
	openssl rand -hex 24
}

# Whether the archive's secrets schema declares a secret by this name.
declares() {
	tar -I zstd -xOf "$1" --wildcards '*secrets.schema.yaml' 2>/dev/null \
		| grep -E "^[[:space:]]*- name: $2\$" >/dev/null
}

# shortcut: a bundle published before S-0003 (the `:main` smoke-update starts
# from until S-0003's bundle is published) generates neither infrastructure
# pair and declares each twice, so its operator set each pair from one value.
# morzer 0.6.0's `secret set` exits 6 while another required secret is unset,
# which before the first `apply` is every set but the last. Drop this once
# `:main` carries S-0003.
set_legacy_pairs() {
	local database storage name value status
	database=$(random)
	storage=$(random)
	for name in postgres_password pgbouncer_password s3_secret_key rustfs_secret_key; do
		case "${name}" in
		postgres_password | pgbouncer_password) value=${database} ;;
		*) value=${storage} ;;
		esac
		status=0
		printf %s "${value}" | sudo morzer secret set "${name}" || status=$?
		[ "${status}" -eq 0 ] || [ "${status}" -eq 6 ] || exit "${status}"
	done
}

install_release() {
	local archive=$1 key
	shift
	local keys=()
	for key in "$@"; do
		[ -n "${key}" ] && keys+=(--signing-key "${key}")
	done
	[ ${#keys[@]} -gt 0 ] || die "install needs at least one signing key"

	sudo morzer init --mode dev --release "${archive}" --require-signature \
		--no-recovery-recipient --install-units=false "${keys[@]}"

	if declares "${archive}" pgbouncer_password; then
		set_legacy_pairs
	fi
	random | sudo morzer secret set admin_password

	# --verbose: morzer prints a one-shot's output, a migration's error, only then.
	sudo morzer --verbose apply
	sudo docker image inspect "${volume_helper}" >/dev/null 2>&1 \
		|| sudo docker pull --quiet "${volume_helper}"
}

# The running container of one of the erp project's services, by the labels
# Compose puts on it. A restore recreates it, so each call looks it up again.
service_container() {
	local container
	container=$(sudo docker ps --quiet \
		--filter label=com.docker.compose.project=erp \
		--filter "label=com.docker.compose.service=$1" | sed -n 1p)
	[ -n "${container}" ] || die "no running $1 container of the erp project"
	printf '%s\n' "${container}"
}

psql_erp() {
	sudo docker exec "$(service_container postgres)" \
		psql -U postgres -d erp -v ON_ERROR_STOP=1 -tAqc "$1"
}

# The password stays inside the container: valkey-cli reads it from the
# environment, never from an argument or this script's output.
valkey() {
	# shellcheck disable=SC2016 # expanded by the container's sh
	sudo docker exec "$(service_container valkey)" sh -c \
		'VALKEYCLI_AUTH="$(cat /run/secrets/valkey_password)" exec valkey-cli --no-auth-warning "$@"' \
		valkey "$@"
}

write_marker() {
	psql_erp "create table if not exists smoke_marker (value text not null);
		delete from smoke_marker; insert into smoke_marker values ('$1')" >/dev/null
	[ "$(valkey set smoke:marker "$1")" = OK ] || die "valkey did not store the marker"
}

check_marker() {
	local database cache
	database=$(psql_erp "select value from smoke_marker")
	cache=$(valkey get smoke:marker)
	[ "${database}" = "$1" ] || die "smoke_marker reads '${database}', not '$1'"
	[ "${cache}" = "$1" ] || die "smoke:marker reads '${cache}', not '$1'"
	echo "smoke.sh: both markers read $1"
}

backup_restore() {
	local out id installation
	write_marker before

	# Under --json morzer's error is only in the envelope on stdout.
	if ! out=$(sudo morzer backup --reason smoke --json); then
		printf '%s\n' "${out}" >&2
		exit 1
	fi
	id=$(jq -r '.data.id // .data.backup.id // .data.backup_id // empty' <<<"${out}")
	[ -n "${id}" ] || die "morzer backup reported no backup id"
	echo "smoke.sh: backup ${id}"

	write_marker after
	check_marker after

	installation=$(sudo morzer status --json | jq -r '.data.installation_id // .data.installation.id // empty')
	[ -n "${installation}" ] || die "morzer status reported no installation id"
	sudo morzer --verbose restore --backup "${id}" --force --confirm "${installation}"
	check_marker before
}

# The one reader a rotated password must satisfy: PgBouncer, which connects on
# to postgres as `postgres`. The password is read from the secret inside the
# container's shell and passed in the environment, never in an argument here.
psql_pgbouncer() {
	# shellcheck disable=SC2016 # expanded by the container's sh
	sudo docker exec "$(service_container pgbouncer)" sh -c \
		'PGPASSWORD="$(cat /run/secrets/postgres_password)" exec psql -h 127.0.0.1 -p 6432 -U postgres -d erp -v ON_ERROR_STOP=1 -tAqc "$1"' \
		pgbouncer "$1"
}

rotate_db_password() {
	# The marker is written once, before the rotation, and read after it: what
	# it proves is that a connection with the new password reaches the data,
	# not that the row was reinserted.
	write_marker rotated
	sudo morzer secret rotate postgres_password
	sudo morzer --verbose apply

	local database
	database=$(psql_pgbouncer "select value from smoke_marker")
	[ "${database}" = rotated ] \
		|| die "smoke_marker reads '${database}' through pgbouncer, not 'rotated'"
	echo "smoke.sh: the rotated database password reads the marker through pgbouncer"
}

# A field an archive's manifest declares, by its key: `rollback_safe`,
# `database_schema_produces`.
manifest_field() {
	local manifest
	manifest=$(tar -I zstd -tf "$1" | grep -E '(^|/)manifest\.yaml$' | awk '{ print length, $0 }' \
		| sort -n | sed -n '1s/^[0-9]* //p')
	[ -n "${manifest}" ] || die "$1 holds no manifest.yaml"
	tar -I zstd -xOf "$1" "${manifest}" \
		| sed -n "s/^[[:space:]]*$2:[[:space:]]*\([^[:space:]#]*\).*/\1/p" | sed -n 1p
}

rollback() {
	local published=$1 new=$2 status=0 from to
	sudo morzer --verbose rollback || status=$?
	[ "${status}" -ne 0 ] || { echo "smoke.sh: rolled back"; return; }
	[ "${status}" -eq 9 ] || die "morzer rollback exited ${status}"
	# A release takes rollback_safe from components.yaml, and false refuses
	# any rollback from it, on one schema or not.
	if [ "$(manifest_field "${new}" rollback_safe)" = false ]; then
		echo "smoke.sh: rollback refused, as the new release declares rollback_safe: false"
		return
	fi
	from=$(manifest_field "${new}" database_schema_produces)
	to=$(manifest_field "${published}" database_schema_produces)
	[ -n "${from}" ] && [ -n "${to}" ] || die "an archive declares no database_schema_produces"
	[ "${from}" != "${to}" ] \
		|| die "morzer rollback refused (exit 9) between two releases on schema ${from}"
	echo "smoke.sh: rollback refused across the schema change ${from} -> ${to}, as it must be"
}

probe() {
	local path
	for path in /__platform_healthz /health; do
		curl -fsS --max-time 10 --retry 10 --retry-delay 3 --retry-all-errors \
			-o /dev/null "http://127.0.0.1:${health_port}${path}" \
			|| die "127.0.0.1:${health_port}${path} did not answer 2xx"
		echo "smoke.sh: ${path} ok"
	done
}

# A hosted runner's root has about 14 GiB free, and the release's preflight
# wants 20 GiB under /var/lib/erp; the preinstalled toolchains hold about 25.
free_disk() {
	[ "${RUNNER_ENVIRONMENT:-}" = github-hosted ] \
		|| die "free-disk deletes the runner's toolchains; GitHub-hosted runners only"
	sudo rm -rf /usr/local/lib/android /usr/share/dotnet /opt/ghc /opt/hostedtoolcache/CodeQL
	df -h /
}

diagnose() {
	sudo morzer status || true
	# The manifest's Compose project.
	sudo docker compose -p erp ps -a || true
	sudo docker compose -p erp logs --no-color --timestamps || true
}

case "${1:-}" in
install)
	[ $# -ge 3 ] || die "usage: smoke.sh install <archive> <pubkey>..."
	shift
	install_release "$@"
	;;
update)
	[ $# -eq 2 ] || die "usage: smoke.sh update <archive>"
	sudo morzer --verbose update "$2"
	;;
probe) probe ;;
backup-restore) backup_restore ;;
rotate-db-password) rotate_db_password ;;
rollback)
	[ $# -eq 3 ] || die "usage: smoke.sh rollback <published archive> <new archive>"
	rollback "$2" "$3"
	;;
free-disk) free_disk ;;
diagnose) diagnose ;;
*) die "usage: smoke.sh install|update|probe|backup-restore|rotate-db-password|rollback|diagnose|free-disk" ;;
esac
