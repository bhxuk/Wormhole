#!/usr/bin/env python3
"""Wormhole helper - created by bhxuk.com

Small utilities used by entrypoint.sh:
  helper.py unattend <template> <output>   render autounattend.xml from env vars
  helper.py monitor <command...>           send a command to the QEMU monitor
  helper.py status-loop                    keep web/status.json up to date
  helper.py health                         container health check
"""
import json
import os
import re
import socket
import sys
import time
from xml.sax.saxutils import escape

APP = "/opt/wormhole"
RUN = "/run/wormhole"
STORAGE = "/storage"
MONITOR_SOCK = os.path.join(RUN, "monitor.sock")
STATUS_FILE = os.path.join(APP, "web", "status.json")
INSTALLED_MARKER = os.path.join(STORAGE, "wormhole.installed")

# Generic installation keys published by Microsoft. They only select the
# edition during setup - they do NOT activate Windows.
GENERIC_KEYS = {
    "home": "YTMG3-N6DKC-DKB77-7M9GH-8HVX7",
    "pro": "VK7JG-NPHTM-C97JM-9MPGT-3V66T",
    "education": "YNMGQ-8RYV3-4PGQ3-C8XTP-7CFBY",
    "pro-workstation": "DXG7C-N36C4-C4HTG-X4T3X-2YV77",
}


def env(name, default=""):
    value = os.environ.get(name, "").strip()
    return value if value else default


def computer_name():
    name = re.sub(r"[^A-Za-z0-9-]", "", env("COMPUTER_NAME", "WORMHOLE"))[:15]
    return name.upper() or "WORMHOLE"


def render_unattend(template_path, output_path):
    edition = env("EDITION", "Pro").lower().replace(" ", "-")
    key = env("PRODUCT_KEY") or GENERIC_KEYS.get(edition, GENERIC_KEYS["pro"])
    values = {
        "LANGUAGE": env("LANGUAGE", "en-US"),
        "REGION": env("REGION", "en-US"),
        "KEYBOARD": env("KEYBOARD", "en-US"),
        "TIMEZONE": env("TIMEZONE", "UTC"),
        "COMPUTER_NAME": computer_name(),
        "USERNAME": env("USERNAME", "wormhole")[:20],
        "PASSWORD": env("PASSWORD", "wormhole"),
        "PRODUCT_KEY": key,
    }
    with open(template_path, encoding="utf-8") as fh:
        xml = fh.read()
    for name, value in values.items():
        xml = xml.replace("{{%s}}" % name, escape(value, {'"': "&quot;", "'": "&apos;"}))
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as fh:
        fh.write(xml)


def monitor(command):
    """Send one HMP command to the QEMU monitor and return its reply."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect(MONITOR_SOCK)
    try:
        time.sleep(0.2)
        sock.recv(4096)  # greeting + prompt
        sock.sendall((command + "\n").encode())
        time.sleep(0.3)
        try:
            return sock.recv(65536).decode(errors="ignore")
        except socket.timeout:
            return ""
    finally:
        sock.close()


def rdp_ready(host="127.0.0.1", port=3389):
    """True when something inside the VM answers an RDP negotiation request."""
    request = bytes.fromhex("030000130ee000000000000100080003000000")
    try:
        with socket.create_connection((host, port), timeout=3) as sock:
            sock.settimeout(5)
            sock.sendall(request)
            reply = sock.recv(64)
            return len(reply) >= 4 and reply[0] == 0x03
    except OSError:
        return False


def write_status(state, message):
    data = {
        "state": state,
        "message": message,
        "computer": computer_name(),
        "username": env("USERNAME", "wormhole"),
        "version": open(os.path.join(APP, "VERSION")).read().strip()
        if os.path.exists(os.path.join(APP, "VERSION")) else "dev",
        "updated": int(time.time()),
    }
    tmp = STATUS_FILE + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh)
    os.replace(tmp, STATUS_FILE)


def status_loop():
    was_ready = False
    while True:
        ready = rdp_ready()
        if ready:
            if not os.path.exists(INSTALLED_MARKER):
                with open(INSTALLED_MARKER, "w") as fh:
                    fh.write(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()) + "\n")
                print("[wormhole] Windows is installed - the ISO will not be attached on future starts.", flush=True)
            if not was_ready:
                print("[wormhole] Windows is ready. Connect with RDP or the web viewer.", flush=True)
            write_status("ready", "Windows is running. Connect with RDP or open the desktop below.")
        elif os.path.exists(INSTALLED_MARKER):
            write_status("starting", "Windows is starting up...")
        else:
            write_status("installing", "Windows is installing. This takes 10-30 minutes - watch it below.")
        was_ready = ready
        time.sleep(10)


def health():
    try:
        socket.create_connection(("127.0.0.1", 8006), timeout=5).close()
    except OSError:
        sys.exit(1)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == "unattend" and len(argv) == 4:
        render_unattend(argv[2], argv[3])
    elif cmd == "monitor" and len(argv) >= 3:
        print(monitor(" ".join(argv[2:])), end="")
    elif cmd == "status":
        write_status(argv[2], argv[3] if len(argv) > 3 else "")
    elif cmd == "status-loop":
        status_loop()
    elif cmd == "health":
        health()
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
