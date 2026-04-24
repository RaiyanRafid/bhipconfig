# bhipconfig

`bhipconfig` is a no-extra-package Linux network control CLI with a menu-driven terminal UI.

## What it does

- Shows `Add IP` only when the selected interface has no managed IP
- Switches to `Change IP` and `Remove IP` when the interface already has one or more IPs
- Adds, removes, and changes IP addresses with `iproute2`
- Sets default gateways
- Sets DNS with `systemd-resolved` when available, otherwise `/etc/resolv.conf`
- Switches between interfaces and can enable/disable them
- Reconfigures or restarts an interface from the same menu
- Arms an automatic rollback timer before disruptive changes so SSH users do not get locked out

## Why this approach

The tool stays dependency-free:

- UI: Python standard library
- IP/Gateway/Link actions: `ip`
- DNS: `resolvectl` or `/etc/resolv.conf`
- Reconfigure: `networkctl` when present, with a link-bounce fallback

That keeps the command portable across many Linux servers without asking the user to memorize `ip addr`, `ip route`, or distro-specific config syntax.

## Usage

From this directory:

```bash
chmod +x /var/tools/bhipconfig
/var/tools/bhipconfig
```

If you want it globally:

```bash
sudo install -m 755 /var/tools/bhipconfig /usr/local/bin/bhipconfig
```

Then run:

```bash
bhipconfig
```

## Packaging

This repository keeps only source files in Git. Generated build outputs such as
`dist/` and `publish/` are created locally when you run the packaging scripts and
are intentionally ignored.

There is no single native package format that both `apt` and `yum`/`dnf` install directly.
To support Ubuntu and AlmaLinux cleanly, this repo now includes both package targets:

- Debian/Ubuntu package: `scripts/build-deb.sh`
- RPM package for AlmaLinux/RHEL: `scripts/build-rpm.sh`
- Combined helper: `scripts/build-packages.sh`

Local install examples:

```bash
./scripts/build-deb.sh
sudo apt install ./dist/bhipconfig_$(cat VERSION)_all.deb
```

```bash
./scripts/build-rpm.sh
sudo dnf install ./dist/rpmbuild/RPMS/noarch/bhipconfig-$(cat VERSION)-1.noarch.rpm
```

If you want users to run `apt install bhipconfig` or `dnf install bhipconfig` by package name,
you must host a repository and publish metadata:

- APT metadata helper: `scripts/build-apt-repo.sh`
- YUM/DNF metadata helper: `scripts/build-rpm-repo.sh`
- Client repo templates: `packaging/repos/bhipconfig.list.example`, `packaging/repos/bhipconfig.sources.example`, and `packaging/repos/bhipconfig.repo.example`

Ubuntu production flow:

```bash
export APT_GPG_KEY_ID="YOUR_GPG_KEY_ID"
SIGN_APT_REPO=1 ./scripts/build-apt-repo.sh
```

This produces:

- signed `Release`, `InRelease`, and `Release.gpg`
- exported public key files under `dist/repo/apt/keyrings/`
- `amd64` and `arm64` package indexes for Ubuntu clients

Client setup on Ubuntu can then use:

```bash
./scripts/install-ubuntu-repo.sh https://your-domain.example/apt
```

The RPM helper expects `createrepo_c` on the build host.

## Safety model

- `Add IP` is a wizard for no-IP interfaces; if you also set a gateway, it is rollback-protected
- `Change IP` is a replace wizard: add the new IP, optionally update gateway/DNS, then remove the old IP
- `Remove IP` first offers a replacement path; without replacement it shows a warning and requires typing `REMOVE`
- Riskier actions like `Change IP`, `Remove IP`, `Set Gateway`, `Disable Interface`, and `Restart Network` create a snapshot first
- After the change, you must confirm it within the timer window
- If you do not confirm, or your SSH session drops, the background rollback helper restores the previous state

## Notes

- The current implementation focuses on live network state rather than distro-specific persistent config files
- On systems that regenerate `/etc/resolv.conf`, DNS fallback changes may later be overwritten by the host resolver manager
