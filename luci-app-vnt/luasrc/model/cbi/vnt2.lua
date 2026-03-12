local m, s, o

m = Map("vnt2", _("VNT2 Virtual Network Tunnel"),
    _("Configuration for VNT2 (Version 2) virtual network tunnel.")
)

s = m:section(TypedSection, "vnt2", _("Global Settings"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", _("Enable VNT2"))
o.rmempty = false

o = s:option(Value, "server", _("Server Address"), _("VNT2 server IP or domain"))
o.datatype = "host"
o.rmempty = true

o = s:option(Value, "port", _("Server Port"))
o.datatype = "port"
o.default = "10086"
o.rmempty = false

o = s:option(Value, "token", _("Auth Token"), _("Token for server authentication"))
o.password = true
o.rmempty = true

o = s:option(ListValue, "interface", _("Bind Interface"))
for _, iface in ipairs(luci.sys.net.devices()) do
    o:value(iface)
end
o.default = "lan"
o.rmempty = false

o = s:option(ListValue, "encrypt", _("Encryption Method"), _("V2 supported encryption algorithms"))
o:value("aes-128", _("AES-128"))
o:value("aes-256", _("AES-256"))
o:value("none", _("None"))
o.default = "aes-128"
o.rmempty = false

o = s:option(Value, "mtu", _("MTU Size"), _("MTU for VNT2 tunnel interface"))
o.datatype = "uinteger"
o.default = "1400"
o.rmempty = false

s = m:section(TableSection, "status", _("Running Status"))
s.anonymous = true
s.template = "vnt2/status"

return m
