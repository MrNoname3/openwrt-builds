# Working on this repo

Orientation for an AI agent (or a new contributor) starting from a fresh clone.
What the project is and how to build and release it is in the
[README](README.md); the hardware mod is in
[docs/hardware-mod.md](docs/hardware-mod.md); running the deployed AP is in
[docs/operations.md](docs/operations.md). This file covers how to work here.

## Ground rules

- **The repo is public.** Files, commit messages, PR and issue bodies must not
  contain the owner's home-network specifics: IP addresses, hostnames
  (including the self-hosted forge's), SSIDs and keys, MAC addresses, SSH
  ports, key paths or fingerprints, or anything about other devices on that
  network. Write "the forge", "the AP", "the main router" instead.
- **Everything in files is English**: code comments, docs, commit messages,
  PR bodies — whatever language the conversation is in.
- **Install nothing on the host.** The build toolchain lives in the container
  (`Containerfile`); anything else goes in a throwaway container.
- **Device-unique data never enters git.** `firmware/` (flash dumps holding the
  unit's MAC and WiFi calibration, full-chip images) is git-ignored; keep it so.
- **Never flash or suggest official OpenWrt images or attended sysupgrade** for
  this device: the board reports the stock 4 MB compat string, and those
  images brick it.
- **Do not change the deployed AP** (config, reboot, sysupgrade) without the
  owner's explicit go-ahead. Reading its state is fine.
- Commit subjects use an area prefix — `docs:`, `ci:`, `seed:`, `build-16m:`,
  `renovate:`, `tag-release:` — one concern per commit.

## Where things live

| Location | In git | What it holds |
|----------|:------:|---------------|
| this clone | yes | sources, seeds, DTS, scripts, CI, docs |
| `~/.local/share/openwrt-wr941nd/openwrt-<series>/` | no | OpenWrt build tree, one per release series (~12 GB), created by `scripts/build.sh`; reused incrementally |
| `<build tree>/private-key.pem`, `public-key.pem` | no | the project's apk signing keypair; CI holds the same pair as Actions secrets |
| `firmware/router-backup/<ts>/` | no | mtd dumps of the original flash — `u-boot` and `art` are irreplaceable |
| `firmware/built/16m-<version>/` | no | build output; the FULLFLASH image only when a backup is present |
| podman image `openwrt-builder` | no | build container from `Containerfile`, rebuilt automatically when that file changes |

On a fresh machine `firmware/` is empty and there is no build tree: the build
still works, it just skips the FULLFLASH assembly. A fresh build tree generates
its own signing keypair, so its images differ from the CI's in every package
signature; copy the project keypair into the tree root before the first build
when bit-identity with CI matters.

The container image carries the sha256 of the `Containerfile` it was
built from; `build-16m.sh` and `repro-compare.sh` rebuild it when the file
changes (Renovate digest bumps included), so local builds use the same base as
CI.

## Environment

- Scripts auto-detect a VS Code **Flatpak** sandbox and run podman through
  `flatpak-spawn --host`. Other host tools (ssh, ping, flashrom, the serial
  port) are reachable the same way only; the sandbox's `/tmp` is not the host's,
  so pass data to host commands on stdin.
- Bind mounts carry `:Z` for SELinux hosts.
- A clean build takes 2–4 h at `JOBS=4`; a too-high `JOBS` runs out of memory.

## Forge topology

- `origin` is a **self-hosted Gitea** — the source of truth, default branch
  `master`. Gitea **push-mirrors** to GitHub (`MrNoname3/openwrt-builds`), where
  Actions builds and Releases are published. There is no `github` remote;
  reach GitHub through its API or web UI.
- A self-hosted **Renovate** runs daily against Gitea and opens PRs for OpenWrt
  patch releases (`OPENWRT_TAG` in `ci/*.env`), SHA-pinned Actions and
  base-image digests. Each `renovate/**` branch reaches GitHub through the
  mirror and runs a **canary build** there.

### Handling a Renovate PR

1. Check the canary build for that branch on GitHub Actions is green.
2. Read the diff. For an Action bump, confirm the pinned SHA is the upstream
   tag's commit: `git ls-remote --tags <action repo> 'vX.Y.Z*'` (the `^{}` line).
3. Merge on Gitea.
4. Only for an `OPENWRT_TAG` bump: run `scripts/tag-release.sh`, which tags on
   `origin`; the mirror forwards the tag and GitHub builds the Release. Digest
   and Action bumps need no release. Flashing is the owner's call.

Series jumps (e.g. v26.x) and base-image major bumps wait on Renovate's
dependency dashboard: they need a DTS/seed review first.

### Forge gotchas

- The Gitea merge API can answer `405 Please try again later` for a while after
  another merge. Fallback: `git merge --no-ff` locally, using the message format
  of `.gitea/default_merge_message/MERGE_TEMPLATE.md`, and push. The repo has
  manual-merge autodetection enabled, so Gitea marks the PR merged within
  seconds; then delete its branch.
- **Tags and releases originate on `origin` only.** The push mirror prunes refs
  that exist only on GitHub.
- A tag build runs the workflow as it is **at the tagged commit**. To change a
  published release, delete the Release on GitHub (web UI) and the tag on
  `origin`, then re-run `tag-release.sh`.
- Plain `master` pushes trigger no build, so docs-only commits cost nothing.
- Merge commits get mirrored to the public GitHub repo; the merge-message
  template keeps Gitea's `Reviewed-on: <forge URL>` trailer out of them.

## Verifying images

- `scripts/repro-compare.sh a.bin b.bin` compares two same-tag sysupgrade
  images and passes only modulo the whitelisted timestamp residue documented
  in `scripts/_inner-repro-compare.sh`. Any other difference is a red flag.
- Compare package manifests as sets: `sort` collates differently between
  environments.
- Rebuilding the same tag never brings newer packages: a release's
  `feeds.conf.default` pins every feed to a commit. Newer packages need a new
  OpenWrt release.
- Adding or removing a `kmod-*` changes the kernel vermagic; in an
  already-built tree, rebuild the kernel (see the README).

## Ideas not pursued yet

- A status-check bridge that reports the GitHub canary result on the Gitea PR,
  which would make Renovate automerge safe.
- A self-hosted ASU server backed by a custom ImageBuilder that knows the
  `tplink_tl-wr941-v4-16m` profile, giving the AP a real attended-sysupgrade
  path.
