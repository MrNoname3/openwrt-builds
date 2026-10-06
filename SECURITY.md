# Security

## What a release is built from

Every Release is built by GitHub Actions from this repository at the release
tag: an OpenWrt tag pinned to its commit in `ci/*.env`, a build container on a
digest-pinned base image, and SHA-pinned Actions. A Release can be checked
independently against a local build of the same tag — see "Reproducibility"
in the [README](README.md). A difference beyond the documented residue is
worth reporting.

Each Release asset also has a signed build-provenance attestation that ties it
to this repository's workflow run and commit (Releases up to v25.12.5 were
published without one):

```bash
gh attestation verify <asset> --repo MrNoname3/openwrt-builds
```

Packages in the images are signed with the project's apk key. Its private half
is held by the maintainer and as an Actions secret, never in this repository.

## Bricking a stock router is not a vulnerability

The images claim the stock `tplink,tl-wr941-v4` compat string, so `sysupgrade`
on an unmodified 4 MB router accepts them and bricks it. That is a known
consequence of the hardware mod, documented in the [README](README.md), not a
flaw to report.

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue.
On GitHub use *Security → Report a vulnerability* (private advisory), or
contact the maintainer directly. You will get an acknowledgement as soon as
possible.
