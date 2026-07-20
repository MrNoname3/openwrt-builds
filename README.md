# OpenWrt builds — TP-Link TL-WR941ND v4 (16 MB / 64 MB mod)

Custom OpenWrt firmware for a hardware-modded **TL-WR941ND v4** (Atheros
AR7240, `ath79`/`tiny`): **4→16 MB flash + 32→64 MB RAM**. Stock hardware died
with OpenWrt 18.06/19.07; the modded device runs the **current 25.12 series**
built from this repo, in production, as a dumb AP.

What lives here:

- a **containerized buildroot** (rootless podman, nothing installed on the host)
  that injects a custom 16 MB DTS/device profile into a stock OpenWrt tree;
- **GitHub Actions CI** that builds the exact same image, watches OpenWrt for
  new releases (auto-PR), and publishes flashable **Releases**;
- a **reproducibility cross-check** proving the local and CI images are
  byte-identical (modulo a documented 6-byte timestamp residue).

> ⚠️ **Hardware requirement.** The images need **BOTH** mods: 16 MB flash
> (W25Q128-class) **and** the 32→64 MB RAM upgrade. Stock 4 MB flash cannot
> hold them, and on stock 32 MB RAM kernel 6.12 OOM-reboots constantly
> (verified on this unit). **Never flash a stock device**, and never use
> official OpenWrt images on a modded one (the official
> `tplink,tl-wr941-v4` profile targets the 4 MB layout → brick).

## From a stock unit to where this repo is — the complete path

If you own this router and want to end up here, this is the whole journey:

1. **Gather parts & tools**: a 16 MB SOIC-8 SPI NOR chip (W25Q128 family), a
   64 MB ×16 DDR1 chip (same type AR7240 boards ship with in their 64 MB
   variants), soldering iron/hot air, a SPI programmer (CH341A — do the 3.3 V
   mod before writing!), a 3.3 V USB-UART for serial. Soldering SOIC-8 is
   easy; the DDR swap is the hard part.
2. **Back up the original flash** — twice if you can (SSH + chip read). The
   `u-boot` (contains your MAC) and `art` (your radio calibration) regions are
   irreplaceable. → [docs/hardware-mod.md](docs/hardware-mod.md), step 1.
3. **Do the hardware mod** (RAM swap + optionally recap; the flash chip gets
   written in step 5 and soldered then).
   → [docs/hardware-mod.md](docs/hardware-mod.md), step 5.
4. **Build the firmware**: `JOBS=4 ./scripts/build.sh` (below). With your
   backup in place it also assembles the **full-chip image** (your u-boot +
   new firmware + your art, at the right offsets).
5. **Write the new chip, first boot, configure.**
   → [docs/hardware-mod.md](docs/hardware-mod.md), steps 4 and 6.
6. **Updates from then on are software-only**: fork this repo for your own CI
   (see [Forking](#forking-this-repo-for-your-own-device)) or just build
   locally; new OpenWrt patch release → PR → Release → `sysupgrade` with
   settings kept. The programmer is never needed again.

## Building

`scripts/build.sh` builds **exactly what the CI builds**, driven by the same
per-device pin file (`ci/<device>.env`: `OPENWRT_TAG` + `SEED_FILE`). On a
fresh machine it bootstraps everything itself (blobless OpenWrt clone at the
pinned tag, container image, build):

```bash
git clone https://github.com/MrNoname3/openwrt-builds.git
cd openwrt-builds
JOBS=4 ./scripts/build.sh          # JOBS=4 is the safe setting on a 15 GB host
```

Knobs (all optional, no TTY needed — automation/AI friendly):

| Variable | Meaning |
|----------|---------|
| `DEVICE=<name>` | which `ci/*.env` pin to build when several exist |
| `TAG=vX.Y.Z` | override the pinned OpenWrt tag |
| `JOBS=N` | parallel jobs (default `nproc`) |
| `OPENWRT_SRC_ROOT=dir` | where source trees live (default `~/.local/share/openwrt-wr941nd`) |
| `DRY_RUN=1` | print the resolved plan (pin/tag/seed/tree), change nothing |

Requirements: rootless **podman** (the scripts auto-detect a VS Code Flatpak
terminal and go through `flatpak-spawn --host`), ~20 GB disk for the build
tree, a full clean build takes ~2–4 h at `JOBS=4`. The tree deliberately lives
**outside** the repo clone (`~/.local/share/openwrt-wr941nd/`) so a cloud-drive
synced clone never tries to sync 300k build files.

Output → `firmware/built/16m-<version>/`: factory + sysupgrade + SHA256SUMS,
plus the FULLFLASH full-chip image when a router backup exists locally (the
u-boot/art dumps are device-unique and not in git — see the
[hardware guide](docs/hardware-mod.md) for what each image is for).

## CI — automated builds and releases

The **source of truth is a self-hosted Gitea instance**, push-mirrored to
GitHub; GitHub Actions is the build + release executor (an OpenWrt build is
too heavy for the Gitea box — and an *independent* build infrastructure is
what makes the reproducibility cross-check meaningful). The CI runs the
**same build** as `build.sh`: same `Containerfile.modern` container, same
`_inner-build-16m.sh`, same seed, same pin file. Pieces:

- **`ci/wr941nd-v4-16m.env`** — the single source of truth: `OPENWRT_TAG`
  (exact release), `SEED_FILE`, `DEVICE_NAME`. Both CI and `build.sh` read it.
- **`renovate.json`** — a self-hosted Renovate (daily) bumps the
  `OPENWRT_TAG` pin from OpenWrt's release tags: a patch release in the
  pinned series → auto-PR on Gitea; a **series jump** (e.g. v26.x) waits for
  approval on the dependency dashboard, because it needs manual DTS/seed
  review first (the 24.10→25.12 nvmem-layout change is the precedent).
  Renovate also bumps the SHA-pinned GitHub Actions and digest-pins the
  container base images.
- **`.github/workflows/build.yml`** — a push to a `renovate/**` branch
  (arriving via the mirror) runs a **canary build**; a `v*` **tag** push
  builds and publishes the **Release** (`<tag>-wr941nd-v4-16m`: factory +
  sysupgrade + manifest + SHA256SUMS — never the FULLFLASH). Plain `master`
  pushes do not build.
- **`scripts/tag-release.sh`** — run on master after merging a bump PR:
  creates the release tag on Gitea; the mirror forwards it and GitHub
  releases. (Tags must originate on Gitea — the push mirror prunes refs that
  exist only on GitHub.)

**Update flow:** Renovate bump PR on Gitea → canary build on GitHub green? →
merge on Gitea → `scripts/tag-release.sh` → Release → download sysupgrade
image, verify SHA256 → `sysupgrade` on the router (settings kept).
Wall-clock cost: a full CI build is ~2 h; a private repo's 2000 free monthly
Actions minutes fit a few builds comfortably.

### Forking this repo for your own device

One-time setup after forking:

1. Decide where the bump PRs come from. This repo drives them from a
   self-hosted **Renovate on Gitea** (see `renovate.json`) and mirrors to
   GitHub. A GitHub-only fork works too: run Renovate (or the hosted
   Mend app) against the fork, or bump `ci/*.env` by hand — the build only
   needs a `renovate/**` branch push (canary) or a `v*` tag push (release),
   whatever creates them.
2. Run one local build — it generates the apk signing keypair
   (`private-key.pem` / `public-key.pem`) in the build-tree root — then add
   their contents as the **`APK_PRIVATE_KEY`** and **`APK_PUBLIC_KEY`** Actions
   secrets. Without them every CI run signs with a throwaway key and the
   images can never match your local ones bit-for-bit.
3. Replace the backup-dependent bits with your own device's dumps (keep them
   out of git!) and, for a different router model, your own DTS + seed +
   `ci/*.env`.

> **Note on the build container.** `Containerfile` (the legacy 18.06 flow) is
> permanently pinned to Debian **bullseye** — it needs `python2`, and bullseye
> is the last release that ships it. `Containerfile.modern` stays on
> **bookworm** deliberately: a base image swap changes the toolchain and
> invalidates the reproducibility baseline, so it is an approval-only decision
> rather than an automatic bump.

### Reproducibility (supply-chain cross-check)

Verified on v25.12.4 and v25.12.5: a clean local build and the CI build are
**byte-identical** — kernel and every rootfs file — except a known-benign
residue of build timestamps (in 25.12.4: 6 bytes in `usr/bin/apk` +
`libnftables.so`, both ignoring `SOURCE_DATE_EPOCH`; by 25.12.5 upstream fixed
those, leaving only the apk-db checksum cascade). Two determinism fixes make
this possible:

- `CONFIG_KERNEL_BUILD_USER/DOMAIN` pinned in the seed (otherwise the kernel
  banner embeds the random container hostname);
- CI signs with the **project apk keypair** from the Actions secrets instead
  of a per-run throwaway key.

Check any two same-tag images (e.g. your local build vs the Release asset):

```bash
scripts/repro-compare.sh local-sysupgrade.bin release-sysupgrade.bin
```

It PASSes only if the images match modulo the exact whitelisted residue — any
other difference is a supply-chain red flag.

## Repo layout

| Path | Role |
|------|------|
| [scripts/build.sh](scripts/build.sh) | **entry point** — pin-driven build, bootstraps everything |
| [scripts/build-16m.sh](scripts/build-16m.sh) | 16M build + FULLFLASH assembly (called by build.sh) |
| [scripts/_inner-build-16m.sh](scripts/_inner-build-16m.sh) | in-container build: DTS/profile injection + seed + make |
| [scripts/repro-compare.sh](scripts/repro-compare.sh) | reproducibility check of two same-tag images |
| [scripts/router-backup.sh](scripts/router-backup.sh) | mtd partition backup over SSH, 3× verified |
| [config/wr941nd-v4-25.12-16m.seed.config](config/wr941nd-v4-25.12-16m.seed.config) | current seed (LuCI, HTTPS, ed25519, deterministic banner) |
| [config/ath79-24.10/](config/ath79-24.10/) | custom 16M DTS + device definition (injected at build time) |
| [ci/wr941nd-v4-16m.env](ci/wr941nd-v4-16m.env) | device pin: OpenWrt tag + seed (single source of truth) |
| [renovate.json](renovate.json) | Renovate: OpenWrt tag bumps, action SHA pins, base-image digests |
| [scripts/tag-release.sh](scripts/tag-release.sh) | tag the merged bump on Gitea → GitHub builds the Release |
| [Containerfile.modern](Containerfile.modern) | Debian bookworm build container (24.10/25.12) |
| [docs/hardware-mod.md](docs/hardware-mod.md) | the flash + RAM upgrade guide |
| `firmware/` | not in git: backups, dumps and built images |
| [scripts/shell.sh](scripts/shell.sh), [scripts/clean.sh](scripts/clean.sh) | interactive container shell (menuconfig); build-tree cleanup |
| [Containerfile](Containerfile), [scripts/fw-build.sh](scripts/fw-build.sh), `config/*18.06*` | legacy 18.06/ar71xx flow (see below) |

## Operations / troubleshooting (deployed AP)

### Spontaneous reboot due to serial console + SysRq (IMPORTANT)

Symptom: the AP **reboots on its own** (`dmesg`/`logread` only shows
`Watchdog has previously reset the system`, no OOM/panic/crash), typically
around serial-adapter plug/unplug — or when the soldered serial **pin header
is left unconnected on the board**.

Cause: the kernel runs with `console=ttyS0,115200` and **SysRq enabled by
default**; a floating/noisy serial line can produce a **BREAK**, which the
kernel interprets as a SysRq command. The AR7240 watchdog (30 s) then resets
the stuck system.

Fix (applied on this unit, no downside on a headless AP — serial *output*
still works):

```sh
echo 0 > /proc/sys/kernel/sysrq
echo 'kernel.sysrq=0' >> /etc/sysctl.conf
```

Also: plug/unplug the serial adapter only with the board powered off, or
connect **GND first / disconnect it last**.

### Historical: RAM on the stock 32 MB

Pre-mod, 24.10 + LuCI + 802.11r left ~7 MB free — no OOM but no headroom, and
25.12 didn't fit at all (constant OOM reboots). This is what motivated the
64 MB upgrade; post-mod there is ~19 MB free + ~17 MB cache.

## Legacy: the original 18.06 phases

The project started (2026-06) with different goals, kept here for context:
**(1)** reproduce the then-running stock `18.06.9` firmware from source —
done, `scripts/fw-build.sh` + the `18.06` seeds, `ar71xx` target, Debian
bullseye [Containerfile](Containerfile); **(2)** strip it to an AP-only
package set — done as the "pragmatic AP" seed; **(3)** the 16 MB / 64 MB mod
and a current OpenWrt — done, and that flow (above) replaced the rest.

Usage of the legacy flow: `./scripts/img-build.sh` once, then
`./scripts/fw-build.sh` (`OPENWRT_TAG=`, `SEED_FILE=`, `BUILD_LABEL=` as
knobs; outputs under `firmware/built/<label>/`).

> ⚠️ **Kernel lesson** (applies to any seed editing): a seed change that adds/
> removes `kmod-*` packages changes the kernel VERMAGIC; in an already-built
> tree `package/install` then fails with *"Cannot satisfy … kernel (= hash)"*.
> Rebuild with `CLEAN=kernel` (or `CLEAN=all`). The pragmatic-AP seed avoided
> the problem by only removing userspace daemons (dnsmasq, odhcpd).

## License

**GPL-2.0** (see [LICENSE](LICENSE)) — the custom DTS and device definition
under `config/` are derived from OpenWrt's GPL-2.0 sources, and the rest of
the repo follows the same license for simplicity.
