# Memory on a 64 MiB board

All numbers are from a TL-WR902AC v3 (58 MB usable RAM after the kernel).
The baseline is OpenWrt 24.10.1; the result is this build on 25.12.6.

## Why it rebooted

The kernel default `vm.watermark_boost_factor=15000` adds a 16 MB
watermark boost on top of `min_free_kbytes=8192`.  That raised the minimum
watermark to **24.5 MB**, so on a 58 MB system the OOM killer started while
**14.6 MB were still free**.  A UDP flood reproduced it: the OOM killer took
collectd, then hostapd (Wi-Fi down), then rpcd.  The reboots followed.

`files/etc/sysctl.d/20-lowmem.conf`:

- `vm.watermark_boost_factor=0`
- `vm.min_free_kbytes=2048` (Gluon uses the same value)
- the IP fragment thresholds of Gluon's 64 MB profile

This file alone raised MemAvailable by 12 MB.

## Where the memory went

Each change below was measured as the change in MemAvailable, with the rest
of the configuration fixed:

| Change | Gain | Where |
|---|---|---|
| watermark boost off, `min_free_kbytes` 2048 | +12.1 MB | `files/etc/sysctl.d/20-lowmem.conf` |
| squashfs blocks 1024 → 128 KiB | SUnreclaim −3.6 MiB, vmalloc −0.9 MiB | `config/diffconfig` |
| ralink ethernet DMA rings 1024 → 256 | +2.2 MB | patch 0001 |
| no collectd / statistics | +2.0 MB | `config/diffconfig` |
| 5 GHz driver not loaded | +0.9 MB (kept in the image; the radio is disabled in UCI instead) | — |
| printk buffer 128 → 16 KiB | +112 KiB | patch 0004 |
| mt76x02 RX ring 256 → 128 | 256 KiB per MT76x0E radio | patch 0002 |

Two more changes cap memory under load rather than at idle:

- **TXQ limit (patch 0003, `files/etc/hotplug.d/ieee80211/10-txq-limit`).**
  mac80211's default TXQ memory limit is 16 MiB for VHT radios, a quarter of
  the RAM.  The patch caps it at 1/32 of RAM (openwrt/openwrt#25733, for
  #25722).  The hotplug script sets 2 MiB per wiphy.
- **OOM priorities (patches 0006, 0007).**  procd gets `oom_score_adj` per
  instance.  hostapd, wpa_supplicant, netifd and dropbear are protected
  (−900), dnsmasq less so (−500), and uhttpd and rpcd go first (+500).  If
  memory ever runs out, the web UI dies, not Wi-Fi.

Kernel swap support stays, but there is no zram.  The CPU is at about 90%
at 100 Mbit/s, and swap cannot hold kernel or Wi-Fi memory anyway.

## Stress tests (this build)

| Test | Result |
|---|---|
| Memory hog with OOM score 0, growing to 60 MB | the hog was the first and only OOM victim; all services stayed up |
| Unkillable hog (−1000), 36 / 38 MB | MemAvailable down to 3.7 / 1.7 MB; no service died (page cache absorbed it) |
| Unkillable hog, 40 MB | SSH stopped answering; the device rebooted by itself and was back after about 1.5 min |
| conntrack flood, 15,000 new flows/s for 60 s | table full (8190/8192); services up, memory −3 MB; LuCI unusable during the flood, fine right after |
| 2,000 new flows/s with a full table | LuCI 25/25 requests answered, worst 0.74 s |
| everything at once for 90 s (bidirectional TCP, 30 Mbit/s UDP, 2,000 flows/s) | services up, no OOM, TXQ held at 2 MiB (907 drops); LuCI unresponsive meanwhile (softirq) |
| 10 min bidirectional TCP | 82 + 22 Mbit/s; no OOM, watchdog or BUG; PIDs unchanged |
| 40 Wi-Fi associate/disassociate cycles | 40/40, average 668 ms, worst 3.1 s |

A 40 MB unkillable allocation is not something the device meets in normal
use.

## LuCI over HTTPS

| | |
|---|---|
| Flash | about 7 KB (px5g-mbedtls; mbedtls is already in the image) |
| Certificate | ECDSA P-256, self-signed, generated within 1 s at first boot; TLS 1.3 |
| Handshake, idle | 74 ms average, 76 ms worst |
| Handshake under 100 Mbit/s bidirectional load | 263 ms average, 324 ms worst |
| RAM per connection | about 46 KB, freed on close |

## Ideas for upstream

- procd `oom_score_adj` (patch 0006) is generic.
- A lower `vm.watermark_boost_factor` default for small-RAM targets.
- small_flash forces 1024 KiB squashfs blocks, which costs about 3.6 MiB of
  RAM on 64 MiB boards (Gluon reported the same in 2020).
- 1024 ethernet descriptors are too many for a 10/100 port.
