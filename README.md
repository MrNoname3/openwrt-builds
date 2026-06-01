# OpenWRT build környezet — TP-Link TL-WR941ND v4

Podman-alapú, **rootless**, konténerizált OpenWRT buildroot a TL-WR941ND **v4**
routerhez (Atheros AR7240, `ar71xx` target, `tiny` subtarget).

A hostra **semmit nem telepítünk** — minden ebben a mappában és a Podman saját
konténer-tárolójában él. A nagy OpenWRT forrás-/build-fa a [`src/`](src/) mappában
lakik (a git nem követi), és bind-mounttal kerül a konténerbe.

## Cél (fázisok)

1. **(jelen)** Forrásból reprodukálni a routeren most futó firmware-t:
   `openwrt-18.06.9-ar71xx-tiny-tl-wr941nd-v4-squashfs-factory.bin`.
2. Csomagok/modulok kivétele (a router csak **AP módot** kell tudjon) — `make menuconfig`.
3. Flash bővítés **16MB**-ra (Winbond **W25Q128**) + RAM 64MB, és újabb OpenWRT
   (ath79, pl. 24.10) egyedi partíciós/DTS layouttal.

## Előfeltétel

- Rootless **Podman** a hoston (`podman --version`).
- A scriptek automatikusan felismerik, ha a VS Code **Flatpak** termináljából futnak,
  és olyankor `flatpak-spawn --host podman`-t használnak. Host-terminálból sima
  `podman`-nal mennek.
- Lemez: ~10 GB a `src/`-nek. Első build: kb. 20–60 perc (CPU-tól függ).

## Használat

```bash
cd ~/Documents/openwrt-wr941nd

# 1) Konténer-image megépítése (egyszer, ill. ha a Containerfile változik)
./scripts/img-build.sh

# 2) Firmware fordítása (forrásklón + feeds + defconfig + build)
./scripts/fw-build.sh
#   JOBS=4 ./scripts/fw-build.sh          # kevesebb párhuzamos job
#   OPENWRT_TAG=v19.07.10 ./scripts/fw-build.sh   # másik tag (3. fázis)

# címkézett kimeneti mappa (nem írja felül a korábbit)
BUILD_LABEL=ap-only ./scripts/fw-build.sh

# 3) Interaktív shell a konténerben (pl. csomagok kivétele a 2. fázisban)
./scripts/shell.sh
#   majd: cd openwrt && make menuconfig
```

### Eredmény
A build a friss image-eket a forrásfából **automatikusan átmásolja egy címkézett,
nem felülíródó almappába**:
```
firmware/built/<címke>/
  openwrt-ar71xx-tiny-tl-wr941nd-v4-squashfs-factory.bin
  openwrt-ar71xx-tiny-tl-wr941nd-v4-squashfs-sysupgrade.bin
  openwrt-ar71xx-tiny-device-tl-wr941nd-v4.manifest
```
- A `<címke>` alapból `<verzió>-<időbélyeg>` (pl. `18.06.9-20260601-224500`), vagy add
  meg magad: `BUILD_LABEL=ap-only ./scripts/fw-build.sh`. Így **minden build megmarad**,
  egy következő nem írja felül az előzőt.
- A **factory.bin** a gyári TP-Link webfelületről történő első telepítéshez.
- A **sysupgrade.bin** egy már OpenWRT-t futtató eszköz frissítéséhez (LuCI / `sysupgrade`).
- A gyári-ekvivalens 18.06.9 build itt van: `firmware/built/18.06.9-stock-equivalent/`.

## Felépítés

| Fájl | Szerep |
|------|--------|
| [Containerfile](Containerfile) | Debian bullseye + OpenWRT 18.06 build-függőségek, `builder` user |
| [config/wr941nd-v4-18.06.seed.config](config/wr941nd-v4-18.06.seed.config) | Seed `.config` (target+subtarget+profil); a `make defconfig` egészíti ki |
| [scripts/img-build.sh](scripts/img-build.sh) | Konténer-image build |
| [scripts/fw-build.sh](scripts/fw-build.sh) | Teljes, idempotens firmware build a konténerben |
| [scripts/shell.sh](scripts/shell.sh) | Interaktív shell (menuconfig, hibakeresés) |
| [scripts/_inner-build.sh](scripts/_inner-build.sh) | A konténeren belül futó build-logika |
| [scripts/_common.sh](scripts/_common.sh) | Podman-detektálás (host vagy flatpak) |
| `firmware/` | Bináris gyűjtő (nem verziókezelt): `stock/` = gyári/ref dumpok, `built/<címke>/` = az általunk fordított image-ek, buildenként külön mappában |

## Megjegyzések

- **„Ugyanaz a FW”** itt *funkcionálisan azonosat* jelent: ugyanaz a verzió (18.06.9),
  target (`ar71xx`), subtarget (`tiny`), profil (`tl-wr941nd-v4`) és az alapértelmezett
  csomagkészlet. A **bit-pontos** egyezéshez a toolchain és az időbélyegek pinnelése is
  kellene (reproducible build), ami nem cél ebben a fázisban.
- A buildroot **nem fordít root-ként** — ezért `--userns=keep-id` + nem-root `builder`
  user. A `src/`-be írt fájlok a hoston a te uid-eddel (`attila`) jönnek létre.
- A `src/openwrt/dl/`, `build_dir/`, `staging_dir/` a `src/`-ben marad, így az
  újrafordítás gyors (a letöltött forrásokat és a lefordított toolchaint újrahasználja).

## 3. fázis — 16MB flash (W25Q128) — vázlat

- A jelenlegi chip helyére **Winbond W25Q128** (16MB) kerül. A flash-t ki kell olvasni
  (flashrom + CH341A vagy Raspberry Pi + SOIC-csipesz), és **meg kell őrizni** az
  `u-boot` (0x0) és az **ART/kalibrációs** partíciót (a WiFi rádió kalibrációja eszköz-
  egyedi!).
- Mai OpenWRT-ben a WR941ND a **`ath79`** targetre került. A 16MB-os flashhez a
  készülék **DTS**-ében (device tree) kell átírni a partíciós layoutot (a firmware/
  rootfs partíció felső határát kitolni 16MB-ig, az ART-ot a flash végére igazítani).
- 16MB flash + 64MB RAM mellett a „4MB/32MB nem elég” figyelmeztetés megszűnik, így
  futtatható **mai** OpenWRT (pl. 24.10). Ehhez ebben a környezetben elég az
  `OPENWRT_TAG`-et átállítani és a DTS-patcht a forrásfába tenni.
