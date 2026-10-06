# OpenWrt builds — TP-Link TL-WR941ND v4 (16 MB / 64 MB mod)

Custom OpenWrt firmware for a hardware-modded **TL-WR941ND v4** (Atheros
AR7240, `ath79`/`tiny`): **4→16 MB flash + 32→64 MB RAM**. Stock hardware died
with OpenWrt 18.06/19.07; the modded device runs the **current 25.12 series**
built from this repo, in production, as a dumb AP.

What lives here:

- a **containerized buildroot** (rootless podman, nothing installed on the host)
  that injects a custom 16 MB DTS/device profile into a stock OpenWrt tree;
- **GitHub Actions CI** that builds the exact same image and publishes
  flashable **Releases** (new OpenWrt releases are picked up by Renovate on the
  upstream Gitea, not by a workflow here — see [CI](#ci--automated-builds-and-releases));
- a **reproducibility cross-check** proving the local and CI images are
  identical apart from a documented residue.

> ⚠️ **Hardware requirement.** The images need **BOTH** mods: 16 MB flash
> (W25Q128-class) **and** the 32→64 MB RAM upgrade. Stock 4 MB flash cannot
> hold them, and on stock 32 MB RAM kernel 6.12 OOM-reboots constantly
> (verified on this unit). **Never flash a stock device**, and never use
> official OpenWrt images on a modded one (the official
> `tplink,tl-wr941-v4` profile targets the 4 MB layout → brick).
>
> ⚠️ **No safety net — read this before you flash anything.** The modded board
> still reports the stock compat string, so the 16M image *must* claim
> `tplink,tl-wr941-v4` in `SUPPORTED_DEVICES` to be installable at all. The
> consequence: **`sysupgrade` will happily accept these images on a stock 4 MB
> device without `--force`** (the list also covers `tl-wr741nd`). The usual
> "wrong device" guard does not protect you here. Only ever flash a board you
> personally modded, and keep the FULLFLASH image + a programmer for recovery.

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
3. **Swap the RAM** (and optionally recap while the board is open). The flash
   chip is *not* soldered yet — it gets written first, in step 5.
   → [docs/hardware-mod.md](docs/hardware-mod.md), step 5 (RAM swap).
4. **Build the firmware**: `JOBS=4 ./scripts/build.sh` (below). With your
   backup in place it also assembles the **full-chip image** (your u-boot +
   new firmware + your art, at the right offsets).
   → [docs/hardware-mod.md](docs/hardware-mod.md), steps 2–3.
5. **Write the new chip with the programmer, solder it in, first boot,
   configure.**
   → [docs/hardware-mod.md](docs/hardware-mod.md), step 4 (write + solder) and
   step 6 (first boot).
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
JOBS=4 ./scripts/build.sh          # lower JOBS if the build runs out of memory
```

Knobs (all optional, no TTY needed):

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
**outside** the repo clone (`~/.local/share/openwrt-wr941nd/`), so 300k
intermediate build files never land in the clone.

Output → `firmware/built/16m-<version>/`: factory + sysupgrade + SHA256SUMS,
plus the FULLFLASH full-chip image when a router backup exists locally (the
u-boot/art dumps are device-unique and not in git — see the
[hardware guide](docs/hardware-mod.md) for what each image is for).

> ⚠️ **When editing a seed:** adding or removing `kmod-*` packages changes the
> kernel VERMAGIC, and in an already-built tree `package/install` then fails
> with *"Cannot satisfy … kernel (= hash)"*. Rebuild the kernel in that case
> (delete the build tree, or run `make clean` in it). Seed changes that only
> touch userspace packages are safe.

## CI — automated builds and releases

The **source of truth is a self-hosted Gitea instance**, push-mirrored to
GitHub; GitHub Actions is the build + release executor (an OpenWrt build is
too heavy for the Gitea box — and an *independent* build infrastructure is
what makes the reproducibility cross-check meaningful). The CI runs the
**same build** as `build.sh`: same `Containerfile` container, same
`_inner-build.sh`, same seed, same pin file. Pieces:

- **`ci/wr941nd-v4-16m.env`** — the single source of truth: `OPENWRT_TAG`
  (exact release) with `OPENWRT_COMMIT` (the commit it must resolve to),
  `SEED_FILE`, `DEVICE_NAME`. Both CI and `build.sh` read it, and both refuse a
  source tree whose commit differs from the pin.
- **`renovate.json`** — a self-hosted Renovate (daily) bumps the
  `OPENWRT_TAG`/`OPENWRT_COMMIT` pin from OpenWrt's release tags: a patch
  release in the pinned series → auto-PR on Gitea; a **series jump** (e.g. v26.x) waits for
  approval on the dependency dashboard, because it needs manual DTS/seed
  review first (the 24.10→25.12 nvmem-layout change is the precedent).
  Renovate also bumps the SHA-pinned GitHub Actions and the container base
  image digest, collected into one "build tooling" PR on the 1st of each month.
- **`.github/workflows/build.yml`** — a push to a `renovate/**` branch
  (arriving via the mirror) runs a **canary build**; a `v*` **tag** push
  builds and publishes the **Release** (`<tag>-wr941nd-v4-16m`: factory +
  sysupgrade + manifest + SHA256SUMS — never the FULLFLASH). The build runs
  with a read-only token; only the separate release job can write. Plain
  `master` pushes do not build.
- **`.github/workflows/check.yml`** — runs `scripts/check.sh` (secret scan,
  shellcheck, yamllint) on every push.
- **`scripts/tag-release.sh`** — run on master after merging a bump PR:
  creates the release tag on Gitea; the mirror forwards it and GitHub
  releases. (Tags must originate on Gitea — the push mirror prunes refs that
  exist only on GitHub.)

### Releasing a new OpenWrt version — the whole recipe

Everything up to the merge happens on its own; the parts that need you are
**two steps**, and the router is never touched automatically.

1. **A bump PR appears on Gitea** (Renovate, daily) changing `OPENWRT_TAG` in
   `ci/*.env`. Its `renovate/**` branch reaches GitHub through the mirror and
   starts a **canary build** — this only proves the new version still
   compiles with our DTS/seed; it publishes nothing.
2. **Canary green → merge the PR on Gitea.** ← *step 1 of yours*
3. **Tag it:** ← *step 2 of yours*
   ```bash
   ./scripts/tag-release.sh      # syncs with origin itself, no git pull needed
   ```
   It reads the merged pin, tags that commit `<OPENWRT_TAG>-<DEVICE_NAME>` and
   pushes to Gitea; the mirror forwards the tag, and GitHub's tag build
   publishes the **Release**. A tag build aborts immediately if the tag and the
   pin disagree.
4. **Flash** — download the `-sysupgrade.bin` from the Release, check it
   against `SHA256SUMS`, then upgrade from LuCI or over SSH with settings
   kept. Optionally cross-check the release against your own build first:
   ```bash
   JOBS=4 ./scripts/build.sh                      # same pin as CI
   scripts/repro-compare.sh release-sysupgrade.bin firmware/built/16m-<ver>/*sysupgrade.bin
   ```

A **series jump** (e.g. v26.x) or a build-container major bump never gets an
automatic PR: it waits on Renovate's dependency dashboard until you approve
it, because it needs a DTS/seed review first. Treat the first flash of a new
series as a risk moment — keep the FULLFLASH image and the CH341A at hand.

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
4. `scripts/tag-release.sh` assumes it runs on a **`master`** branch and pushes
   the tag to **`origin`**. In a GitHub-only fork that is simply your fork, and
   it works unchanged — the "tags must originate on Gitea" rule above is a
   consequence of *this* repo's push mirror, not of the tooling. Rename the
   branch check if your default branch is `main`.

> **Note on the build container.** `Containerfile` stays on Debian
> **bookworm** deliberately: a base image swap changes the toolchain and
> invalidates the reproducibility baseline, so it is an approval-only decision
> rather than an automatic bump.

### Reproducibility (supply-chain cross-check)

A local build and the CI build of the same tag are **byte-identical** — the
kernel and every rootfs file — except for a known-benign residue in the apk
database (the exact whitelist is in
[scripts/_inner-repro-compare.sh](scripts/_inner-repro-compare.sh)). Two
determinism fixes make this possible:

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
| [scripts/build.sh](scripts/build.sh) | **entry point** — pin-driven build, bootstraps everything, assembles the FULLFLASH |
| [scripts/_inner-build.sh](scripts/_inner-build.sh) | in-container build: DTS/profile injection + seed + make |
| [scripts/repro-compare.sh](scripts/repro-compare.sh) | reproducibility check of two same-tag images |
| [scripts/router-backup.sh](scripts/router-backup.sh) | mtd partition backup over SSH, 3× verified |
| [config/wr941nd-v4-25.12-16m.seed.config](config/wr941nd-v4-25.12-16m.seed.config) | current seed (LuCI, HTTPS, ed25519, deterministic banner) |
| [config/ath79-16m/](config/ath79-16m/) | custom 16M DTS + device definition (injected at build time) |
| [ci/wr941nd-v4-16m.env](ci/wr941nd-v4-16m.env) | device pin: OpenWrt tag + seed (single source of truth) |
| [renovate.json](renovate.json) | Renovate: OpenWrt tag bumps, action SHA pins, base-image digests |
| [scripts/tag-release.sh](scripts/tag-release.sh) | tag the merged bump on Gitea → GitHub builds the Release |
| [scripts/check.sh](scripts/check.sh) | pre-push gate: secret scan + shellcheck + yamllint (also run by CI; `.githooks/pre-push` runs it once enabled with `git config core.hooksPath .githooks`) |
| [Containerfile](Containerfile) | Debian bookworm build container (24.10/25.12) |
| [docs/hardware-mod.md](docs/hardware-mod.md) | the flash + RAM upgrade guide |
| [docs/operations.md](docs/operations.md) | running the AP: setup, updates, harmless messages, pitfalls |
| [SECURITY.md](SECURITY.md) | how releases can be verified, and how to report a vulnerability |
| [AGENTS.md](AGENTS.md) | notes for coding agents: ground rules, forge topology, gotchas |
| `firmware/` | not in git: backups, dumps and built images |

## Operations / troubleshooting (deployed AP)

Dumb-AP setup, updating, harmless log messages and known pitfalls — including
the **spontaneous reboots a connected serial header can cause** — are in
[docs/operations.md](docs/operations.md).

## History: the original 18.06 flow

The project started out reproducing and slimming the stock 4 MB firmware on
OpenWrt 18.06 (ar71xx). That flow is retired; its build container, scripts and
seeds are preserved at the `legacy-18.06` tag.

## License

**GPL-2.0** (see [LICENSE](LICENSE)) — the custom DTS and device definition
under `config/` are derived from OpenWrt's GPL-2.0 sources, and the rest of
the repo follows the same license for simplicity.
