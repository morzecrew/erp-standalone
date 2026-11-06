#!/usr/bin/env bash
#
# Write the marker into Postgres and Valkey, run the `reset` task, and fail
# unless both markers are gone, the database is migrated and bootstrapped again,
# and nothing else is in it; then seed it, as a dev machine would. The probe
# bundle.yml runs after this hook proves the backend answers on the new database.
set -euo pipefail
# shellcheck source=/dev/null
. /rig/smoke-lib.sh
# shellcheck source=.github/smoke.d/lib/markers.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/markers.sh"

# A rehearsal runs the hooks against the published bundle, which may predate
# the task.
if ! sudo morzer task list --json | jq -e '.. | objects | select(.name? == "reset")' >/dev/null; then
	echo "40-reset.sh: the installed release has no reset task"
	exit 0
fi

write_marker reset
sudo morzer --verbose task run reset

[ "$(psql_erp "select count(*) from pg_tables where tablename = 'smoke_marker'")" = 0 ] \
	|| die "smoke_marker survived the reset"
[ "$(valkey exists smoke:marker)" = 0 ] || die "smoke:marker survived the reset"
[ "$(psql_erp "select count(*) > 0 from flyway_schema_history where success")" = t ] \
	|| die "the reset left the database unmigrated"
[ "$(psql_erp "select count(*) > 0 from erp.catalogs")" = t ] \
	|| die "the reset left the database without its catalogs"
[ "$(psql_erp "select count(*) from erp.details") $(psql_erp "select count(*) from erp.specifications")" = "0 0" ] \
	|| die "the reset left records behind, or seeded"
echo "40-reset.sh: the database was made again, migrated and bootstrapped, and is empty"

# Demo data is the seed's to bring, into the empty database the reset left.
sudo morzer --verbose task run seed -- --size s --seed smoke
[ "$(psql_erp "select count(*) > 0 from erp.details")" = t ] \
	|| die "the seed filled nothing after the reset"
echo "40-reset.sh: the seed filled the reset database"
