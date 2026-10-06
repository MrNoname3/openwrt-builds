# openwrt-builds — notes for coding agents

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
- Commit subjects use an area prefix — `docs:`, `ci:`, `seed:`, `config:`,
  `build:`, `scripts:`, `renovate:`, `editor:`, `repo:`, `style:` — one
  concern per commit.
- **Run `./scripts/check.sh` before every push** (a push is a publication,
  through the mirror); `git config core.hooksPath .githooks` makes git run it
  as a pre-push hook. Its private scan patterns live in the gitignored
  `.secret-patterns.local`; on a machine without that file only the generic
  patterns run, so ask the owner for it rather than skipping the scan.

## Where things live

| Location | In git | What it holds |
|----------|:------:|---------------|
| `~/.local/share/openwrt-wr941nd/openwrt-<series>/` | no | OpenWrt build tree, one per release series, created by `scripts/build.sh`; reused incrementally |
| `<build tree>/private-key.pem`, `public-key.pem` | no | the project's apk signing keypair; CI holds the same pair as Actions secrets |
| `firmware/router-backup/<ts>/` | no | mtd dumps of the original flash — `u-boot` and `art` are irreplaceable |
| `firmware/built/16m-<version>/` | no | build output; the FULLFLASH image only when a backup is present |
| podman image `openwrt-builder` | no | build container from `Containerfile`, rebuilt automatically when that file changes |

On a fresh machine `firmware/` is empty and there is no build tree: the build
still works, it just skips the FULLFLASH assembly. Copy the project keypair into
the tree root before the first build when bit-identity with CI matters (why:
the README's "Reproducibility").

## Working files go in work/

An agent's own temp directory is not on the host's filesystem, so a path
reported from there is one the user cannot open, and host-side podman cannot
mount it either — `repro-compare.sh` on a downloaded release image fails that
way. Downloads, comparison inputs and captured logs belong in `work/`: the
directory is committed, its contents are gitignored, and everything in it can
be deleted at any time. Keep secrets out of it; it is plain and unencrypted.

## Environment

From a VS Code **Flatpak** sandbox, host tools other than podman (which the
scripts handle) — ssh, ping, flashrom, the serial port — are reachable only
through `flatpak-spawn --host`, and the sandbox's `/tmp` is not the host's:
pass data on stdin or through `work/`.

## Forge topology

The setup is in the README's CI section. Here, `origin` is the Gitea with
default branch `master`; there is no `github` remote, so reach the mirror
(`MrNoname3/openwrt-builds`) through its API or web UI.

### Handling a Renovate PR

The routine is the README's "Releasing a new OpenWrt version". What it leaves
to judgement:

- **Canary status** is on GitHub, readable without a token:
  `curl -s 'https://api.github.com/repos/MrNoname3/openwrt-builds/actions/runs?branch=<branch>&per_page=3'`.
- **Read the diff.** For an Action bump, confirm the pinned SHA is the upstream
  tag's commit: `git ls-remote --tags <action repo> 'vX.Y.Z*'` (the `^{}` line
  for an annotated tag). For an OpenWrt bump, `OPENWRT_COMMIT` must be the
  `^{}` commit of the new tag in `github.com/openwrt/openwrt`.
- Only an `OPENWRT_TAG` bump gets a release (`scripts/tag-release.sh`); digest
  and Action bumps do not. Flashing is the owner's call.

### Forge gotchas

- The Gitea merge API can answer `405 Please try again later` for a while after
  another merge. Fallback: `git merge --no-ff` locally, using the message format
  of `.gitea/default_merge_message/MERGE_TEMPLATE.md`, and push. The repo has
  manual-merge autodetection enabled, so Gitea marks the PR merged within
  seconds; then delete its branch.
- A tag build runs the workflow as it is **at the tagged commit**. To change a
  published release, delete the Release on GitHub (web UI) and the tag on
  `origin`, then re-run `tag-release.sh`.
- Merge commits get mirrored to the public GitHub repo; the merge-message
  template keeps Gitea's `Reviewed-on: <forge URL>` trailer out of them.

## Verifying images

- How `scripts/repro-compare.sh` decides is in the README's "Reproducibility"
  section. Put a downloaded Release image in `work/` before comparing it.
- Compare package manifests as sets: `sort` collates differently between
  environments.
- Rebuilding the same tag never brings newer packages: a release's
  `feeds.conf.default` pins every feed to a commit. Newer packages need a new
  OpenWrt release.

## Ideas not pursued yet

- A status-check bridge that reports the GitHub canary result on the Gitea PR,
  which would make Renovate automerge safe.
- A self-hosted ASU server backed by a custom ImageBuilder that knows the
  `tplink_tl-wr941-v4-16m` profile, giving the AP a real attended-sysupgrade
  path.
