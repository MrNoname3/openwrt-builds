# TL-WR941ND v4 hardware mod: 4→16 MB flash, 32→64 MB RAM

This documents the hardware upgrade that makes a TP-Link TL-WR941ND **v4**
(Atheros AR7240 @ 400 MHz, ath9k `pci168c:002a` radio) capable of running
**current OpenWrt** (25.12, kernel 6.12). Stock hardware — 4 MB SPI flash,
32 MB RAM — stopped being usable after OpenWrt 18.06/19.07.

Both mods are **required** for the images this repo builds:

| Mod | Stock | Upgraded | Why it is required |
|-----|-------|----------|--------------------|
| SPI flash | 4 MB (Winbond W25Q32, SOIC-8) | 16 MB W25Q128-class (this unit: XTX XT25F128B) | the 16M image simply does not fit in 4 MB |
| RAM | 32 MB | 64 MB (single DDR1 chip, ×16 organization) | kernel 6.12 + LuCI on 32 MB OOM-reboots constantly (verified on this unit before the RAM mod) |

While the board is open, also consider **recapping**: this unit's aging
electrolytics were replaced with 5× 470 µF/16 V — a common failure item on
routers of this age.

## Flash layout (16 MB)

```
0x000000  u-boot    128 KiB   device-specific (contains the MAC!)
0x020000  firmware  0xFD0000  kernel (OKLI/lzma) + squashfs rootfs + overlay
0xFF0000  art        64 KiB   radio calibration -- DEVICE-UNIQUE, irreplaceable
```

The custom DTS (`config/ath79-24.10/ar7240_tplink_tl-wr941-v4-16m.dts`) and
device definition (`tplink_tl-wr941-v4-16m.device.mk`) describe this layout;
the build injects them into a stock OpenWrt tree (`scripts/_inner-build-16m.sh`).

## Procedure (flash)

1. **Back up the original flash before touching anything.** Two independent
   ways, do both if possible:
   - live router over SSH: `scripts/router-backup.sh` (reads all `mtd`
     partitions 3× and cross-checks sha256);
   - desoldered chip in a CH341A (or Raspberry Pi + SOIC clip) with
     `flashrom`.
2. Build the 16 MB firmware: `./scripts/build.sh` (see the README).
3. Assemble the full 16 MB flash image — `scripts/build-16m.sh` does this
   automatically when a backup exists under `firmware/router-backup/`:
   your original **u-boot** at 0x0, the built firmware at 0x20000, your
   original **art** at 0xFF0000, gaps 0xFF-filled.
4. Write the new chip: `flashrom -p ch341a_spi -c <chip> -w full16-....bin`,
   then read back and verify.
5. Solder the new chip in (SOIC-8; hot air or drag soldering).

> ⚠️ **The art partition is device-unique radio calibration and the u-boot
> dump contains the device MAC.** Never flash another device's dump; if you
> lose art, the WiFi is gone for good. This is also why the FULLFLASH image
> is never published in CI releases — only factory/sysupgrade images are.

## Procedure (RAM)

The AR7240 supports 64 MB with a single ×16 DDR1 chip; u-boot on this unit
detected the new size without any modification ("DRAM: 64 MB").

Lesson from this unit: after the swap the router **hung right after the
`DRAM: 64 MB` line** with corrupted serial output — a bad joint on an address
line. Rework every pin if boot stalls there; after re-soldering it booted
cleanly. A serial console (soldered header, 115200 8N1) is essentially
mandatory for diagnosing this stage — and read the README's SysRq warning
before leaving the header attached.

## After the mod

- 25.12 runs comfortably: ~19 MB free RAM + ~17 MB cache with LuCI, HTTPS,
  802.11r on a dumb-AP config; zram is deliberately NOT used (400 MHz CPU).
- The board still reports `tplink,tl-wr941-v4`, so **never** use official
  OpenWrt images or attended sysupgrade — their profile targets the stock
  4 MB layout and would brick the device. Upgrade only with this repo's
  `-sysupgrade.bin` images (settings survive) or full reflash via CH341A.
