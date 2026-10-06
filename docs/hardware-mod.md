# TL-WR941ND v4 hardware mod: 4→16 MB flash, 32→64 MB RAM

This is the full guide for upgrading a TP-Link TL-WR941ND **v4** (Atheros
AR7240 @ 400 MHz, ath9k `pci168c:002a` radio) so it can run **current
OpenWrt** (25.12, kernel 6.12). Stock hardware — 4 MB SPI flash, 32 MB RAM —
stopped being usable after OpenWrt 18.06/19.07.

Both mods are **required** for the images this repo builds:

| Mod | Stock | Upgraded | Why required |
|-----|-------|----------|--------------|
| SPI flash | 4 MB Winbond W25Q32 (SOIC-8) | 16 MB W25Q128-class (this unit: XTX XT25F128B) | the 16M image does not fit in 4 MB |
| RAM | 32 MB | 64 MB (single ×16 DDR1 chip) | kernel 6.12 + LuCI on 32 MB OOM-reboots constantly (verified on this unit) |

While the board is open, consider **recapping** too (this unit: 5× 470 µF/16 V).

## The one fact everything revolves around

Two regions of the original flash are **device-unique and irreplaceable**:

| Region | Stock 4 MB location | New 16 MB location | Contents |
|--------|--------------------:|-------------------:|----------|
| `u-boot` | `0x000000` (128 KiB) | `0x000000` (unchanged) | bootloader **+ the device MAC** |
| `art` | `0x3F0000` (64 KiB, *last* 64K of 4 MB) | `0xFF0000` (*last* 64K of 16 MB) | WiFi radio calibration |

`art` always lives in the **last 64 KiB of the chip**, so on the bigger chip it
**moves** — this is why a plain 1:1 copy of the old chip onto the new one would
not work, and why the custom DTS exists. Lose `art` and the WiFi is gone for
good; flash another unit's dump and you inherit its MAC and mis-calibration.

## Step 1 — dump the original flash

Do it **before touching anything**, ideally both ways:

**a) Over SSH from the running router** (no soldering):

```bash
./scripts/router-backup.sh          # host alias + destination are parameters
```

It reads every `mtd` partition 3× and cross-checks sha256 (`RUNS=5` for more
passes). Output lands in `firmware/router-backup/<timestamp>/`, one file per
partition — the two that matter later:

```
mtd0_u-boot.bin   (128 KiB)
mtd4_art.bin      ( 64 KiB)     # partition number may differ per firmware
```

**b) Chip-off with a programmer** (CH341A + SOIC-8 clip, or Raspberry Pi):

```bash
flashrom -p ch341a_spi -c W25Q32.V -r dump1.bin
flashrom -p ch341a_spi -c W25Q32.V -r dump2.bin
cmp dump1.bin dump2.bin            # two reads must be identical
```

> ⚠️ Cheap CH341A clones drive the data lines at **5 V** — fine for a one-off
> read of a chip that is being replaced anyway, but do the 3.3 V mod (or use a
> known-good programmer) before writing the **new** chip with it.

## Step 2 — build the 16 MB firmware

```bash
JOBS=4 ./scripts/build.sh          # see the README for details
```

Output in `firmware/built/16m-<version>/`. Two image types come out of the
OpenWrt recipe:

- `...-squashfs-factory.bin` — the full firmware-partition payload, **padded to
  0xFD0000**. Despite the name it can NOT be installed from the stock TP-Link
  web UI (stock firmware only exists on 4 MB chips); here it serves as the
  building block for the full-chip image.
- `...-squashfs-sysupgrade.bin` — for updating a router **already running** a
  16M build (LuCI or `sysupgrade`, settings kept). This is what you use for
  every update after the initial chip swap.

## Step 3 — assemble the full-chip image (FULLFLASH)

`scripts/build.sh` does this automatically when a backup exists under
`firmware/router-backup/`:

```
0x000000  mtd0_u-boot.bin      (128 KiB, from YOUR backup)
0x020000  ...-factory.bin      (0xFD0000)
0xFF0000  mtd*_art*.bin        ( 64 KiB, from YOUR backup)
gaps      0xFF                 (erased-flash filler)
```

Result: `firmware/built/16m-<version>/full16-wr941nd-v4.bin` (exactly 16 MiB)
plus `SHA256SUMS`. This file is device-specific — it is deliberately never
built in CI and never published in releases.

## Step 4 — write the new chip

```bash
flashrom -p ch341a_spi -c XT25F128B -w full16-wr941nd-v4.bin   # -c per your chip
```

Pass the chip name flashrom detects, not the one printed on the package:
cheap W25Q128 parts are often relabelled clones (this unit's chip, labelled
Winbond 25Q128JVSQ, identifies as XTX XT25F128B). flashrom flags that chip's
write protection as untested, which does not matter here. A new chip should
read back as all `0xFF`.

`flashrom -w` verifies after writing; for extra certainty read it back and
compare:

```bash
flashrom -p ch341a_spi -c XT25F128B -r readback.bin
cmp full16-wr941nd-v4.bin readback.bin
```

Then solder the chip in (SOIC-8; hot air or drag soldering).

## Step 5 — RAM swap

The AR7240 supports 64 MB as a single ×16 DDR1 chip; u-boot on this unit
detected the new size with **no firmware/u-boot change** ("DRAM: 64 MB").

Lesson from this unit: after the swap the boot **hung right after the
`DRAM: 64 MB` line** with corrupted serial output — a bad joint on an address
line. Rework every pin if boot stalls there; after re-soldering it booted
cleanly.

## Step 6 — first boot & checks

A serial console (soldered header, 115200 8N1) is essentially mandatory for
this stage — but read the [SysRq warning](operations.md#spontaneous-reboots-from-the-serial-consoles-sysrq)
before leaving the header attached.

The AR7240's UART TX line is driven weakly: without help the output is garbled
and the console takes no input. Pull the board's TX up to its 3.3 V pin through
a resistor (10–22 kΩ; lower values give cleaner output). Wire board TX → adapter
RX, board RX → adapter TX and a common GND, and power the router from its own
supply — never connect the adapter's VCC to the board.

Expected: u-boot banner → `DRAM: 64 MB` → kernel boot → OpenWrt on
`192.168.1.1` (fresh config). u-boot prints `Flash: 04 MB` because its chip
table does not know the new part; that is harmless, since it only reads the
kernel from the first 4 MB. The very first boot takes about 1.5 minutes while
the overlay is created. Verify:

```
free            # ~59 MB total
df -h /overlay  # ~10 MB overlay
iwinfo          # radio up (art OK)
```

Then configure, or restore a config backup.

## Updating later

After the initial swap you never need the programmer again: every new release
from this repo is flashed with the **sysupgrade** image (settings kept). The
FULLFLASH path exists only for the initial swap and for disaster recovery.

> ⚠️ The board still reports `tplink,tl-wr941-v4`, so **never** use official
> OpenWrt images or attended sysupgrade — their profile targets the stock 4 MB
> layout and would brick the device.
>
> ⚠️ The same compat string forces this repo's device definition to claim
> `tplink,tl-wr941-v4` in `SUPPORTED_DEVICES`, which means the check runs in
> **both** directions: these images also install on a *stock* 4 MB device (or a
> `tl-wr741nd`) without `--force`, and brick it. Never hand a build from here to
> someone with an unmodded router.
