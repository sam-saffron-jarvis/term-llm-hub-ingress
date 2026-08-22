#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 <exact-DROPLET_HOST-value> [ssh-port]" >&2
  exit 64
fi

host=$1
port=${2:-22022}
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
home_secrets="$root/home/secrets"
droplet_secrets="$root/droplet/secrets"

command -v ssh-keygen >/dev/null 2>&1 || {
  echo "ssh-keygen is required" >&2
  exit 1
}
command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required" >&2
  exit 1
}

outputs="
$home_secrets/tunnel_ed25519
$home_secrets/tunnel_ed25519.pub
$home_secrets/known_hosts
$home_secrets/passkey_bootstrap_token
$home_secrets/hub_registration_token
$droplet_secrets/ssh_host_ed25519_key
$droplet_secrets/ssh_host_ed25519_key.pub
$droplet_secrets/tunnel_authorized_keys
"

printf '%s\n' "$outputs" | while IFS= read -r file; do
  [ -n "$file" ] || continue
  if [ -e "$file" ]; then
    echo "refusing to overwrite existing secret material: $file" >&2
    exit 1
  fi
done

mkdir -p "$home_secrets" "$droplet_secrets"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM HUP
umask 077

ssh-keygen -q -t ed25519 -N '' \
  -C term-llm-hub-home-tunnel \
  -f "$tmp/tunnel_ed25519"

ssh-keygen -q -t ed25519 -N '' \
  -C term-llm-hub-droplet-endpoint \
  -f "$tmp/ssh_host_ed25519_key"

{
  printf '%s' 'restrict,port-forwarding,permitlisten="0.0.0.0:18080",permitlisten="0.0.0.0:18081" '
  cat "$tmp/tunnel_ed25519.pub"
} > "$tmp/tunnel_authorized_keys"

host_key=$(awk '{print $1 " " $2}' "$tmp/ssh_host_ed25519_key.pub")
printf '[%s]:%s %s\n' "$host" "$port" "$host_key" > "$tmp/known_hosts"

openssl rand -hex 32 > "$tmp/passkey_bootstrap_token"
openssl rand -hex 32 > "$tmp/hub_registration_token"

install -m 0600 "$tmp/tunnel_ed25519" "$home_secrets/tunnel_ed25519"
install -m 0644 "$tmp/tunnel_ed25519.pub" "$home_secrets/tunnel_ed25519.pub"
install -m 0600 "$tmp/known_hosts" "$home_secrets/known_hosts"
install -m 0600 "$tmp/passkey_bootstrap_token" "$home_secrets/passkey_bootstrap_token"
install -m 0600 "$tmp/hub_registration_token" "$home_secrets/hub_registration_token"
install -m 0600 "$tmp/ssh_host_ed25519_key" "$droplet_secrets/ssh_host_ed25519_key"
install -m 0644 "$tmp/ssh_host_ed25519_key.pub" "$droplet_secrets/ssh_host_ed25519_key.pub"
install -m 0600 "$tmp/tunnel_authorized_keys" "$droplet_secrets/tunnel_authorized_keys"

fingerprint=$(ssh-keygen -lf "$droplet_secrets/ssh_host_ed25519_key.pub")
printf '%s\n' \
  "Generated separate home and droplet secrets." \
  "DROPLET_HOST must remain exactly: $host" \
  "Droplet SSH host-key fingerprint: $fingerprint" \
  "Nothing under */secrets/ is tracked by git."
