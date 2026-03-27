local http = luci.http
local nixio = require "nixio"

m = Map("vnt2")
m.description = translate('VNT2是一个简便高效的异地组网、内网穿透工具。<br>官网：<a href="http://rustvnt.com/">rustvnt.com</a>&nbsp;&nbsp;项目地址：<a href="https://github.com/vnt-dev/vnt">github.com/vnt-dev/vnt</a>')

-- vnt2-cli 状态显示
m:section(SimpleSection).template  = "vnt2/vnt2_status"

-- ==================== vnt2-cli 客户端设置 ====================
s = m:section(TypedSection, "vnt2_cli", translate("vnt2-cli 客户端设置"))
s.anonymous = true

s:tab("general", translate("基本设置"))
s:tab("advanced", translate("高级设置"))
s:tab("network", translate("网络设置"))
s:tab("security", translate("安全设置"))
s:tab("infos", translate("连接信息"))
s:tab("upload", translate("上传程序"))

-- 基本设置选项
switch = s:taboption("general",Flag, "enabled", translate("启用"))
switch.rmempty = false

btncq = s:taboption("general", Button, "btncq", translate("重启"))
btncq.inputtitle = translate("重启")
btncq.description = translate("在没有修改参数的情况下快速重新启动一次")
btncq.inputstyle = "apply"
btncq:depends("enabled", "1")
btncq.write = function()
  os.execute("/etc/init.d/vnt2 restart ")
end

server = s:taboption("general", DynamicList, "server", translate("服务器地址"),
	translate("服务器地址，支持quic/tcp/wss/dynamic协议<br>例如：quic://101.35.230.139:6660"))
server.optional = false
server.placeholder = "quic://101.35.230.139:6660"

network_code = s:taboption("general", Value, "network_code", translate("网络编号"),
	translate("这是必填项！一个虚拟局域网的标识，连接同一服务器时，使用相同网络编号的客户端设备才会组成一个局域网"))
network_code.optional = false
network_code.placeholder = "123456"
network_code.datatype = "string"
network_code.maxlength = 63
network_code.minlength = 1
network_code.validate = function(self, value, section)
    if value and #value >= 1 and #value <= 63 then
        return value
    else
        return nil, translate("网络编号为必填项，可填1至63位字符")
    end
end
switch.write = function(self, section, value)
    if value == "1" then
        network_code.rmempty = false
    else
        network_code.rmempty = true
    end
    return Flag.write(self, section, value)
end

device_id = s:taboption("general",Value, "device_id", translate("设备ID"),
	translate("每台设备的唯一标识，注意不要重复，每个vnt2-cli客户端的设备ID不能相同"))
device_id.placeholder = ""

device_name = s:taboption("general", Value, "device_name", translate("设备名称"),
    translate("本机设备名称，方便区分不同设备"))
device_name.placeholder = "OpenWrt"

local model = nixio.fs.readfile("/proc/device-tree/model") or ""
local hostname = nixio.fs.readfile("/proc/sys/kernel/hostname") or ""
model = model:gsub("\n", "")
hostname = hostname:gsub("\n", "")
local default_device_name = (model ~= "" and model) or (hostname ~= "" and hostname) or "OpenWrt"
default_device_name = default_device_name:gsub(" ", "_")
device_name.default = default_device_name

-- 高级设置选项
vnt2_cli_bin = s:taboption("advanced", Value, "vnt2_cli_bin", translate("vnt2-cli程序路径"),
	translate("自定义vnt2-cli的存放路径，确保填写完整的路径及名称，默认会自动下载"))
vnt2_cli_bin.placeholder = "/usr/bin/vnt2-cli"

tun_name = s:taboption("advanced",Value, "tun_name", translate("虚拟网卡名称"),
	translate("自定义虚拟网卡的名称，在多开时虚拟网卡名称不能相同，默认为 vnt-tun"))
tun_name.placeholder = "vnt-tun"

mtu = s:taboption("advanced",Value, "mtu", translate("MTU"),
	translate("设置虚拟网卡的mtu值，大多数情况下（留空）使用默认值效率会更高"))
mtu.datatype = "range(1,1500)"
mtu.placeholder = "1400"

ctrl_port = s:taboption("advanced", Value, "ctrl_port", translate("控制端口"),
	translate("控制服务的tcp端口，设置0时禁用控制服务"))
ctrl_port.datatype = "port"
ctrl_port.placeholder = "11233"

tunnel_port = s:taboption("advanced", Value, "tunnel_port", translate("隧道端口"),
	translate("隧道端口，用于P2P通信，默认为0，自动分配"))
tunnel_port.datatype = "port"
tunnel_port.placeholder = "0"

no_punch = s:taboption("advanced",Flag, "no_punch", translate("关闭P2P打洞"),
	translate("关闭后禁止P2P打洞，只使用服务器中继"))
no_punch.rmempty = false

rtx = s:taboption("advanced",Flag, "rtx", translate("启用QUIC优化传输"),
	translate("启用后使用QUIC协议优化传输，提升网络稳定性"))
rtx.rmempty = false

compress = s:taboption("advanced",Flag, "compress", translate("启用压缩"),
	translate("启用LZ4压缩，减少带宽使用"))
compress.rmempty = false

fec = s:taboption("advanced",Flag, "fec", translate("启用FEC前向纠错"),
	translate("启用FEC前向纠错，损失一定带宽来提升网络稳定性"))
fec.rmempty = false

no_nat = s:taboption("advanced",Flag, "no_nat", translate("关闭内置子网NAT"),
	translate("关闭后需要配置网卡转发，否则无法使用点对网。通常关闭内置子网NAT，使用系统的网卡转发，点对网性能会更好"))
no_nat.rmempty = false

no_tun = s:taboption("advanced",Flag, "no_tun", translate("禁用TUN虚拟网卡"),
	translate("禁用后只能充当流量出口或者进行端口映射，禁用后无需管理员权限"))
no_tun.rmempty = false

allow_mapping = s:taboption("advanced",Flag, "allow_mapping", translate("允许作为端口映射出口"),
	translate("开启后其他设备才可使用本设备的ip为"目标虚拟IP""))
allow_mapping.rmempty = false

-- 网络设置选项
input = s:taboption("network", DynamicList, "input", translate("入栈监听网段"),
	translate("入栈监听网段 (逗号分隔的 CIDR 和目标 IP)，用于点对网，将指定网段的流量发送到目标节点<br>例如：192.168.0.0/24,10.26.0.2"))
input.placeholder = "192.168.0.0/24,10.26.0.2"

output = s:taboption("network", DynamicList, "output", translate("出栈允许网段"),
	translate("出栈允许网段，用于点对网，允许指定网段的转发<br>例如：0.0.0.0/0"))
output.placeholder = "0.0.0.0/0"

port_mapping = s:taboption("network", DynamicList, "port_mapping", translate("端口映射"),
	translate("端口映射，格式为：协议://本地监听地址-目标虚拟IP-目标映射地址<br>例如：tcp://0.0.0.0:81-10.0.0.2-10.0.0.2:80"))
port_mapping.placeholder = "tcp://0.0.0.0:81-10.0.0.2-10.0.0.2:80"

-- 安全设置选项
password = s:taboption("security", Value, "password", translate("加密密码"),
	translate("设置加密密码，使用相同密码的客户端才能通信"))
password.placeholder = ""
password.password = true

cert_mode = s:taboption("security", ListValue, "cert_mode", translate("证书验证模式"),
	translate("服务端证书验证模式"))
cert_mode:value("skip", translate("跳过验证"))
cert_mode:value("standard", translate("使用系统证书验证"))
cert_mode:value("finger", translate("使用证书指纹验证"))
cert_mode.default = "skip"

-- 连接信息选项
vnt2_info = s:taboption("infos", Button, "vnt2_info")
vnt2_info.inputtitle = translate("本机设备信息")
vnt2_info.description = translate("点击按钮刷新，查看当前设备信息")
vnt2_info.inputstyle = "apply"
vnt2_info.write = function()
  local uci = require "luci.model.uci".cursor()
  local ctrl_port = tonumber(uci:get_first("vnt2", "vnt2_cli", "ctrl_port")) or 11233
  local vnt2_cli_bin = uci:get_first("vnt2", "vnt2_cli", "vnt2_cli_bin") or "/usr/bin/vnt2-cli"
  os.execute(vnt2_cli_bin .. " info --port " .. ctrl_port .. " >/tmp/vnt2-cli_info 2>&1")
end

vnt2_info_view = s:taboption("infos", DummyValue, "vnt2_info_view")
vnt2_info_view.rawhtml = true
vnt2_info_view.cfgvalue = function(self, section)
    local content = nixio.fs.readfile("/tmp/vnt2-cli_info") or ""
    return string.format("<pre>%s</pre>", luci.util.pcdata(content))
end

vnt2_ips = s:taboption("infos", Button, "vnt2_ips")
vnt2_ips.inputtitle = translate("客户端IP列表")
vnt2_ips.description = translate("点击按钮刷新，查看客户端IP列表")
vnt2_ips.inputstyle = "apply"
vnt2_ips.write = function()
  local uci = require "luci.model.uci".cursor()
  local ctrl_port = tonumber(uci:get_first("vnt2", "vnt2_cli", "ctrl_port")) or 11233
  local vnt2_cli_bin = uci:get_first("vnt2", "vnt2_cli", "vnt2_cli_bin") or "/usr/bin/vnt2-cli"
  os.execute(vnt2_cli_bin .. " ips --port " .. ctrl_port .. " >/tmp/vnt2-cli_ips 2>&1")
end

vnt2_ips_view = s:taboption("infos", DummyValue, "vnt2_ips_view")
vnt2_ips_view.rawhtml = true
vnt2_ips_view.cfgvalue = function(self, section)
    local content = nixio.fs.readfile("/tmp/vnt2-cli_ips") or ""
    return string.format("<pre>%s</pre>", luci.util.pcdata(content))
end

vnt2_clients = s:taboption("infos", Button, "vnt2_clients")
vnt2_clients.inputtitle = translate("客户端信息列表")
vnt2_clients.description = translate("点击按钮刷新，查看客户端信息列表")
vnt2_clients.inputstyle = "apply"
vnt2_clients.write = function()
  local uci = require "luci.model.uci".cursor()
  local ctrl_port = tonumber(uci:get_first("vnt2", "vnt2_cli", "ctrl_port")) or 11233
  local vnt2_cli_bin = uci:get_first("vnt2", "vnt2_cli", "vnt2_cli_bin") or "/usr/bin/vnt2-cli"
  os.execute(vnt2_cli_bin .. " clients --port " .. ctrl_port .. " >/tmp/vnt2-cli_clients 2>&1")
end

vnt2_clients_view = s:taboption("infos", DummyValue, "vnt2_clients_view")
vnt2_clients_view.rawhtml = true
vnt2_clients_view.cfgvalue = function(self, section)
    local content = nixio.fs.readfile("/tmp/vnt2-cli_clients") or ""
    return string.format("<pre>%s</pre>", luci.util.pcdata(content))
end

vnt2_route = s:taboption("infos", Button, "vnt2_route")
vnt2_route.inputtitle = translate("路由转发信息")
vnt2_route.description = translate("点击按钮刷新，查看本机路由转发路径")
vnt2_route.inputstyle = "apply"
vnt2_route.write = function()
  local uci = require "luci.model.uci".cursor()
  local ctrl_port = tonumber(uci:get_first("vnt2", "vnt2_cli", "ctrl_port")) or 11233
  local vnt2_cli_bin = uci:get_first("vnt2", "vnt2_cli", "vnt2_cli_bin") or "/usr/bin/vnt2-cli"
  os.execute(vnt2_cli_bin .. " route --port " .. ctrl_port .. " >/tmp/vnt2-cli_route 2>&1")
end

vnt2_route_view = s:taboption("infos", DummyValue, "vnt2_route_view")
vnt2_route_view.rawhtml = true
vnt2_route_view.cfgvalue = function(self, section)
    local content = nixio.fs.readfile("/tmp/vnt2-cli_route") or ""
    return string.format("<pre>%s</pre>", luci.util.pcdata(content))
end

-- 上传程序选项
local upload = s:taboption("upload", FileUpload, "upload_file")
upload.optional = true
upload.default = ""
upload.template = "vnt2/other_upload"
upload.description = translate("可直接上传二进制程序vnt2_cli或者以.tar.gz结尾的压缩包,上传新版本会自动覆盖旧版本，下载地址：<a href='https://github.com/vnt-dev/vnt/releases' target='_blank'>vnt2_cli</a><br>上传的文件将会保存在/tmp文件夹里，如果在高级设置里自定义了程序路径那么启动程序时将会自动移至自定义的路径<br>")
local um = s:taboption("upload",DummyValue, "", nil)
um.template = "vnt2/other_dvalue"

local dir, fd, chunk
dir = "/tmp/"
nixio.fs.mkdir(dir)
http.setfilehandler(
    function(meta, chunk, eof)
        if not fd then
            if not meta then return end
            if meta and chunk then fd = nixio.open(dir .. meta.file, "w") end
            if not fd then
                um.value = translate("错误：上传失败！")
                return
            end
        end
        if chunk and fd then
            fd:write(chunk)
        end
        if eof and fd then
            fd:close()
            fd = nil
            um.value = translate("文件已上传至") .. ' "/tmp/' .. meta.file .. '"'
            if string.sub(meta.file, -7) == ".tar.gz" then
                local file_path = dir .. meta.file
                os.execute("tar -xzf " .. file_path .. " -C " .. dir)
                if nixio.fs.access("/tmp/vnt2_cli") then
                    um.value = um.value .. "\n" .. translate("-程序/tmp/vnt2_cli上传成功，重启一次客户端才生效")
                end
            end
            os.execute("chmod 777 /tmp/vnt2_cli")
        end
    end
)
if luci.http.formvalue("upload") then
    local f = luci.http.formvalue("ulfile")
end

-- ==================== vnts2 服务端设置 ====================
s2 = m:section(TypedSection, "vnts2", translate("vnts2 服务端设置"))
s2.anonymous = true

s2:tab("server_general", translate("基本设置"))
s2:tab("server_web", translate("Web设置"))

-- 服务端基本设置
switch2 = s2:taboption("server_general", Flag, "enabled", translate("启用服务端"))
switch2.rmempty = false

btnsvr = s2:taboption("server_general", Button, "btnsvr", translate("重启服务端"))
btnsvr.inputtitle = translate("重启")
btnsvr.description = translate("在没有修改参数的情况下快速重新启动一次")
btnsvr.inputstyle = "apply"
btnsvr:depends("enabled", "1")
btnsvr.write = function()
  os.execute("/etc/init.d/vnt2 restart ")
end

server_port = s2:taboption("server_general", Value, "server_port", translate("服务端口"),
	translate("服务端监听的端口，用于接收客户端连接"))
server_port.datatype = "port"
server_port.placeholder = "6660"
server_port.default = "6660"

vnts2_bin = s2:taboption("server_general", Value, "vnts2_bin", translate("vnts2程序路径"),
	translate("自定义vnts2的存放路径，确保填写完整的路径及名称，默认会自动下载"))
vnts2_bin.placeholder = "/usr/bin/vnts2"

white_token = s2:taboption("server_general", Value, "white_token", translate("连接密钥"),
	translate("客户端连接时需要提供的密钥，留空则不验证"))
white_token.placeholder = ""

subnet = s2:taboption("server_general", Value, "subnet", translate("虚拟网段"),
	translate("服务端分配的虚拟网段，例如：10.0.0.1"))
subnet.placeholder = "10.0.0.1"

servern_netmask = s2:taboption("server_general", Value, "servern_netmask", translate("子网掩码"),
	translate("子网掩码，例如：255.255.255.0"))
servern_netmask.placeholder = "255.255.255.0"

logs = s2:taboption("server_general", Flag, "logs", translate("启用日志"),
	translate("启用后将记录服务端日志到/tmp/vnts2.log"))
logs.rmempty = false

-- Web界面设置
web = s2:taboption("server_web", Flag, "web", translate("启用Web管理界面"),
	translate("启用后可在本设备上通过浏览器管理服务端（mips架构不支持）"))
web.rmempty = false

web_port = s2:taboption("server_web", Value, "web_port", translate("Web管理端口"),
	translate("Web管理界面的访问端口"))
web_port.datatype = "port"
web_port.placeholder = "29870"
web_port.default = "29870"
web_port:depends("web", "1")

webuser = s2:taboption("server_web", Value, "webuser", translate("管理用户名"),
	translate("Web管理界面的登录用户名"))
webuser.placeholder = "admin"
webuser:depends("web", "1")

webpass = s2:taboption("server_web", Value, "webpass", translate("管理密码"),
	translate("Web管理界面的登录密码"))
webpass.placeholder = ""
webpass.password = true
webpass:depends("web", "1")

web_wan = s2:taboption("server_web", Flag, "web_wan", translate("允许从WAN访问"),
	translate("允许从广域网访问Web管理界面（建议设置强密码）"))
web_wan.rmempty = false
web_wan:depends("web", "1")

-- 服务端上传选项
local upload2 = s2:taboption("server_general", FileUpload, "upload_vnts2")
upload2.optional = true
upload2.default = ""
upload2.template = "vnt2/other_upload"
upload2.description = translate("可直接上传二进制程序vnts2或者以.tar.gz结尾的压缩包<br>下载地址：<a href='https://github.com/vnt-dev/vnt/releases' target='_blank'>vnts2</a>")
local um2 = s2:taboption("server_general",DummyValue, "", nil)
um2.template = "vnt2/other_dvalue"

http.setfilehandler(
    function(meta, chunk, eof)
        if not fd then
            if not meta then return end
            if meta and chunk then fd = nixio.open(dir .. meta.file, "w") end
            if not fd then
                um2.value = translate("错误：上传失败！")
                return
            end
        end
        if chunk and fd then
            fd:write(chunk)
        end
        if eof and fd then
            fd:close()
            fd = nil
            um2.value = translate("文件已上传至") .. ' "/tmp/' .. meta.file .. '"'
            if string.sub(meta.file, -7) == ".tar.gz" then
                local file_path = dir .. meta.file
                os.execute("tar -xzf " .. file_path .. " -C " .. dir)
                if nixio.fs.access("/tmp/vnts2") then
                    um2.value = um2.value .. "\n" .. translate("-程序/tmp/vnts2上传成功，重启一次服务端才生效")
                end
            end
            os.execute("chmod 777 /tmp/vnts2")
        end
    end
)

return m
