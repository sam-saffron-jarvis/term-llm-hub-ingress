#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

export HUB_DOMAIN=${HUB_DOMAIN:-hub.example.com}
export ACME_EMAIL=${ACME_EMAIL:-admin@example.com}
export DROPLET_HOST=${DROPLET_HOST:-192.0.2.10}
export TUNNEL_SSH_PORT=${TUNNEL_SSH_PORT:-22022}
export LOCAL_BIND_IP=${LOCAL_BIND_IP:-127.0.0.1}
export TERM_LLM_VERSION=${TERM_LLM_VERSION:-v0.0.403}
export EDGE_PROXY_SOURCE_CIDR=${EDGE_PROXY_SOURCE_CIDR:-172.31.0.1/32}

for script in \
  "$root/scripts/generate-secrets.sh" \
  "$root/scripts/generate-recovery-token.sh" \
  "$root/scripts/validate-haproxy.sh" \
  "$root/droplet/tunnel-sshd/entrypoint.sh" \
  "$root/home/autossh/entrypoint.sh" \
  "$root/home/hub/entrypoint.sh"
do
  sh -n "$script"
done

docker compose --env-file "$root/droplet/.env.example" \
  -f "$root/droplet/compose.yaml" config --quiet

docker compose --env-file "$root/home/.env.example" \
  -f "$root/home/compose.yaml" config --quiet

docker compose --env-file "$root/home/.env.example" \
  -f "$root/home/compose.yaml" \
  -f "$root/home/compose.bootstrap.yaml" config --quiet

docker compose --env-file "$root/home/.env.example" \
  -f "$root/home/compose.yaml" \
  -f "$root/home/compose.recovery.yaml" config --quiet

validate_caddyfile() {
  file=$1
  if command -v caddy >/dev/null 2>&1; then
    HUB_DOMAIN="$HUB_DOMAIN" \
      ACME_EMAIL="$ACME_EMAIL" \
      EDGE_PROXY_SOURCE_CIDR="$EDGE_PROXY_SOURCE_CIDR" \
      caddy validate --config "$file"
  else
    docker run --rm \
      -e HUB_DOMAIN="$HUB_DOMAIN" \
      -e ACME_EMAIL="$ACME_EMAIL" \
      -e EDGE_PROXY_SOURCE_CIDR="$EDGE_PROXY_SOURCE_CIDR" \
      -v "$file:/etc/caddy/Caddyfile:ro" \
      caddy:2.11.4-alpine caddy validate --config /etc/caddy/Caddyfile
  fi
}

validate_caddyfile "$root/droplet/Caddyfile"
validate_caddyfile "$root/home/Caddyfile"
"$root/scripts/validate-haproxy.sh"

printf 'configuration validation passed\n'
