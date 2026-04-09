local http = require "luci.http"
local fs = require "nixio.fs"
local nixio = require "nixio"
local util = require "luci.util"
local sys = require "luci.sys"

local m = Map("vnt2", translate("VNT2"))
m.description = translate('VNT2 是一个简单、高效、可快速组建虚拟局域网的工具。<br>官网：<a href="https://rustvnt.com/" target="_blank">rustvnt.com</a>&nbsp;&nbsp;项目：<a href="https://github.com/vnt-dev/vnt" target="_blank">github.com/vnt-dev/vnt</a>&nbsp;&nbsp;当前 LuCI 适配基于 vnt2_cli / vnt2_ctrl / vnt2_web 实际能力开发，适用于 OpenWrt 24.10。')

m:section(SimpleSection).template = "vnt2/vnt2_status"

local function trim(v)
	if v == nil then
		return ""
	end

	local t = type(v)
	if t == "string" then
		return util.trim(v)
	end

	if t == "number" or t == "boolean" then
		return util.trim(tostring(v))
	end

	return ""
end

local function default_device_name()
	local model = trim(fs.readfile("/proc/device-tree/model") or "")
	local hostname = trim(fs.readfile("/proc/sys/kernel/hostname") or "")
	local def = (model ~= "" and model) or (hostname ~= "" and hostname) or "OpenWrt"
	return def:gsub("[%s/]+", "_")
end

local function process_running(name)
	return sys.exec("pidof " .. util.shellquote(name) .. " 2>/dev/null"):match("%d+") ~= nil
end

local function render_pre(path)
	local content = fs.readfile(path) or ""
	if content == "" then
		content = translate("暂无数据")
	end
	return "<pre style='white-space:pre-wrap;word-break:break-all;'>" .. util.pcdata(content) .. "</pre>"
end

local function list_net_devices()
	local devs, seen = {}, {}
	local lines = sys.exec("ip -o -4 addr show 2>/dev/null | awk '{print $2\" \"$4}'")
	for line in string.gmatch(lines or "", "[^\n]+") do
		local iface, ip = line:match("^(%S+)%s+(%S+)$")
		if iface and ip and iface ~= "lo" and not seen[iface] then
			seen[iface] = true
			devs[#devs + 1] = { iface = iface, ip = ip }
		end
	end
	table.sort(devs, function(a, b)
		return a.iface < b.iface
	end)
	return devs
end

local function add_file_upload_handler(note_options)
	local dir = "/tmp/"
	local fd
	local uploaded_name

	fs.mkdir(dir)

	http.setfilehandler(function(meta, chunk, eof)
		if not fd then
			if not meta then
				return
			end

			uploaded_name = meta.file or ""
			if uploaded_name == "" then
				return
			end

			fd = nixio.open(dir .. uploaded_name, "w")
			if not fd then
				for _, opt in ipairs(note_options) do
					opt.value = translate("错误：上传失败")
				end
				return
			end
		end

		if chunk and fd then
			fd:write(chunk)
		end

		if eof and fd then
			fd:close()
			fd = nil

			local full = dir .. uploaded_name
			local msg = translate("文件已上传至") .. " " .. util.pcdata(full)

			if uploaded_name:sub(-7) == ".tar.gz" then
				sys.call("tar -xzf " .. util.shellquote(full) .. " -C /tmp >/dev/null 2>&1")
				for _, bin in ipairs({ "vnt2_cli", "vnt2_ctrl", "vnt2_web" }) do
					if fs.access(dir .. bin) then
						sys.call("chmod 755 " .. util.shellquote(dir .. bin) .. " >/dev/null 2>&1")
						msg = msg .. "<br />- " .. util.pcdata(dir .. bin) .. " " .. translate("已就绪，重启服务后生效")
					end
				end
			else
				sys.call("chmod 755 " .. util.shellquote(full) .. " >/dev/null 2>&1")
				msg = msg .. "<br />- " .. translate("文件已赋予执行权限")
			end

			for _, opt in ipairs(note_options) do
				opt.value = msg
			end
		end
	end)
end

local function validate_nonempty(self, value)
	value = trim(value)
	if value == "" then
		return nil, translate("该字段不能为空")
	end
	return value
end

local function normalized_list_values(value)
	local result = {}

	if type(value) == "string" then
		value = { value }
	end

	if type(value) ~= "table" then
		return result
	end

	for _, item in ipairs(value) do
		item = trim(item)
		if item ~= "" then
			result[#result + 1] = item
		end
	end

	return result
end

local function validate_server_item(value)
	value = trim(value)
	if value == "" then
		return value
	end

	if value:match("^[a-zA-Z][a-zA-Z0-9+.-]*://.+$") then
		return value
	end

	if value:match("^%d+%.%d+%.%d+%.%d+:%d+$") then
		return value
	end

	if value:match("^%[[0-9a-fA-F:]+%]:%d+$") then
		return value
	end

	if value:match("^[%w._-]+:%d+$") then
		return value
	end

	return nil, translate("服务器地址格式错误，支持 host:port、IPv4:port、[IPv6]:port 或 quic://host:port 等格式")
end

local function validate_server(self, value)
	if type(value) == "table" then
		local result = {}
		for _, item in ipairs(normalized_list_values(value)) do
			local valid, err = validate_server_item(item)
			if not valid then
				return nil, err
			end
			if valid ~= "" then
				result[#result + 1] = valid
			end
		end
		return result
	end

	return validate_server_item(value)
end

local function validate_port_or_zero(self, value)
	value = trim(value)
	if value == "" then
		return value
	end

	local n = tonumber(value)
	if n and n >= 0 and n <= 65535 and tostring(math.floor(n)) == tostring(n) then
		return tostring(math.floor(n))
	end

	return nil, translate("端口范围必须为 0~65535")
end

local function validate_input_rule_item(value)
	value = trim(value)
	if value == "" then
		return value
	end
	if not value:match("^[^,]+,%s*%d+%.%d+%.%d+%.%d+$") then
		return nil, translate("格式错误，应为 CIDR,目标虚拟IP，例如 192.168.1.0/24,10.26.0.2")
	end
	return value
end

local function validate_input_rule(self, value)
	if type(value) == "table" then
		local result = {}
		for _, item in ipairs(normalized_list_values(value)) do
			local valid, err = validate_input_rule_item(item)
			if not valid then
				return nil, err
			end
			if valid ~= "" then
				result[#result + 1] = valid
			end
		end
		return result
	end

	return validate_input_rule_item(value)
end

local function validate_port_mapping_item(value)
	value = trim(value)
	if value == "" then
		return value
	end
	if not value:match("^[%w]+://.+%-.+%-.+$") then
		return nil, translate("格式错误，应为 协议://本地监听地址-目标虚拟IP-目标映射地址")
	end
	return value
end

local function validate_port_mapping(self, value)
	if type(value) == "table" then
		local result = {}
		for _, item in ipairs(normalized_list_values(value)) do
			local valid, err = validate_port_mapping_item(item)
			if not valid then
				return nil, err
			end
			if valid ~= "" then
				result[#result + 1] = valid
			end
		end
		return result
	end

	return validate_port_mapping_item(value)
end

local function validate_cert_mode(self, value)
	value = trim(value)
	if value == "" then
		return "skip"
	end
	if value == "skip" or value == "standard" or value:match("^finger:[0-9a-fA-F]+$") then
		return value
	end
	return nil, translate("证书验证模式仅支持 skip、standard 或 finger:指纹")
end

local function bind_dynamiclist(option)
	option.cfgvalue = function(self, section)
		local value = AbstractValue.cfgvalue(self, section)
		local result = normalized_list_values(value)
		if #result == 0 then
			return nil
		end
		return result
	end

	option.write = function(self, section, value)
		local values = normalized_list_values(value)
		self.map.uci:delete(self.map.config, section, self.option)
		if #values > 0 then
			self.map.uci:set_list(self.map.config, section, self.option, values)
		end
	end

	option.remove = function(self, section)
		self.map.uci:delete(self.map.config, section, self.option)
	end
end

local cli_running = process_running("vnt2_cli")
local web_running = process_running("vnt2_web")

-- ==================== vnt2_cli ====================
local s = m:section(TypedSection, "vnt2_cli", translate("vnt2_cli 客户端设置"))
s.anonymous = true
s.addremove = false

s:tab("general", translate("基本设置"))
s:tab("network", translate("网络与映射"))
s:tab("security", translate("安全设置"))
s:tab("stun", translate("STUN 设置"))
s:tab("advanced", translate("高级设置"))
s:tab("infos", translate("连接信息"))
s:tab("upload", translate("上传程序"))

local enabled = s:taboption("general", Flag, "enabled", translate("启用cli 客户端"))
enabled.rmempty = false
enabled.write = function(self, section, value)
	self.map.uci:set(self.map.config, section, self.option, value)
	if value == "1" then
		self.map.uci:set(self.map.config, "vnt2_web", "enabled", "0")
	end
end

local restart_btn = s:taboption("general", Button, "_restart_cli", translate("重启客户端"))
restart_btn.inputtitle = translate("重启")
restart_btn.inputstyle = "apply"
restart_btn.description = translate("在未修改参数时快速重启 vnt2_cli")
restart_btn:depends("enabled", "1")
restart_btn.write = function()
	sys.call("/etc/init.d/vnt2 restart >/dev/null 2>&1")
end

local network_code = s:taboption("general", Value, "network_code", translate("网络编号"),
	translate("同一服务器下，使用相同网络编号的客户端会加入同一虚拟局域网"))
network_code.rmempty = false
network_code.placeholder = "123456"
network_code.validate = function(self, value)
	value = trim(value)
	if value ~= "" and #value >= 1 and #value <= 63 then
		return value
	end
	return nil, translate("网络编号必须为 1~63 个字符")
end

local server = s:taboption("general", DynamicList, "server", translate("服务器地址"),
	translate("支持 quic://、tcp://、wss://、dynamic:// 等格式，可填写多个以实现容灾或负载均衡"))
server.rmempty = false
server.placeholder = "quic://101.35.230.139:6660"
server.validate = validate_server
bind_dynamiclist(server)

local ip = s:taboption("general", Value, "ip", translate("虚拟 IP"),
	translate("留空则由服务端自动分配"))
ip.placeholder = "10.10.0.2"
ip.datatype = "ip4addr"

local device_id = s:taboption("general", Value, "device_id", translate("设备 ID"),
	translate("每台设备建议固定且唯一；留空则自动生成"))
device_id.placeholder = ""

local device_name = s:taboption("general", Value, "device_name", translate("设备名称"),
	translate("显示在节点列表中，便于区分设备"))
device_name.placeholder = default_device_name()
device_name.default = default_device_name()

local password = s:taboption("general", Value, "password", translate("通信加密密码"),
	translate("用于客户端之间加密通信，留空则不启用"))
password.password = true

local cert_mode = s:taboption("security", Value, "cert_mode", translate("服务端证书验证"),
	translate("支持 skip、standard、finger:证书指纹"))
cert_mode.placeholder = "skip"
cert_mode.default = "skip"
cert_mode.validate = validate_cert_mode

local compress = s:taboption("security", Flag, "compress", translate("启用压缩（LZ4）"))
compress.rmempty = false

local fec = s:taboption("security", Flag, "fec", translate("启用 FEC 前向纠错"),
	translate("在弱网环境下提升稳定性，但会增加带宽开销"))
fec.rmempty = false

local rtx = s:taboption("security", Flag, "rtx", translate("启用 QUIC 优化传输"),
	translate("适用于需要提升链路稳定性的场景"))
rtx.rmempty = false

local no_punch = s:taboption("security", Flag, "no_punch", translate("禁用 P2P 打洞"),
	translate("开启后将优先通过中继或服务端转发"))
no_punch.rmempty = false

local input = s:taboption("network", DynamicList, "input", translate("入栈监听规则"),
	translate("格式：CIDR,目标虚拟IP，例如 192.168.1.0/24,10.26.0.2"))
input.placeholder = "192.168.1.0/24,10.26.0.2"
input.validate = validate_input_rule
bind_dynamiclist(input)

local output = s:taboption("network", DynamicList, "output", translate("出栈允许网段"),
	translate("例如 0.0.0.0/0；用于限制可访问的目标网段"))
output.placeholder = "0.0.0.0/0"
bind_dynamiclist(output)

local port_mapping = s:taboption("network", DynamicList, "port_mapping", translate("端口映射"),
	translate("格式：协议://本地监听地址-目标虚拟IP-目标映射地址，例如 tcp://0.0.0.0:81-10.0.0.2-10.0.0.2:80"))
port_mapping.placeholder = "tcp://0.0.0.0:81-10.0.0.2-10.0.0.2:80"
port_mapping.validate = validate_port_mapping
bind_dynamiclist(port_mapping)

local allow_mapping = s:taboption("network", Flag, "allow_mapping", translate("允许作为端口映射出口"),
	translate("开启后其他客户端可借助本机执行映射出口"))
allow_mapping.rmempty = false

local no_nat = s:taboption("network", Flag, "no_nat", translate("关闭内置子网 NAT"),
	translate("关闭后若需跨网段访问，请自行配置 OpenWrt 转发/NAT"))
no_nat.rmempty = false

local no_tun = s:taboption("network", Flag, "no_tun", translate("无 TUN 模式"),
	translate("启用后不创建虚拟网卡，仅适用于端口映射或流量出口类场景"))
no_tun.rmempty = false

local vnt2_forward = s:taboption("network", MultiValue, "vnt2_forward", translate("访问控制 / 防火墙转发"),
	translate("按需自动创建 OpenWrt 防火墙区域与转发规则"))
vnt2_forward:value("vnt2fwlan", translate("允许从 VNT2 到 LAN"))
vnt2_forward:value("vnt2fwwan", translate("允许从 VNT2 到 WAN"))
vnt2_forward:value("lanfwvnt2", translate("允许从 LAN 到 VNT2"))
vnt2_forward:value("wanfwvnt2", translate("允许从 WAN 到 VNT2"))
vnt2_forward.widget = "checkbox"

local udp_stun = s:taboption("stun", DynamicList, "udp_stun", translate("UDP STUN 列表"),
	translate("不带端口时通常默认使用 3478"))
udp_stun.placeholder = "stun.chat.bilibili.com:3478"
bind_dynamiclist(udp_stun)

local tcp_stun = s:taboption("stun", DynamicList, "tcp_stun", translate("TCP STUN 列表"),
	translate("适用于 TCP / TLS / WSS 环境探测"))
tcp_stun.placeholder = "stun.nextcloud.com:443"
bind_dynamiclist(tcp_stun)

local download_repo_cli = s:taboption("advanced", Value, "download_repo", translate("客户端下载仓库"),
	translate("默认 vnt-dev/vnts，通常无需修改"))
download_repo_cli.placeholder = "vnt-dev/vnts"
download_repo_cli.default = "vnt-dev/vnts"
download_repo_cli.validate = validate_nonempty

local vnt2_cli_bin = s:taboption("advanced", Value, "vnt2_cli_bin", translate("vnt2_cli 程序路径"),
	translate("默认 /usr/bin/vnt2_cli；若不存在，将优先尝试自动下载，失败后回退到 /tmp 上传程序"))
vnt2_cli_bin.placeholder = "/usr/bin/vnt2_cli"
vnt2_cli_bin.validate = validate_nonempty

local vnt2_ctrl_bin = s:taboption("advanced", Value, "vnt2_ctrl_bin", translate("vnt2_ctrl 程序路径"),
	translate("用于读取运行状态、节点信息、路由信息；自动下载成功后会自动写入实际路径"))
vnt2_ctrl_bin.placeholder = "/usr/bin/vnt2_ctrl"
vnt2_ctrl_bin.validate = validate_nonempty

local cli_conf_file = s:taboption("advanced", Value, "cli_conf_file", translate("配置文件路径"),
	translate("用于指定 vnt2_cli 运行时配置文件路径"))
cli_conf_file.placeholder = "/etc/vnt2/vnt2-cli.toml"
cli_conf_file.default = "/etc/vnt2/vnt2-cli.toml"
cli_conf_file.validate = validate_nonempty

local cli_conf_shared_tip = s:taboption("advanced", DummyValue, "_cli_conf_shared_tip")
cli_conf_shared_tip.rawhtml = true
cli_conf_shared_tip.cfgvalue = function()
	return [[
<div class="cbi-value-description">vnt2_cli 客户端和 vnt2_web 客户端 共用同一配置文件</div>
]]
end

local tun_name = s:taboption("advanced", Value, "tun_name", translate("虚拟网卡名称"),
	translate("多开时请确保不同实例网卡名不冲突"))
tun_name.placeholder = "vnt-tun"

local mtu = s:taboption("advanced", Value, "mtu", translate("MTU"))
mtu.placeholder = "1400"
mtu.datatype = "range(576,9000)"

local ctrl_port = s:taboption("advanced", Value, "ctrl_port", translate("控制端口"),
	translate("vnt2_ctrl 将通过该端口读取状态，设置 0 表示关闭"))
ctrl_port.placeholder = "11233"
ctrl_port.validate = validate_port_or_zero

local tunnel_port = s:taboption("advanced", Value, "tunnel_port", translate("隧道端口"),
	translate("用于 P2P 通信，0 表示自动分配"))
tunnel_port.placeholder = "0"
tunnel_port.validate = validate_port_or_zero

local bind_dev = s:taboption("advanced", ListValue, "bind_dev", translate("绑定出口网卡"),
	translate("当前 vnt2 原生参数未直接提供对应选项，此项作为扩展保留并由 init 脚本保存"))
bind_dev:value("", translate("不绑定"))
for _, dev in ipairs(list_net_devices()) do
	bind_dev:value(dev.iface, dev.iface .. " (" .. dev.ip .. ")")
end

local info_mode = s:taboption("infos", ListValue, "info_mode", translate("显示模式"))
info_mode:value("panel", translate("面板说明"))
info_mode:value("raw", translate("原始输出"))
info_mode.default = "panel"
info_mode.rmempty = false

local panel_tip = s:taboption("infos", DummyValue, "_panel_tip", translate("面板说明"))
panel_tip.rawhtml = true
panel_tip:depends("info_mode", "panel")
panel_tip.cfgvalue = function()
	return [[
<div class="cbi-value-description">
	<div>1. 页面顶部状态面板支持自动轮询显示客户端 / Web 服务运行状态、版本、资源占用与当前配置摘要。</div>
	<div>2. 当前页面下方可手动读取 vnt2_ctrl 输出，包括本机信息、节点列表、设备详情、路由信息和实际启动参数。</div>
	<div>3. 日志实时查看请进入“客户端日志 / Web 日志”菜单。</div>
</div>
]]
end

local btn1 = s:taboption("infos", Button, "_info_raw", translate("本机设备信息"))
btn1.inputtitle = translate("刷新本机设备信息")
btn1.inputstyle = "apply"
btn1:depends("info_mode", "raw")
btn1.write = function()
	if cli_running then
		sys.call("(vnt2_ctrl info --port $(uci -q get vnt2.@vnt2_cli[0].ctrl_port 2>/dev/null || echo 11233) || vnt2_ctrl info $(uci -q get vnt2.@vnt2_cli[0].ctrl_port 2>/dev/null || echo 11233) || vnt2_cli info) >/tmp/vnt2-cli_info 2>&1")
	else
		sys.call("echo '错误：程序未运行！请先启动 vnt2_cli。' >/tmp/vnt2-cli_info")
	end
end

local btn1info = s:taboption("infos", DummyValue, "_info_content")
btn1info.rawhtml = true
btn1info:depends("info_mode", "raw")
btn1info.cfgvalue = function()
	return render_pre("/tmp/vnt2-cli_info")
end

local btn2 = s:taboption("infos", Button, "_ips_raw", translate("所有节点列表"))
btn2.inputtitle = translate("刷新所有节点列表")
btn2.inputstyle = "apply"
btn2:depends("info_mode", "raw")
btn2.write = function()
	if cli_running then
		sys.call("(vnt2_ctrl ips --port $(uci -q get vnt2.@vnt2_cli[0].ctrl_port 2>/dev/null || echo 11233) || vnt2_ctrl ips $(uci -q get vnt2.@vnt2_cli[0].ctrl_port 2>/dev/null || echo 11233) || vnt2_cli ips) >/tmp/vnt2-cli_ips 2>&1")
	else
		sys.call("echo '错误：程序未运行！请先启动 vnt2_cli。' >/tmp/vnt2-cli_ips")
	end
end

local btn2ips = s:taboption("infos", DummyValue, "_ips_content")
btn2ips.rawhtml = true
btn2ips:depends("info_mode", "raw")
btn2ips.cfgvalue = function()
	return render_pre("/tmp/vnt2-cli_ips")
end

local btn3 = s:taboption("infos", Button, "_clients_raw", translate("所有设备详情"))
btn3.inputtitle = translate("刷新所有设备详情")
btn3.inputstyle = "apply"
btn3:depends("info_mode", "raw")
btn3.write = function()
	if cli_running then
		sys.call("(vnt2_ctrl clients --port $(uci -q get vnt2.@vnt2_cli[0].ctrl_port 2>/dev/null || echo 11233) || vnt2_ctrl clients $(uci -q get vnt2.@vnt2_cli[0].ctrl_port 2>/dev/null || echo 11233) || vnt2_cli clients) >/tmp/vnt2-cli_clients 2>&1")
	else
		sys.call("echo '错误：程序未运行！请先启动 vnt2_cli。' >/tmp/vnt2-cli_clients")
	end
end

local btn3clients = s:taboption("infos", DummyValue, "_clients_content")
btn3clients.rawhtml = true
btn3clients:depends("info_mode", "raw")
btn3clients.cfgvalue = function()
	return render_pre("/tmp/vnt2-cli_clients")
end

local btn4 = s:taboption("infos", Button, "_route_raw", translate("路由转发信息"))
btn4.inputtitle = translate("刷新路由转发信息")
btn4.inputstyle = "apply"
btn4:depends("info_mode", "raw")
btn4.write = function()
	if cli_running then
		sys.call("(vnt2_ctrl route --port $(uci -q get vnt2.@vnt2_cli[0].ctrl_port 2>/dev/null || echo 11233) || vnt2_ctrl route $(uci -q get vnt2.@vnt2_cli[0].ctrl_port 2>/dev/null || echo 11233) || vnt2_cli route) >/tmp/vnt2-cli_route 2>&1")
	else
		sys.call("echo '错误：程序未运行！请先启动 vnt2_cli。' >/tmp/vnt2-cli_route")
	end
end

local btn4route = s:taboption("infos", DummyValue, "_route_content")
btn4route.rawhtml = true
btn4route:depends("info_mode", "raw")
btn4route.cfgvalue = function()
	return render_pre("/tmp/vnt2-cli_route")
end

local btn5 = s:taboption("infos", Button, "_cmd_raw", translate("本机启动参数"))
btn5.inputtitle = translate("刷新本机启动参数")
btn5.inputstyle = "apply"
btn5:depends("info_mode", "raw")
btn5.write = function()
	if cli_running then
		sys.call("tr '\\000' ' ' </proc/$(pidof vnt2_cli | awk '{print $1}')/cmdline >/tmp/vnt2-cli_cmd 2>/dev/null")
	else
		sys.call("echo '错误：程序未运行！请先启动 vnt2_cli。' >/tmp/vnt2-cli_cmd")
	end
end

local btn5cmd = s:taboption("infos", DummyValue, "_cmd_content")
btn5cmd.rawhtml = true
btn5cmd:depends("info_mode", "raw")
btn5cmd.cfgvalue = function()
	return render_pre("/tmp/vnt2-cli_cmd")
end

local upload = s:taboption("upload", FileUpload, "upload_file")
upload.optional = true
upload.default = ""
upload.template = "vnt2/other_upload"
upload.description = translate("支持上传 vnt2_cli / vnt2_ctrl / vnt2_web 二进制文件，或包含这些文件的 .tar.gz 压缩包。文件会存入 /tmp，重启服务后生效；当自动下载失败时，系统会自动回退使用这里上传的程序。")

local upload_note = s:taboption("upload", DummyValue, "_upload_note")
upload_note.rawhtml = true
upload_note.template = "vnt2/other_dvalue"

-- ==================== vnt2_web ====================
local w = m:section(TypedSection, "vnt2_web", translate("vnt2_web 客户端设置"))
w.anonymous = true
w.addremove = false

w:tab("general", translate("基本设置"))
w:tab("advanced", translate("高级设置"))
w:tab("upload", translate("上传程序"))

local web_enabled = w:taboption("general", Flag, "enabled", translate("启用web 客户端"))
web_enabled.rmempty = false
web_enabled.write = function(self, section, value)
	self.map.uci:set(self.map.config, section, self.option, value)
	if value == "1" then
		self.map.uci:set(self.map.config, "vnt2_cli", "enabled", "0")
	end
end

local web_restart = w:taboption("general", Button, "_restart_web", translate("重启 Web 服务"))
web_restart.inputtitle = translate("重启")
web_restart.inputstyle = "apply"
web_restart.description = translate("快速重启 vnt2_web")
web_restart:depends("enabled", "1")
web_restart.write = function()
	sys.call("/etc/init.d/vnt2 restart >/dev/null 2>&1")
end

local download_repo_web = w:taboption("general", Value, "download_repo", translate("Web 下载仓库"),
	translate("默认 vnt-dev/vnts，通常无需修改"))
download_repo_web.placeholder = "vnt-dev/vnts"
download_repo_web.default = "vnt-dev/vnts"
download_repo_web.validate = validate_nonempty

local vnt2_web_bin = w:taboption("general", Value, "vnt2_web_bin", translate("vnt2_web 程序路径"),
	translate("默认 /usr/bin/vnt2_web；若不存在，将优先尝试自动下载，失败后回退到 /tmp 上传程序"))
vnt2_web_bin.placeholder = "/usr/bin/vnt2_web"
vnt2_web_bin.validate = validate_nonempty

local web_cli_conf_file = w:taboption("general", Value, "_shared_cli_conf_file", translate("配置文件路径"),
	translate("用于指定 vnt2_cli / vnt2_web 共用配置文件路径"))
web_cli_conf_file.placeholder = "/etc/vnt2/vnt2-cli.toml"
web_cli_conf_file.default = "/etc/vnt2/vnt2-cli.toml"
web_cli_conf_file.cfgvalue = function(self, section)
	return m.uci:get("vnt2", "vnt2_cli", "cli_conf_file") or "/etc/vnt2/vnt2-cli.toml"
end
web_cli_conf_file.write = function(self, section, value)
	value = trim(value)
	if value == "" then
		value = "/etc/vnt2/vnt2-cli.toml"
	end
	m.uci:set("vnt2", "vnt2_cli", "cli_conf_file", value)
end
web_cli_conf_file.remove = function(self, section)
	m.uci:delete("vnt2", "vnt2_cli", "cli_conf_file")
end
web_cli_conf_file.validate = validate_nonempty

local web_cli_conf_shared_tip = w:taboption("general", DummyValue, "_web_cli_conf_shared_tip")
web_cli_conf_shared_tip.rawhtml = true
web_cli_conf_shared_tip.cfgvalue = function()
	return [[
<div class="cbi-value-description">vnt2_cli 客户端和 vnt2_web 客户端 共用同一配置文件</div>
]]
end

local web_host = w:taboption("general", Value, "web_host", translate("监听地址"),
	translate("默认仅监听本地 127.0.0.1；若需外部访问，请改为 0.0.0.0 并按需开启 WAN 放行"))
web_host.placeholder = "127.0.0.1"
web_host.datatype = "ipaddr"

local web_port = w:taboption("general", Value, "web_port", translate("监听端口"))
web_port.placeholder = "19099"
web_port.datatype = "port"

local web_wan = w:taboption("general", Flag, "web_wan", translate("允许 WAN 访问"),
	translate("仅当监听地址为 0.0.0.0 或 :: 时才会自动创建 WAN 放行规则"))
web_wan.rmempty = false

local open_web = w:taboption("general", Button, "_open_web", translate("打开页面"),
	translate("打开当前配置对应的 Web 管理页面，默认地址通常为 http://127.0.0.1:19099/"))
open_web.inputtitle = translate("打开页面")
open_web.inputstyle = "apply"
open_web.write = function()
	http.redirect(luci.dispatcher.build_url("admin", "vpn", "vnt2", "open_web"))
end

local web_user = w:taboption("advanced", Value, "web_user", translate("页面备注用户名"),
	translate("当前原生 vnt2_web 未由本 LuCI 页面接管认证，此处仅作为备注保存"))
web_user.placeholder = "admin"

local web_pass = w:taboption("advanced", Value, "web_pass", translate("页面备注密码"),
	translate("当前原生 vnt2_web 未由本 LuCI 页面接管认证，此处仅作为备注保存"))
web_pass.password = true

local log_level = w:taboption("advanced", ListValue, "log_level", translate("日志级别"),
	translate("通过环境变量 RUST_LOG 注入给 vnt2_web"))
for _, lv in ipairs({ "error", "warn", "info", "debug", "trace" }) do
	log_level:value(lv, lv)
end
log_level.default = "info"

local web_cmd = w:taboption("advanced", Button, "_web_cmd", translate("读取 Web 启动参数"))
web_cmd.inputtitle = translate("刷新")
web_cmd.inputstyle = "apply"
web_cmd.write = function()
	if web_running then
		sys.call("tr '\\000' ' ' </proc/$(pidof vnt2_web | awk '{print $1}')/cmdline >/tmp/vnt2-web_cmd 2>/dev/null")
	else
		sys.call("echo '错误：程序未运行！请先启动 vnt2_web。' >/tmp/vnt2-web_cmd")
	end
end

local web_cmd_content = w:taboption("advanced", DummyValue, "_web_cmd_content")
web_cmd_content.rawhtml = true
web_cmd_content.cfgvalue = function()
	return render_pre("/tmp/vnt2-web_cmd")
end

local web_upload = w:taboption("upload", FileUpload, "upload_web")
web_upload.optional = true
web_upload.default = ""
web_upload.template = "vnt2/other_upload"
web_upload.description = translate("支持上传 vnt2_web 二进制文件或包含 vnt2_web 的 .tar.gz 压缩包；当自动下载失败时，系统会自动回退使用这里上传的程序。")

local web_upload_note = w:taboption("upload", DummyValue, "_upload_note_web")
web_upload_note.rawhtml = true
web_upload_note.template = "vnt2/other_dvalue"

add_file_upload_handler({ upload_note, web_upload_note })

return m
