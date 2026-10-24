#!/usr/bin/env bash
#
# Smoke-test a bundle archive on the runner, the way a machine installs it.
#
#   smoke.sh install <archive> <pubkey>...  fresh `sudo morzer init` and `apply`
#   smoke.sh update <archive>               `sudo morzer update` to the archive
#   smoke.sh probe                          the edge's loopback health port
#   smoke.sh diagnose                       `morzer status` and the Compose logs
#
# `install` trusts every key it is given and refuses an unsigned release. The
# operator's secrets get throwaway values, each pair set from one value as the
# operator would; nothing here prints one.
set -euo pipefail

health_port=8081

die() {
	echo "smoke.sh: $*" >&2
	exit 1
}

random() {
	openssl rand -hex 24
}

# shortcut: morzer 0.6.0's `secret set` stores the value, then renders every
# secret to restart the services that read it, and exits 6 while another
# required secret is unset. Before the first `apply` that is every set but the
# last; `apply` renders them all and refuses a missing one. Drop this when
# `secret set` skips the restart on an installation never applied.
set_secret() {
	local status=0
	sudo morzer secret set "$1" || status=$?
	[ "${status}" -eq 0 ] || [ "${status}" -eq 6 ] || exit "${status}"
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

	local database storage
	database=$(random)
	storage=$(random)
	printf %s "${database}" | set_secret postgres_password
	printf %s "${database}" | set_secret pgbouncer_password
	printf %s "${storage}" | set_secret s3_secret_key
	printf %s "${storage}" | set_secret rustfs_secret_key
	random | set_secret admin_password

	sudo morzer apply
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
	sudo morzer update "$2"
	;;
probe) probe ;;
diagnose) diagnose ;;
*) die "usage: smoke.sh install|update|probe|diagnose" ;;
esac
