# term-llm Hub hybrid ingress

Reference deployment configuration for running **term-llm Hub at home** while keeping one stable public URL. All domains, routable addresses, LAN addresses, and nonstandard ports in tracked files are documentation examples; put real deployment values only in ignored `.env` and `secrets/` files.

```text
https://hub.example.com
```

LAN clients resolve the hostname to local Caddy through MikroTik split DNS. Public clients resolve it to the droplet, where HAProxy and an outer Caddy proxy through a restricted reverse SSH tunnel to the same home Hub.

No authoritative DNS API credential is used. Each Caddy has its own private key and automatically renewed public certificate:

- **Droplet Caddy:** TLS-ALPN-01 through HAProxy's TCP passthrough on public port 443.
- **Home Caddy:** HTTP-01 forwarded from droplet port 80 through the restricted tunnel.

## Architecture

```text
LAN browser
  │ hub.example.com → 192.168.50.10 (MikroTik override)
  ▼
home Caddy ───────────────▶ term-llm Hub :8090
  ▲                                  ▲
  │ HTTP-01                          │ public Hub traffic
  │ reverse tunnel                   │ reverse tunnel
  │                                  │
restricted autossh ─────────▶ restricted sshd container
                                      ▲
                                      │ private Docker network
public browser → HAProxy → droplet Caddy
   public DNS      │          │
                   │          └─ TLS-ALPN-01 certificate
                   └─ :80/:443 public edge
```

The home machine accepts no inbound Internet connection. It initiates one key-only SSH connection to a container on the droplet. That account has no shell and can create only the two configured reverse listeners.

## Repository layout

```text
droplet/
  compose.yaml              HAProxy-facing Caddy and restricted sshd
  Caddyfile
  haproxy.cfg.example
  tunnel-sshd/
home/
  compose.yaml              term-llm Hub, local Caddy, autossh
  Caddyfile
  hub/
  autossh/
docs/
  mikrotik.md
  nodes.md
  operations.md
scripts/
  generate-secrets.sh
  validate.sh
```

## Prerequisites

- Public authoritative DNS `A` record for `hub.example.com` pointing directly to the droplet.
- HAProxy already owning public TCP ports 80 and 443.
- Docker Engine with Compose v2 on the droplet and home host.
- Public TCP access to the restricted tunnel endpoint, default port 22022.
- MikroTik RouterOS 7 providing LAN DNS.
- `ssh-keygen` and `openssl` on the trusted machine used for initial setup.

## 1. Generate secrets

Run once on a trusted machine, passing exactly the same host/IP that will be placed in `home/.env` as `DROPLET_HOST`:

```bash
./scripts/generate-secrets.sh 203.0.113.10 22022
```

This creates, outside Git tracking:

- A dedicated home tunnel key.
- A dedicated droplet SSH host key.
- A pinned `known_hosts` entry—no `StrictHostKeyChecking=no` nonsense.
- A restricted `authorized_keys` entry.
- Hub passkey bootstrap and reverse-node registration secrets.

The script refuses to overwrite existing secrets.

Distribute only the relevant tree to each machine. For example, when this checkout is on the home host:

```bash
rsync -a droplet/ deploy@203.0.113.10:/opt/term-llm-hub/droplet/
```

The droplet never receives `home/secrets/tunnel_ed25519`. The home host does not need the droplet host private key.

## 2. Configure the droplet

```bash
cd /opt/term-llm-hub/droplet
cp .env.example .env
$EDITOR .env
```

The edge host ports are configurable. The supplied defaults match this HAProxy layout:

```dotenv
EDGE_BIND_IP=127.0.0.1
EDGE_HTTP_PORT=19080
EDGE_HTTPS_PORT=19443
```

```haproxy
backend term_llm_hub_http
    mode http
    server term_llm_hub 127.0.0.1:19080 check send-proxy-v2

backend term_llm_hub_ssl
    mode tcp
    server term_llm_hub 127.0.0.1:19443 check send-proxy-v2
```

`send-proxy-v2` is required on both backends. It preserves the real public client address through HAProxy so Hub's passkey rate limiter does not collapse every external user into one shared bucket. Outer Caddy accepts PROXY headers only from the fixed Docker bridge gateway configured by `EDGE_PROXY_SOURCE_CIDR`.

Merge the SNI/Host ACL examples from [`droplet/haproxy.cfg.example`](droplet/haproxy.cfg.example) into the existing frontends.

**Port 443 must remain TCP passthrough for this hostname.** If HAProxy terminates TLS, Caddy cannot answer TLS-ALPN-01 and does not own the browser-facing certificate. HTTP can remain `mode http`.

Start the edge:

```bash
cd /opt/term-llm-hub/droplet
docker compose up -d --build
```

The restricted SSH endpoint defaults to public TCP port 22022. Prefer a provider firewall rule that allows only the home's current egress IP. If that IP is dynamic, apply host-level connection/rate limits and monitor rejected/pre-auth connections. The container itself uses key-only auth plus `LoginGraceTime 20`, `MaxAuthTries 1`, explicit `MaxStartups`, no shell, and restricted reverse listeners—but firewalling still protects availability.

HAProxy should then report `127.0.0.1:19080` and `127.0.0.1:19443` available. The tunnel service remains `unhealthy` until home connects; that is expected.

## 3. Configure home

```bash
cd home
cp .env.example .env
$EDITOR .env
docker compose \
  -f compose.yaml \
  -f compose.bootstrap.yaml \
  up -d --build
```

Use the bootstrap override only for first-passkey enrolment. The cleanup step comes immediately after enrolment below; routine starts use the base `compose.yaml` alone.

The home stack runs:

- term-llm Hub pinned to `TERM_LLM_VERSION` and checksum-verified at build time.
- Passkey authentication with `https://hub.example.com` as its stable WebAuthn origin.
- Local Caddy on the selected LAN address.
- autossh with keepalives and automatic reconnection.
- Persistent named volumes for Hub state and both Caddy certificate stores.

Hub itself is not published on a host port; only Caddy and the tunnel client can reach it.

### Optional: give Caddy a dedicated LAN IP

If another proxy already owns ports 80 and 443 on every host interface, attach
Caddy directly to an existing macvlan or ipvlan network instead of publishing
host ports. Reserve an unused address outside the DHCP pool, then set the
following deployment-specific values in `home/.env`:

```dotenv
CADDY_LAN_NETWORK=homelab_lan
CADDY_LAN_IP=192.168.50.11
```

The external Docker network must already exist and cover `CADDY_LAN_IP`. Start
the first-passkey stack with the dedicated-IP override:

```bash
docker compose \
  -f compose.yaml \
  -f compose.lan-ip.yaml \
  -f compose.bootstrap.yaml \
  up -d --build
```

For routine starts after enrolment, omit only the bootstrap override:

```bash
docker compose -f compose.yaml -f compose.lan-ip.yaml up -d
```

Caddy remains attached to the private `hub` network as well, so autossh and Hub
continue to use their internal addresses. The override removes Caddy's host port
publications; use `CADDY_LAN_IP` for the split-DNS record. Include the same
Compose files when running `down`, `logs`, or other lifecycle commands so
Compose operates on the intended model.

## 4. Add split DNS

Follow [`docs/mikrotik.md`](docs/mikrotik.md). The essential override is:

```routeros
/ip dns static add \
    name=hub.example.com \
    type=A \
    address=192.168.50.10 \
    ttl=5m
```

## 5. Enrol the first passkey

```bash
cat home/secrets/passkey_bootstrap_token
```

Open:

```text
https://hub.example.com/auth/setup
```

Enter the setup code and register a passkey. Then remove the bootstrap secret and recreate Hub without the override:

```bash
cd home
docker compose -f compose.yaml -f compose.bootstrap.yaml down
rm secrets/passkey_bootstrap_token
docker compose up -d
```

The named Hub volume, including `auth.json`, survives this transition. See [`docs/operations.md`](docs/operations.md) for expiry, recovery, and backup details.

## 6. Connect term-llm nodes

See [`docs/nodes.md`](docs/nodes.md). Reverse-connected nodes maintain their own outbound WebSocket to Hub and require no additional inbound firewall exposure.

## Validation

```bash
./scripts/validate.sh
```

This validates shell syntax, the HAProxy fragment when HAProxy is installed, both Compose models, and both Caddyfiles. GitHub Actions installs HAProxy and builds all custom images.

Runtime smoke:

```bash
curl -fsS https://hub.example.com/healthz
```

Expected:

```json
{"role":"hub","status":"ok"}
```

## Security boundaries

- No DNS-management credential.
- No private-key copying between Caddy instances.
- Home initiates the tunnel; the droplet has no login credential for home.
- Tunnel SSH key has `restrict`, `permitlisten`, no PTY, no shell, and remote-forwarding-only policy.
- Reverse listeners exist only on a private Docker network and are not host-published.
- The SSH endpoint container has no Docker socket or host filesystem mount.
- Hub uses passkey authentication and stores credentials in a persistent private volume.
- External monitoring should probe `/healthz`; a living autossh process alone proves remarkably little.
