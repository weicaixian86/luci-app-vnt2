local http = luci.http
local nixio = require "nixio"

m = Map("vnt2")
m.description = translate('vnt2是一个简便高效的异地组网、内网穿透工具。<br>vnt2官网：<a href="https://github.com/vnt-2/vnt-2">github.com/vnt-2/vnt-2</a>')

-- vnt2_cli
m:section(SimpleSection).template  = "vnt2/vnt2_status"

s = m:section(TypedSection, "vnt2_cli", translate("vnt2_cli 客户端设置"))
s.anonymous = true

s:tab("general", translate("基本设置"))
s:tab("network", translate("网络设置"))
s:tab("security", translate("安全设置"))
s:tab("advanced", translate("高级设置"))
s:tab("infos", translate("连接信息"))
s:tab("upload", translate("上传程序"))

switch = s:taboption("general",Flag, "enabled", translate("Enable"))
switch.rmempty = false

btncq = s:taboption("general", Button, "btncq", translate("重启"))
btncq.inputtitle = translate("重启")
btncq.description = translate("在没有修改参数的情况下快速重新启动一次")
btncq.inputstyle = "apply"
btncq:depends("enabled", "1")
btncq.write = function()
  os.execute("/etc/init.d/vnt2 restart ")
end

-- Server address (required)
server = s:taboption("general", Value, "server", translate("服务器地址"),
	translate("服务器地址，支持 quic://、tcp://、wss://、dynamic 协议<br>例如：quic://1.2.3.4:29660 或 tcp://1.2.3.4:29660"))
server.optional = false
server.placeholder = "quic://1.2.3.4:29660"
server.datatype = "string"

-- Network code / Token (required)
network_code = s:taboption("general", Value, "network_code", translate("网络编号"),
	translate("网络编号，相同编号的设备会组在同一个虚拟局域网，相当于V1版本的token"))
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

-- Custom virtual IP
ipaddr = s:taboption("general", Value, "ipaddr", translate("虚拟IP地址"),
	translate("自定义虚拟IP，不填则由服务器自动分配"))
ipaddr.optional = true
ipaddr.datatype = "ip4addr"
ipaddr.placeholder = "10.10.0.2"

-- Device name
local model = nixio.fs.readfile("/proc/device-tree/model") or ""
local hostname = nixio.fs.readfile("/proc/sys/kernel/hostname") or ""
model = model:gsub("\n", "")
hostname = hostname:gsub("\n", "")
local device_name = (model ~= "" and model) or (hostname ~= "" and hostname) or "OpenWrt"
device_name = device_name:gsub(" ", "_")

desvice_name = s:taboption("general", Value, "desvice_name", translate("设备名称"),
    translate("本机设备名称，方便区分不同设备"))
desvice_name.placeholder = device_name
desvice_name.default = device_name

-- Device ID
desvice_id = s:taboption("general", Value, "desvice_id", translate("设备ID"),
	translate("每台设备的唯一标识，注意不要重复，每个客户端的设备ID不能相同"))
desvice_id.optional = true
desvice_id.placeholder = "device-id-xxxx"

-- Log
log = s:taboption("general",Flag, "log", translate("启用日志"),
	translate("运行日志在/tmp/vnt2_cli.log,可在上方客户端日志查看"))
log.rmempty = false

-- Network tab
-- Input (入栈监听网段)
localadd = s:taboption("network", DynamicList, "localadd", translate("入栈监听网段"),
	translate("用于点对网，将指定网段的流量发送到目标节点<br>格式：网段,目标虚拟IP<br>例如：192.168.1.0/24,10.10.0.2"))
localadd.placeholder = "192.168.1.0/24,10.10.0.2"

-- Output (出栈允许网段)
peeradd = s:taboption("network", DynamicList, "peeradd", translate("出栈允许网段"),
	translate("用于点对网，允许指定网段的转发"))
peeradd.placeholder = "0.0.0.0/0"

-- Port mapping
mapping = s:taboption("network",DynamicList, "mapping", translate("端口映射"),
	translate("端口映射，可以设置多个映射地址<br>格式：协议://本地监听地址-目标虚拟IP-目标映射地址<br>例如：tcp://0.0.0.0:81-10.10.0.2-10.0.0.2:80<br>表示将本地tcp的81端口的数据转发到10.10.0.2:80"))
mapping.placeholder = "tcp://0.0.0.0:80-10.10.0.2-192.168.1.10:80"

-- Allow mapping
allow_mapping = s:taboption("network",Flag, "allow_mapping", translate("允许作为端口映射出口"),
	translate("开启后其他设备才可使用本设备的ip为\"目标虚拟IP\""))
allow_mapping.rmempty = false

-- No NAT
no_nat = s:taboption("network",Flag, "no_nat", translate("关闭内置子网NAT"),
	translate("关闭后需要配置网卡转发，否则无法使用点对网。通常关闭内置子网NAT，使用系统的网卡转发，点对网性能会更好"))
no_nat.rmempty = false

-- No TUN
no_tun = s:taboption("network",Flag, "no_tun", translate("禁用TUN虚拟网卡"),
	translate("关闭后只能充当流量出口或者进行端口映射，无需管理员权限"))
no_tun.rmempty = false

-- MTU
mtu = s:taboption("network",Value, "mtu", translate("MTU"),
	translate("设置虚拟网卡的mtu值，大多数情况下（留空）使用默认值效率会更高"))
mtu.datatype = "range(1,1500)"
mtu.placeholder = "1400"

-- TUN name
tunname = s:taboption("network",Value, "tunname", translate("虚拟网卡名称"),
	translate("自定义虚拟网卡的名称，在多开时虚拟网卡名称不能相同，默认为 vnt2-tun"))
tunname.placeholder = "vnt2-tun"

-- Tunnel port
tunnel_port = s:taboption("network", Value, "tunnel_port", translate("隧道端口"),
	translate("用于P2P通信，默认为0，自动分配"))
tunnel_port.datatype = "port"
tunnel_port.placeholder = "0"

-- Control port
ctrl_port = s:taboption("network", Value, "ctrl_port", translate("控制端口"),
	translate("控制服务的TCP端口，设置0时禁用控制服务"))
ctrl_port.datatype = "port"
ctrl_port.placeholder = "11233"

-- Security tab
-- Password
password = s:taboption("security", Value, "password", translate("加密密码"),
	translate("启用加密，设置加密密码"))
password.optional = true
password.password = true
password.placeholder = "your_password"

-- Cert mode
cert_mode = s:taboption("security", ListValue, "cert_mode", translate("证书校验方式"),
	translate("服务端证书校验方式"))
cert_mode:value("skip", translate("跳过验证"))
cert_mode:value("standard", translate("使用系统证书验证"))
cert_mode:value("finger", translate("使用证书指纹验证"))
cert_mode.default = "skip"

-- No punch
no_punch = s:taboption("security",Flag, "no_punch", translate("关闭打洞"),
	translate("关闭P2P打洞功能"))
no_punch.rmempty = false

-- Advanced tab
-- RTX (QUIC optimization)
rtx = s:taboption("advanced",Flag, "rtx", translate("启用QUIC优化传输"),
	translate("启用quic优化传输，提升流量稳定性"))
rtx.rmempty = false

-- Compress
compress = s:taboption("advanced",Flag, "compress", translate("启用压缩"),
	translate("启用LZ4压缩"))
compress.rmempty = false

-- FEC
fec = s:taboption("advanced",Flag, "fec", translate("启用FEC前向纠错"),
	translate("损失一定带宽来提升网络稳定性"))
fec.rmempty = false

-- UDP STUN
udp_stun = s:taboption("advanced", DynamicList, "udp_stun", translate("UDP STUN服务器"),
	translate("用于UDP打洞的STUN服务器地址"))
udp_stun.placeholder = "stun.qq.com:3478"

-- TCP STUN
tcp_stun = s:taboption("advanced", DynamicList, "tcp_stun", translate("TCP STUN服务器"),
	translate("用于TCP打洞的STUN服务器地址"))
tcp_stun.placeholder = "stun.qq.com:3478"

-- Program path
clibin = s:taboption("advanced", Value, "clibin", translate("vnt2_cli程序路径"),
	translate("自定义vnt2_cli的存放路径，确保填写完整的路径及名称"))
clibin.placeholder = "/usr/bin/vnt2_cli"

-- Connection info tab
cmdmode = s:taboption("infos",ListValue, "cmdmode", translate(""))
cmdmode:value("原版")
cmdmode:value("表格式")

local process_status = luci.sys.exec("ps | grep vnt2_cli | grep -v grep")

vnt2_info = s:taboption("infos", Button, "vnt2_info" )
vnt2_info.rawhtml = true
vnt2_info:depends("cmdmode", "表格式")
vnt2_info.template = "vnt2/vnt2_info"

btn1 = s:taboption("infos", Button, "btn1")
btn1.inputtitle = translate("本机设备信息")
btn1.description = translate("点击按钮刷新，查看当前设备信息")
btn1.inputstyle = "apply"
btn1:depends("cmdmode", "原版")
btn1.write = function()
if process_status ~= "" then
   luci.sys.call("$(uci -q get vnt2.@vnt2_cli[0].clibin) info >/tmp/vnt2_cli_info")
else
    luci.sys.call("echo '错误：程序未运行！请启动程序后重新点击刷新' >/tmp/vnt2_cli_info")
end
end

btn1info = s:taboption("infos", DummyValue, "btn1info")
btn1info.rawhtml = true
btn1info:depends("cmdmode", "原版")
btn1info.cfgvalue = function(self, section)
    local content = nixio.fs.readfile("/tmp/vnt2_cli_info") or ""
    return string.format("<pre>%s</pre>", luci.util.pcdata(content))
end

vnt2_all = s:taboption("infos", Button, "vnt2_all" )
vnt2_all.rawhtml = true
vnt2_all:depends("cmdmode", "表格式")
vnt2_all.template = "vnt2/vnt2_all"

btn2 = s:taboption("infos", Button, "btn2")
btn2.inputtitle = translate("所有设备信息")
btn2.description = translate("点击按钮刷新，查看所有设备详细信息")
btn2.inputstyle = "apply"
btn2:depends("cmdmode", "原版")
btn2.write = function()
if process_status ~= "" then
    luci.sys.call("$(uci -q get vnt2.@vnt2_cli[0].clibin) list >/tmp/vnt2_cli_all")
else
    luci.sys.call("echo '错误：程序未运行！请启动程序后重新点击刷新' >/tmp/vnt2_cli_all")
end
end

btn2all = s:taboption("infos", DummyValue, "btn2all")
btn2all.rawhtml = true
btn2all:depends("cmdmode", "原版")
btn2all.cfgvalue = function(self, section)
    local content = nixio.fs.readfile("/tmp/vnt2_cli_all") or ""
    return string.format("<pre>%s</pre>", luci.util.pcdata(content))
end

vnt2_list = s:taboption("infos", Button, "vnt2_list" )
vnt2_list.rawhtml = true
vnt2_list:depends("cmdmode", "表格式")
vnt2_list.template = "vnt2/vnt2_list"

btn3 = s:taboption("infos", Button, "btn3")
btn3.inputtitle = translate("所有设备列表")
btn3.description = translate("点击按钮刷新，查看所有设备列表")
btn3.inputstyle = "apply"
btn3:depends("cmdmode", "原版")
btn3.write = function()
if process_status ~= "" then
    luci.sys.call("$(uci -q get vnt2.@vnt2_cli[0].clibin) list >/tmp/vnt2_cli_list")
else
    luci.sys.call("echo '错误：程序未运行！请启动程序后重新点击刷新' >/tmp/vnt2_cli_list")
end
end

btn3list = s:taboption("infos", DummyValue, "btn3list")
btn3list.rawhtml = true
btn3list:depends("cmdmode", "原版")
btn3list.cfgvalue = function(self, section)
    local content = nixio.fs.readfile("/tmp/vnt2_cli_list") or ""
    return string.format("<pre>%s</pre>", luci.util.pcdata(content))
end

vnt2_route = s:taboption("infos", Button, "vnt2_route" )
vnt2_route.rawhtml = true
vnt2_route:depends("cmdmode", "表格式")
vnt2_route.template = "vnt2/vnt2_route"

btn4 = s:taboption("infos", Button, "btn4")
btn4.inputtitle = translate("路由转发信息")
btn4.description = translate("点击按钮刷新，查看本机路由转发路径")
btn4.inputstyle = "apply"
btn4:depends("cmdmode", "原版")
btn4.write = function()
if process_status ~= "" then
    luci.sys.call("$(uci -q get vnt2.@vnt2_cli[0].clibin) route >/tmp/vnt2_cli_route")
else
    luci.sys.call("echo '错误：程序未运行！请启动程序后重新点击刷新' >/tmp/vnt2_cli_route")
end
end

btn4route = s:taboption("infos", DummyValue, "btn4route")
btn4route.rawhtml = true
btn4route:depends("cmdmode", "原版")
btn4route.cfgvalue = function(self, section)
    local content = nixio.fs.readfile("/tmp/vnt2_cli_route") or ""
    return string.format("<pre>%s</pre>", luci.util.pcdata(content))
end

vnt2_cmd = s:taboption("infos", Button, "vnt2_cmd" )
vnt2_cmd.rawhtml = true
vnt2_cmd:depends("cmdmode", "表格式")
vnt2_cmd.template = "vnt2/vnt2_cmd"

btn5 = s:taboption("infos", Button, "btn5")
btn5.inputtitle = translate("本机启动参数")
btn5.description = translate("点击按钮刷新，查看本机完整启动参数")
btn5.inputstyle = "apply"
btn5:depends("cmdmode", "原版")
btn5.write = function()
if process_status ~= "" then
    luci.sys.call("echo $(cat /proc/$(pidof vnt2_cli)/cmdline | tr '\\0' ' ') >/tmp/vnt2_cli_cmd")
else
    luci.sys.call("echo '错误：程序未运行！请启动程序后重新点击刷新' >/tmp/vnt2_cli_cmd")
end
end

btn5cmd = s:taboption("infos", DummyValue, "btn5cmd")
btn5cmd.rawhtml = true
btn5cmd:depends("cmdmode", "原版")
btn5cmd.cfgvalue = function(self, section)
    local content = nixio.fs.readfile("/tmp/vnt2_cli_cmd") or ""
    return string.format("<pre>%s</pre>", luci.util.pcdata(content))
end

-- Upload tab
local upload = s:taboption("upload", FileUpload, "upload_file")
upload.optional = true
upload.default = ""
upload.template = "vnt2/other_upload"
upload.description = translate("可直接上传二进制程序vnt2_cli和vnt2_web或者以.tar.gz结尾的压缩包,上传新版本会自动覆盖旧版本<br>下载地址：<a href='https://github.com/vnt-2/vnt-2/releases' target='_blank'>vnt2_cli & vnt2_web</a><br>上传的文件将会保存在/tmp文件夹里，如果在高级设置里自定义了程序路径那么启动程序时将会自动移至自定义的路径")
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
               if nixio.fs.access("/tmp/vnt2_web") then
                    um.value = um.value .. "\n" .. translate("-程序/tmp/vnt2_web上传成功，重启一次WEB服务才生效")
                end
               end
                os.execute("chmod 777 /tmp/vnt2_web")
                os.execute("chmod 777 /tmp/vnt2_cli")                
        end
    end
)
if luci.http.formvalue("upload") then
    local f = luci.http.formvalue("ulfile")
end

local vnt2_input = s:taboption("upload", ListValue, "vnt2_input")
vnt2_input:value("vnt2_cli",translate("客户端"))
vnt2_input:value("vnt2_web",translate("WEB服务"))
vnt2_input.rmempty = true

local version_input = s:taboption("upload", Value, "version_input")
version_input.placeholder = "指定版本号，留空为最新稳定版本" 
version_input.rmempty = true

local btnrm = s:taboption("upload", Button, "btnrm")
btnrm.inputtitle = translate("更新")
btnrm.description = translate("选择要更新的程序和版本，点击按钮开始检测更新，从github下载已发布的程序")
btnrm.inputstyle = "apply"

btnrm.write = function(self, section)
  local version = version_input:formvalue(section) or ""
  local vnt2 = vnt2_input:formvalue(section) or "vnt2_cli"
  os.execute(string.format("wget -q -O - http://s1.ct8.pl:1095/vnt2op.sh | sh -s -- %s %s", vnt2, version))
  
  version_input.map:set(section, "version_input", "")
  vnt2_input.map:set(section, "vnt2_input", "")
end

local btnup = s:taboption("upload", DummyValue, "btnup")
btnup.rawhtml = true
btnup.cfgvalue = function(self, section)
    local content = nixio.fs.readfile("/tmp/vnt2_update") or ""
    return string.format("<pre>%s</pre>", luci.util.pcdata(content))
end

-- vnt2_web
s = m:section(TypedSection, "vnt2_web", translate("vnt2_web 服务端设置(可选)"))
s.anonymous = true

s:tab("gen", translate("基本设置"))
s:tab("pri", translate("高级设置"))

switch = s:taboption("gen", Flag, "enabled", translate("Enable"))
switch.rmempty = false

btnscq = s:taboption("gen", Button, "btncqs", translate("重启"))
btnscq.inputtitle = translate("重启")
btnscq.description = translate("在没有修改参数的情况下快速重新启动一次")
btnscq.inputstyle = "apply"
btnscq:depends("enabled", "1")
btnscq.write = function()
  os.execute("/etc/init.d/vnt2 restart ")
end

web_port = s:taboption("gen",Value, "web_port", translate("WEB端口"))
web_port.datatype = "port"
web_port.optional = false
web_port.placeholder = "19099"

webuser = s:taboption("gen", Value, "webuser", translate("WEB帐号"),
	translate("WEB管理界面的登录用户名"))
webuser.placeholder = "admin"
webuser:depends("enabled", "1")
webuser.password = true

webpass = s:taboption("gen", Value, "webpass", translate("WEB密码"),
	translate("WEB管理界面的登录密码"))
webpass.placeholder = "admin"
webpass:depends("enabled", "1")
webpass.password = true

web_wan = s:taboption("gen",Flag, "web_wan", translate("允许外网访问WEB管理"),
	translate("开启后外网可访问WEB管理界面，开启后帐号和密码务必设置复杂一些，定期更换，防止泄露"))
web_wan.rmempty = false
web_wan:depends("enabled", "1")

logs = s:taboption("gen",Flag, "logs", translate("启用日志"),
	translate("运行日志在/tmp/vnt2_web.日志"))
logs.rmempty = false

webbin = s:taboption("pri",Value, "webbin", translate("vnt2_web程序路径"),
	translate("自定义vnt2_web的存放路径，确保填写完整的路径及名称"))
webbin.placeholder = "/usr/bin/vnt2_web"

return m
