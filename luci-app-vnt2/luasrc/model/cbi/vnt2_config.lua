local m, s, o

m = Map("vnt2", translate("VNT2 Settings"))
m.description = translate("Configure VNT2 client and server")

-- 客户端配置
s = m:section(TypedSection, "client", translate("vnt-cli Client Settings"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("Enable Client"))
o.default = 0
o.rmempty = false

o = s:option(Value, "token", translate("Token"))
o.password = true
o.rmempty = false

o = s:option(Value, "device_id", translate("Device ID"))
o.datatype = "ip4addr"
o.default = "10.10.10.3"

o = s:option(DynamicList, "lan_allow", translate("Local LAN Routes"))
o.placeholder = "192.168.1.0/24"

o = s:option(Value, "server_addr", translate("Server Address"))
o.default = "tcp://8.138.1.239:29872"

-- 服务端配置
s = m:section(TypedSection, "server", translate("vnts2 Server Settings"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("Enable Server"))
o.default = 0
o.rmempty = false

o = s:option(Value, "port", translate("Listen Port"))
o.datatype = "port"
o.default = "29872"

o = s:option(Value, "dhcp_gw", translate("DHCP Gateway"))
o.datatype = "ip4addr"
o.default = "10.26.0.1"

o = s:option(Value, "netmask", translate("Subnet Mask"))
o.datatype = "ip4addr"
o.default = "255.255.255.0"

return m
