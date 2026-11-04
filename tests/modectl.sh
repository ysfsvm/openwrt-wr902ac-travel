#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# modectl tests.  Run inside an OpenWrt rootfs (real uci, jsonfilter, lock
# and config_generate) by tests/run.sh; the repository is mounted at $SRC.
# Only reload_config, slide-switch and logger are stubbed.  Output is TAP.
#
# shellcheck disable=SC2016,SC2034 # check() evaluates its condition later

SRC=${SRC:-/src}
T=/tmp/modeswitch-test
FILES=$SRC/feed/modeswitch/files

# --- setup ---------------------------------------------------------------

rm -rf "$T"; mkdir -p "$T/bin" /var/lock
PATH=$T/bin:$PATH
printf '#!/bin/sh\necho reload >> %s/reloads\n' "$T" > "$T/bin/reload_config"
printf '#!/bin/sh\ncat %s/position\n' "$T" > "$T/bin/slide-switch"
printf '#!/bin/sh\nshift 2; echo "$*" >> %s/log\n' "$T" > "$T/bin/logger"
chmod 755 "$T"/bin/*
: > "$T/reloads"; : > "$T/log"

set -e
mkdir -p /usr/sbin /usr/share/modeswitch /etc/modeswitch/defaults
cp "$FILES/modectl" /usr/sbin/modectl; chmod 755 /usr/sbin/modectl
cp "$FILES/lib.sh" /usr/share/modeswitch/lib.sh
cp "$FILES"/defaults/*.sh /etc/modeswitch/defaults/
cp "$FILES/modeswitch.config" /etc/config/modeswitch

# a freshly installed TL-WR902AC v3, after the image's uci-defaults
cp "$SRC/tests/fixture/board.json" /etc/board.json
rm -f /etc/config/network
config_generate >/dev/null 2>&1
cp "$SRC/tests/fixture/wireless" /etc/config/wireless
sh "$SRC/files/etc/uci-defaults/90-no-ipv6" >/dev/null 2>&1
uci set modeswitch.share_eth.home_key='home-key-123'
uci set modeswitch.share_eth.guest_key='guest-key-123'
uci commit modeswitch
# the user set up Wi-Fi before the first position change
uci set wireless.radio0.disabled=0
uci set wireless.default_radio0.ssid=Travel
uci set wireless.default_radio0.encryption=sae-mixed
uci set wireless.default_radio0.key=travel-key-123
uci commit wireless
set +e

# --- helpers -------------------------------------------------------------

n=0; failed=0
check() { # check <description> <shell condition>
	n=$((n + 1))
	if eval "$2"; then echo "ok $n - $1"; else echo "not ok $n - $1"; failed=$((failed + 1)); fi
}
reloads() { wc -l < "$T/reloads"; }
saved() { # running mode files == the active profile
	local f c; c="$(cat /etc/modes/current)"
	for f in network wireless firewall dhcp; do cmp -s "/etc/config/$f" "/etc/modes/$c/$f" || return 1; done
}
clean() { [ -z "$(uci changes)" ] && [ -z "$(find /tmp/.uci -type f -size +0 2>/dev/null)" ]; }
br() { uci -X show network | sed -n "s/^network\.\([^.]*\)\.name='br-lan'$/\1/p"; }
ports() { uci -q get "network.$(br).ports"; }
trigger() { /usr/sbin/modectl save; }   # what procd runs after every commit
move() { echo "$1" > "$T/position"; /usr/sbin/modectl handle "$1"; }

# --- AP: first boot ------------------------------------------------------

move share-hotspot
check "first move: AP is active" '[ "$(cat /etc/modes/current)" = share-hotspot ]'
check "first move: the pre-modeswitch config is the base" '[ -f /etc/modes/_initial/network ]'
check "AP: profile built from its template" '[ -f /etc/modes/share-hotspot/.generated ]'
check "AP: LAN 192.168.50.1/24" '[ "$(uci -q get network.lan.ipaddr)" = 192.168.50.1/24 ]'
check "AP: serves DHCP" '[ "$(uci -q get dhcp.lan.ignore)" != 1 ]'
check "AP: DNS rebind protection off" '[ "$(uci -q get dhcp.@dnsmasq[0].rebind_protection)" = 0 ]'
check "AP: wired port is the uplink" '[ -z "$(ports)" ] && [ "$(uci -q get network.wan.device)" = eth0.1 ] && [ "$(uci -q get network.wan.disabled)" != 1 ]'
check "AP: Wi-Fi AP on the LAN" '[ "$(uci -q get wireless.default_radio0.disabled)" = 0 ] && [ "$(uci -q get wireless.default_radio0.network)" = lan ]'
check "AP: Wi-Fi settings taken from the base" '[ "$(uci -q get wireless.default_radio0.ssid)" = Travel ] && [ "$(uci -q get wireless.default_radio0.key)" = travel-key-123 ]'
check "AP: saved, no uci changes left" 'saved && clean'

# --- AP: wired port role -------------------------------------------------

uci set network.wwan=interface; uci set network.wwan.proto=dhcp
uci set wireless.wwan=wifi-iface; uci set wireless.wwan.device=radio0
uci set wireless.wwan.mode=sta; uci set wireless.wwan.network=wwan
uci set wireless.wwan.ssid=Hotel; uci set wireless.wwan.encryption=none
uci add_list firewall.@zone[1].network=wwan
uci commit; trigger; trigger
check "join a Wi-Fi: wired port is LAN" '[ "$(ports)" = eth0.1 ] && [ "$(uci -q get network.wan.disabled)" = 1 ]'
check "join a Wi-Fi: saved" 'saved && clean'
r=$(reloads); trigger; trigger
check "no change: no reload" '[ "$(reloads)" = "$r" ]'

uci set wireless.wwan.disabled=1; uci commit wireless; trigger; trigger
check "STA disabled: wired port is the uplink" '[ -z "$(ports)" ] && [ "$(uci -q get network.wan.disabled)" != 1 ]'

mkdir -p /var/run/rpcd/snapshot-files; echo x > /var/run/rpcd/snapshot-files/wireless
uci delete wireless.wwan.disabled; uci commit wireless; trigger; trigger
check "LuCI apply pending: port not moved" '[ -z "$(ports)" ]'
check "LuCI apply pending: one waiter" '[ -d /var/run/modeswitch-role-wait ]'
rm -rf /var/run/rpcd/snapshot-files
i=0; while [ "$(ports)" != eth0.1 ] && [ $i -lt 10 ]; do sleep 1; i=$((i + 1)); done
check "LuCI apply confirmed: wired port is LAN" '[ "$(ports)" = eth0.1 ]'
trigger

uci set wireless.wwan.disabled=1; uci commit wireless
uci set network.lan.test=1; trigger
check "uncommitted network changes: port not moved" '[ "$(ports)" = eth0.1 ]'
uci revert network; trigger
check "after revert: wired port is the uplink" '[ -z "$(ports)" ]'

uci delete wireless.wwan.disabled; uci set wireless.radio0.disabled=1; uci commit wireless; trigger
check "radio disabled: no Wi-Fi uplink" '[ -z "$(ports)" ]'
uci set wireless.radio0.disabled=0; uci commit wireless; trigger
check "radio enabled: wired port is LAN" '[ "$(ports)" = eth0.1 ]'

# --- RNDIS ---------------------------------------------------------------

uci set dhcp.lan.leasetime=2h; uci commit dhcp; trigger
move ap
check "RNDIS: active" '[ "$(cat /etc/modes/current)" = ap ]'
check "RNDIS: usb0 is the uplink, wired port is LAN" '[ "$(uci -q get network.wan.device)" = usb0 ] && [ "$(ports)" = eth0.1 ]'
check "RNDIS: AP change kept in the AP profile" '[ "$(uci -q -c /etc/modes/share-hotspot get dhcp.lan.leasetime)" = 2h ]'
check "RNDIS: saved, no uci changes left" 'saved && clean'

# --- Home ----------------------------------------------------------------

move share-eth
check "Home: trunk VLANs 10 20 30 40, tagged" '[ "$(uci -q show network | grep -c "\.ports=.4t 6t.")" = 4 ] && uci -q show network | grep -q "vlan=.40."'
check "Home: management address on its VLAN" '[ "$(uci -q get network.mgmt.ipaddr)" = 192.168.20.2/24 ] && [ "$(uci -q get network.mgmt.device)" = eth0.20 ]'
check "Home: SSIDs on their VLAN bridges" '[ "$(uci -q get wireless.home_2g.network)" = home ] && [ "$(uci -q get wireless.guest_2g.isolate)" = 1 ]'
check "Home: no DHCP server, no LAN" '[ -z "$(uci -q get dhcp.lan)" ] && [ -z "$(uci -q get network.lan)" ]'
check "Home: country kept when not set" '[ -z "$(uci -q get wireless.radio0.country)" ]'

uci delete modeswitch.share_eth.home_key; uci commit modeswitch
md5=$(cat /etc/modes/share-eth/* | md5sum)
/usr/sbin/modectl reset share-eth 2>/dev/null; rc=$?
check "Home reset without keys: fails" '[ $rc -ne 0 ]'
check "Home reset without keys: profile unchanged" '[ -f /etc/modes/share-eth/network ] && [ "$(cat /etc/modes/share-eth/* | md5sum)" = "$md5" ]'
uci set modeswitch.share_eth.home_key='home-key-123'; uci commit modeswitch

# --- back to AP: its profile, not its template ---------------------------

move share-hotspot
check "back to AP: Wi-Fi uplink still configured" '[ "$(uci -q get wireless.wwan.ssid)" = Hotel ] && [ "$(ports)" = eth0.1 ]'
check "back to AP: lease time kept" '[ "$(uci -q get dhcp.lan.leasetime)" = 2h ]'

# --- put -----------------------------------------------------------------

printf 'config bad\n\toption x "unterminated\n' > "$T/bad"
md5=$(md5sum < /etc/modes/ap/dhcp)
/usr/sbin/modectl put ap dhcp "$T/bad" 2>/dev/null; rc=$?
check "put: invalid uci syntax rejected" '[ $rc -ne 0 ] && [ -f /etc/modes/ap/dhcp ] && [ "$(md5sum < /etc/modes/ap/dhcp)" = "$md5" ]'
sed 's/192.168.50.1/192.168.51.1/' /etc/modes/ap/network > "$T/net"
r=$(reloads); /usr/sbin/modectl put ap network "$T/net"
check "put: inactive profile stored, not applied" '[ "$(uci -q -c /etc/modes/ap get network.lan.ipaddr)" = 192.168.51.1/24 ] && [ "$(reloads)" = "$r" ]'

# --- follow, status ------------------------------------------------------

/usr/sbin/modectl follow off
move ap
check "follow off: switch ignored" '[ "$(cat /etc/modes/current)" = share-hotspot ]'
/usr/sbin/modectl follow on
check "brief: valid JSON" '[ "$(/usr/sbin/modectl brief | jsonfilter -e @.current_alias)" = AP ]'
check "status --json: three positions with summaries" '[ "$(/usr/sbin/modectl status --json | jsonfilter -e "@.modes[*].summary" | wc -l)" = 3 ]'
check "status --json: Home trunk VLANs" '[ "$(/usr/sbin/modectl status --json | jsonfilter -e "@.modes[0].summary.vlans")" = "10 20 30 40" ]'
check "status --json: AP wired role auto" '[ "$(/usr/sbin/modectl status --json | jsonfilter -e "@.modes[1].summary.wired_role")" = auto ]'

# --- migration of a kept 2.2 config --------------------------------------

uci delete modeswitch.share_hotspot.wired_role; uci commit modeswitch
sh "$FILES/modeswitch.uci-defaults"; sh "$FILES/modeswitch.uci-defaults"
check "migration: wired_role added once" '[ "$(uci -q get modeswitch.share_hotspot.wired_role)" = auto ]'
check "migration: Home keys kept" '[ "$(uci -q get modeswitch.share_eth.home_key)" = home-key-123 ]'

check "no uci changes left behind" 'clean'

echo "1..$n"
[ $failed -eq 0 ] || { echo "# $failed of $n failed"; echo "# log:"; sed 's/^/#   /' "$T/log"; exit 1; }
