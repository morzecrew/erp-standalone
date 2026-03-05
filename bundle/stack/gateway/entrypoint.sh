#!/bin/sh
set -e
echo "Generating configuration files..."

defined_envs=$(printf '${%s} ' $(awk "END { for (name in ENVIRON) { print ( name ~ /${filter}/ ) ? name : \"\" } }" </dev/null))

# ....................... #

echo "    - Generating Caddyfile from template /templates/Caddyfile"
envsubst "${defined_envs}" <"/templates/Caddyfile" >"/etc/caddy/Caddyfile"
caddy fmt --overwrite /etc/caddy/Caddyfile
echo "    - Done"

# ....................... #

echo "Launching $*"
exec "$@"
