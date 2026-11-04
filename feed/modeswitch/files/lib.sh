# Helpers for /etc/modeswitch/defaults/<mode>.sh
# $UCI is "uci -q -c <scratch dir>"; the scratch dir starts as a copy of the
# active config, so templates must set everything they rely on explicitly.

ms_opt() { uci -q get "modeswitch.main.$1"; }

# mode_opt <option> [default]: option of the position being generated ($MODE);
# uci section names cannot contain '-', so share-eth is section share_eth
mode_opt() { local v; v="$(uci -q get "modeswitch.$(echo "$MODE" | tr -c 'a-zA-Z0-9_\n' '_').$1")"; echo "${v:-$2}"; }

# the wired LAN port as defined by the board (eth0.1 on switch-based
# targets such as MT76x8, where the CPU port is tagged)
WIRED="$(jsonfilter -q -i /etc/board.json -e '@.network.lan.device' 2>/dev/null)"
WIRED="${WIRED:-eth0}"

br_dev() { $UCI -X show network | sed -n "s/^network\.\([^.]*\)\.name='br-lan'$/\1/p" | head -n1; }

# set_bridge_ports [port...]: replace br-lan's wired ports (none = Wi-Fi only)
set_bridge_ports() {
	local d p
	d="$(br_dev)"
	if [ -z "$d" ]; then
		d="$($UCI add network device)"
		$UCI set "network.$d.name=br-lan"
		$UCI set "network.$d.type=bridge"
	fi
	$UCI delete "network.$d.ports"
	for p in "$@"; do $UCI add_list "network.$d.ports=$p"; done
	if [ $# -eq 0 ]; then $UCI set "network.$d.bridge_empty=1"; else $UCI delete "network.$d.bridge_empty"; fi
}

drop_iface() { local i; for i in "$@"; do $UCI delete "network.$i"; done; }

lan_static() { # lan_static <ip/prefix>
	$UCI set network.lan=interface
	$UCI set network.lan.device=br-lan
	$UCI set network.lan.proto=static
	$UCI set "network.lan.ipaddr=$1"
	$UCI delete network.lan.netmask
	$UCI delete network.lan.gateway
}

wan_dhcp() { # wan_dhcp <device>
	$UCI set network.wan=interface
	$UCI set "network.wan.device=$1"
	$UCI set network.wan.proto=dhcp
}

lan_dhcp_server() { # on|off
	$UCI set dhcp.lan=dhcp
	$UCI set dhcp.lan.interface=lan
	if [ "$1" = on ]; then $UCI delete dhcp.lan.ignore; else $UCI set dhcp.lan.ignore=1; fi
}

fw_zone() { $UCI -X show firewall | sed -n "s/^firewall\.\([^.]*\)\.name='$1'$/\1/p" | head -n1; }

set_zone_networks() { # set_zone_networks <zone> [network...]
	local z n
	z="$(fw_zone "$1")"; shift
	[ -n "$z" ] || return 0
	$UCI delete "firewall.$z.network"
	for n in "$@"; do $UCI add_list "firewall.$z.network=$n"; done
}

wifi_ap_on_lan() { # the main 2.4 GHz AP; SSID/key are inherited from the active config
	$UCI set wireless.default_radio0.network=lan
	$UCI set wireless.default_radio0.mode=ap
	$UCI set wireless.default_radio0.disabled=0
	$UCI delete wireless.wwan
}

# switch_trunk <vid>...: the wired LAN port carries all given VLANs tagged.
# Port numbers come from board.json (lan role "4 6t" on the WR902AC v3);
# sets $CPUDEV so templates can use "$CPUDEV.<vid>" devices.
switch_trunk() {
	local ports port cpu s v
	ports="$(jsonfilter -q -i /etc/board.json -e '@.switch.switch0.roles[@.role="lan"].ports')"
	CPUDEV="$(jsonfilter -q -i /etc/board.json -e '@.switch.switch0.ports[@.device].device')"
	port="${ports%% *}"; cpu="${ports##* }"; cpu="${cpu%t}"
	[ -n "$port" ] && [ -n "$cpu" ] && [ -n "$CPUDEV" ] || return 1
	while $UCI delete 'network.@switch_vlan[0]'; do :; done
	s="$($UCI -X show network | sed -n "s/^network\.\([^.]*\)=switch$/\1/p" | head -n1)"
	[ -n "$s" ] || { s="$($UCI add network switch)"; $UCI set "network.$s.name=switch0"; $UCI set "network.$s.reset=1"; }
	$UCI set "network.$s.enable_vlan=1"
	for v in "$@"; do
		s="$($UCI add network switch_vlan)"
		$UCI set "network.$s.device=switch0"
		$UCI set "network.$s.vlan=$v"
		$UCI set "network.$s.ports=${port}t ${cpu}t"
	done
}

# bridge_dev <name> <port>...: a plain (non VLAN-aware) bridge device
bridge_dev() {
	local name="$1" d p; shift
	d="$($UCI -X show network | sed -n "s/^network\.\([^.]*\)\.name='$name'$/\1/p" | head -n1)"
	[ -n "$d" ] || { d="$($UCI add network device)"; $UCI set "network.$d.name=$name"; }
	$UCI set "network.$d.type=bridge"
	$UCI delete "network.$d.ports"
	for p in "$@"; do $UCI add_list "network.$d.ports=$p"; done
}

drop_dev() { # drop_dev <name>: remove a network device section by name
	local d
	d="$($UCI -X show network | sed -n "s/^network\.\([^.]*\)\.name='$1'$/\1/p" | head -n1)"
	[ -n "$d" ] && $UCI delete "network.$d"
}
