#!/bin/sh
set -eu

: "${DROPLET_HOST:?DROPLET_HOST is required}"
: "${TUNNEL_SSH_PORT:?TUNNEL_SSH_PORT is required}"
: "${REMOTE_ACME_PORT:?REMOTE_ACME_PORT is required}"
: "${REMOTE_HUB_PORT:?REMOTE_HUB_PORT is required}"
: "${LOCAL_ACME_TARGET:?LOCAL_ACME_TARGET is required}"
: "${LOCAL_HUB_TARGET:?LOCAL_HUB_TARGET is required}"

for file in /run/secrets/tunnel_ed25519 /run/secrets/known_hosts; do
  if [ ! -s "$file" ]; then
    echo "required autossh file is missing or empty: $file" >&2
    exit 1
  fi
done

exec autossh \
  -M 0 \
  -N -T \
  -o BatchMode=yes \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=/run/secrets/known_hosts \
  -o IdentitiesOnly=yes \
  -i /run/secrets/tunnel_ed25519 \
  -p "$TUNNEL_SSH_PORT" \
  -R "0.0.0.0:${REMOTE_ACME_PORT}:${LOCAL_ACME_TARGET}" \
  -R "0.0.0.0:${REMOTE_HUB_PORT}:${LOCAL_HUB_TARGET}" \
  "tunnel@${DROPLET_HOST}"
