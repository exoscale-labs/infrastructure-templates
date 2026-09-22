#!/usr/bin/env python3
"""
privnet-namer (managed-network / offline variant, openSUSE Leap 16 + NetworkManager).

For MANAGED private networks the guest gets a DHCP lease from each network's
subnet. That lease is enough to tell the networks apart -- no API call, no
metadata, no internet -- so this works on instances created with
--public-ip none.

Each configured subnet is pinned to a stable interface name by MAC:
  - write a systemd.link file so the name survives reboots (udev renames by
    MAC before NetworkManager starts)
  - rename the live device and give it a NetworkManager profile that keeps DHCP

Differences to the RHEL variant
-------------------------------
openSUSE Leap 16 dropped wicked and ships NetworkManager plus a regular
/usr/bin/python3 (3.13) -- there is no /usr/libexec/platform-python. The
mechanism is otherwise identical to RHEL: NetworkManager auto-creates a DHCP
profile ("Wired connection N") for every NIC nothing else claims, so the leases
are already there when this runs.

One extra step is needed though. cloud-init on SUSE renders its network config
as a NetworkManager keyfile that binds by **MAC address**, not by interface
name (`/etc/NetworkManager/system-connections/cloud-init-ethN.nmconnection`,
autoconnect-priority 120). On an instance created with --public-ip none, eth0
is a private network, so that profile follows the NIC through the rename and
would keep competing with ours. Any profile bound to a MAC or interface we take
over is therefore removed, and ours is written with a higher priority.

A NIC without a lease cannot be identified, so if some subnet is still missing
after the first few seconds the helper brings DHCP up itself (an image may have
NetworkManager's auto-default turned off) instead of waiting for something that
will never happen.

Requires NetworkManager. SLES 15 and older openSUSE releases that still run
wicked are not covered by this variant -- there the private NICs stay
`device-unconfigured` and nmcli does not exist.

No extra packages required (python3, nmcli and udevadm are in the cloud image);
it stays compatible with python 3.6 so the guard below can still report itself
on an older image.
Config: /etc/privnet-namer/config.json
"""
import ipaddress
import json
import os
import subprocess
import sys
import time

CONFIG = os.environ.get("PRIVNET_NAMER_CONFIG", "/etc/privnet-namer/config.json")
LINK_DIR = "/etc/systemd/network"
# cloud-init's own keyfiles use 120; stay above them.
PRIORITY = "200"


def log(msg):
    print("[privnet-namer] " + msg, flush=True)


def run(cmd, check_output=False):
    if not check_output:
        log("+ " + " ".join(cmd))
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       universal_newlines=True)
    if p.returncode != 0 and not check_output:
        log("  -> rc=%d: %s" % (p.returncode, (p.stdout or "").strip()))
    return p


def iface_ipv4(ifname):
    p = subprocess.run(["ip", "-o", "-4", "addr", "show", "dev", ifname],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                       universal_newlines=True)
    out = []
    for line in (p.stdout or "").splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[2] == "inet":
            out.append(parts[3].split("/")[0])
    return out


def scan():
    """Return {ifname: {"mac": mac, "ips": [..]}} for every non-loopback NIC."""
    res = {}
    for ifname in os.listdir("/sys/class/net"):
        if ifname == "lo":
            continue
        try:
            with open("/sys/class/net/%s/address" % ifname) as f:
                mac = f.read().strip().lower()
        except OSError:
            continue
        res[ifname] = {"mac": mac, "ips": iface_ipv4(ifname)}
    return res


def networkmanager_active():
    p = subprocess.run(["systemctl", "is-active", "NetworkManager"],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                       universal_newlines=True)
    return (p.stdout or "").strip() == "active"


def nm_connection_ids():
    p = subprocess.run(["nmcli", "-g", "NAME", "connection", "show"],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                       universal_newlines=True)
    return [l.strip() for l in (p.stdout or "").splitlines() if l.strip()]


def has_real_address(info):
    """True if the NIC holds an IPv4 address that came from somewhere real.

    A 169.254.x.x link-local address is what NetworkManager falls back to when
    DHCP got no answer, so it does not count as configured.
    """
    return any(not ip.startswith("169.254.") for ip in info["ips"])


def bootstrap_dhcp(started):
    """Start DHCP on every NIC that has no address yet.

    On a stock image NetworkManager already auto-creates a DHCP profile
    ("Wired connection N") for each unclaimed NIC, so there is nothing to do.
    An image that disables that (`no-auto-default`) would otherwise leave the
    private NICs down forever, and a NIC without a lease cannot be matched to
    its network. The temporary profiles are removed again when the interface is
    taken over.

    Called once per NIC (`started` remembers which), and re-called on later
    rounds because the private NICs do not all exist yet when cloud-init runs --
    they are attached while the instance is booting.
    """
    for ifname, info in sorted(scan().items()):
        if has_real_address(info) or ifname in started:
            continue
        started.add(ifname)
        log("no address on %s yet -- starting DHCP on it" % ifname)
        run(["ip", "link", "set", "dev", ifname, "up"])
        run(["nmcli", "device", "set", ifname, "managed", "yes"])
        con = "privnet-bootstrap-%s" % ifname
        if con in nm_connection_ids():
            run(["nmcli", "connection", "delete", con])
        run(["nmcli", "connection", "add", "type", "ethernet",
             "con-name", con, "ifname", ifname,
             "connection.autoconnect", "no",
             "ipv4.method", "auto", "ipv6.method", "disabled"])
        run(["nmcli", "connection", "up", con])


def match_networks(networks):
    """Map each configured subnet to the NIC that holds an IP inside it."""
    nets = [(ipaddress.ip_network(n["subnet"]), n) for n in networks]
    bootstrapped = set()
    for attempt in range(1, 41):
        found = {}
        for ifname, info in scan().items():
            for ip in info["ips"]:
                addr = ipaddress.ip_address(ip)
                for net, n in nets:
                    if addr in net:
                        found[n["name"]] = (ifname, info["mac"], n, ip)
        if len(found) == len(networks):
            return found
        # Give the image's own DHCP a few seconds, then take over -- and keep
        # doing it, since NICs keep appearing while the instance boots.
        if attempt >= 5:
            bootstrap_dhcp(bootstrapped)
        log("waiting for DHCP on all subnets (%d/%d)... %d"
            % (len(found), len(networks), attempt))
        time.sleep(3)
    raise SystemExit("timed out: not every configured subnet got a lease")


def nm_get(uuid, field):
    """Read one property of a NetworkManager connection (terse, unescaped)."""
    p = subprocess.run(["nmcli", "-g", field, "connection", "show", uuid],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                       universal_newlines=True)
    return (p.stdout or "").strip().replace("\\:", ":")


def drop_conflicting_profiles(macs, ifnames):
    """Delete every NM profile bound to one of our MACs or interfaces.

    That covers NetworkManager's auto-created "Wired connection N" (bound by
    interface name) and cloud-init's keyfile (bound by MAC), both of which
    would otherwise fight our own profile for the device.
    """
    p = subprocess.run(["nmcli", "-g", "UUID", "connection", "show"],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                       universal_newlines=True)
    for uuid in (p.stdout or "").split():
        mac = nm_get(uuid, "802-3-ethernet.mac-address").lower()
        ifname = nm_get(uuid, "connection.interface-name")
        device = nm_get(uuid, "GENERAL.DEVICES")
        if mac in macs or ifname in ifnames or device in ifnames:
            log("removing conflicting profile '%s' (mac=%s ifname=%s dev=%s)"
                % (nm_get(uuid, "connection.id"), mac or "-", ifname or "-",
                   device or "-"))
            run(["nmcli", "connection", "delete", uuid])


def apply(found):
    os.makedirs(LINK_DIR, exist_ok=True)

    # 1. persistent naming for future boots: udev renames by MAC before
    #    NetworkManager ever looks at the device.
    for name, (ifname, mac, n, ip) in found.items():
        with open("%s/10-%s.link" % (LINK_DIR, name), "w") as f:
            f.write("[Match]\nMACAddress=%s\n\n[Link]\nName=%s\n" % (mac, name))
    run(["udevadm", "control", "--reload"])

    macs = set(mac for (_, mac, _, _) in found.values())
    ifnames = set(ifname for (ifname, _, _, _) in found.values())
    ifnames |= set(found.keys())

    # 2. current boot: hand the devices over before renaming them, so
    #    NetworkManager does not re-activate a stale profile mid-flight.
    for name, (ifname, mac, n, ip) in found.items():
        run(["nmcli", "device", "disconnect", ifname])
        run(["nmcli", "device", "set", ifname, "managed", "no"])

    drop_conflicting_profiles(macs, ifnames)

    # 3. rename and give each device a profile of ours that keeps DHCP.
    for name, (ifname, mac, n, ip) in found.items():
        log("subnet %s -> %s (mac %s, lease %s)" % (n["subnet"], name, mac, ip))
        if ifname != name:
            run(["ip", "link", "set", "dev", ifname, "down"])
            run(["ip", "link", "set", "dev", ifname, "name", name])
        run(["ip", "link", "set", "dev", name, "up"])
        run(["nmcli", "device", "set", name, "managed", "yes"])
        cmd = ["nmcli", "connection", "add", "type", "ethernet",
               "con-name", name, "ifname", name,
               "802-3-ethernet.mac-address", mac,
               "connection.autoconnect", "yes",
               "connection.autoconnect-priority", PRIORITY,
               "ipv4.method", "auto", "ipv6.method", "disabled"]
        if n.get("mtu"):
            cmd += ["802-3-ethernet.mtu", str(n["mtu"])]
        run(cmd)
        run(["nmcli", "connection", "up", name])


def wait_for_addresses(found, tries=20):
    for _ in range(tries):
        if all(iface_ipv4(name) for name in found):
            return True
        time.sleep(3)
    return False


def main():
    if not networkmanager_active():
        raise SystemExit(
            "NetworkManager is not running -- this variant is for openSUSE "
            "Leap 16 and other NetworkManager images. On a wicked system "
            "(SLES 15) the private NICs stay device-unconfigured and nmcli "
            "does not exist; that setup needs a wicked-based variant.")
    cfg = json.load(open(CONFIG))
    networks = cfg["networks"]
    log("expecting %d managed private network(s)" % len(networks))
    found = match_networks(networks)
    apply(found)

    if wait_for_addresses(found):
        log("all interfaces named and addressed:")
    else:
        log("WARNING: not every interface regained its lease, state is:")
    for name in sorted(found):
        log("  %s -> %s" % (name, ", ".join(iface_ipv4(name)) or "no address"))

    log("done")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log("ERROR: %s" % e)
        sys.exit(1)
