# MikroTik split-horizon DNS

Public authoritative DNS remains unchanged:

```text
hub.example.com A 203.0.113.10
```

Before enabling the MikroTik as a recursive resolver, verify the input firewall does not expose DNS on WAN:

```routeros
/ip firewall filter print where chain=input
```

The input chain must permit LAN clients and reject both UDP and TCP destination port 53 from `in-interface-list=WAN`. RouterOS default firewall configurations usually already drop unsolicited WAN input, but do not assume that. If explicit DNS rules are needed, place WAN rejects before any broad WAN accept rule:

```routeros
/ip firewall filter add chain=input in-interface-list=WAN protocol=udp dst-port=53 action=drop comment="block WAN DNS"
/ip firewall filter add chain=input in-interface-list=WAN protocol=tcp dst-port=53 action=drop comment="block WAN DNS"
```

Rule order matters. Confirm LAN DNS still works and an external probe cannot query the router before continuing.

Then enable LAN DNS and add the split answer:

```routeros
/ip dns set allow-remote-requests=yes
/ip dns static add name=hub.example.com type=A address=192.168.50.10 ttl=5m
```

Ensure the DHCP network advertises the router as DNS:

```routeros
/ip dhcp-server network print
/ip dhcp-server network set <entry-number> dns-server=192.168.50.1
```

Verify both views:

```bash
dig @192.168.50.1 hub.example.com +short
dig @1.1.1.1 hub.example.com +short
```

Expected answers are `192.168.50.10` locally and `203.0.113.10` publicly.

## Caveats

- Clients using their own DoH/private DNS can bypass the MikroTik override.
- Do not publish a public AAAA record unless the local DNS view also has the intended IPv6 answer. Otherwise Happy Eyeballs may take the public route while at home.
- No inbound home NAT rule is needed. The SSH tunnel is initiated from home.
