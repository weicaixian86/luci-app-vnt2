local m, s, o

m = Map("vnt2", "vnts2 服务端设置", "配置 vnts2 服务端的所有参数，修改后点击「保存&应用」生效")

-- 基本设置 Tab
s = m:section(NamedSection, "server", "server", "基本设置")
s.anonymous = true

o = s:option(Flag, "enabled", "启用服务端")
o.default = 0
o.rmempty = false

o = s:option(Value, "port", "本地监听端口")
o.default = "29872"
o.datatype = "port"
o.description = "服务端监听的端口，客户端需要填写此端口连接"

o = s:option(DynamicList, "token_whitelist", "Token 白名单")
o.description = "填写后仅指定的 Token 可以连接此服务端，留空则无限制"
o.placeholder = "your_token"

o = s:option(Value, "gateway", "指定 DHCP 网关")
o.default = "10.26.0.1"
o.description = "分配给客户端的虚拟网段网关，决定客户端的虚拟IP网段"

o = s:option(Value, "netmask", "指定子网掩码")
o.default = "255.255.255.0"
o.description = "虚拟网段的子网掩码，默认 255.255.255.0"

o = s:option(Flag, "web_management", "启用 WEB 管理")
o.default = 0
o.description = "开启服务端自带的 WEB 管理界面，可图形化查看客户端详情"

o = s:option(Value, "web_port", "WEB 管理端口")
o.default = "29873"
o.datatype = "port"
o:depends("web_management", "1")
o.description = "WEB 管理界面的监听端口"

o = s:option(Flag, "log_enabled", "启用日志")
o.default = 1
o.description = "开启服务端日志记录，日志可在「服务端日志」页查看"

-- 高级设置 Tab
s = m:section(NamedSection, "server", "server", "高级设置")
s.anonymous = true

o = s:option(Value, "bind_addr", "监听地址")
o.default = "0.0.0.0"
o.description = "服务端绑定的监听地址，默认 0.0.0.0 监听所有网卡"

o = s:option(ListValue, "log_level", "日志级别")
o:value("info", "信息（info）")
o:value("debug", "调试（debug）")
o:value("error", "错误（error）")
o:value("warn", "警告（warn）")
o:value("trace", "追踪（trace）")
o.default = "info"
o.description = "程序输出的日志级别"

o = s:option(Value, "log_path", "日志文件路径")
o.default = "/tmp/vnts2.log"
o:depends("log_enabled", "1")
o.description = "服务端日志保存路径"

o = s:option(Flag, "port_forward", "启用端口转发")
o.default = 0
o.description = "开启服务端端口转发功能"

o = s:option(Value, "port_forward_bind", "端口转发监听地址")
o.default = "0.0.0.0"
o:depends("port_forward", "1")
o.description = "端口转发功能绑定的监听地址"

o = s:option(Value, "custom_args", "自定义启动参数")
o.description = "额外的自定义启动参数，多个参数用空格分隔，高级用户使用"
o.placeholder = "--max-clients 100 --ip-segment 10.26.0.0/24"

-- 保存后自动重启服务
m.on_after_commit = function(self)
    luci.sys.exec("/etc/init.d/vnt2 restart")
end

return m
