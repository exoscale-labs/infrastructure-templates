#!/usr/bin/env python3
"""
privnet-namer: give Exoscale private-network interfaces deterministic names.

At boot the kernel enumerates extra NICs (ens6/ens7/...) in a non-deterministic
order. This tool asks the Exoscale API which MAC address belongs to which
private network, then writes a netplan file that pins each network to a stable
interface name (and optional static IP) by matching on MAC. Interface *ordering*
therefore stops mattering.

Config: /etc/privnet-namer/config.json
Needs only Python 3 stdlib (present in the Ubuntu cloud image).
"""
import base64, hashlib, hmac, json, os, sys, time, urllib.request

CONFIG = os.environ.get("PRIVNET_NAMER_CONFIG", "/etc/privnet-namer/config.json")
NETPLAN_OUT = "/etc/netplan/99-privnets.yaml"


def log(msg):
    print(f"[privnet-namer] {msg}", flush=True)


def get_instance_id():
    """Free, no credentials: the metadata service knows our own instance-id."""
    url = "http://169.254.169.254/1.0/meta-data/instance-id"
    with urllib.request.urlopen(url, timeout=5) as r:
        return r.read().decode().strip()


def api_get_instance(key, secret, zone, instance_id):
    """Signed GET /v2/instance/{id} using Exoscale's EXO2-HMAC-SHA256 scheme."""
    host = f"https://api-{zone}.exoscale.com"
    path = f"/v2/instance/{instance_id}"
    expires = int(time.time()) + 600
    # sig = METHOD path \n body \n query-values \n headers \n expires
    sig_string = "\n".join([f"GET {path}", "", "", "", str(expires)])
    sig = base64.b64encode(
        hmac.new(secret.encode(), sig_string.encode(), hashlib.sha256).digest()
    ).decode()
    auth = f"EXO2-HMAC-SHA256 credential={key},expires={expires},signature={sig}"
    req = urllib.request.Request(host + path, headers={"Authorization": auth})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def guest_macs():
    """MAC -> ifname for every NIC currently present in the guest."""
    out = {}
    base = "/sys/class/net"
    for name in os.listdir(base):
        if name == "lo":
            continue
        try:
            with open(f"{base}/{name}/address") as f:
                out[f.read().strip().lower()] = name
        except OSError:
            pass
    return out


def build_netplan(networks, id_to_mac):
    eths = {}
    for n in networks:
        mac = id_to_mac.get(n["id"])
        if not mac:
            raise SystemExit(f"network {n['id']} has no MAC in API response")
        block = {"match": {"macaddress": mac}, "set-name": n["name"]}
        if n.get("cidr"):
            block["addresses"] = [n["cidr"]]
        else:
            block["dhcp4"] = True
        if n.get("mtu"):
            block["mtu"] = n["mtu"]
        eths[n["name"]] = block
    return {"network": {"version": 2, "ethernets": eths}}


def to_yaml(obj, indent=0):
    """Tiny YAML emitter (avoids a PyYAML dependency)."""
    pad = "  " * indent
    lines = []
    for k, v in obj.items():
        if isinstance(v, dict):
            lines.append(f"{pad}{k}:")
            lines.append(to_yaml(v, indent + 1))
        elif isinstance(v, list):
            inline = ", ".join(json.dumps(x) for x in v)
            lines.append(f"{pad}{k}: [{inline}]")
        else:
            lines.append(f"{pad}{k}: {json.dumps(v)}")
    return "\n".join(l for l in lines if l)


def main():
    cfg = json.load(open(CONFIG))
    key, secret, zone = cfg["api_key"], cfg["api_secret"], cfg["zone"]
    networks = cfg["networks"]
    want_ids = {n["id"] for n in networks}

    instance_id = get_instance_id()
    log(f"instance-id {instance_id}, expecting {len(want_ids)} private network(s)")

    # 1. Resolve network-id -> MAC from the API (retry: attachments may lag boot).
    id_to_mac = {}
    for attempt in range(1, 31):
        inst = api_get_instance(key, secret, zone, instance_id)
        id_to_mac = {
            pn["id"]: pn["mac-address"].lower()
            for pn in inst.get("private-networks", [])
            if pn.get("mac-address")
        }
        if want_ids <= set(id_to_mac):
            break
        log(f"waiting for API to report all MACs ({len(id_to_mac)}/{len(want_ids)})... {attempt}")
        time.sleep(5)
    else:
        raise SystemExit("timed out waiting for private-network MACs from API")

    # 2. Wait for those NICs to actually appear in the guest.
    want_macs = {id_to_mac[n["id"]] for n in networks}
    for attempt in range(1, 31):
        present = set(guest_macs())
        if want_macs <= present:
            break
        log(f"waiting for NICs to enumerate ({len(want_macs & present)}/{len(want_macs)})... {attempt}")
        time.sleep(3)
    else:
        raise SystemExit("timed out waiting for private NICs to appear in guest")

    # 3. Render + apply netplan.
    plan = build_netplan(networks, id_to_mac)
    text = to_yaml(plan) + "\n"
    with open(NETPLAN_OUT, "w") as f:
        f.write(text)
    os.chmod(NETPLAN_OUT, 0o600)
    log(f"wrote {NETPLAN_OUT}:\n{text}")
    rc = os.system("netplan apply")
    log(f"netplan apply exit={rc >> 8}")


if __name__ == "__main__":
    main()
