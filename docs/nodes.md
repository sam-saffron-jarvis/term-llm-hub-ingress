# Connecting term-llm nodes

Hub runs with reverse-node registration enabled. A node can register itself and maintain its own WebSocket connection to the public Hub; its serve port does not need to be exposed publicly.

Create a dedicated bearer token for the node and read the registration token from the home deployment:

```bash
export TERM_LLM_SERVE_TOKEN="$(openssl rand -hex 32)"
export TERM_LLM_HUB_REGISTRATION_TOKEN="$(cat home/secrets/hub_registration_token)"

term-llm serve web \
  --agent assistant \
  --host 127.0.0.1 \
  --port 8080 \
  --base-path /chat \
  --hub-url https://hub.example.com \
  --hub-node-id assistant \
  --hub-node-name Assistant \
  --hub-connect reverse \
  --hub-register
```

Persist the node's `TERM_LLM_SERVE_TOKEN`; changing it requires re-registration. Treat the registration token as a secret shared only with nodes allowed to join the Hub.

The Hub captures and scrubs registration/token environment values during startup. Caddy supports the reverse connector's WebSocket and normal streamed responses without manual upgrade-header rules.

Nodes can alternatively be added in the Hub UI using a directly reachable URL, but reverse connection mode is the safer default across networks.
