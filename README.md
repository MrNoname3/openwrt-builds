# OpenWrt builds — TP-Link TL-WR941ND v4 (16 MB / 64 MB mod)

Custom OpenWrt firmware for a hardware-modded **TL-WR941ND v4** (Atheros
AR7240, `ath79`/`tiny`): **4→16 MB flash + 32→64 MB RAM**. The stock hardware
cannot run current OpenWrt; the modded device runs it, built from this repo, in
production as a dumb AP.

What lives here:

- a **containerized buildroot** (rootless podman, nothing installed on the host)
  that injects a custom 16 MB DTS/device profile into a stock OpenWrt tree;
- **GitHub Actions CI** that builds the exact same image and publishes
  flashable **Releases** (see [CI](#ci--automated-builds-and-releases));
- a **reproducibility cross-check** proving the local and CI images are
  identical apart from a documented residue.

> ⚠️ **Hardware requirement — no safety net.** The images need **BOTH** mods:
> 16 MB flash (W25Q128-class) **and** 64 MB RAM. Stock 4 MB flash cannot hold
> them, and current OpenWrt does not run reliably in the stock 32 MB RAM
> ([why](docs/operations.md#why-32-mb-ram-is-not-enough)).
>
> The modded board still reports the stock `tplink,tl-wr941-v4` compat string,
> so these images must claim it to be installable at all. As a result
> **`sysupgrade` accepts them on a stock device without `--force`, and bricks
> it.** The other way round, official OpenWrt images and attended sysupgrade
> target the 4 MB layout and brick a modded unit. Only flash a board you
> modded yourself, and keep its FULLFLASH image and a programmer for recovery.

## From a stock unit to where this repo is — the complete path

If you own this router and want to end up here, this is the whole journey:

1. **Gather parts & tools**: a 16 MB SOIC-8 SPI NOR chip (W25Q128 family), a
   64 MB ×16 DDR1 chip (same type AR7240 boards ship with in their 64 MB
   variants), soldering iron/hot air, a SPI programmer (e.g. CH341A), a 3.3 V
   USB-UART for serial. Soldering SOIC-8 is
   easy; the DDR swap is the hard part.
2. **Back up the original flash** — twice if you can (SSH + chip read). The
   `u-boot` (contains your MAC) and `art` (your radio calibration) regions are
   irreplaceable. → [docs/hardware-mod.md](docs/hardware-mod.md), step 1.
3. **Swap the RAM** (and optionally recap while the board is open). The flash
   chip is *not* soldered yet — it gets written first, in step 5.
   → [docs/hardware-mod.md](docs/hardware-mod.md), step 5 (RAM swap).
4. **Build the firmware** ([below](#building)). With your backup in place it
   also assembles the **full-chip image**.
   → [docs/hardware-mod.md](docs/hardware-mod.md), steps 2–3.
5. **Write the new chip with the programmer, solder it in, first boot,
   configure.**
   → [docs/hardware-mod.md](docs/hardware-mod.md), step 4 (write + solder) and
   step 6 (first boot); setup in [docs/operations.md](docs/operations.md).
6. **Updates from then on are software-only**: build locally or fork this repo
   for your own CI (see [Forking](#forking-this-repo-for-your-own-device)),
   then [sysupgrade](docs/operations.md#updating). The programmer is never
   needed again.

## Building

`scripts/build.sh` builds **exactly what the CI builds**, driven by the same
per-device pin file (`ci/<device>.env`). On a fresh machine it bootstraps
everything itself (OpenWrt clone at the pinned tag, container image, build):

```bash
git clone https://github.com/MrNoname3/openwrt-builds.git
cd openwrt-builds
JOBS=4 ./scripts/build.sh          # lower JOBS if the build runs out of memory
```

Optional settings (which device, a different tag, parallelism, where the source
trees live, a dry run) are environment variables listed at the top of
[scripts/build.sh](scripts/build.sh).

Requirements: rootless **podman** (the scripts auto-detect a VS Code Flatpak
terminal and go through `flatpak-spawn --host`), ~20 GB disk for the build
tree, a full clean build takes ~2–4 h at `JOBS=4`. The tree lives **outside**
the repo clone (`~/.local/share/openwrt-wr941nd/`), so its build files never
land in the clone.

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
GitHub, where Actions builds and releases. An OpenWrt build is too heavy for
the Gitea box, and an *independent* build infrastructure is what makes the
reproducibility cross-check meaningful. Pieces:

- **`ci/wr941nd-v4-16m.env`** — the pin: `OPENWRT_TAG` with the commit it must
  resolve to (`OPENWRT_COMMIT`), `SEED_FILE`, `DEVICE_NAME`. Both builds refuse
  a source tree whose commit differs from the pin.
- **`renovate.json`** — a self-hosted Renovate on Gitea bumps the pin from
  OpenWrt's release tags. A patch release in the pinned series becomes a PR; a
  **series jump** waits for approval on the dependency dashboard, because a
  new series can need DTS or seed changes. Everything else (Action SHAs, the
  base-image digest, actionlint) is collected into one monthly "build tooling"
  PR. Moving the build container to a new Debian release is never automatic:
  it changes the toolchain and invalidates the reproducibility baseline.
- **`.github/workflows/build.yml`** — a `renovate/**` branch push runs a
  **canary build**; a `v*` **tag** push builds and publishes the **Release**
  (factory + sysupgrade + manifest + SHA256SUMS, never the FULLFLASH). Only
  the release job gets write access. Plain `master` pushes do not build.
- **`.github/workflows/check.yml`** — runs `scripts/check.sh` on every push,
  on Gitea Actions as well.
- **`scripts/tag-release.sh`** — creates the release tag on Gitea. Tags must
  originate there: the push mirror prunes refs that exist only on GitHub.

### Releasing a new OpenWrt version

Two steps need you; the router is never touched automatically.

1. **A bump PR appears on Gitea.** Its `renovate/**` branch reaches GitHub
   through the mirror and runs the canary build, which proves the new version
   still builds with this DTS and seed; it publishes nothing.
2. **Canary green → merge the PR on Gitea.** ← *you*
3. **Tag it** ← *you*: run `./scripts/tag-release.sh` on master; it syncs with
   origin itself. The mirror forwards the tag and GitHub publishes the
   **Release**.
4. **Flash** — see [Updating](docs/operations.md#updating). Optionally
   cross-check the Release against your own build first
   ([Reproducibility](#reproducibility-supply-chain-cross-check)). For the
   first flash of a new series, keep the FULLFLASH image and the programmer at
   hand.

### Forking this repo for your own device

One-time setup after forking:

1. Decide where the bump PRs come from. A GitHub-only fork works too: run
   Renovate (or the hosted Mend app) against the fork, or bump `ci/*.env` by
   hand. The build only needs a `renovate/**` branch push (canary) or a `v*`
   tag push (release).
2. Run one local build: it generates the apk signing keypair
   (`private-key.pem`, `public-key.pem`) in the build-tree root. Add their
   contents as the **`APK_PRIVATE_KEY`** and **`APK_PUBLIC_KEY`** Actions
   secrets.
3. Your own unit's flash dumps go under `firmware/router-backup/`, never into
   git. A different router model needs its own DTS, seed and `ci/*.env`.
4. `scripts/tag-release.sh` tags `master` and pushes to `origin`; in a
   GitHub-only fork that is the fork itself. Adjust its branch check if your
   default branch is `main`.

### Reproducibility (supply-chain cross-check)

A local build and the CI build of the same tag are **byte-identical** — the
kernel and every rootfs file — except for a known residue in the apk database
(the exact list is in
[scripts/_inner-repro-compare.sh](scripts/_inner-repro-compare.sh)). Two
settings make this possible:

- the seed fixes the build user and host in the kernel banner
  (`CONFIG_KERNEL_BUILD_USER/DOMAIN`);
- CI signs packages with the **project apk keypair** from the Actions secrets;
  without them every run signs with a throwaway key.

Compare any two same-tag images, e.g. your local build and the Release asset:

```bash
scripts/repro-compare.sh local-sysupgrade.bin release-sysupgrade.bin
```

Any difference beyond that residue fails the check and is a supply-chain red
flag.

## Repo layout

| Path | Role |
|------|------|
| [scripts/build.sh](scripts/build.sh) | **entry point** — pin-driven build, bootstraps everything, assembles the FULLFLASH |
| [scripts/_inner-build.sh](scripts/_inner-build.sh) | in-container build: DTS/profile injection + seed + make |
| [scripts/repro-compare.sh](scripts/repro-compare.sh) | reproducibility check of two same-tag images |
| [scripts/router-backup.sh](scripts/router-backup.sh) | mtd partition backup over SSH, cross-checked over several passes |
| [config/wr941nd-v4-25.12-16m.seed.config](config/wr941nd-v4-25.12-16m.seed.config) | seed config: packages and build options |
| [config/ath79-16m/](config/ath79-16m/) | custom 16M DTS + device definition (injected at build time) |
| [ci/wr941nd-v4-16m.env](ci/wr941nd-v4-16m.env) | device pin: OpenWrt tag and commit, seed, release name |
| [renovate.json](renovate.json) | Renovate rules that keep every pin current |
| [scripts/tag-release.sh](scripts/tag-release.sh) | tag the merged bump on Gitea → GitHub builds the Release |
| [scripts/check.sh](scripts/check.sh) | pre-push gate: secret scan and linters (CI runs it too) |
| [Containerfile](Containerfile) | build container on a digest-pinned Debian base |
| [docs/hardware-mod.md](docs/hardware-mod.md) | the flash + RAM upgrade guide |
| [docs/operations.md](docs/operations.md) | running the AP: setup, updates, harmless messages, pitfalls (including serial-console reboots) |
| [SECURITY.md](SECURITY.md) | how releases can be verified, and how to report a vulnerability |
| [AGENTS.md](AGENTS.md) | notes for coding agents: ground rules, forge topology, gotchas |
| `firmware/` | flash backups and built images; the directory is in git, its contents never are |
| `work/` | scratch files (downloads, comparison inputs, logs); contents not in git |
| `.githooks/` | `pre-push` runs `scripts/check.sh` (enable with `git config core.hooksPath .githooks`) |
| `.editorconfig`, `.vscode/`, [openwrt-wr941nd.code-workspace](openwrt-wr941nd.code-workspace) | editor settings: whitespace rules in `.editorconfig`, VS Code extras in the other two |

## History: the original 18.06 flow

The project started out reproducing and slimming the stock 4 MB firmware on
OpenWrt 18.06 (ar71xx). That flow is retired; its build container, scripts and
seeds are preserved at the `legacy-18.06` tag.

## License

**GPL-2.0** (see [LICENSE](LICENSE)) — the custom DTS and device definition
under `config/` are derived from OpenWrt's GPL-2.0 sources, and the rest of
the repo follows the same license for simplicity.
