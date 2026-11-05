<h1 align="center">Wormhole</h1>
<p align="center"><b>Windows 11 in Docker - with RDP and browser access.</b><br>
One command on a Linux server. Created by <a href="https://bhxuk.com">bhxuk.com</a>.</p>

<p align="center">
  <a href="https://bhxuk.github.io/Wormhole/">Website</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="https://github.com/bhxuk/Wormhole/issues">Issues</a>
</p>

---

## Features

- **One command install** - an interactive installer asks a few questions and does the rest.
- **Unattended Windows setup** - no clicking through Windows setup, no Microsoft account.
- **Browser access** - open `http://<server-ip>:8006` and use Windows from any browser.
- **RDP** - connect with Remote Desktop on `<server-ip>:3389` (or the port you choose).
- **Persistent** - Windows lives on a disk file on your server. Restarts and reboots never reset it.
- **Clean shutdown** - `docker stop` shuts Windows down properly.
- **Bring your own ISO** - uses the official Windows 11 ISO from Microsoft.

## Requirements

| | |
|---|---|
| Server | Linux, x86_64, with hardware virtualisation (KVM / `/dev/kvm`) |
| CPU / RAM | 2+ cores and 4+ GB RAM for Windows (more is better) |
| Disk | 40+ GB free (64 GB recommended) |
| Software | Docker - the installer can install it for you |
| Windows | An official Windows 11 ISO and a valid licence |

Cloud VPS? It must support **nested virtualisation**. Bare-metal servers and most home servers work.

## Install

### 1. Download the Windows 11 ISO

Get it from Microsoft: **https://www.microsoft.com/en-gb/software-download/windows11**
→ *Download Windows 11 Disk Image (ISO) for x64 devices*.

Put it anywhere on the server (for example `/root` or `/opt`). The installer looks for any file
whose name contains `windows11` or `win11`, e.g. `Windows11_Client_x64_en-us_26300_9457.iso`.

### 2. Run the installer

```bash
curl -fsSL https://raw.githubusercontent.com/bhxuk/Wormhole/main/install.sh | sudo bash
```

The installer will:

1. Check the server (KVM, Docker, CPU, RAM).
2. Find your Windows 11 ISO and ask you to confirm it.
3. Ask where to install (default `/opt/wormhole`) and whether to copy, move or leave the ISO.
4. Ask for CPU cores, RAM, disk size and Windows edition.
5. Suggest free, easy ports for the web viewer (8006, 8080, 8000...) and RDP (3389, 3390, 3399...).
6. Ask for the computer (RDP) name, username and password.
7. Show a summary - you confirm.
8. Create the files and show them - you confirm.
9. Start Windows and print the browser URL, RDP address, RDP name and login.

Windows then installs by itself in 10-30 minutes. Watch it in the browser.

## Connect

| | |
|---|---|
| Browser | `http://<server-ip>:<web-port>` |
| RDP | `<server-ip>:<rdp-port>` - username and password from the installer |
| RDP file | `/opt/wormhole/<NAME>.rdp` - copy it to your PC and double-click |

Forgot the details? Run `wormhole info`.

## Manage

```text
wormhole info        connection details (browser URL, RDP, login)
wormhole status      installing / ready / stopped
wormhole start       start Windows
wormhole stop        shut Windows down cleanly
wormhole restart     restart Windows (keeps everything)
wormhole logs        follow the container log
wormhole update      update Wormhole - your Windows disk is kept
wormhole edit        change ports / CPU / RAM
wormhole uninstall   remove (asks before deleting Windows)
```

## Docker Compose (manual)

Prefer to do it yourself? Use [`docker-compose.yml`](docker-compose.yml):

```yaml
services:
  windows:
    image: ghcr.io/bhxuk/wormhole:latest
    container_name: wormhole
    devices:
      - /dev/kvm
    environment:
      RAM_SIZE: "8G"
      CPU_CORES: "4"
      DISK_SIZE: "64G"
      USERNAME: "wormhole"
      PASSWORD: "change-me"
    ports:
      - "8006:8006"
      - "3389:3389/tcp"
      - "3389:3389/udp"
    volumes:
      - ./storage:/storage
      - ./iso:/iso:ro
    restart: unless-stopped
    stop_grace_period: 2m
```

### Settings

| Variable | Default | Meaning |
|---|---|---|
| `RAM_SIZE` | `8G` | Memory for Windows |
| `CPU_CORES` | `4` | CPU cores for Windows |
| `DISK_SIZE` | `64G` | Virtual disk size (grows as used; can be increased later) |
| `USERNAME` / `PASSWORD` | `wormhole` / `wormhole` | Windows login (first install only) |
| `COMPUTER_NAME` | `WORMHOLE` | Windows computer name / RDP name |
| `EDITION` | `Pro` | `Pro`, `Home` or `Education` |
| `LANGUAGE` | `en-US` | Must match the ISO language |
| `REGION` / `KEYBOARD` | `en-US` | Locale and keyboard, e.g. `en-GB` |
| `TIMEZONE` | `UTC` | Windows time zone name, e.g. `GMT Standard Time` |
| `BOOT_ISO` | auto | Full path to the ISO inside the container |
| `EXTRA_ARGS` | | Extra QEMU arguments |

## How it works

Wormhole runs QEMU/KVM inside the container with UEFI firmware, a software TPM 2.0, an
unattended-setup answer file and NAT networking that forwards RDP. The screen is served to your
browser by noVNC. Everything that matters - the Windows disk, firmware settings and TPM state -
is stored in `./storage`, so the same Windows boots every time. Once Windows has installed, the
ISO is no longer attached.

## FAQ

**Does it activate Windows?** No. Setup uses Microsoft's generic installation key to pick the
edition. Activate with your own licence in *Settings → Activation*.

**Will a reboot wipe Windows?** No. Only deleting `storage/` does that.

**Can I change CPU/RAM later?** Yes - `wormhole edit`, then it restarts with the new values.

**The installer says `/dev/kvm` is missing.** Enable VT-x / AMD-V in the BIOS, or ask your
provider for nested virtualisation.

## Licence

MIT © [bhxuk.com](https://bhxuk.com). Windows is a trademark of Microsoft Corporation. Wormhole
does not include Windows - you supply your own ISO and licence.
