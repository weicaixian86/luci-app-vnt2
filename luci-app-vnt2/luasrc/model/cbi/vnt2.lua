local m, s, o

m = Map("vnt2", translate("VNT2 Network"), translate("VNT2 P2P Network Configuration"))
m:section(SimpleSection).template  = "vnt2/status"

s = m:section(NamedSection, "global", "vnt2", translate("Global Settings"))
s.addremove = false
s.anonymous = true

-- 启用开关
o = s:option(Flag, "enabled", translate("Enable"))
o.rmempty = false

-- 组网标识
o = s:option(Value, "token", translate("Token (-k)"))
o.description = translate("VNT Network Token")
o.rmempty = false

-- 设备ID
o = s:option(Value, "device_id", translate("Device ID (-d)"))
o.description = translate("Unique Device ID")
o.rmempty = false

-- 设备名称
o = s:option(Value, "device_name", translate("Device Name (-n)"))
o.default = luci.sys.hostname()
o.rmempty = false

-- 服务器地址
o = s:option(Value, "server", translate("Server Address (-s)"))
o.default = "vnt.wherewego.top:29872"
o.rmempty = false

-- STUN服务器
o = s:option(Value, "stun_server", translate("STUN Server (-e)"))
o.default = "stun.qq.com:3478"
o.rmempty = false

-- 客户端加密密码
o = s:option(Value, "password", translate("Client Encryption (-w)"))
o.password = true
o.rmempty = true

-- 服务端加密
o = s:option(Flag, "server_encrypt", translate("Server Encryption (-W)"))
o.rmempty = true

-- MTU配置
o = s:option(Value, "mtu", translate("MTU (-u)"))
o.default = "1430"
o.datatype = "uinteger"
o.rmempty = true

-- 端口映射
o = s:option(Value, "port_mapping", translate("Port Mapping (--mapping)"))
o.description = translate("Format: udp:127.0.0.1:80->10.26.0.10:8080")
o.rmempty = true

return m
