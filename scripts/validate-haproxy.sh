#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
command -v haproxy >/dev/null 2>&1 || {
  echo "haproxy not installed; skipping fragment validation" >&2
  exit 0
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT INT TERM HUP

cat > "$tmp" <<'EOF'
global
    daemon

defaults
    timeout connect 5s
    timeout client 30s
    timeout server 30s

frontend public_http
    bind 127.0.0.1:10080
    mode http
    acl host_term_llm_hub hdr(host) -i hub.example.com
    use_backend term_llm_hub_http if host_term_llm_hub

frontend public_tls
    bind 127.0.0.1:10443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    use_backend term_llm_hub_ssl if { req_ssl_sni -i hub.example.com }
EOF

cat "$root/droplet/haproxy.cfg.example" >> "$tmp"
haproxy -c -f "$tmp"
