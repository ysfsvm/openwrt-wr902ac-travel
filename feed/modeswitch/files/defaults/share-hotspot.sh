# share-hotspot (middle, factory label "Mobile Hotspot", alias AP): travel router.
# Wi-Fi AP + own LAN 192.168.50.1/24 (modeswitch.main.lan_ip) with DHCP, always.
# Uplink, decided by configuration (modeswitch.share_hotspot.wired_role=auto):
#  - no Wi-Fi uplink configured: the wired port is the uplink (wan, DHCP, NAT);
#  - a Wi-Fi uplink joined in LuCI (Scan -> Join: STA + wwan in the wan zone):
#    the wired port is LAN; modectl moves it on every config change.
# DNS rebind protection is off so captive portals that resolve to private
# addresses load; wan/wwan keep peerdns (the portal's DNS).
set_bridge_ports                  # wired port starts as the uplink
drop_iface wan wan6 wwan lan_fallback
wan_dhcp "$WIRED"
lan_static "$(ms_opt lan_ip)"
lan_dhcp_server on
$UCI set dhcp.@dnsmasq[0].rebind_protection=0
set_zone_networks lan lan
set_zone_networks wan wan
wifi_ap_on_lan
