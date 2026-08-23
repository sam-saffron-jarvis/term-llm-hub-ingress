# Operations

## Lifecycle

Start the droplet first:

```bash
cd droplet
docker compose up -d --build
```

Then start home for first-passkey enrolment:

```bash
cd home
docker compose -f compose.yaml -f compose.bootstrap.yaml up -d --build
```

After enrolment, remove the bootstrap material and run the base stack as documented below. Routine starts use:

```bash
docker compose up -d
```

When Caddy uses the optional dedicated-LAN-IP mode, include
`-f compose.yaml -f compose.lan-ip.yaml` in every lifecycle command and append
`-f compose.bootstrap.yaml` or `-f compose.recovery.yaml` when needed. For
example, a first-passkey start is:

```bash
docker compose \
  -f compose.yaml \
  -f compose.lan-ip.yaml \
  -f compose.bootstrap.yaml \
  up -d
```

Stop in the opposite order. `docker compose down` at home removes the reverse listeners immediately; the edge remains up but returns `502` until the tunnel returns.

## Status

```bash
docker compose ps
docker compose logs --tail=100 caddy
docker compose logs --tail=100 autossh       # home
docker compose logs --tail=100 tunnel-sshd   # droplet
```

The droplet `tunnel-sshd` service becomes healthy only when the ACME reverse listener exists and `/healthz` succeeds through the application tunnel. Compose does not restart containers solely because they are marked unhealthy; autossh's server-alive checks cause a dead client to reconnect or exit, and `restart: unless-stopped` handles process exit.

## Health checks

```bash
curl -fsS https://hub.example.com/healthz
```

Expected response:

```json
{"role":"hub","status":"ok"}
```

Force each HTTPS endpoint independently when diagnosing split DNS:

```bash
curl -v --resolve hub.example.com:443:192.168.50.10 \
  https://hub.example.com/healthz

curl -v --resolve hub.example.com:443:203.0.113.10 \
  https://hub.example.com/healthz
```

The public check covers HAProxy, outer Caddy, reverse SSH, and Hub. The local check covers inner Caddy and Hub.

## First passkey

Start with the bootstrap override and read the one-time setup code locally:

```bash
docker compose -f compose.yaml -f compose.bootstrap.yaml up -d
cat secrets/passkey_bootstrap_token
```

Open:

```text
https://hub.example.com/auth/setup
```

The bootstrap grant expires ten minutes after Hub startup and can create one passkey. Once enrolled, remove the reusable bootstrap material:

```bash
docker compose -f compose.yaml -f compose.bootstrap.yaml down
rm secrets/passkey_bootstrap_token
docker compose up -d
```

Preserve `/data/auth.json`; deleting it is not a recovery procedure.

## Passkey recovery

If all enrolled passkeys are unavailable but `auth.json` remains intact, create a temporary recovery secret:

```bash
cd "$(git rev-parse --show-toplevel)"
./scripts/generate-recovery-token.sh
docker compose -f home/compose.yaml -f home/compose.recovery.yaml up -d hub
```

Open `https://hub.example.com/auth/recover`, enter the token from `home/secrets/passkey_recovery_token`, and enrol a replacement passkey. The grant lasts ten minutes. Immediately remove it and recreate Hub without the override:

```bash
docker compose -f home/compose.yaml -f home/compose.recovery.yaml down
rm home/secrets/passkey_recovery_token
docker compose -f home/compose.yaml up -d
```

## Backup and restore

`hub_data` contains passkey identity state, node bearer tokens, node metadata, and delegation state. Back it up encrypted. A simple quiesced backup from the home project is:

```bash
cd home
backup_dir="$HOME/term-llm-hub-backups"
mkdir -p "$backup_dir"
docker compose stop hub
docker run --rm \
  -v term-llm-hub-home_hub_data:/data:ro \
  -v "$backup_dir:/backup" \
  alpine:3.22.5 \
  tar -C /data -czf /backup/hub-data-$(date +%Y%m%d-%H%M%S).tar.gz .
docker compose start hub
```

Move the archive into encrypted durable storage rather than leaving it as an unencrypted local copy. On restore, stop Hub, restore the archive into the named volume, then enforce UID/GID `10001:10001`, directory mode `0700`, and private file modes before startup. Test restoration periodically rather than discovering your backup is decorative during an incident.

## Updating term-llm

Run the home updater whenever you want to deploy the latest published release:

```bash
cd home
./update-term-llm.sh
```

If the configured version is already current, the script exits without changing
anything. Otherwise it downloads both Linux release archives, verifies that they
contain the expected executable, calculates their SHA-256 values, and updates the
three pinned `TERM_LLM_*` settings in `home/.env`. It then rebuilds only Hub and
waits for its container health check. A failed build leaves the running Hub alone;
a failed health check triggers a rebuild and rollback to the previous pin.

The updater requires `curl`, `docker compose`, `tar`, and `sha256sum` on the home
host. It discovers releases and downloads assets from GitHub, so the calculated
hashes preserve repeatable subsequent builds but are not an independent signature
of the upstream release.

To select a release manually instead, change `TERM_LLM_VERSION` and both
architecture-specific SHA-256 values in `home/.env`, then run:

```bash
cd home
docker compose build --pull hub
docker compose up -d hub
curl -fsS https://hub.example.com/healthz
```

The image always verifies the selected release archive against the explicit
SHA-256 pinned in `.env`; it does not trust a checksum downloaded beside the
archive.

## Changing the droplet SSH hostname

`DROPLET_HOST` must match the host field in `home/secrets/known_hosts`. If only the address/name changes while the droplet host key stays the same, regenerate that entry from the existing public host key rather than key-scanning the network:

```bash
host=new-droplet.example.com
port=22022
key=$(awk '{print $1 " " $2}' droplet/secrets/ssh_host_ed25519_key.pub)
printf '[%s]:%s %s\n' "$host" "$port" "$key" > home/secrets/known_hosts
chmod 600 home/secrets/known_hosts
```

Update `home/.env` to the exact same `host` value.

## Monitoring recommendation

Point an external uptime monitor at `https://hub.example.com/healthz`. Container health alone cannot prove the public SNI route, certificates, or whole tunnel path work.
