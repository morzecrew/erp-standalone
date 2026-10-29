# The erp project's marker: a fixed word written into Postgres and Valkey,
# which the backup and rotation hooks read back. Sourced by a hook after
# /rig/smoke-lib.sh; no secret is ever read out here.
# shellcheck shell=bash

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
	echo "${0##*/}: both markers read $1"
}
