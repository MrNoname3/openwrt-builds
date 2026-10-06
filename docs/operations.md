# Running the modded AP

How the 16 MB / 64 MB unit is set up, updated and debugged. The lessons here
come from running it in production as a *dumb AP*: a bridge between the WiFi
and the wired LAN, with routing, DHCP and DNS left to the main router.

## Dumb-AP configuration

A first boot comes up with OpenWrt defaults (`192.168.1.1`, DHCP server on).
To turn it into a dumb AP:

- **LAN as DHCP client**: `network.lan.proto=dhcp`, with a static lease on
  the main router.
- **Bridge the WAN port too**: add the WAN port's device (`eth0` on this
  board; the four LAN ports are `eth1.1`) to `br-lan`, so every port is a
  switch port. Pin `macaddr` on `br-lan` to keep the main router's lease stable.
- **No DHCP/RA, ever**: disable the `dnsmasq` and `odhcpd` services **and** set
  `dhcp.lan.ignore=1` (dropping the `dhcpv4`/`dhcpv6`/`ra` options). Disabling
  only the services leaves a config that serves DHCP the moment a service is
  re-enabled.
- **Firewall off**: on a pure bridge it adds nothing (the default lan zone
  accepts input, and there is no wan zone member to masquerade), while an
  input-restricting ruleset risks locking you out. Protect management instead:
  key-only SSH, HTTPS-only LuCI.
- **HTTPS-only LuCI** works out of the box: the seed bakes in
  `libustream-mbedtls` + `px5g-mbedtls`, which generate a self-signed
  certificate. Remove uhttpd's `listen_http` to drop port 80.
- **802.11r (fast transition)** is stable on 64 MB. To roam with another
  OpenWrt AP, use the same SSID, key and `mobility_domain`, set
  `ft_psk_generate_local=1` and `ft_over_ds=0` on both, and give each AP its
  own `nasid`.

## Updating

1. Take a config backup and copy it off the device: `sysupgrade -b /tmp/b.tar.gz`.
2. Download the `-sysupgrade.bin` from the Release and check it against
   `SHA256SUMS`.
3. Flash with **settings kept** — from LuCI, or over SSH. Dropbear has no
   scp/sftp, so upload through a pipe:
   ```sh
   cat fw-sysupgrade.bin | ssh root@<ap> 'cat > /tmp/fw.bin'
   ssh root@<ap> 'sha256sum /tmp/fw.bin && sysupgrade -v /tmp/fw.bin'
   ```
4. Wait. The first boot after a sysupgrade takes **5–6 minutes** while the
   overlay is rebuilt and the config migrated; the system LED blinks
   throughout. Do not power-cycle. Normal reboots take about 90 s.

Things that do not survive a sysupgrade with this custom image:

- **Packages installed live with `apk`.** Anything the device needs long-term
  goes into the seed. Kernel modules cannot be added live at all: the kernel
  hash of a custom build matches no official repository.
- **Files you add** (scripts in `/usr/bin`, edited `/etc/rc.button/*`) unless
  they are listed in `/etc/sysupgrade.conf`.

Rolling back: flash an earlier Release's sysupgrade image, restore the config
backup, or — as the last resort — write the FULLFLASH image with the programmer.
Before going back to an image without Ed25519 support in dropbear
(`CONFIG_DROPBEAR_ED25519`), put an RSA key into `authorized_keys`, or an
Ed25519-only login locks you out.

## Messages that are harmless

| Where | Message | Why it is fine |
|-------|---------|----------------|
| u-boot | `Flash: 04 MB` | u-boot's chip table does not know the 16 MB part; it only reads the kernel from the first 4 MB, and Linux sees the whole chip |
| kernel | `OF: Bad cell count for .../partitions` | generic device-tree address-translation noise, also on stock TP-Link ath79 boards |
| kernel | `force read-only` on `kernel`/`rootfs` | inherent to the TP-Link firmware split; the writable `rootfs_data` is aligned |
| ath9k | `Ignoring endianness difference in EEPROM` | the calibration was read from `art` correctly |
| hostapd | `nl80211: kernel reports: key addition failed` on FT reassociation | a key-cleanup race seen on other OpenWrt APs too; the client connects |
| hostapd | periodic deauth for inactivity + FT reconnects of one client | a client that keeps WiFi associated while on Ethernet; nothing to fix on the AP |
| logs | wrong timestamps early in boot | the board has no RTC; time is right once NTP syncs |

Readings that mislead:

- LuCI's memory bar counts reclaimable cache as used. `MemAvailable` in
  `/proc/meminfo` is the honest figure.
- TX power stays at 17 dBm even when 20 dBm is requested: that is the AR9280's
  calibrated per-rate ceiling, not a regulatory limit.
- After `wifi down; wifi up` it takes about 12 s before `phy0-ap0` exists again;
  readings taken sooner show stale or missing state.

## Pitfalls

### Spontaneous reboots from the serial console's SysRq

Symptom: the AP **reboots on its own**; `logread` only shows
`Watchdog has previously reset the system`, with no OOM, panic or crash —
typically around plugging or unplugging the serial adapter, or with the
soldered serial header left unconnected.

Cause: the kernel runs with `console=ttyS0,115200` and SysRq enabled. A
floating or noisy serial line produces a BREAK, which the kernel takes as a
SysRq command; the AR7240 watchdog (30 s) then resets the stuck system.

Fix (no downside on a headless AP; serial output keeps working):

```sh
echo 0 > /proc/sys/kernel/sysrq
echo 'kernel.sysrq=0' >> /etc/sysctl.conf
```

Plug and unplug the serial adapter only with the board powered off, or connect
GND first and disconnect it last.

### Why 32 MB RAM is not enough

On the stock 32 MB, 24.10 with LuCI and 802.11r left about 7 MB free, and the
unit rebooted through the watchdog under management load (an SSH login or a
LuCI page was enough) and with 802.11r on. 25.12 did not run at all. zram swap
made it worse: on the 400 MHz CPU, swap-in stalls hit timing-critical hostapd
pages. With 64 MB the same configuration, 802.11r included, is stable, so the
seed carries no zram.

### LEDs

The power LED is wired to the supply rail and cannot be switched in software;
every other LED is under `/sys/class/leds/`. `/etc/init.d/led restart` restores
the triggers configured in `/etc/config/system`.
