#!/usr/bin/env bash
#
# Write the marker `before` into Postgres and Valkey, back up, write `after`,
# restore, and fail unless both read `before` again.
set -euo pipefail
# shellcheck source=/dev/null
. /rig/smoke-lib.sh
# shellcheck source=.github/smoke.d/lib/markers.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/markers.sh"

write_marker before

# Under --json morzer's error is only in the envelope on stdout.
if ! out=$(sudo morzer backup --reason smoke --json); then
	printf '%s\n' "${out}" >&2
	exit 1
fi
id=$(jq -r '.data.id // .data.backup.id // .data.backup_id // empty' <<<"${out}")
[ -n "${id}" ] || die "morzer backup reported no backup id"
echo "20-backup-restore.sh: backup ${id}"

write_marker after
check_marker after

installation=$(sudo morzer status --json | jq -r '.data.installation_id // .data.installation.id // empty')
[ -n "${installation}" ] || die "morzer status reported no installation id"
sudo morzer --verbose restore --backup "${id}" --force --confirm "${installation}"
check_marker before
