# Legacy: the original 18.06 / ar71xx flow

Before the hardware mod, this repo had a different goal: reproduce and then
slim down the firmware the **stock** (4 MB / 32 MB) router was running. That
work is finished and superseded by the 16M flow in the README, but the files
are kept because they still build:

1. **Reproduce the running stock `18.06.9` from source** — done, with
   `scripts/fw-build.sh`, the `18.06` seeds and the `ar71xx` target.
2. **Strip it to an AP-only package set** — done, as the "pragmatic AP" seed
   (`config/wr941nd-v4-18.06-ap.seed.config`).
3. **The 16 MB / 64 MB mod on a current OpenWrt** — done, and that flow
   replaced the rest. See the [README](../README.md).

The legacy flow uses its own build container ([Containerfile](../Containerfile),
Debian bullseye — 18.06 drives its build system with Python 2, and bullseye is
the last Debian that ships it) and its own source tree at
`~/.local/share/openwrt-wr941nd/src`.

## Usage

```bash
./scripts/img-build.sh        # once: build the bullseye container image
./scripts/fw-build.sh         # build; knobs below
```

| Variable | Meaning |
|----------|---------|
| `OPENWRT_TAG=vX.Y.Z` | which OpenWrt tag to build (default `v18.06.9`) |
| `SEED_FILE=...` | seed config under `config/` |
| `BUILD_LABEL=name` | output folder name under `firmware/built/` |
| `CLEAN=kernel\|all` | clean before rebuilding (see below) |

`scripts/shell.sh` opens an interactive shell in this container (for
`make menuconfig`), and `scripts/clean.sh` removes this tree and image. Neither
touches the current 16M build tree.
