# Custom device definition for the 16MB-flash TL-WR941ND v4.
# Appended to target/linux/ath79/image/tiny-tp-link.mk by scripts/_inner-build.sh.
#
# The stock u-boot can only gunzip, so the image uses the okli loader
# (Device/tplink-nolzma): u-boot starts a small gzip loader, which decompresses
# the lzma kernel. TPLINK_FLASHLAYOUT 16M is the okli-compatible 16 MB layout.

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
  # Deliberately the stock names: the modded board still reports them, so
  # sysupgrade needs them -- and a stock 4 MB device accepts the image too, and
  # bricks (see the README's warning).
  SUPPORTED_DEVICES += tplink,tl-wr941-v4 tl-wr941nd-v4 tl-wr741nd
endef
TARGET_DEVICES += tplink_tl-wr941-v4-16m
