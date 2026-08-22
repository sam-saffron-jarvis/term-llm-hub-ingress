#!/bin/sh
set -eu

for file in \
  /run/secrets/tunnel_authorized_keys \
  /etc/ssh/keys/ssh_host_ed25519_key \
  /etc/ssh/keys/ssh_host_ed25519_key.pub
do
  if [ ! -s "$file" ]; then
    echo "required tunnel SSH file is missing or empty: $file" >&2
    exit 1
  fi
done

install -m 0600 -o tunnel -g tunnel \
  /run/secrets/tunnel_authorized_keys \
  /home/tunnel/.ssh/authorized_keys

exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
