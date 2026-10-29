#!/usr/bin/env bash
#
# Write `rotated`, rotate `postgres_password`, apply, and fail unless the
# marker reads `rotated` through PgBouncer: the rotated password reaches the
# role and every reader of it.
set -euo pipefail
# shellcheck source=/dev/null
. /rig/smoke-lib.sh
# shellcheck source=.github/smoke.d/lib/markers.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/markers.sh"

# The one reader a rotated password must satisfy: PgBouncer, which connects on
# to postgres as `postgres`. The password is read from the secret inside the
# container's shell and passed in the environment, never in an argument here.
psql_pgbouncer() {
	# shellcheck disable=SC2016 # expanded by the container's sh
	sudo docker exec "$(service_container pgbouncer)" sh -c \
		'PGPASSWORD="$(cat /run/secrets/postgres_password)" exec psql -h 127.0.0.1 -p 6432 -U postgres -d erp -v ON_ERROR_STOP=1 -tAqc "$1"' \
		pgbouncer "$1"
}

# The marker is written once, before the rotation, and read after it: what it
# proves is that a connection with the new password reaches the data, not that
# the row was reinserted.
write_marker rotated
sudo morzer secret rotate postgres_password
sudo morzer --verbose apply

database=$(psql_pgbouncer "select value from smoke_marker")
[ "${database}" = rotated ] \
	|| die "smoke_marker reads '${database}' through pgbouncer, not 'rotated'"
echo "30-rotate-db-password.sh: the rotated database password reads the marker through pgbouncer"
