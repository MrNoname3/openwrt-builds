# Custom device definition for the 16MB-flash TL-WR941ND v4.
# Appended to target/linux/ath79/image/tiny-tp-link.mk by scripts/_inner-build.sh.
#
# IMPORTANT: this device's stock u-boot can only gunzip, NOT decompress lzma
# (confirmed: the stock booting kernel is the gzip okli loader). So we MUST use
# the okli path (Device/tplink-nolzma): u-boot boots the small gzip okli loader,
# which then decompresses the real lzma kernel. We pair it with the "16M"
# flash layout (okli-compatible: rootfs_ofs 0x140000, fw_max_len 0xf80000) and
# our 16MB DTS. (A plain tplink-16mlzma image would NOT boot here.)

define Device/tplink_tl-wr941-v4-16m
  $(Device/tplink-nolzma)
  SOC := ar7240
  DEVICE_MODEL := TL-WR941ND
  DEVICE_VARIANT := v4 (16M)
  DEVICE_DTS := ar7240_tplink_tl-wr941-v4-16m
  TPLINK_HWID := 0x09410004
  TPLINK_FLASHLAYOUT := 16M
  IMAGE_SIZE := 16192k
  DEVICE_PACKAGES := kmod-ath9k wpad-basic-mbedtls
  # DANGER: this list is deliberately WIDE. sysupgrade uses SUPPORTED_DEVICES for
  # its compatibility check, and the modded board still reports the stock
  # compat string -- so the 16M image must claim tplink,tl-wr941-v4 to be
  # installable here at all. The side effect: a STOCK 4MB device (or even a
  # tl-wr741nd) running official OpenWrt will accept this sysupgrade image
  # WITHOUT --force and brick itself. The image is only ever safe on a board
  # with both mods; nothing in the tooling will stop a wrong flash.
  SUPPORTED_DEVICES += tplink,tl-wr941-v4 tl-wr941nd-v4 tl-wr741nd
endef
TARGET_DEVICES += tplink_tl-wr941-v4-16m
