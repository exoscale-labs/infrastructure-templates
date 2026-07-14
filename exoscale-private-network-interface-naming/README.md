# Deterministic private-network interface names on Exoscale

## The problem

When you attach two or more private networks to an instance, the guest kernel
decides the order it enumerates the NICs. That order isn't stable — across
rebuilds (and sometimes reboots) the network you think of as "A" can show up as
`ens6` on one instance and `ens7` on the next. Anything that hard-codes an
interface name — firewall rules, routing, an app binding to a specific NIC —
ends up pointing at the wrong network.

Attaching the networks one at a time, or in a fixed order, doesn't fix this. The
ordering problem is on the guest side, not the API side.

## What this does

Every private-network attachment gets a MAC address from Exoscale. That MAC is
stable for the life of the attachment (it survives reboots; it only changes if
you detach and re-attach the network). So instead of trusting enumeration order,
we pin each network to a fixed interface name by matching on its MAC.

The catch: the guest can't work out which MAC belongs to which network on its
own. That mapping only lives in the API. The metadata service
(`169.254.169.254`) exposes the instance ID but nothing about private networks.

So at first boot the instance:

1. reads its own instance ID from the metadata service,
2. calls the Exoscale API (`GET /v2/instance/{id}`) to get the
   network-ID → MAC mapping,
3. writes a netplan file that matches each network's MAC and renames the
   interface (and optionally assigns a static IP),
4. runs `netplan apply`.

After that, `pna` is always the interface on private network A regardless of
what the kernel called it (`ens6`, `ens7`, whatever).

Everything is in one file: `cloud-init.yaml`. The Python helper is embedded in
it, so there's nothing else to copy. `privnet-namer.py` in this folder is the
same script kept standalone for reading and editing.

## Requirements

- Ubuntu (or Debian) cloud image — uses netplan and Python 3 stdlib, no extra
  packages.
- The private networks created ahead of time (you need their UUIDs).
- A scoped API key (below).

## Setup

### 1. Create a read-only API key

The instance has to call the API, which means the key lives inside the instance.
To keep that safe, scope the key so it can *only* read instance details and
nothing else. `role-policy.json` in this folder is that policy.

```bash
exo iam role create privnet-namer-ro --policy - < role-policy.json
exo iam api-key create privnet-namer-key privnet-namer-ro
```

The second command prints the key and secret once. If the key ever leaks, the
worst it can do is read instance metadata — it can't create, delete, or list
anything. Verified: it returns `403` on any other call.

### 2. Fill in the config

Edit the block at the top of `cloud-init.yaml`:

```json
{
  "api_key": "EXO...",
  "api_secret": "...",
  "zone": "ch-gva-2",
  "networks": [
    { "id": "PRIVNET_A_UUID", "name": "pna", "cidr": "10.0.10.5/24" },
    { "id": "PRIVNET_B_UUID", "name": "pnb", "cidr": "10.0.20.5/24" }
  ]
}
```

- `id` — the private-network UUID (`exo compute private-network list`).
- `name` — whatever you want the interface called. Referenced by your firewall,
  routes, etc.
- `cidr` — static address for unmanaged networks. Drop it and the interface
  falls back to DHCP (for managed networks).
- `mtu` — optional, add it per network if you need a non-default MTU.

Add or remove entries to match how many networks you attach.

### 3. Launch

```bash
exo compute instance create my-instance -z ch-gva-2 \
  --instance-type standard.medium \
  --template "Linux Ubuntu 24.04 LTS 64-bit" \
  --ssh-key <your-key> \
  --private-network <privnet-a> --private-network <privnet-b> \
  --cloud-init cloud-init.yaml
```

The order of the `--private-network` flags doesn't matter — that's the point.

## Config reference

| Field       | Required | Notes                                             |
|-------------|----------|---------------------------------------------------|
| `api_key`   | yes      | scoped read-only key                              |
| `api_secret`| yes      | matching secret                                   |
| `zone`      | yes      | e.g. `ch-gva-2`                                   |
| `networks[].id`   | yes | private-network UUID                            |
| `networks[].name` | yes | target interface name                          |
| `networks[].cidr` | no  | static IP; omit for DHCP                        |
| `networks[].mtu`  | no  | interface MTU                                   |

## Notes and limits

- The scoped key sits in the instance user-data and in
  `/etc/privnet-namer/config.json`. That's the trade-off for a self-contained
  cloud-init. If you'd rather keep no secret in the instance, render the netplan
  from your provisioning host instead (read the MACs from the API there and drop
  the finished file in via `write_files`) — same idea, different delivery.
- MAC changes on detach/re-attach. If your automation ever detaches and
  re-attaches a network, re-run the helper:
  `python3 /usr/local/bin/privnet-namer.py`.
- The primary/public interface (`eth0`) is left alone. Only the private NICs
  listed in the config are touched.
- Managed networks don't strictly need this — you can tell them apart by which
  subnet each NIC gets a DHCP lease from. It's the unmanaged case, with no DHCP,
  where the MAC lookup is the only reliable handle.
- Non-netplan images (RHEL family, etc.) would need a NetworkManager or
  systemd.link variant of the same approach.

## Testing

Booted verbatim on `standard.micro` / Ubuntu 24.04 with two unmanaged networks.
The interfaces came up as `pna` (10.0.10.5/24) and `pnb` (10.0.20.5/24) bound to
the correct networks, while the kernel had enumerated them as `ens6`/`ens7`.

The helper logs to the cloud-init output, so if something goes wrong:

```bash
sudo cloud-init status --long
grep privnet-namer /var/log/cloud-init-output.log
```
