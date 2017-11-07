#!/usr/bin/env sh

sessionid=$1
meshIp=$2
ipv4=$3
ipv4gateway=$4
cidr4=$5
ipv6=$6
ipv6gateway=$7
cidr6=$8
interface4=$9
interface6=$10

backupfile=/opt/transitd/uci.network.normal.config

if [ -e "$backupfile" ]; then
	cat $backupfile | uci import network
	rm $backupfile
fi

uci commit network

/etc/init.d/network reload
/etc/init.d/firewall reload
