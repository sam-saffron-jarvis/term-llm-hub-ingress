#!/bin/sh
set -eu

home_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
env_file="$home_dir/.env"
repo=samsaffron/term-llm

if [ "$#" -ne 0 ]; then
  echo "usage: $0" >&2
  exit 64
fi

for command in awk curl docker mktemp sha256sum tar; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "$command is required" >&2
    exit 1
  }
done

[ -f "$env_file" ] || {
  echo "missing $env_file; copy .env.example to .env and configure it first" >&2
  exit 1
}

if ! current_version=$(awk -F= '
  /^TERM_LLM_VERSION=/ { value = substr($0, index($0, "=") + 1); count++ }
  END { if (count != 1) exit 1; print value }
' "$env_file"); then
  echo "expected exactly one TERM_LLM_VERSION setting in $env_file" >&2
  exit 1
fi
case "$current_version" in
  v[0-9]*) ;;
  *)
    echo "TERM_LLM_VERSION is missing or invalid in $env_file" >&2
    exit 1
    ;;
esac

printf 'Checking for the latest term-llm release (currently %s)...\n' "$current_version"
latest_url=$(curl --connect-timeout 15 --max-time 60 --retry 3 \
  -fsSL -o /dev/null -w '%{url_effective}' \
  "https://github.com/$repo/releases/latest")

case "$latest_url" in
  "https://github.com/$repo/releases/tag/"v[0-9]*) ;;
  *)
    echo "could not determine the latest release from: $latest_url" >&2
    exit 1
    ;;
esac

latest_version=${latest_url##*/}
if [ "$latest_version" = "$current_version" ]; then
  printf 'term-llm is already current at %s.\n' "$current_version"
  exit 0
fi

version=${latest_version#v}
tmp=$(mktemp -d)
env_next=$(mktemp "$home_dir/.env.update.XXXXXX")
env_changed=0
committed=0

restore_env() {
  restore=$(mktemp "$home_dir/.env.restore.XXXXXX")
  cp -p "$tmp/env.old" "$restore"
  mv -f "$restore" "$env_file"
  env_changed=0
}

cleanup() {
  status=$?
  trap - EXIT INT TERM HUP
  if [ "$env_changed" -eq 1 ] && [ "$committed" -eq 0 ]; then
    echo "Restoring the previous .env." >&2
    restore_env
  fi
  rm -rf "$tmp"
  rm -f "$env_next"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

for arch in amd64 arm64; do
  asset="term-llm_${version}_linux_${arch}.tar.gz"
  printf 'Downloading %s...\n' "$asset"
  curl --connect-timeout 15 --max-time 300 --retry 3 \
    -fsSLo "$tmp/$asset" \
    "https://github.com/$repo/releases/download/$latest_version/$asset"
  tar -tzf "$tmp/$asset" | grep -Eq '(^|/)term-llm$' || {
    echo "$asset does not contain the term-llm executable" >&2
    exit 1
  }
done

sha_amd64=$(sha256sum "$tmp/term-llm_${version}_linux_amd64.tar.gz" | awk '{print $1}')
sha_arm64=$(sha256sum "$tmp/term-llm_${version}_linux_arm64.tar.gz" | awk '{print $1}')

cp -p "$env_file" "$tmp/env.old"
awk \
  -v version="$latest_version" \
  -v amd64="$sha_amd64" \
  -v arm64="$sha_arm64" '
  BEGIN { versions = amd64s = arm64s = 0 }
  /^TERM_LLM_VERSION=/ { print "TERM_LLM_VERSION=" version; versions++; next }
  /^TERM_LLM_SHA256_AMD64=/ { print "TERM_LLM_SHA256_AMD64=" amd64; amd64s++; next }
  /^TERM_LLM_SHA256_ARM64=/ { print "TERM_LLM_SHA256_ARM64=" arm64; arm64s++; next }
  { print }
  END {
    if (versions != 1 || amd64s != 1 || arm64s != 1) {
      print "expected exactly one of each TERM_LLM setting in .env" > "/dev/stderr"
      exit 1
    }
  }
' "$env_file" > "$tmp/env.new"

cp -p "$env_file" "$env_next"
cat "$tmp/env.new" > "$env_next"
mv -f "$env_next" "$env_file"
env_changed=1

compose() {
  (cd "$home_dir" && docker compose "$@")
}

wait_for_hub() {
  attempts=0
  while [ "$attempts" -lt 60 ]; do
    container=$(compose ps -q hub)
    if [ -n "$container" ]; then
      health=$(docker inspect \
        --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
        "$container" 2>/dev/null || true)
      case "$health" in
        healthy|running) return 0 ;;
        unhealthy|exited|dead) return 1 ;;
      esac
    fi
    attempts=$((attempts + 1))
    sleep 2
  done
  return 1
}

printf 'Updating term-llm from %s to %s...\n' "$current_version" "$latest_version"
if ! compose build --pull hub; then
  echo "The new image did not build; the running Hub was not changed." >&2
  exit 1
fi

if compose up -d hub && wait_for_hub; then
  committed=1
  env_changed=0
  printf 'term-llm Hub is healthy on %s.\n' "$latest_version"
  exit 0
fi

echo "The updated Hub did not become healthy; rolling back to $current_version." >&2
restore_env
if compose build hub && compose up -d hub && wait_for_hub; then
  echo "Rollback to $current_version succeeded." >&2
else
  echo "Rollback failed; inspect: cd $home_dir && docker compose logs hub" >&2
fi
exit 1
