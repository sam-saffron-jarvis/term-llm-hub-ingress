#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out="$root/home/secrets/passkey_recovery_token"

if [ -e "$out" ]; then
  echo "refusing to overwrite existing recovery token: $out" >&2
  exit 1
fi

command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required" >&2
  exit 1
}

umask 077
openssl rand -hex 32 > "$out"
printf 'created %s; delete it immediately after recovery\n' "$out"
