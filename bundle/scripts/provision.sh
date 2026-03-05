#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# ....................... #

log() { echo "[provision] $*"; }

# ....................... #

apt_install() {
	# Usage: apt_install pkg1 pkg2 ...
	apt-get update -y
	apt-get install -y --no-install-recommends "$@"
	rm -rf /var/lib/apt/lists/*
}

# ....................... #

install_docker() {
	log "Installing Docker Engine (official repo for Debian)"

	# Remove older packages if any (ignore errors)
	apt-get remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1 || true

	install -m 0755 -d /etc/apt/keyrings

	# Docker GPG key
	if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
		curl -fsSL https://download.docker.com/linux/debian/gpg |
			gpg --dearmor -o /etc/apt/keyrings/docker.gpg
		chmod a+r /etc/apt/keyrings/docker.gpg
	fi

	# Detect Debian codename (bookworm, bullseye, etc.)
	local codename
	codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

	if [[ -z "${codename}" ]]; then
		log "ERROR: Could not detect Debian codename"
		exit 1
	fi

	log "Detected Debian codename: ${codename}"

	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian ${codename} stable" \
		>/etc/apt/sources.list.d/docker.list

	apt-get update -y

	apt-get install -y --no-install-recommends \
		docker-ce-cli \
		docker-compose-plugin

	log "Docker installed successfully"
}

# ....................... #

install_just() {
	log "Installing just (official install.sh)"

	local target_dir="/usr/local/bin"
	install -d -m 0755 "${target_dir}"

	local version="${JUST_VERSION:-}"

	if [[ -n "${version}" ]]; then
		log "Requested just version: ${version}"
		if curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh |
			bash -s -- --to "${target_dir}" --tag "${version}"; then
			:
		else
			log "Pinned install failed; falling back to latest"
			curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh |
				bash -s -- --to "${target_dir}"
		fi
	else
		curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh |
			bash -s -- --to "${target_dir}"
	fi

	command -v just >/dev/null 2>&1 || {
		log "ERROR: just not found after install"
		exit 1
	}
	log "just installed: $(just --version || true)"
}

# ....................... #

install_ops_tools() {
	# Add tools you want inside the invocation image (keep minimal!)
	# Example:
	# apt_install jq git unzip
	:
}

# ....................... #

main() {
	install_docker
	install_just
	install_ops_tools
	log "Provisioning done"
}

main "$@"
