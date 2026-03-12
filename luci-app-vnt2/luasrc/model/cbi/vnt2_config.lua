-- VNT2 基础配置页面 CBI 文件
-- 路径：/luasrc/model/cbi/vnt2_config.lua
local m, s, o

m = Map("vnt", _("VNT2 Tunnel Basic Settings"))
m.description = _("Configure VNT2 client and server parameters for virtual network tunneling")

-- 客户端配置区块
s = m:section(TypedSection, "vnt-cli", _("Client Settings"))
s.anonymous = true
s.addremove = false

-- 启用/禁用客户端
o = s:option(Flag, "enabled", _("Enable Client"))
o.default = 0
o.rmempty = false

-- IP 分配模式
o = s:option(ListValue, "mode", _("IP Mode"))
o:value("static", _("Static IP"))
o:value("dhcp", _("DHCP"))
o.default = "static"
o.rmempty = false

-- 静态IP地址
o = s:option(Value, "ipaddr", _("Static IP Address"))
o.datatype = "ip4addr"
o.default = "10.26.0.6"
o:depends("mode", "static")
o.rmempty = false

-- 设备ID
o = s:option(Value, "desvice_id", _("Device ID"))
o.default = "10.26.0.6"
o.rmempty = false

-- 打洞协议
o = s:option(ListValue, "punch", _("Punch Protocol"))
o:value("ipv4", _("IPv4 Only"))
o:value("ipv6", _("IPv6 Only"))
o:value("ipv4/ipv6", _("IPv4 + IPv6"))
o.default = "ipv4/ipv6"
o.rmempty = false

-- 服务端配置区块
s = m:section(TypedSection, "vnts", _("Server Settings"))
s.anonymous = true
s.addremove = false

-- 启用/禁用服务端
o = s:option(Flag, "enabled", _("Enable Server"))
o.default = 0
o.rmempty = false

-- 服务端端口
o = s:option(Value, "server_port", _("Server Port"))
o.datatype = "port"
o.default = 29872
o.rmempty = false

-- 服务端子网网关
o = s:option(Value, "subnet", _("Server Subnet Gateway"))
o.datatype = "ip4addr"
o.default = "10.26.0.1"
o.rmempty = false

-- 日志开关
o = s:option(Flag, "logs", _("Enable Server Log"))
o.default = 1
o.rmempty = false

return m
