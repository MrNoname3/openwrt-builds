# OpenWRT build környezet — TP-Link TL-WR941ND v4

Podman-alapú, **rootless**, konténerizált OpenWRT buildroot a TL-WR941ND **v4**
routerhez (Atheros AR7240, `ar71xx` target, `tiny` subtarget).

A hostra **semmit nem telepítünk** — minden ebben a mappában és a Podman saját
konténer-tárolójában él.

> ⚠️ **Fontos — a build-fa NEM ebben a mappában van.** A teljes OpenWRT forrás-/build-fa
> ~9 GB és 300 000+ apró fájl. Mivel ez a `Documents` mappa egy **szinkronizált
> felhő-Drive** alatt van, a build-fa **szándékosan kívül** lakik:
> `~/.local/share/openwrt-wr941nd/src` (a `.local/share` nincs a Drive alatt).
> Így a Drive **csak a kis, fontos fájlokat és a végleges binárisokat** (`firmware/`)
> szinkronizálja. A helyét a `OPENWRT_SRC` környezeti változóval bárhová átteheted:
> `OPENWRT_SRC=/path/to/src ./scripts/fw-build.sh`.

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

### Build variánsok és a kernel-tanulság

Másik seed-configgal másik image-et építhetsz a `SEED_FILE` változóval:
```bash
SEED_FILE=wr941nd-v4-18.06-ap.seed.config BUILD_LABEL=ap ./scripts/fw-build.sh
```

> ⚠️ **Kernel-tanulság.** Ha egy seed olyan csomagot ad/vesz ki, ami **kernel-modult**
> (`kmod-*`) érint (pl. `iptables`/`firewall` eltávolítása → netfilter kmod-ok kiesnek),
> az megváltoztatja a kernel VERMAGIC-ot. Egy már megépített fában ettől a kernel-csomag
> deszinkronizálódik az opkg-tól, és a `package/install` elhasal: *„Cannot satisfy …
> kernel (= <hash>)"*. Ilyenkor add hozzá a `CLEAN=kernel`-t (kernel + kmod-ok tiszta
> újrafordítása) vagy `CLEAN=all`-t (teljes clean, a toolchain marad):
> ```bash
> CLEAN=kernel SEED_FILE=valami.seed.config ./scripts/fw-build.sh
> ```
> Ezért a **pragmatikus AP** seed szándékosan NEM nyúl egyetlen kmod-hoz sem — csak
> userspace daemont vesz ki (dnsmasq, odhcpd) —, így a kernel változatlan és a build stabil.

## Felépítés

| Fájl | Szerep |
|------|--------|
| [Containerfile](Containerfile) | Debian bullseye + OpenWRT 18.06 build-függőségek, `builder` user |
| [config/wr941nd-v4-18.06.seed.config](config/wr941nd-v4-18.06.seed.config) | Seed `.config` — **gyári-ekvivalens** (LuCI + xt_CT); `make defconfig` egészíti ki |
| [config/wr941nd-v4-18.06-ap.seed.config](config/wr941nd-v4-18.06-ap.seed.config) | Seed `.config` — **pragmatikus AP** (gyári mínusz dnsmasq/odhcpd; kernel változatlan) |
| [scripts/img-build.sh](scripts/img-build.sh) | Konténer-image build |
| [scripts/fw-build.sh](scripts/fw-build.sh) | Teljes, idempotens firmware build a konténerben |
| [scripts/shell.sh](scripts/shell.sh) | Interaktív shell (menuconfig, hibakeresés) |
| [scripts/clean.sh](scripts/clean.sh) | A (Drive-on kívüli) build-fa teljes kitakarítása, megerősítéssel; `--image`-dzsel a konténer-image is |
| [scripts/router-backup.sh](scripts/router-backup.sh) | A futó router flash-partícióinak mentése SSH-n (3× ellenőrzéssel); `firmware/router-backup/<ts>/` |
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

## Router mentés (SSH, chip-kiolvasás nélkül)

A `scripts/router-backup.sh` a futó eszközről menti az `mtd` partíciókat (olvasás
non-destruktív), 3× lefuttatva és sha256-tal összevetve; ha egyeznek, egy készletet tart meg.
```bash
./scripts/router-backup.sh                 # tplink-router, firmware/router-backup/<ts>/
./scripts/router-backup.sh my-host /út      # más host/cél
RUNS=5 ./scripts/router-backup.sh           # több ellenőrző menet
```
Régi dropbearhez a `~/.ssh/openssl-allow-sha1.cnf` megléte esetén automatikusan engedi a
SHA-1-et (lásd [`ssh-legacy`](#) wrapper). A jelenlegi eszköz feltérképezve:

- **Flash chip:** Winbond **W25Q32** (4 MB) → a cél **W25Q128** (16 MB), ugyanaz a család.
- **Partíciók (4 MB):** `u-boot` @0x000000 (128K) · `firmware`=kernel+rootfs @0x020000 (≈3,99 MB)
  · `art` @0x3F0000 (64K). A `firmware` átfedi a `kernel`+`rootfs` nézeteket.
- Az **`art`** (kalibráció) **eszköz-egyedi** — a 16MB-os chipre a végére (0xFF0000) kell.

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

## CI — automatikus build GitHub Actions-szel

A repo (privát, `MrNoname3/openwrt-builds`) CI-je **ugyanazt a buildet** futtatja a
felhőben, mint a helyi `scripts/build-16m.sh`: ugyanaz a `Containerfile.modern`
konténer, ugyanaz a `_inner-build-16m.sh`, ugyanaz a seed. Így a helyi podman-build
és a CI-build kimenete közvetlenül összevethető (supply-chain keresztellenőrzés).

**Fájlok:**

- `ci/wr941nd-v4-16m.env` — az eszköz pinjei: `OPENWRT_TAG` (pontos OpenWRT release),
  `SEED_FILE`, `DEVICE_NAME`.
- `.github/workflows/build.yml` — a build: PR-en és `master` pushon fut, ha
  build-releváns fájl változik (`ci/`, `config/`, `scripts/`, `Containerfile.modern`).
  `master`-ön sikeres build után **Release**-t publikál
  (`<tag>-wr941nd-v4-16m`, benne factory + sysupgrade + manifest + SHA256SUMS).
  A **FULLFLASH szándékosan nem** készül CI-ben: ahhoz az eszköz-egyedi
  u-boot/art dump kell (MAC-kel), ami csak a helyi backupban él.
- `.github/workflows/check-openwrt-release.yml` — hetente (hétfő 06:17 UTC) nézi az
  OpenWRT tag-eket:
  - **azonos sorozaton belüli** új kiadás (pl. v25.12.4 → v25.12.5): PR-t nyit a
    bumppal, és elindítja rá a buildet → a PR maga a kanári, merge után jön a Release;
  - **új sorozat** (pl. v26.x): csak **issue**-t nyit — sorozatváltás előtt kézi
    DTS/seed-ellenőrzés kell (lásd a 24.10 → 25.12 nvmem-layout törést).

**Frissítési folyamat:** bump-PR érkezik → Actions fül: zöld a branch-build? →
merge → Release → a sysupgrade image letöltése, SHA256 ellenőrzés →
`sysupgrade` a routeren (beállítások megtartásával).

**Egyszeri repo-beállítás:** Settings → Actions → General →
„Allow GitHub Actions to create and approve pull requests" bekapcsolása
(enélkül a bump-PR létrehozása hibára fut).

**Korlátok:** privát repónál havi 2000 ingyenes Actions-perc van; egy teljes build
~2–3 óra (≈120–180 perc), tehát havi néhány build bőven belefér. A `dl/` cache-elve
van, a toolchain minden futáskor újrafordul.

## Üzemeltetés / hibakeresés (telepített AP)

### Spontán újraindulás soros konzol + SysRq miatt (FONTOS)

Tünet: az AP **magától újraindul** (a `dmesg`/`logread` csak
`Watchdog has previously reset the system`-et mutat, **nincs** OOM/panic/crash). Az
újraindulás jellemzően a soros adapterhez köthető — vagy a **be-/kihúzáskor**, vagy ha a
beforrasztott soros **pinheader üresen, csatlakoztatás nélkül a panelen marad**.

Ok: a kernel `console=ttyS0,115200`-val fut, és a **SysRq alapból engedélyezett**
(`/proc/sys/kernel/sysrq = 1`). Egy **lebegő/zajos soros vonal** (üres header, vagy
hot-unplug) **BREAK jelet** generálhat, amit a kernel **SysRq-parancsnak** értelmez
(reboot/crash/hang). A `wmac`/AR7240 watchdog (timeout **30 mp**, etetés 5 mp-enként)
ilyenkor ~25–30 mp múlva resetel, ha a rendszer beragadt.

Megoldás (alkalmazva a telepített eszközön, perzisztens a `/etc/sysctl.conf`-ban):
```sh
# runtime + perzisztens
echo 0 > /proc/sys/kernel/sysrq
echo 'kernel.sysrq=0' >> /etc/sysctl.conf
```
Ez headless AP-n **hátrány nélküli** (a SysRq csak debug-funkció; a soros konzol
**kimenete** továbbra is megy). Ha valaha SysRq-debug kell, ideiglenesen vissza:
`echo 1 > /proc/sys/kernel/sysrq`.

Továbbá: a soros adaptert **csak áramtalanított panelnél** dugd/húzd, vagy ha menet közben
muszáj, a **GND-t kösd be elsőnek és húzd ki utolsónak**, a 3,3 V/TX vezetéket ne mozgasd
(a megosztott tápon keletkező tranziens szintén watchdog-resetet okozhat).

### RAM (32 MB) — szűkös, de elég

24.10 + LuCI + 802.11r mellett ~7 MB szabad RAM. Nincs OOM, de kevés a tartalék; ha több
fejhely kell, az **AP-only csomag-strip** (LuCI/uhttpd/ppp eltávolítása) felszabadít pár MB-ot.
