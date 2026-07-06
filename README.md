# OpenWRT build environment — TP-Link TL-WR941ND v4

Podman-based, **rootless**, containerized OpenWRT buildroot for the TL-WR941ND **v4**
router (Atheros AR7240, `ar71xx` target, `tiny` subtarget).

**Nothing is installed on the host** — everything lives in this folder and in
Podman's own container storage.

> ⚠️ **Important — the build tree is NOT inside the repo.** The full OpenWRT
> source/build tree is ~9 GB and 300,000+ small files, so it deliberately lives
> **outside** the working copy, at `~/.local/share/openwrt-wr941nd/` by default.
> This matters especially when the repo clone sits under a **synced cloud-drive
> folder** — the drive then only syncs the small tracked files and the final
> binaries (`firmware/`, not in git), never the build tree. Relocate it with
> `OPENWRT_SRC_ROOT` (new flow) or `OPENWRT_SRC` (legacy flow).

## Goal (phases)

1. **(current)** Reproduce from source the firmware currently running on the router:
   `openwrt-18.06.9-ar71xx-tiny-tl-wr941nd-v4-squashfs-factory.bin`.
2. Remove packages/modules (the router only needs **AP mode**) — `make menuconfig`.
3. Flash upgrade to **16MB** (Winbond **W25Q128**) + 64MB RAM, and a newer OpenWRT
   (ath79, e.g. 24.10) with a custom partition/DTS layout.

## Prerequisites

- Rootless **Podman** on the host (`podman --version`).
- The scripts auto-detect when they run from the VS Code **Flatpak** terminal and
  use `flatpak-spawn --host podman` in that case. From a host terminal they use
  plain `podman`.
- Disk: ~10 GB for `src/`. First build: about 20–60 minutes (CPU-dependent).

## Usage

### One-command build (recommended)

`scripts/build.sh` builds **exactly what the CI builds**, driven by the same
per-device pin file (`ci/<device>.env`: `OPENWRT_TAG` + `SEED_FILE`). On a
fresh machine it bootstraps everything itself (blobless OpenWrt clone at the
pinned tag, container image, build):

```bash
git clone https://github.com/MrNoname3/openwrt-builds.git
cd openwrt-builds
JOBS=4 ./scripts/build.sh          # JOBS=4 is the safe setting on a 15GB host
```

Knobs (all optional, no TTY needed — automation/AI friendly):

| Variable | Meaning |
|----------|---------|
| `DEVICE=<name>` | which `ci/*.env` pin to build when several exist (menu on a TTY, listed error otherwise) |
| `TAG=vX.Y.Z` | override the pinned OpenWrt tag |
| `JOBS=N` | parallel jobs (default `nproc`) |
| `OPENWRT_SRC_ROOT=dir` | where source trees live (default `~/.local/share/openwrt-wr941nd`) |
| `DRY_RUN=1` | print the resolved plan (pin/tag/seed/tree), change nothing |

Output lands in `firmware/built/16m-<version>/` (factory + sysupgrade +
SHA256SUMS; the FULLFLASH image is assembled only where a router backup
exists, since the u-boot/art dumps are device-unique and not in git).

### Legacy 18.06 flow (phase 1–2, ar71xx)

```bash
cd <repo clone>

# 1) Build the container image (once, or when the Containerfile changes)
./scripts/img-build.sh

# 2) Build the firmware (source clone + feeds + defconfig + build)
./scripts/fw-build.sh
#   JOBS=4 ./scripts/fw-build.sh          # fewer parallel jobs
#   OPENWRT_TAG=v19.07.10 ./scripts/fw-build.sh   # different tag (phase 3)

# labeled output folder (does not overwrite previous builds)
BUILD_LABEL=ap-only ./scripts/fw-build.sh

# 3) Interactive shell in the container (e.g. removing packages in phase 2)
./scripts/shell.sh
#   then: cd openwrt && make menuconfig
```

### Output
The build **automatically copies** the fresh images from the source tree into a
labeled, non-overwriting subfolder:
```
firmware/built/<label>/
  openwrt-ar71xx-tiny-tl-wr941nd-v4-squashfs-factory.bin
  openwrt-ar71xx-tiny-tl-wr941nd-v4-squashfs-sysupgrade.bin
  openwrt-ar71xx-tiny-device-tl-wr941nd-v4.manifest
```
- `<label>` defaults to `<version>-<timestamp>` (e.g. `18.06.9-20260601-224500`), or
  set it yourself: `BUILD_LABEL=ap-only ./scripts/fw-build.sh`. This way **every build
  is kept**; a later one never overwrites an earlier one.
- **factory.bin** is for the first install from the stock TP-Link web UI.
- **sysupgrade.bin** is for updating a device already running OpenWRT (LuCI / `sysupgrade`).
- The stock-equivalent 18.06.9 build lives at `firmware/built/18.06.9-stock-equivalent/`.

### Build variants and the kernel lesson

You can build a different image from another seed config via the `SEED_FILE` variable:
```bash
SEED_FILE=wr941nd-v4-18.06-ap.seed.config BUILD_LABEL=ap ./scripts/fw-build.sh
```

> ⚠️ **Kernel lesson.** If a seed adds/removes a package that touches a **kernel
> module** (`kmod-*`) (e.g. removing `iptables`/`firewall` → netfilter kmods drop
> out), the kernel VERMAGIC changes. In an already-built tree the kernel package
> then desyncs from opkg and `package/install` fails: *"Cannot satisfy …
> kernel (= <hash>)"*. In that case add `CLEAN=kernel` (clean rebuild of kernel +
> kmods) or `CLEAN=all` (full clean, toolchain kept):
> ```bash
> CLEAN=kernel SEED_FILE=some.seed.config ./scripts/fw-build.sh
> ```
> This is why the **pragmatic AP** seed deliberately does NOT touch any kmod — it
> only removes userspace daemons (dnsmasq, odhcpd) — so the kernel stays unchanged
> and the build is stable.

## Layout

| File | Role |
|------|------|
| [Containerfile](Containerfile) | Debian bullseye + OpenWRT 18.06 build deps, `builder` user |
| [config/wr941nd-v4-18.06.seed.config](config/wr941nd-v4-18.06.seed.config) | Seed `.config` — **stock-equivalent** (LuCI + xt_CT); completed by `make defconfig` |
| [config/wr941nd-v4-18.06-ap.seed.config](config/wr941nd-v4-18.06-ap.seed.config) | Seed `.config` — **pragmatic AP** (stock minus dnsmasq/odhcpd; kernel unchanged) |
| [scripts/img-build.sh](scripts/img-build.sh) | Container image build |
| [scripts/fw-build.sh](scripts/fw-build.sh) | Full, idempotent firmware build in the container |
| [scripts/shell.sh](scripts/shell.sh) | Interactive shell (menuconfig, debugging) |
| [scripts/clean.sh](scripts/clean.sh) | Full cleanup of the (outside-the-drive) build tree, with confirmation; `--image` also removes the container image |
| [scripts/router-backup.sh](scripts/router-backup.sh) | Backup of the running router's flash partitions over SSH (with 3× verification); `firmware/router-backup/<ts>/` |
| [scripts/_inner-build.sh](scripts/_inner-build.sh) | Build logic running inside the container |
| [scripts/_common.sh](scripts/_common.sh) | Podman detection (host or flatpak) |
| `firmware/` | Binary collection (not version-controlled): `stock/` = factory/reference dumps, `built/<label>/` = our built images, one folder per build |

## Notes

- **"The same FW"** here means *functionally identical*: same version (18.06.9),
  target (`ar71xx`), subtarget (`tiny`), profile (`tl-wr941nd-v4`) and the default
  package set. **Bit-exact** equality would also require pinning the toolchain and
  timestamps (reproducible build), which is not a goal in this phase.
- The buildroot **does not build as root** — hence `--userns=keep-id` + the non-root
  `builder` user. Files written into `src/` are created on the host with your uid
  (`attila`).
- `src/openwrt/dl/`, `build_dir/` and `staging_dir/` stay in `src/`, so rebuilds are
  fast (downloaded sources and the compiled toolchain are reused).

## Router backup (SSH, without reading the chip)

`scripts/router-backup.sh` backs up the `mtd` partitions from the running device
(reading is non-destructive), running 3× and comparing sha256; if they match, one
set is kept.
```bash
./scripts/router-backup.sh                 # tplink-router, firmware/router-backup/<ts>/
./scripts/router-backup.sh my-host /path    # different host/destination
RUNS=5 ./scripts/router-backup.sh           # more verification passes
```
For old dropbear it automatically allows SHA-1 if `~/.ssh/openssl-allow-sha1.cnf`
exists (see the [`ssh-legacy`](#) wrapper). The current device, mapped out:

- **Flash chip:** Winbond **W25Q32** (4 MB) → target is **W25Q128** (16 MB), same family.
- **Partitions (4 MB):** `u-boot` @0x000000 (128K) · `firmware`=kernel+rootfs @0x020000 (≈3.99 MB)
  · `art` @0x3F0000 (64K). `firmware` overlaps the `kernel`+`rootfs` views.
- The **`art`** (calibration) partition is **device-unique** — on the 16MB chip it goes
  at the end (0xFF0000).

## Phase 3 — 16MB flash (W25Q128) — outline

> 📖 The mod has since been **done and documented**: see
> [docs/hardware-mod.md](docs/hardware-mod.md) for the full flash + RAM
> upgrade guide (layout, procedure, pitfalls). The outline below is kept as
> the original plan.

- The current chip is replaced with a **Winbond W25Q128** (16MB). The flash must be
  read out (flashrom + CH341A or Raspberry Pi + SOIC clip), and the `u-boot` (0x0)
  and **ART/calibration** partitions must be **preserved** (the WiFi radio
  calibration is device-unique!).
- In current OpenWRT the WR941ND moved to the **`ath79`** target. For the 16MB flash
  the partition layout must be rewritten in the device's **DTS** (device tree):
  extend the firmware/rootfs partition's upper bound to 16MB, move ART to the end of
  the flash.
- With 16MB flash + 64MB RAM the "4MB/32MB not enough" warning goes away, so a
  **current** OpenWRT (e.g. 24.10) can run. In this environment that only takes
  changing `OPENWRT_TAG` and dropping the DTS patch into the source tree.

## CI — automated builds with GitHub Actions

This repo's CI runs **the same build** in the
cloud as the local `scripts/build-16m.sh`: same `Containerfile.modern` container,
same `_inner-build-16m.sh`, same seed. So the local podman build and the CI build
outputs are directly comparable (supply-chain cross-check).

> ⚠️ **Hardware requirement.** The released 25.12 images need **BOTH** mods:
> **16MB flash** (W25Q128-class) **and the 32→64MB RAM upgrade**. On the stock
> 32MB RAM, OpenWrt 25.12 (kernel 6.12) constantly reboots with OOM — verified
> on this device before the RAM mod. Never flash a stock 4MB/32MB unit.

**Files:**

- `ci/wr941nd-v4-16m.env` — the device pins: `OPENWRT_TAG` (exact OpenWRT release),
  `SEED_FILE`, `DEVICE_NAME`.
- `.github/workflows/build.yml` — the build: runs on PRs and on `master` pushes
  when a build-relevant file changes (`ci/`, `config/`, `scripts/`,
  `Containerfile.modern`). After a successful build on `master` it publishes a
  **Release** (`<tag>-wr941nd-v4-16m`, containing factory + sysupgrade + manifest +
  SHA256SUMS). The **FULLFLASH image is deliberately NOT** built in CI: it needs
  the device-unique u-boot/art dumps (with the MAC), which live only in the local
  backup.
- `.github/workflows/check-openwrt-release.yml` — checks the OpenWRT tags weekly
  (Monday 06:17 UTC):
  - **new release within the same series** (e.g. v25.12.4 → v25.12.5): opens a PR
    with the bump and dispatches a build on it → the PR itself is the canary; the
    Release comes after the merge;
  - **new series** (e.g. v26.x): only opens an **issue** — a series jump needs a
    manual DTS/seed review first (see the 24.10 → 25.12 nvmem-layout breakage).

**Update flow:** bump PR arrives → Actions tab: is the branch build green? →
merge → Release → download the sysupgrade image, verify SHA256 →
`sysupgrade` on the router (keeping settings).

**One-time repo setting:** Settings → Actions → General → enable
"Allow GitHub Actions to create and approve pull requests"
(without it, creating the bump PR fails).

**Limits:** a private repo has 2000 free Actions minutes per month; a full build is
~2–3 hours (≈120–180 minutes), so a few builds a month fit comfortably. `dl/` is
cached; the toolchain is rebuilt on every run.

### Reproducibility (supply-chain cross-check)

Verified 2026-07-06 on v25.12.4: a clean local build and the CI build are
**byte-identical** — kernel and every rootfs file — except a known-benign
6-byte residue of build timestamps in two packages that ignore
`SOURCE_DATE_EPOCH` (`usr/bin/apk`: gzip MTIME of the embedded help blob;
`libnftables.so`: two raw timestamps), plus their cascade into the apk db
checksums and `scripts.tar.gz`. Two determinism fixes were needed to get there:

- `CONFIG_KERNEL_BUILD_USER/DOMAIN` pinned in the seed (otherwise the kernel
  banner embeds the random container hostname);
- the CI installs the **project apk signing keypair** from the
  `APK_PRIVATE_KEY` / `APK_PUBLIC_KEY` Actions secrets (same
  `private-key.pem` / `public-key.pem` as in the local tree root); without it
  every tree generates its own key into `/etc/apk/keys/`.

Compare any two same-tag images with:
```bash
scripts/repro-compare.sh local-sysupgrade.bin ci-sysupgrade.bin
```
It PASSes only if the images match modulo the exact whitelisted residue —
any other difference is a supply-chain red flag.

## Operations / troubleshooting (deployed AP)

### Spontaneous reboot due to serial console + SysRq (IMPORTANT)

Symptom: the AP **reboots on its own** (`dmesg`/`logread` only shows
`Watchdog has previously reset the system`, **no** OOM/panic/crash). The reboot is
typically tied to the serial adapter — either on **plug/unplug**, or when the
soldered-on serial **pin header is left empty, unconnected, on the board**.

Cause: the kernel runs with `console=ttyS0,115200`, and **SysRq is enabled by
default** (`/proc/sys/kernel/sysrq = 1`). A **floating/noisy serial line** (empty
header, or hot-unplug) can generate a **BREAK signal**, which the kernel interprets
as a **SysRq command** (reboot/crash/hang). The `wmac`/AR7240 watchdog (timeout
**30 s**, fed every 5 s) then resets after ~25–30 s if the system got stuck.

Fix (applied on the deployed device, persistent in `/etc/sysctl.conf`):
```sh
# runtime + persistent
echo 0 > /proc/sys/kernel/sysrq
echo 'kernel.sysrq=0' >> /etc/sysctl.conf
```
On a headless AP this has **no downside** (SysRq is a debug-only feature; serial
console **output** still works). If SysRq debugging is ever needed, re-enable
temporarily: `echo 1 > /proc/sys/kernel/sysrq`.

Also: plug/unplug the serial adapter **only with the board powered off**, or if it
must happen live, **connect GND first and disconnect it last**, and don't touch the
3.3 V/TX wires (a transient on the shared rail can also cause a watchdog reset).

### RAM (32 MB) — tight but sufficient

With 24.10 + LuCI + 802.11r there is ~7 MB free RAM. No OOM, but little headroom; if
more is needed, the **AP-only package strip** (removing LuCI/uhttpd/ppp) frees up a
few MB.

## License

**GPL-2.0** (see [LICENSE](LICENSE)) — the custom DTS and device definition under
`config/` are derived from OpenWrt's GPL-2.0 sources, and the rest of the repo
follows the same license for simplicity.
