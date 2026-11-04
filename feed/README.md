# feed: modeswitch and luci-app-modeswitch

Every position of the TL-WR902AC v3 mode switch gets its own `network`,
`wireless`, `firewall` and `dhcp` configuration.  The positions keep the
names `slide-switch` gives them; aliases are what LuCI, the logs and
`modectl` show.

| # | Position | Factory label | Alias | Default configuration |
|---|---|---|---|---|
| 1 | `share-eth` | Share ETH | **Home** | 2.4 GHz access point on a VLAN trunk.  The wired port carries the home, management, IoT and guest VLANs tagged (10/20/30/40 by default).  The management address is on its VLAN (192.168.20.2/24 by default).  The home and guest SSIDs (sae-mixed, 802.11k/v, guest isolated) are bridged to their VLANs.  No DHCP, no NAT: the upstream router does that. |
| 2 | `share-hotspot` | Mobile Hotspot | **AP** | Travel router.  The Wi-Fi AP and its own LAN (192.168.50.1/24 with DHCP) are always on.  The uplink is the wired port (DHCP, NAT), or a Wi-Fi network joined in LuCI, in which case the wired port is LAN (see [Wired port role](#wired-port-role)).  Captive portals work: DNS rebind protection is off and the uplink's DNS (`peerdns`) is used. |
| 3 | `ap` | AP | **RNDIS** | USB tethering.  An Android phone on USB (RNDIS or CDC-NCM, `usb0`) is the uplink; the wired port and Wi-Fi are the LAN (192.168.50.1/24, DHCP, NAT). |

The `position` sections of `/etc/config/modeswitch` hold the alias, the
label and the inputs of the defaults templates; their order is the physical
order.  `modectl` takes a position or an alias, case-insensitive
(`modectl apply home`).

## Model

- **Mode files.**  `modeswitch.main.files` (network, wireless, firewall,
  dhcp) belong to a position.  Everything else (system, uhttpd, dropbear,
  passwords) is shared and never touched.
- **The running configuration is the truth.**  The active position is
  configured on the usual LuCI pages, or with `uci commit` and
  `reload_config`.  A procd config trigger (`modectl save`) copies every
  committed change into the position's profile, `/etc/modes/<position>/`.
- **Moving the switch** saves the active profile, loads the target profile
  and lets procd apply it.  `/etc/modes/current` records the active
  position, so a switch moved while the device was off is handled at boot.
- **Other positions** are edited in LuCI (*System → Mode Switch → Edit…*):
  each mode file is shown twice, the running configuration (read-only) and
  the position's configuration (editable), with a button that copies the
  former into the latter.  `modectl put` checks the uci syntax before it
  stores a file and applies it if the position is active.
- **Defaults templates** (`/etc/modeswitch/defaults/<position>.sh`) only
  build a profile that does not exist yet, or rebuild one on *Reset*.  They
  run on a copy of the base configuration (`/etc/modes/_initial`) with a
  private uci change directory, so nothing leaks into `/tmp/.uci`.  The
  Home template needs `modeswitch.share_eth.home_key` and `guest_key` and
  refuses to build without them.
- Uncommitted changes to mode files are discarded, and logged, when the
  position changes.
- `/etc/modes/` survives sysupgrade; `/etc/config/modeswitch` is a
  conffile.

## Wired port role

A position with `option wired_role 'auto'` (AP by default) has no fixed
role for the wired port:

| Wi-Fi uplink configured | Wired port | Uplink |
|---|---|---|
| no | `wan` (DHCP client) | the cable |
| yes (an enabled STA on an enabled radio) | LAN, in `br-lan` | the Wi-Fi network (`wwan`) |

- The role follows the configuration, never the link state, so it does not
  flap when the Wi-Fi uplink drops.  Joining a network in LuCI (*Scan →
  Join*) makes the port LAN; disabling or deleting the STA makes it the
  uplink again.
- `modectl` checks the role after every configuration change and when a
  position is applied.
- While a LuCI apply waits for its rollback confirmation
  (`/var/run/rpcd/snapshot-files` is not empty), the port is not moved:
  that could cut the browser off and roll the change back.  The check runs
  once the apply is confirmed or rolled back.
- Uncommitted `network` changes block the move; this is logged.
- While the Wi-Fi uplink is configured but out of range, OpenWrt does not
  start the AP on the same radio (it waits for the STA's channel).  The
  wired port is LAN then, so the device stays reachable by cable.  Disable
  the uplink when leaving its network.

## modectl

```
modectl status [--json]               switch position, active position, profiles
modectl brief                         one-line JSON for the LuCI header indicator
modectl apply <position>              switch now (until the switch moves or the next boot)
modectl save                          save the running mode files into the active profile (automatic)
modectl put <position> <file> <path>  replace one file of a profile (syntax checked; applied if active)
modectl reset <position>              rebuild a profile from its defaults template (applied if active)
modectl set-base                      use the running configuration as the base for the templates
modectl follow on|off                 follow the hardware switch, or ignore it
modectl wired-role                    re-check the wired port role (automatic)
```

Logs: `logread -e modeswitch`.

## LuCI

*System → Mode Switch*:

- One tile per position, in physical order: factory label, alias,
  description and a summary of its profile (addresses, uplink, trunk VLANs,
  SSIDs, DHCP).  The switch position is outlined; the active position is
  filled.  The active tile also shows the live uplink state.
- *Apply* asks for confirmation and says where the device will be
  reachable afterwards.  *Edit…* opens the editor described above.  *Reset*
  rebuilds the profile from its template.
- *Follow the hardware switch* takes effect immediately.
- Every LuCI page shows the switch position in the header.
- The page polls `modectl brief` every 3 s and the full status only on a
  change or every 30 s.

ACL: read access to `modectl status --json` and `modectl brief`, the four
mode files and `/etc/modes/*/*`; write access to `modectl *` and
`/tmp/modeswitch-edit/*`.

## Rescue

- **Home:** the device is reachable only on the tagged management VLAN.
- **AP:** 192.168.50.1 over Wi-Fi.  Over the cable only while a Wi-Fi
  uplink is configured, because otherwise the wired port is the uplink.
- **RNDIS:** the wired port is LAN, 192.168.50.1 with DHCP.  Move the
  switch here to reach the device by cable.

## Use

In `feeds.conf` of an OpenWrt tree:

```
src-link wr902ac /path/to/this/repository/feed
```

then `./scripts/feeds update wr902ac && ./scripts/feeds install -a -p wr902ac`
and select `luci-app-modeswitch`.  `scripts/build.sh` does this.
