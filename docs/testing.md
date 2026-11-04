# Testing

## Automated (CI and `tests/run.sh`)

`tests/modectl.sh` runs `modectl` in an OpenWrt 25.12.6 rootfs container
with the real uci, jsonfilter, lock and config_generate, on a TL-WR902AC v3
`board.json`.  Only `reload_config`, `slide-switch` and `logger` are stubs.
It covers:

- first use: the base configuration is saved, then the profile is built
  from the template;
- the defaults of every position (addresses, DHCP, rebind protection,
  trunk VLANs, SSIDs);
- automatic saving, and switching between the positions and back;
- the wired port role: joining a Wi-Fi network, disabling the STA, a
  disabled radio, a pending LuCI apply, uncommitted changes;
- `put` (rejecting invalid syntax, storing into an inactive profile),
  `reset` (a failing template keeps the old profile), `follow`, and the JSON
  status;
- the 2.3.0 configuration migration;
- no uci changes left behind in `/tmp/.uci`.

`scripts/lint.sh` runs shellcheck as busybox ash, a syntax check of the
LuCI JavaScript, and JSON validation.  CI also applies the patches to the
pinned release and builds the packages with the SDK.

## On hardware

All on a TL-WR902AC v3 with this build:

| Area | Test | Result |
|---|---|---|
| Home | VLAN trunk against tagged VLANs on the bench: SSIDs to their VLANs (SAE + PMF), management only on its VLAN | as configured; no frames crossed VLANs |
| Home | as the access point of a network with these VLANs, in daily use | stable |
| AP | DHCP for an Android phone over Wi-Fi and a wired client | leases from 192.168.50.0/24 |
| RNDIS | an Android phone (CDC-NCM) as the uplink | WAN up, NAT and DNS work, 79 Mbit/s download on a LAN client |
| Mode switch | real switch moves, `follow off`, profiles kept over sysupgrade | as designed |
| LuCI | Mode Switch page at desktop and phone width, editor, apply, follow toggle, header indicator | no JavaScript errors |
| AP, cable uplink | the router took a DHCP lease on the wired port; a Wi-Fi client reached the upstream through NAT | as configured |
| AP, captive portal | fake portal upstream whose DNS answers with a private address; login from one Wi-Fi client | with rebind protection off: redirect, login page, login; afterwards the Android and Apple connectivity checks got 204, since the portal only sees the router's WAN address.  With it on: dnsmasq drops the answers ("possible DNS-rebind attack detected") and the portal never loads |
| AP, Wi-Fi uplink | STA joined to a WPA2 network on channel 6 (configured with uci, as LuCI's Join does) | wired port moved to LAN; the AP followed the uplink to channel 6; a wired LAN client reached the upstream through NAT: 58.6 Mbit/s up, 40.3 Mbit/s down |
| AP, wired port role | STA disabled through LuCI's RPC (`uci apply` with rollback) from a wired LAN client | the port stayed LAN until `uci confirm`, then became the uplink; the AP returned to its own channel |
| Repeater | 2.4 GHz uplink on a busy network (−53 dBm) | wired client 35.9 / 19.3 Mbit/s, Wi-Fi client 27.8 / 15.7 Mbit/s (down / up); the router CPU stayed under 50%, so the uplink was the limit |

Memory and stress tests are in [memory.md](memory.md).

### Known behaviour: Wi-Fi uplink configured but not in range

While a STA is configured and its network is not in range, OpenWrt 25.12
does not start the AP on the same radio.  The AP waits for the STA's
channel, and hostapd logs `handle_probe_req: send failed`.  The AP comes
back as soon as the STA associates, or when the STA is disabled.  In that
state the wired port is LAN (the Wi-Fi uplink is still configured), so the
device stays reachable by cable at 192.168.50.1.  Disable the Wi-Fi uplink
in LuCI when leaving its network.

## Not tested yet

- A real hotel captive portal (the fake one above follows the common
  redirect-and-login pattern).
- The router's own ceiling for Wi-Fi client → repeater → upstream: it needs
  an uplink faster than the ones tested.
- A 24-hour soak; memory was followed for 16 minutes only (−0.95 MB, mostly
  cache).
- mt76 #1166: an mt7603 watchdog hang after an MCU timeout on a channel
  change.  This matters for a repeater that follows its uplink's channel.
  Only a draft fix exists upstream.
