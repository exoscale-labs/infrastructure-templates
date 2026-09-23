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
own. That mapping only lives in the API — the metadata service
(`169.254.169.254`) exposes the instance ID but nothing about private networks.

So at first boot the instance:

1. reads its own instance ID from the metadata service,
2. calls the Exoscale API (`GET /v2/instance/{id}`) for the network-ID → MAC map,
3. pins each network to a fixed interface name (and optional static IP) by MAC,
4. applies it.

After that, `oam` is always the interface on the OAM network regardless of what
the kernel called it (`ens6`, `ens7`, whatever).

## Which file to use

Each file is a single self-contained cloud-init with the helper embedded.
Pick by whether your private networks are **managed**
(they have a subnet/DHCP range) or **unmanaged** (no DHCP):

| Networks | cloud-init | how it finds each network | needs |
|----------|-----------|---------------------------|-------|
| **Managed** (RHEL/Rocky/Alma) | `cloud-init-rhel-managed.yaml` | DHCP lease subnet (local) | nothing |
| **Managed** (Ubuntu/Debian) | `cloud-init-ubuntu-managed.yaml` | DHCP lease subnet (local) | nothing |
| **Managed** (openSUSE Leap 16) | `cloud-init-suse-managed.yaml` | DHCP lease subnet (local) | nothing |
| **Managed** (SUSE with wicked) | `cloud-init-suse-wicked.yaml` | DHCP lease subnet (local) | nothing |
| Unmanaged (RHEL/Rocky/Alma) | `cloud-init-rhel.yaml` | API lookup by MAC | scoped API key + internet |
| Unmanaged (Ubuntu/Debian) | `cloud-init-ubuntu.yaml` | API lookup by MAC | scoped API key + internet |

The `privnet-namer-*.py` files are the same helpers kept standalone for reading
and editing. `role-policy.json` is the IAM policy for the scoped key (unmanaged
variants only).

### If you can use managed networks, do

The managed variants are the simplest and the most robust: a managed network
hands out a DHCP lease on its own subnet, so the guest tells the networks apart
locally with no API call, no key, no metadata, and no internet. That also makes
them the only variants that work with `--public-ip none` — a private instance has
no route to the API, so the in-guest lookup the unmanaged variants rely on cannot
run there. Managed does not cost you addressing control: you set the CIDR at
creation and can pin exact IPs with `private-network attach --ip` (at attach
time) or `instance private-network update-ip --ip` (afterwards). A pinned address
is picked up on the next reboot and the interface keeps its name, because the
name is bound to the MAC, not the address.

Use an unmanaged variant only if you genuinely cannot use managed networks. Those
instances then need a scoped API key in the instance and outbound internet, and
they will not work with `--public-ip none`.

### Why the variants differ per distribution

The Ubuntu image ships netplan and `python3`. RHEL ships neither by that name —
it uses NetworkManager, and Python is present only as
`/usr/libexec/platform-python` (3.6), which is what cloud-init itself runs on.
The RHEL variants use those directly, so they need no extra packages and work on
an unsubscribed BYOL image where `dnf install` isn't available. Every variant
pins the name by MAC through a systemd `.link` file so the naming survives
reboots (udev renames by MAC before the network stack starts), and renames the
live device for the first boot.

There is a second, less obvious difference that matters for the **managed**
variants. On RHEL/Rocky, NetworkManager auto-creates a DHCP profile ("Wired
connection N") for every NIC nothing else claims, so by the time the namer runs
the leases are already there and it only has to read them.

Netplan has no such fallback — it configures only what is declared. And the
Exoscale Ubuntu 24.04 template ships a `/etc/netplan/50-cloud-init.yaml` that
matches the QEMU default MAC `52:54:00:12:34:56`, which no instance actually
has:

```yaml
network:
  version: 2
  ethernets:
    ens3:
      match:
        macaddress: "52:54:00:12:34:56"
      dhcp4: true
```

On an instance created with `--public-ip none` that means netplan manages
nothing, no interface ever runs DHCP, and the instance boots with no addresses
at all — reachable only through the emergency console. (With a public IP the
problem is masked: cloud-init rewrites the file from the datasource, so the
public NIC comes up and only the private NICs stay unconfigured.)

So `cloud-init-ubuntu-managed.yaml` does three phases instead of one: it parks
the shipped netplan config (keeping a copy in
`/var/log/privnet-namer/original-netplan/`), brings DHCP up on every NIC so
leases can arrive, and only then does the subnet → MAC → name mapping. It also
writes `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg` so cloud-init does
not regenerate the broken file on the next boot, and re-emits any NIC it did not
pin (the public interface, typically) by MAC with plain DHCP so connectivity is
preserved.

### openSUSE

openSUSE Leap 16 dropped wicked, so it is a NetworkManager system like RHEL —
same mechanism, same auto-created DHCP profile for every unclaimed NIC. Three
details differ, and `cloud-init-suse-managed.yaml` handles them:

- Python is a normal `/usr/bin/python3` (3.13 on Leap 16), not platform-python.
- cloud-init renders its network config as a NetworkManager keyfile bound to a
  **MAC address** (`/etc/NetworkManager/system-connections/cloud-init-eth0.nmconnection`,
  `autoconnect-priority=120`), and it is re-rendered on boot. With
  `--public-ip none` that profile sits on a private NIC and follows it through
  the rename. So the SUSE helper deletes any profile bound to a MAC or interface
  it takes over and writes its own at priority 200.
- It does not assume the image runs DHCP on the private NICs at all. If a
  configured subnet still has no lease after ~15 seconds, the helper brings DHCP
  up on the unaddressed NICs itself, and keeps doing so as further NICs appear
  (they are attached while the instance boots). Without a lease a NIC cannot be
  matched to its network, so waiting for one that is never coming is the one
  failure mode worth designing out — a custom image with NetworkManager's
  `no-auto-default` set would otherwise hang until the timeout.

Worth knowing: on an instance created with `--public-ip none`, cloud-init falls
back to the config drive (`DataSourceNoCloud`) and writes that keyfile with the
QEMU placeholder MAC `52:54:00:12:34:56` — the same bogus MAC that breaks Ubuntu.
On the stock Leap 16 image it is harmless, because NetworkManager's auto-default
still gives every unclaimed NIC a DHCP lease, so the instance is never left
without addresses.

### SUSE with wicked

Not every SUSE image is a NetworkManager image. The Exoscale
`SUSE Linux Enterprise Server 15 SP7` template runs wicked, and so do golden
images built on Leap that keep wicked. There is no `nmcli` at all, and the
private NICs stay `device-unconfigured` — attached, but without an address, so
`ip -4 a` shows nothing but `lo` and `eth0`. Which one you have:

```bash
systemctl is-active NetworkManager wicked
```

`cloud-init-suse-wicked.yaml` is that variant. Each helper refuses to run on the
other's system and says which file to use instead, so picking the wrong one
costs a log line, not a broken instance.

Same three phases, different tools: it writes an `ifcfg-<iface>` per NIC and
runs `wicked ifup` to get the leases (wicked configures nothing it was not
asked to), maps subnet → MAC → name, then renames and writes
`ifcfg-<name>`.

Naming is where wicked images differ most, and both points were found by
rebooting, not by reading:

- The SLES image boots with `net.ifnames=0`, which makes udev **ignore the
  `Name=` in a systemd `.link` file**. After a reboot the NICs are `eth1`,
  `eth2`, … again. What does work is the classic SUSE udev rule with `NAME=`,
  so the helper writes both and relies on the rule.
- cloud-init writes its own `85-persistent-net-cloud-init.rules` pinning the
  MAC of the NIC it configured to `eth0`, and SUSE images ship
  `70-persistent-net.rules` doing the same. The last `NAME=` wins, so the
  helper's file is a `99-` one and any line elsewhere claiming a MAC it renames
  is removed (originals kept in `/var/log/privnet-namer/`). Without that, every
  NIC renames except the first one.

The temporary `ifcfg-eth1`, `ifcfg-eth2`, … are deliberately left behind. If a
rename ever fails, the NIC still gets its lease under the kernel name and the
instance stays reachable — which matters when it has no public IP and the
alternative is the emergency console.

## Requirements

- Ubuntu/Debian, RHEL/Rocky/Alma 8 or 9, openSUSE Leap 16, or a SUSE image
  running wicked (SLES 15). Uses only what's on the base image.
- The private networks created ahead of time (you need their UUIDs).
- A scoped API key (below).

## Setup — managed variants (`cloud-init-rhel-managed.yaml`, `cloud-init-suse-managed.yaml`, `cloud-init-suse-wicked.yaml`, `cloud-init-ubuntu-managed.yaml`)

No API key, no IAM role. Just edit the `networks` block: each managed network's
subnet and the interface name you want.

```json
{
  "networks": [
    { "subnet": "10.0.10.0/24", "name": "oam" },
    { "subnet": "10.0.20.0/24", "name": "mgmt" }
  ]
}
```

Then create the instance with the managed networks attached (public IP optional):

```bash
exo compute instance create my-instance -z de-fra-1 \
  --instance-type standard.medium \
  --template "Linux RedHat 8.10 BYOL 64-bit" \
  --ssh-key <your-key> --public-ip none \
  --private-network oam_net --private-network mgmt_net \
  --cloud-init cloud-init-rhel-managed.yaml
```

Same for openSUSE, just the other file:

```bash
exo compute instance create my-instance -z de-fra-1 \
  --instance-type standard.medium \
  --template "OpenSUSE Leap 16.0 64-bit" \
  --ssh-key <your-key> --public-ip none \
  --private-network oam_net --private-network mgmt_net \
  --cloud-init cloud-init-suse-managed.yaml
```

That's it. The rest of this section is only for the unmanaged (API) variants.

## Setup — unmanaged variants

### 1. Create a read-only API key

The instance calls the API, so the key lives inside the instance. To keep that
safe, scope the key so it can *only* read instance details. `role-policy.json`
is that policy.

```bash
exo iam role create privnet-namer-ro --policy - < role-policy.json
exo iam api-key create privnet-namer-key privnet-namer-ro
```

The second command prints the key and secret once. If the key leaks, the worst
it can do is read instance metadata — it can't create, delete, or list anything.
Verified: it returns `403` on any other call.

### 2. Fill in the config

Edit the block at the top of the cloud-init file:

```json
{
  "api_key": "EXO...",
  "api_secret": "...",
  "zone": "de-fra-1",
  "networks": [
    { "id": "PRIVNET_A_UUID", "name": "oam",  "cidr": "10.0.10.5/24" },
    { "id": "PRIVNET_B_UUID", "name": "mgmt", "cidr": "10.0.20.5/24" }
  ]
}
```

- `id` — the private-network UUID (`exo compute private-network list`).
- `name` — whatever you want the interface called.
- `cidr` — static address for unmanaged networks. Drop it to fall back to DHCP.
- `mtu` — optional, per network.

Add or remove entries to match how many networks you attach.

### 3. Launch

```bash
exo compute instance create my-instance -z de-fra-1 \
  --instance-type standard.medium \
  --template "Linux RedHat 8.10 BYOL 64-bit" \
  --ssh-key <your-key> \
  --private-network oam_ne --private-network vnf_mgmt \
  --cloud-init cloud-init-rhel.yaml
```

The order of the `--private-network` flags doesn't matter — that's the point.

## Config reference

| Field       | Required | Notes                        |
|-------------|----------|------------------------------|
| `api_key`   | yes      | scoped read-only key         |
| `api_secret`| yes      | matching secret              |
| `zone`      | yes      | e.g. `de-fra-1`              |
| `networks[].id`   | yes | private-network UUID       |
| `networks[].name` | yes | target interface name      |
| `networks[].cidr` | no  | static IP; omit for DHCP   |
| `networks[].mtu`  | no  | interface MTU              |

## Notes and limits

- The scoped key sits in the instance user-data and in
  `/etc/privnet-namer/config.json`. That's the trade-off for a self-contained
  cloud-init. If you'd rather keep no secret in the instance, render the config
  from your provisioning host instead (read the MACs from the API there and drop
  the finished file in via `write_files`) — same idea, different delivery.
- MAC changes on detach/re-attach. If your automation ever detaches and
  re-attaches a network, re-run the helper:
  `python3 /usr/local/bin/privnet-namer.py` (Ubuntu, openSUSE/SLES) or
  `/usr/libexec/platform-python /usr/local/bin/privnet-namer.py` (RHEL).
- The primary/public interface (`eth0`/`ens3`) is left alone. Only the private
  NICs listed in the config are touched.
- The config reference above is for the unmanaged (API) variants. The managed
  variant's config is just `{ "subnet": "...", "name": "..." }` per network, with
  an optional `mtu` — no key, no zone, no UUIDs.
- The managed variants re-run safely — verified on openSUSE, where a second run
  on a fully configured instance changed nothing and kept every address. They
  re-derive everything from the current leases, so there is no state to keep in
  sync.

## Testing

Every variant was booted verbatim (minus the placeholders) on Exoscale.

- **Ubuntu 24.04**, two unmanaged networks: interfaces came up as the configured
  names bound to the right networks, while the kernel had enumerated them as
  `ens6`/`ens7`.
- **RHEL 8.10 BYOL** (`de-fra-1`), two unmanaged networks: same result via
  NetworkManager, and it held across a reboot — after the reboot the helper does
  not run again; the `systemd.link` files and saved NetworkManager profiles
  bring the interfaces back up correctly on their own.
- **RHEL 8.10 BYOL, managed variant, `--public-ip none`** (`de-fra-1`): a private
  instance with no public IP, two managed networks. It got DHCP leases on both
  subnets and the helper named the interfaces `oam` (`10.0.10.30`) and `mgmt`
  (`10.0.20.50`) with no API, key, metadata, or internet involved. Verified from
  inside the instance by relaying its state to an observer on the same private
  network (the instance itself has no outbound path). Also held across a reboot.
- **openSUSE Leap 16.0, managed variant** (`de-fra-1`, public template
  `OpenSUSE Leap 16.0 64-bit`), three managed networks — the customer setup:
  `10.1.1.0/24` → `vnf_mgmt`, `10.1.3.0/24` → `sig_int`,
  `10.1.5.0/24` → `oam_ne`.
  - With `--public-ip none`: the kernel had enumerated the NICs `eth0`–`eth2`;
    after cloud-init they were `vnf_mgmt`, `sig_int`, `oam_ne` with the right
    lease on each. Verified through a jump host on the same private networks.
  - Addresses then pinned with `instance private-network update-ip` to
    `10.1.1.30` / `10.1.3.30` / `10.1.5.30` and rebooted: each interface kept
    its name and picked up its pinned address.
  - With a public IP: the private NICs were named the same way while `eth0`
    kept its cloud-init profile, its default route and internet access. Held
    across a reboot, and a manual re-run of the helper was a no-op.
  - On an instance doctored to behave like an image that never DHCPs an
    unclaimed NIC (`no-auto-default=*`, profiles deleted, addresses flushed,
    links down), the helper started DHCP on all three NICs itself and named
    them — the public NIC was left alone throughout. This is what makes the
    file safe to hand to someone running a custom image rather than the stock
    template.
- **SLES 15 SP7, wicked variant** (`de-fra-1`, template
  `SUSE Linux Enterprise Server 15 SP7`), three managed networks. With
  `--public-ip none`: all three NICs got a lease from a stack that configures
  nothing by itself, and came up as `vnf_mgmt`, `sig_int`, `oam_ne`. Addresses
  then pinned to `.30` and rebooted — names and addresses held. With a public
  IP: private NICs named, `eth0` kept its cloud-init config, default route and
  internet, held across a reboot, and a manual re-run changed nothing.
  Before the udev findings above were folded in, the same test left a
  private-only instance unreachable after its first reboot; that is what the
  `99-` rule and the conflict stripping fix.

The helper logs to the cloud-init output, so if something goes wrong:

```bash
sudo cloud-init status --long
grep privnet-namer /var/log/cloud-init-output.log
```
