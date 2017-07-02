#!/bin/bash

echo "${green}****************************${col_reset}"
echo "${green}* set up gateway functions *${col_reset}"
echo "${green}****************************${col_reset}"

#Firewall
{	
	if ! ip6tables -t nat -L > /dev/null  2>&1; then
		echo "(E) ${red}NAT66 support not available in Linux kernel.${col_reset}"
		exit 1
	fi

	#only really needed for a gateway
	echo "(I) ${green}Installing persistent iptables${col_reset}"
	apt install --assume-yes iptables-persistent

	cp -rf etc/iptables/* /etc/iptables/
	/etc/init.d/netfilter-persistent restart
}


setup_mullvad() {
	local mullvad_zip="$1"
	local tmp_dir="/tmp/mullvadconfig"
	if [ ! -f "$mullvad_zip" ]; then
		echo "(E) ${red}Mullvad zip file missing: $mullvad_zip${col_reset}"
		exit 1
	fi
	#unzip and copy files to OpenVPN
	rm -rf $tmp_dir
	mkdir -p $tmp_dir
	unzip $mullvad_zip -d $tmp_dir
	cp $tmp_dir/*/mullvad_linux.conf /etc/openvpn
	cp $tmp_dir/*/mullvad.key /etc/openvpn
	# set restrictive access rights on key file
	chmod 600 /etc/openvpn/mullvad.key
	cp $tmp_dir/*/mullvad.crt /etc/openvpn
	cp $tmp_dir/*/ca.crt /etc/openvpn
	cp $tmp_dir/*/crl.pem /etc/openvpn
	rm -rf $tmp_dir

	#prevent OpenVPN from setting routes
	echo "route-noexec" >> /etc/openvpn/mullvad_linux.conf

	# prevent OpenVPN from changing nameservers in resolv.conf
        sed -i "s|up /etc/openvpn/update-resolv-conf|#up /etc/openvpn/update-resolv-conf|g" /etc/openvpn/mullvad_linux.conf
        sed -i "s|down /etc/openvpn/update-resolv-conf|#down /etc/openvpn/update-resolv-conf|g" /etc/openvpn/mullvad_linux.conf

	#set a script that will set routes
	echo "route-up /etc/openvpn/update-route" >> /etc/openvpn/mullvad_linux.conf
		
	#use servers in Sweden only
	sed -i 's/^remote /#remote /' /etc/openvpn/mullvad_linux.conf
	sed -i 's/^#remote se.mullvad.net/remote se.mullvad.net/' /etc/openvpn/mullvad_linux.conf
}



setup_airvpn() {
	local airvpn_zip="$1"
	local tmp_dir="/tmp/airvpnconfig"
	if [ ! -f "$airvpn_zip" ]; then
		echo "(E) ${red}Airvpn zip file missing: $airvpn_zip${col_reset}"
		exit 1
	fi
	#unzip and copy files to OpenVPN
	rm -rf $tmp_dir
	mkdir -p $tmp_dir
	unzip $airvpn_zip -d $tmp_dir
	cp $tmp_dir/*.ovpn /etc/openvpn
	cp $tmp_dir/user.key /etc/openvpn
	# set restrictive access rights on key file
	chmod 600 /etc/openvpn/user.key
	chmod 600 /etc/openvpn/ta.key
	cp $tmp_dir/user.crt /etc/openvpn
	cp $tmp_dir/ca.crt /etc/openvpn
	cp $tmp_dir/ta.key /etc/openvpn
	rm -rf $tmp_dir

	#prevent OpenVPN from setting routes
	echo "route-noexec" >> /etc/openvpn/AirVPN_*.ovpn

	#set a script that will set routes
	echo "route-up /etc/openvpn/update-route" >> /etc/openvpn/AirVPN_*.ovpn

}


#OpenVPN
{
	echo "(I) ${green}Install OpenVPN.${col_reset}"
	apt install --assume-yes openvpn resolvconf zip

	# make sure openvpn is stopped
	# otherwise update-route will never be called resulting in missing iptable rules
	/etc/init.d/openvpn stop

	echo "(I) ${green}Configure OpenVPN${col_reset}"
	case "$vpn_provider" in
		"mullvad")
			setup_mullvad "mullvadconfig.zip"
		;;
		"airvpn")
			setup_airvpn "AirVPN.zip"
		;;
		*)
			echo "(E) ${red}Provide vpn provider string in setup.sh${col_reset}"
			exit 1
		;;
	esac
	cp etc/openvpn/update-route /etc/openvpn/
	# substitute gateway specific IP for DNS on bat0 in routes
	sed -i "s/DNS_SERVER/$ipv4_mesh_interface/g" /etc/openvpn/update-route

	# start OpenVPN
	# ...will be started in update.sh
}

#NAT64
{
	echo "(I) ${green}Install tayga.${col_reset}"
	apt install --assume-yes tayga

	#enable tayga
	sed -i 's/RUN="no"/RUN="yes"/g' /etc/default/tayga

	echo "(I) ${green}Configure tayga${col_reset}"
	cp -r etc/tayga.conf /etc/
}

#DNS64
{
	echo "(I) ${green}Install bind.${col_reset}"
	apt install --assume-yes bind9

	echo "(I) ${green}Configure bind${col_reset}"
	# copy config files to destination
	cp -r etc/bind/named.* /etc/bind/
	# grant write access for zone transfers
	chmod g+w /etc/bind/
	# adjust config
	sed -i "s/fdef:17a0:fff1:300::1/$ip_addr/g" /etc/bind/named.conf.options
	sed -i "s/DNS_SERVER/$ipv4_mesh_interface/g" /etc/bind/named.conf.options
}

#IPv6 Router Advertisments
{
	echo "(I) ${green}Install radvd.${col_reset}"
	apt install --assume-yes radvd

	echo "(I) ${green}Configure radvd${col_reset}"
	cp etc/radvd.conf /etc/
	sed -i "s/fdef:17a0:fff1:300::1/$ip_addr/g" /etc/radvd.conf
	sed -i "s/fdef:17a0:fff1:300::/$ff_prefix/g" /etc/radvd.conf
}

#IPv4 DHCP
{
	echo "(I) ${green}Install DHCP server${col_reset}"
	apt install --assume-yes isc-dhcp-server
	cp -f etc/dhcp/dhcpd.conf /etc/dhcp/
	cp -f etc/dhcp/isc-dhcp-server /etc/default/
	sed -i "s/DNS_SERVER/$ipv4_mesh_interface/g" /etc/dhcp/dhcpd.conf
	sed -i "s/DHCP_RANGE/$ipv4_dhcp_range/g" /etc/dhcp/dhcpd.conf
}


exit 0


