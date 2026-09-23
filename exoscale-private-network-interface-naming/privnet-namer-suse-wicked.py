#!/usr/bin/env python3
"""
privnet-namer (managed-network / offline variant, SUSE + wicked).

Same idea as the other managed variants: a managed private network hands out a
DHCP lease from its own subnet, so the subnet of the lease identifies the
network -- no API call, no key, no metadata, no internet. Works on instances
created with --public-ip none.

When to use this instead of privnet-namer-suse-managed.py
---------------------------------------------------------
The stock openSUSE Leap 16 image runs NetworkManager; use the NM variant there.
This one is for images that still run wicked -- SLES 15, and custom/golden
images built on Leap that keep wicked. Check with:

    systemctl is-active NetworkManager wicked

wicked differs from NetworkManager in the one way that matters here: it does
not configure a NIC nobody asked it to. Without an `ifcfg-<iface>` file the
private NICs simply stay `device-unconfigured` -- link down, no lease, and
therefore no way to tell which network they belong to. So this script always
brings DHCP up itself first, and only then does the subnet -> MAC -> name
mapping.

What it writes
--------------
  /etc/udev/rules.d/99-privnet-namer.rules  renames the device by MAC at boot
  /etc/systemd/network/10-<name>.link       same thing the systemd way
  /etc/sysconfig/network/ifcfg-<name>       wicked config for the renamed device

Both naming files are written on purpose. The SLES image boots with
`net.ifnames=0`, and that switch makes udev ignore the `Name=` in a .link file
entirely -- the NICs come back as eth1, eth2, ... on the next boot. The classic
SUSE udev rule with `NAME=` still applies, so that is what actually carries the
naming across reboots here; the .link file is kept for images that do not
disable ifnames.

Two rule files already in the image pin a MAC to its kernel name: SUSE's
70-persistent-net.rules, and 85-persistent-net-cloud-init.rules, which
cloud-init writes for the NIC it configured. The last NAME= wins, so ours is a
99- file *and* any line in another file that claims one of our MACs is removed
(the original is kept in /var/log/privnet-namer/). Without that, the first NIC
keeps the name eth0 while the others rename fine -- which is exactly what it
looked like before this was understood.

The temporary ifcfg files under the kernel names (ifcfg-eth1, ...) are left in
place as a fallback. If a rename ever fails, the NIC still gets its DHCP lease
under the old name and the instance stays reachable, which matters when it has
no public IP and the only other way in is the emergency console.

Runs on the image's own python3 (3.6 and newer), needs no extra packages.
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
UDEV_DIR = "/etc/udev/rules.d"
UDEV_RULES = os.path.join(UDEV_DIR, "99-privnet-namer.rules")
IFCFG_DIR = "/etc/sysconfig/network"
BACKUP_DIR = "/var/log/privnet-namer"


def log(msg):
    print("[privnet-namer] " + msg, flush=True)


def run(cmd):
    log("+ " + " ".join(cmd))
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       universal_newlines=True)
    if p.returncode != 0:
        log("  -> rc=%d: %s" % (p.returncode, (p.stdout or "").strip()))
    return p


def service_active(name):
    p = subprocess.run(["systemctl", "is-active", name],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                       universal_newlines=True)
    return (p.stdout or "").strip() == "active"


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


def has_real_address(info):
    """A 169.254.x.x address means DHCP got no answer, so it does not count."""
    return any(not ip.startswith("169.254.") for ip in info["ips"])


def write_ifcfg(ifname, mtu=None, comment=""):
    path = os.path.join(IFCFG_DIR, "ifcfg-" + ifname)
    with open(path, "w") as f:
        if comment:
            f.write("# %s\n" % comment)
        f.write("BOOTPROTO='dhcp4'\n")
        f.write("STARTMODE='auto'\n")
        if mtu:
            f.write("MTU='%s'\n" % mtu)
    os.chmod(path, 0o600)
    return path


def strip_conflicting_rules(macs):
    """Remove NAME= lines other rule files hold for the MACs we rename."""
    for fname in sorted(os.listdir(UDEV_DIR)):
        if not fname.endswith(".rules") or fname == os.path.basename(UDEV_RULES):
            continue
        path = os.path.join(UDEV_DIR, fname)
        try:
            with open(path) as f:
                lines = f.readlines()
        except OSError:
            continue
        kept = [l for l in lines
                if not any(mac in l.lower() for mac in macs)]
        if len(kept) == len(lines):
            continue
        os.makedirs(BACKUP_DIR, exist_ok=True)
        with open(os.path.join(BACKUP_DIR, fname), "w") as f:
            f.write("".join(lines))
        with open(path, "w") as f:
            f.write("".join(kept))
        log("removed %d conflicting line(s) from %s (original kept in %s)"
            % (len(lines) - len(kept), path, BACKUP_DIR))


def bootstrap_dhcp(started):
    """Give every unaddressed NIC a temporary DHCP config and bring it up.

    wicked leaves a NIC alone until an ifcfg file exists for it, so on a
    private-only instance nothing but the first NIC ever gets a lease. Without
    a lease the NIC cannot be matched to its network, so this runs before the
    mapping -- and again on later rounds, because the private NICs are attached
    while the instance is still booting and do not all exist yet.
    """
    for ifname, info in sorted(scan().items()):
        if has_real_address(info) or ifname in started:
            continue
        started.add(ifname)
        log("no address on %s yet -- starting DHCP on it" % ifname)
        write_ifcfg(ifname, comment="written by privnet-namer, kept as a "
                                    "fallback in case the rename fails")
        run(["ip", "link", "set", "dev", ifname, "up"])
        run(["wicked", "ifup", ifname])


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
        bootstrap_dhcp(bootstrapped)
        log("waiting for DHCP on all subnets (%d/%d)... %d"
            % (len(found), len(networks), attempt))
        time.sleep(3)
    raise SystemExit("timed out: not every configured subnet got a lease")


def apply(found):
    os.makedirs(LINK_DIR, exist_ok=True)

    # 1. persistent naming for future boots. The udev rule is the one that does
    #    the work on an image booted with net.ifnames=0 (SLES does); the .link
    #    file covers images where ifnames is left enabled.
    rules = ["# written by privnet-namer -- renames each private NIC by MAC\n"]
    for name, (ifname, mac, n, ip) in sorted(found.items()):
        rules.append('SUBSYSTEM=="net", ACTION=="add", ATTR{type}=="1", '
                     'ATTR{address}=="%s", NAME="%s"\n' % (mac, name))
        with open("%s/10-%s.link" % (LINK_DIR, name), "w") as f:
            f.write("[Match]\nMACAddress=%s\n\n[Link]\nName=%s\n" % (mac, name))
    with open(UDEV_RULES, "w") as f:
        f.write("".join(rules))
    log("wrote %s" % UDEV_RULES)
    strip_conflicting_rules(set(mac for (_, mac, _, _) in found.values()))
    run(["udevadm", "control", "--reload"])

    # 2. current boot: rename the live device and hand it a wicked config
    #    under its new name.
    for name, (ifname, mac, n, ip) in sorted(found.items()):
        log("subnet %s -> %s (mac %s, lease %s)" % (n["subnet"], name, mac, ip))
        run(["wicked", "ifdown", ifname])
        if ifname != name:
            run(["ip", "link", "set", "dev", ifname, "down"])
            run(["ip", "link", "set", "dev", ifname, "name", name])
        write_ifcfg(name, mtu=n.get("mtu"),
                    comment="private network %s, written by privnet-namer"
                            % n["subnet"])
        run(["ip", "link", "set", "dev", name, "up"])
        run(["wicked", "ifup", name])


def wait_for_addresses(found, tries=20):
    for _ in range(tries):
        if all(iface_ipv4(name) for name in found):
            return True
        time.sleep(3)
    return False


def main():
    if not service_active("wicked"):
        raise SystemExit(
            "wicked is not running -- this variant is for SUSE images that use "
            "wicked. On a NetworkManager image (the stock openSUSE Leap 16 "
            "template) use cloud-init-suse-managed.yaml instead.")

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
