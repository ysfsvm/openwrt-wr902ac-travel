# ap (end, factory label "AP", alias RNDIS), USB tethering: an Android phone over USB (RNDIS/CDC-Ether, usb0) is the
# uplink; the wired port and Wi-Fi are the LAN with NAT and DHCP.
set_bridge_ports "$WIRED"
drop_iface wan6 wwan lan_fallback
lan_static "$(ms_opt lan_ip)"
wan_dhcp usb0
lan_dhcp_server on
set_zone_networks lan lan
set_zone_networks wan wan
wifi_ap_on_lan
