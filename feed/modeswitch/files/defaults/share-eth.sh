# share-eth (end, factory label "Share ETH", alias Home): 2.4 GHz access
# point on a VLAN trunk. The wired port carries the home, management, IoT
# and guest VLANs tagged; routing, DHCP and firewalling happen upstream.
# Bridged VLAN traffic is not filtered here; the firewall only guards the
# management address.
#
# Settings come from the share_eth section of /etc/config/modeswitch
# (edit with uci; used only when this profile is (re)built). Wi-Fi keys are required.
MGMT_IP="$(mode_opt mgmt_ip 192.168.20.2/24)"
MGMT_GW="$(mode_opt mgmt_gw 192.168.20.1)"
MGMT_DNS="$(mode_opt mgmt_dns "$MGMT_GW")"
VLAN_HOME="$(mode_opt vlan_home 10)";  VLAN_MGMT="$(mode_opt vlan_mgmt 20)"
VLAN_IOT="$(mode_opt vlan_iot 30)";    VLAN_GUEST="$(mode_opt vlan_guest 40)"
HOME_SSID="$(mode_opt home_ssid OpenWrt)";   HOME_KEY="$(mode_opt home_key)"
GUEST_SSID="$(mode_opt guest_ssid OpenWrt-Guest)"; GUEST_KEY="$(mode_opt guest_key)"
WIFI_CHANNEL="$(mode_opt wifi_channel auto)"; WIFI_HTMODE="$(mode_opt wifi_htmode HT40)"
WIFI_COUNTRY="$(mode_opt wifi_country)"
if [ -z "$HOME_KEY" ] || [ -z "$GUEST_KEY" ]; then
	echo "home: home_key/guest_key not set in modeswitch.share_eth" >&2
	exit 1
fi

switch_trunk "$VLAN_HOME" "$VLAN_MGMT" "$VLAN_IOT" "$VLAN_GUEST" || { echo "home: no switch info in board.json" >&2; exit 1; }

drop_iface lan lan_fallback wan wan6 wwan
drop_dev br-lan
bridge_dev br-home  "$CPUDEV.$VLAN_HOME"
bridge_dev br-iot   "$CPUDEV.$VLAN_IOT"
bridge_dev br-guest "$CPUDEV.$VLAN_GUEST"

$UCI set network.mgmt=interface
$UCI set "network.mgmt.device=$CPUDEV.$VLAN_MGMT"
$UCI set network.mgmt.proto=static
$UCI set "network.mgmt.ipaddr=$MGMT_IP"
$UCI set "network.mgmt.gateway=$MGMT_GW"
$UCI delete network.mgmt.dns
$UCI add_list "network.mgmt.dns=$MGMT_DNS"
for i in home iot guest; do
	$UCI set "network.$i=interface"
	$UCI set "network.$i.device=br-$i"
	$UCI set "network.$i.proto=none"
done

# no DHCP here: that is the upstream router's job
$UCI delete dhcp.lan
$UCI delete dhcp.wan

set_zone_networks lan mgmt
set_zone_networks wan

$UCI set wireless.radio0.disabled=0
$UCI set "wireless.radio0.channel=$WIFI_CHANNEL"
$UCI set "wireless.radio0.htmode=$WIFI_HTMODE"
[ -n "$WIFI_COUNTRY" ] && $UCI set "wireless.radio0.country=$WIFI_COUNTRY"
$UCI set wireless.radio0.noscan=1
$UCI set wireless.radio0.cell_density=0
$UCI delete wireless.wwan

ap_iface() { # ap_iface <section> <network> <ssid> <key> [isolate]
	$UCI set "wireless.$1=wifi-iface"
	$UCI set "wireless.$1.device=radio0"
	$UCI set "wireless.$1.mode=ap"
	$UCI set "wireless.$1.network=$2"
	$UCI set "wireless.$1.ssid=$3"
	$UCI set "wireless.$1.encryption=sae-mixed"
	$UCI set "wireless.$1.key=$4"
	$UCI set "wireless.$1.ieee80211k=1"
	$UCI set "wireless.$1.bss_transition=1"
	$UCI set "wireless.$1.disabled=0"
	if [ "$5" = isolate ]; then $UCI set "wireless.$1.isolate=1"; else $UCI delete "wireless.$1.isolate"; fi
}
$UCI delete wireless.default_radio0
ap_iface home_2g home "$HOME_SSID" "$HOME_KEY"
ap_iface guest_2g guest "$GUEST_SSID" "$GUEST_KEY" isolate
