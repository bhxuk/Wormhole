# Changelog

All notable changes to Wormhole are listed here. Newest first.
Versions follow [Semantic Versioning](https://semver.org/). Every push to `main`
rebuilds the Docker image and the website automatically.

## [1.0.0] - 2026-11-05

### Added
- Windows 11 runs in a Docker container using QEMU/KVM with UEFI and a software TPM 2.0.
- Fully unattended install from your own official Microsoft ISO - no clicks inside Windows setup.
- Browser access to the desktop (noVNC) on an easy-to-remember port such as 8006 or 8080.
- RDP access (TCP and UDP) on a port of your choice such as 3389 or 3390, with a ready-made `.rdp` file.
- Interactive one-command installer:
  - finds ISO files containing `windows11` / `win11` automatically and asks you to confirm;
  - copies, moves or leaves the ISO in place - your choice;
  - suggests free, easy port numbers and lets you pick;
  - asks for CPU, RAM, disk, edition, computer name, username, password, keyboard and time zone;
  - shows a full summary and the files it created before starting anything.
- Persistent Windows disk: container restarts, Docker restarts and server reboots never reset Windows.
- Clean shutdown: `docker stop` asks Windows to shut down properly before the container exits.
- Install is detected automatically; after that the ISO is no longer attached.
- `wormhole` command: `info`, `status`, `start`, `stop`, `restart`, `logs`, `update`, `edit`, `uninstall`.
- Public website with docs and this changelog, deployed automatically to GitHub Pages.
- Docker image published automatically to `ghcr.io/bhxuk/wormhole`.
