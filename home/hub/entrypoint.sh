#!/bin/sh
set -eu

registration=/run/secrets/hub_registration_token
bootstrap=/run/secrets/passkey_bootstrap_token
recovery=/run/secrets/passkey_recovery_token

if [ ! -s "$registration" ]; then
  echo "required Hub registration secret is missing or empty: $registration" >&2
  exit 1
fi

install -d -m 0700 -o termllm -g termllm /run/term-llm

if [ -s "$bootstrap" ]; then
  install -m 0600 -o termllm -g termllm \
    "$bootstrap" /run/term-llm/passkey-bootstrap-token
  set -- "$@" \
    --passkey-bootstrap-token-file /run/term-llm/passkey-bootstrap-token
fi

if [ -s "$recovery" ]; then
  install -m 0600 -o termllm -g termllm \
    "$recovery" /run/term-llm/passkey-recovery-token
  set -- "$@" \
    --passkey-recovery-token-file /run/term-llm/passkey-recovery-token
fi

# term-llm captures and scrubs this environment variable during startup.
TERM_LLM_HUB_REGISTRATION_TOKEN=$(cat "$registration")
export TERM_LLM_HUB_REGISTRATION_TOKEN

chown termllm:termllm /data
chmod 0700 /data
exec gosu termllm:termllm term-llm "$@"
