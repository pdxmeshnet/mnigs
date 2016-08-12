--- @module network
local network = {}

local bit32 = require("bit32")
local bit128 = require("bit128")
local shell = require("lib.shell")

-- There are 3 different representations for IPs
-- 1. internal {192,168,1,1} and ipv6 {255,...........}
-- 2. string "192.168.1.1" and ipv6 "ff..:.........."
-- 3. binary 32-bit-number and ipv6 {32-bit-number, 32-bit-number, 32-bit-number, 32-bit-number}
-- internal representation is used for convenience
-- binary representation is used for binary operations
-- string representation is used for user input/output

-- takes a string and returns a string with an ip that has been standardized
function network.canonicalizeIp(ip)
	local n, err = network.parseIp(ip)
	if err then return nil, err end
	if not n then return nil, "Failed to parse IP" end
	return network.ip2string(n), nil
end

-- takes string representation and returns internal representation
function network.parseIp(ip)
	local data, err = network.parseIpv4(ip)
	if err then
		data, err = network.parseIpv6(ip)
	end
	if err or not data then
		return nil, "Failed to parse IP '"..ip.."'"
	end
	return data, nil
end

-- takes string representation and returns internal representation and cidr
function network.parseSubnet(subnet)
	local data, err = network.parseIpv4Subnet(subnet)
	if err then
		data, err = network.parseIpv6Subnet(subnet)
	end
	if err or not data then
		return nil, "Failed to parse subnet '"..subnet.."'"
	end
	return data, nil
end

-- takes string representation and returns internal representation
function network.parseIpv4(ip)
	
	ip = tostring(ip)
	local matches = {ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")}
	
	for key,value in pairs(matches) do
		matches[key] = tonumber(value)
		if 0>matches[key] or matches[key]>255 then
			return nil, "Not a valid IPv4"
		end
	end
	
	if #matches ~= 4 then
		return nil, "Not a valid IPv4"
	end
	
	return matches, nil
end

-- takes string representation and returns internal representation
function network.parseIpv6(ip)
	
	ip = tostring(ip)
	local matches = {ip:match("^([0-9a-f]*)(:?)([0-9a-f]*)(:?)([0-9a-f]*)(:?)([0-9a-f]*)(:?)([0-9a-f]*)(:?)([0-9a-f]*)(:?)([0-9a-f]*)(:?)([0-9a-f]*)$")}
	
	if #matches < 3 then
		return nil, "Not a valid IPv6 '"..ip.."'"
	end
	
	if matches[1] == "" then
		matches[1] = "0000"
	end
	
	local result = {}
	
	local prev
	
	for key,value in pairs(matches) do
		if value ~= ":" and value ~= "" then
			if #value > 4 then
				return nil, "Failed to parse IPv6 '"..ip.."'"
			end
			value = string.rep("0", 4-#value)..value
			table.insert(result, string.lower(value));
		end
		if prev then
			if prev=="" and value==":" then
				break
			end
		end
		prev = value
	end
	
	if #result < 8 then
		
		local result2 = {}
		prev = nil
		local begin = false
		for key,value in pairs(matches) do
			if begin and value ~= ":" and value ~= "" then
				if #value > 4 then
					return nil, "Failed to parse IPv6"
				end
				value = string.rep("0", 4-#value)..value
				table.insert(result2, string.lower(value));
			end
			if prev then
				if prev=="" and value==":" then
					if begin then
						return nil, "Failed to parse IPv6 '"..ip.."'"
					end
					begin = true
				end
			end
			prev = value
		end
		
		for i=#result,(7-#result2) do
			table.insert(result,"0000")
		end
		
		for key,value in pairs(result2) do
			table.insert(result,value)
		end
	end
	
	local ip = {}
	
	for key,value in pairs(result) do
		table.insert(ip,tonumber(string.sub(value,1,2),16))
		table.insert(ip,tonumber(string.sub(value,3,4),16))
	end
	
	return ip, nil
end

-- takes string representation of ip and cidr and returns internal representation and cidr
function network.parseIpv4Subnet(subnet)
	
	local ip, cidr = subnet:match("^(%d+%.%d+%.%d+%.%d+)(/?%d*)$")
	
	if ip == nil and cidr == nil then return nil, "Not a valid subnet" end
	if cidr == "" then cidr = "/32" end
	if cidr:sub(1,1) ~= "/" then return nil, "Not a valid CIDR" end
	cidr = cidr:sub(2)
	if #cidr == 0 then return nil, "Not a valid CIDR" end
	
	local ip, err = network.parseIpv4(ip)
	
	if err then
		return nil, err
	end
	
	cidr = tonumber(cidr)
	if  0>cidr or cidr>32 then
		return nil, "Not a valid IPv4 subnet cidr"
	end
	
	return {ip, cidr}, nil
end

-- takes string representation of ip and cidr and returns internal representation and cidr
function network.parseIpv6Subnet(subnet)
	
	local ip, cidr = subnet:match("^([0-9a-f]*:?[0-9a-f]*:?[0-9a-f]*:?[0-9a-f]*:?[0-9a-f]*:?[0-9a-f]*:?[0-9a-f]*:?[0-9a-f]*)(/?%d*)$")
	
	if ip == nil and cidr == nil then return nil, "Not a valid subnet" end
	if cidr == "" then cidr = "/128" end
	if cidr:sub(1,1) ~= "/" then return nil, "Not a valid CIDR" end
	cidr = cidr:sub(2)
	if #cidr == 0 then return nil, "Not a valid CIDR" end
	
	local ip, err = network.parseIpv6(ip)
	
	if err then
		return nil, err
	end
	
	cidr = tonumber(cidr)
	if  0>cidr or cidr>128 then
		return nil, "Not a valid IPv6 subnet cidr"
	end
	
	return {ip, cidr}, nil
end

-- takes internal representation and returns string representation
function network.ip2string(ip)
	local v6 = #ip > 4
	if v6 then
		local str = ""
		for i=0,7 do
			local segment1 = string.format("%x",ip[i*2+1])
			segment1 = string.rep("0", 2-#segment1)..segment1
			local segment2 = string.format("%x",ip[i*2+2])
			segment2 = string.rep("0", 2-#segment2)..segment2
			str = str..string.lower(segment1..segment2)
			if i < 7 then
				str = str..":"
			end
		end
		return str
	else
		local a1, a2, a3, a4 = unpack(ip)
		return a1.."."..a2.."."..a3.."."..a4;
	end
end

-- takes internal representation and returns binary representation
function network.ip2binary(ip)
	local v6 = #ip > 4
	if v6 then
		local bin = {}
		for i=0,3 do
			table.insert(bin, network.ip2binary({ip[i*4+1],ip[i*4+2],ip[i*4+3],ip[i*4+4]}))
		end
		return bin
	else
		local bin = 0;
		bin = bit32.bor(bin,ip[1])
		bin = bit32.lshift(bin,8)
		bin = bit32.bor(bin,ip[2])
		bin = bit32.lshift(bin,8)
		bin = bit32.bor(bin,ip[3])
		bin = bit32.lshift(bin,8)
		bin = bit32.bor(bin,ip[4])
		return bin
	end
end

-- takes binary representation and returns internal representation
function network.binaryToIp(bin)
	if type(bin) == "table" then
		local ipv6 = {}
		for i=1,4 do
			local segment = network.binaryToIp(bin[i])
			for key,value in pairs(segment) do
				table.insert(ipv6, value)
			end
		end
		return ipv6
	else
		local a1, a2, a3, a4
		a4 = bit32.band(0xFF,bin)
		bin = bit32.rshift(bin,8)
		a3 = bit32.band(0xFF,bin)
		bin = bit32.rshift(bin,8)
		a2 = bit32.band(0xFF,bin)
		bin = bit32.rshift(bin,8)
		a1 = bit32.band(0xFF,bin)
		return {a1, a2, a3, a4};
	end
end

-- takes cidr and returns binary representation of subnet mask
function network.Ipv4cidrToBinaryMask(cidr)
	return bit32.lshift(bit32.bnot(0), 32-cidr)
end

-- takes cidr and returns binary representation of subnet mask
function network.Ipv6cidrToBinaryMask(cidr)
	return bit128.lshift(bit128.bnot({0,0,0,0}), 128-cidr)
end

function network.getInterface(ifname)
	
	local ipv4subnets, err = network.getInterfaceIpv4subnets(ifname)
	local ipv6subnets, err = network.getInterfaceIpv6subnets(ifname)
	
	return { ["name"] = ifname, ["ipv4subnets"] = ipv4subnets, ["ipv6subnets"] = ipv6subnets }
end

function network.getInterfaces()
	local procnetdev, err = io.open("/proc/net/dev", "r")
	if err then
		return nil, err
	end
	local ifs = {}
	for l in procnetdev:lines() do
		local ifname = string.match(string.lower(l), "^%s*(%w+):")
		if ifname then
			ifs[ifname] = network.getInterface(ifname)
		end
	end
	procnetdev:close()
	return ifs, nil
end

function network.getInterfaceIpv4subnets(interface)
	interface = string.lower(interface)
	
	local ipcmd = io.popen(shell.escape({"ip", "addr", "show", interface}), 'r')
	
	if not ipcmd then 
		return nil, "Failed to get IPv4 address for interface "..interface
	end
	
	local subnets = {}
	
	for l in ipcmd:lines() do
		local subnet = string.match(string.lower(l), "^%s*inet%s+(%d+%.%d+%.%d+%.%d+/%d+)%s")
		if subnet then
			local subnet, err = network.parseIpv4Subnet(subnet)
			if not err and subnet then table.insert(subnets, subnet) end
		end
	end
	
	ipcmd:close()
	
	return subnets, nil
end

function network.getInterfaceIpv6subnets(interface)
	interface = string.lower(interface)
	
	local procnetif, err = io.open("/proc/net/if_inet6")
	
	if err then
		return nil, err
	end
	
	local subnets = {}
	
	local ifs = {}
	for l in procnetif:lines() do
		local addr, cidr, iface = string.match(string.lower(l), "^([0-9a-f]+)%s[0-9a-f]+%s([0-9a-f]+)%s.*%s(%w+)$")
		if addr and cidr and iface == interface then
			local ipv6 = {}
			for i=0,15 do table.insert(ipv6, tonumber(addr:sub(i*2+1,i*2+2),16)) end
			table.insert(subnets, {ipv6, tonumber(cidr, 16)})
		end
	end
	
	procnetif:close()
	
	return subnets, nil
end

-- returns subnet prefix address
function network.subnetAddr(subnet)
	local ip, cidr = unpack(subnet)
	local v6 = #ip > 4
	
	ip = network.ip2binary(ip);
	
	if v6 then
		return network.binaryToIp(bit128.band(ip, network.Ipv6cidrToBinaryMask(cidr)))
	else
		return network.binaryToIp(bit32.band(ip, network.Ipv4cidrToBinaryMask(cidr)))
	end
end

function network.compareSubnet(subnet1, subnet2)
	
	local ip1, cidr1 = unpack(subnet1)
	local ip2, cidr2 = unpack(subnet2)
	
	if #ip1 ~= #ip2 then return false end
	if cidr1 ~= cidr2 then return false end
	
	return network.ip2string(network.subnetAddr(subnet1)) == network.ip2string(network.subnetAddr(subnet2))
end

function network.isIpInSubnet(ip, subnet)
	
	local prefixip, cidr = unpack(subnet)
	
	return network.compareSubnet({ip, cidr}, subnet)
end

function network.getInterfaceBySubnet(subnet)
	
	local ip, cidr = unpack(subnet)
	local v6 = #ip > 4
	
	local interfaces, err = network.getInterfaces()
	if err then
		return nil, err
	end
	
	for name,interface in pairs(interfaces) do
		
		local ifsubnets
		
		if v6 then
			ifsubnets = interface.ipv6subnets
		else
			ifsubnets = interface.ipv4subnets
		end
		
		for k,ifsubnet in pairs(ifsubnets) do
			if network.compareSubnet(ifsubnet, subnet) then
				return interface, nil
			end
		end
	end
	
	return nil, nil
end

function network.getIpv4TransitInterface()
	
	local ipcmd = io.popen("ip route show", 'r')
	
	if not ipcmd then
		return nil, "Failed to get routing table"
	end
	
	for l in ipcmd:lines() do
		local interface = string.match(string.lower(l), "^default%s.*dev%s([^%s]+)%s")
		if interface then
			ipcmd:close()
			return network.getInterface(interface), nil
		end
	end
	
	ipcmd:close()
	
	return nil, nil
end

function network.getIpv6TransitInterface()
	
	local ipcmd = io.popen("ip -6 route show", 'r')
	
	if not ipcmd then
		return nil, "Failed to get routing table"
	end
	
	for l in ipcmd:lines() do
		local interface = string.match(string.lower(l), "^default%s.*dev%s([^%s]+)%s")
		if interface then
			ipcmd:close()
			return network.getInterface(interface), nil
		end
	end
	
	ipcmd:close()
	
	return nil, nil
end

function network.ping4(addr)
	
	local ipcmd = io.popen(shell.escape({"ping", "-c", 3, "-s", 0, "-W", 1, addr}), 'r')
	
	if not ipcmd then
		return nil, "Failed to execute ping"
	end
	
	for l in ipcmd:lines() do
		local loss = string.match(string.lower(l), "%s(%d+)%%%s.*loss")
		if loss then
			ipcmd:close()
			if tonumber(loss) < 100 then
				return true, nil
			else
				return false, nil
			end
		end
	end
	
	ipcmd:close()
	
	return nil, "Failed to determine the number of packets received pinging "..addr
end

function network.ping6(addr)
	
	local ipcmd = io.popen(shell.escape({"ping6", "-c", 3, "-s", 0, "-W", 1, addr}), 'r')
	
	if not ipcmd then
		return nil, "Failed to execute ping"
	end
	
	for l in ipcmd:lines() do
		local loss = string.match(string.lower(l), "%s(%d+)%%%s.*loss")
		if loss then
			ipcmd:close()
			if tonumber(loss) < 100 then
				return true, nil
			else
				return false, nil
			end
		end
	end
	
	ipcmd:close()
	
	return nil, "Failed to determine the number of packets received pinging "..addr
end

function network.setIpv4Forwading(value)
	
	local ipforward, err = io.open("/proc/sys/net/ipv4/ip_forward", "w")
	if err then
		return nil, err
	end
	
	ipforward:write(tostring(value))
	ipforward:close()
	
	return true, nil
end

function network.setIpv6Forwading(value)
	
	local ipforward, err = io.open("/proc/sys/net/ipv6/conf/all/forwarding", "w")
	if err then
		return nil, err
	end
	
	ipforward:write(tostring(value))
	ipforward:close()
	
	return true, nil
end

-- takes a string, returns boolean
function network.isAuthorizedIp(ip)
	
	local ip, err = network.parseIp(ip)
	if err then return nil, err end
	
	local v6 = #ip > 4
	
	for subnetStr in string.gmatch(config.daemon.authorizedNetworks, ",?([^,]+),?") do
		local subnet, err = network.parseSubnet(subnetStr)
		if err then return nil, "Failed to parse authorizedNetworks setting in config: "..err end
		if network.isIpInSubnet(ip, subnet) then
			return true, nil
		end
	end
	
	return false, nil
end

return network
