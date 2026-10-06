# Security

## What a release is built from

Every Release is built by GitHub Actions from this repository at the release
tag: an OpenWrt source tag pinned in `ci/*.env`, a build container on a
digest-pinned base image, and SHA-pinned Actions; the OpenWrt tag is pinned
to its commit as well. A Release can be checked independently against a local
build of the same tag — see "Reproducibility" in the [README](README.md). A
difference beyond the documented residue is worth reporting.

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
