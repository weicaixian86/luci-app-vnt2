local http = require "luci.http"
local fs = require "nixio.fs"
local nixio = require "nixio"
local util = require "luci.util"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()
local dispatcher = require "luci.dispatcher"
local toml = require "luci.model.vnt2_toml"

local RESTART_PENDING_FILE = "/tmp/vnt2-restart.pending"
local UPLOAD_DIR = "/etc/vnt2/upload"
local UPLOAD_PENDING_FILE = "/etc/vnt2/upload.pending"
local MAX_UPLOAD_SIZE = 256 * 1024 * 1024

toml.ensure_toml_file(uci)

local m = Map("vnt2", translate("VNT2"))
m.description = translate(
	'VNT2 是一个简单、高效、可快速组建虚拟局域网的工具。<br>官网：<a href="https://rustvnt.com/" target="_blank">rustvnt.com</a>&nbsp;&nbsp;项目：<a href="https://github.com/vnt-dev/vnt" target="_blank">github.com/vnt-dev/vnt</a>&nbsp;&nbsp;当前 LuCI 插件仅适配 vnt2_web 客户端，适用于 OpenWrt 24.10、25.12，运行时配置文件为 /etc/config/vnt2.toml。'
)

m:section(SimpleSection).template = "vnt2/vnt2_status"

local function schedule_vnt2_restart()
	local value = tostring(os.time()) .. "\n"
	local stat = fs.readfile("/proc/self/stat") or ""
	local pid = stat:match("^(%d+)") or tostring(os.time())
	local temp = string.format("%s.%s", RESTART_PENDING_FILE, pid)

	if not fs.writefile(temp, value) then
		fs.remove(temp)
		return false
	end
	if not os.rename(temp, RESTART_PENDING_FILE) then
		fs.remove(temp)
		return false
	end
	return true
end

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

local function process_running(name)
	return sys.exec("pidof " .. util.shellquote(name) .. " 2>/dev/null"):match("%d+") ~= nil
end

local function render_pre_content(content)
	content = trim(content)
	if content == "" then
		content = translate("暂无数据")
	end
	return "<pre style='white-space:pre-wrap;word-break:break-all;'>" .. util.pcdata(content) .. "</pre>"
end

local function render_pre(path)
	return render_pre_content(fs.readfile(path) or "")
end
-- CBI validators may need values from sibling fields in the same form post.
local cbi_options = {}


local function add_file_upload_handler(note_options)
	local fd, uploaded_name, staged_path, upload_size, upload_rejected
	local stat = fs.readfile("/proc/self/stat") or ""
	local pid = stat:match("^(%d+)") or tostring(os.time())

	local function set_note(message)
		for _, opt in ipairs(note_options or {}) do
			opt.value = message
		end
	end

	local function write_atomic(path, value)
		local temp = string.format("%s.%s.%s", path, pid, tostring(os.time()))
		if not fs.writefile(temp, value) then
			fs.remove(temp)
			return false
		end
		if not fs.chmod(temp, "0600") then
			fs.remove(temp)
			return false
		end
		if not os.rename(temp, path) then
			fs.remove(temp)
			return false
		end
		return true
	end

	local function new_staged_path()
		local base = string.format("%s/incoming.%s.%s", UPLOAD_DIR, pid, tostring(os.time()))
		local suffix = 0
		local path = base

		while fs.access(path) do
			suffix = suffix + 1
			path = string.format("%s.%s", base, tostring(suffix))
		end
		return path
	end

	if fs.mkdirr(UPLOAD_DIR) == nil then
		fs.mkdirr(UPLOAD_DIR)
	end
	fs.chmod(UPLOAD_DIR, "0700")

	http.setfilehandler(function(meta, chunk, eof)
		if not fd then
			if not meta then
				return
			end

			local raw_name = tostring(meta.file or "")
			uploaded_name = raw_name:match("([^/\\]+)$") or raw_name
			uploaded_name = uploaded_name:gsub("[\r\n%z]", "")
			uploaded_name = uploaded_name:gsub("[^%w%._-]", "_")
			if uploaded_name == "" then
				return
			end

			staged_path = new_staged_path()
			upload_size = 0
			upload_rejected = false
			fd = nixio.open(staged_path, "w")
			if not fd then
				set_note(translate("错误：无法创建上传暂存文件"))
				return
			end
		end

		if chunk and fd then
			upload_size = upload_size + #chunk
			if upload_size > MAX_UPLOAD_SIZE then
				upload_rejected = true
				fd:close()
				fd = nil
				fs.remove(staged_path)
				set_note(translate("错误：上传文件超过 256 MiB 限制"))
			else
				fd:write(chunk)
			end
		end

		if eof and fd then
			fd:close()
			fd = nil

			if upload_rejected then
				return
			end

			if not fs.chmod(staged_path, "0600") then
				fs.remove(staged_path)
				set_note(translate("错误：无法保护上传暂存文件"))
				return
			end

			local marker = string.format(
				"time=%s\npath=%s\nname=%s\nsize=%s\n",
				tostring(os.time()),
				staged_path,
				uploaded_name,
				tostring(upload_size or 0)
			)
			if not write_atomic(UPLOAD_PENDING_FILE, marker) then
				fs.remove(staged_path)
				set_note(translate("错误：无法排队后台上传任务"))
				return
			end

			set_note(translate("上传文件已接收并进入后台处理队列，请查看下载日志获取安装结果。"))
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

local function validate_server_item(value, allow_udp)
	value = trim(value)
	if value == "" then
		return value
	end

	local scheme = value:match("^([a-zA-Z][a-zA-Z0-9+.-]*)://")
	local address = value
	if scheme then
		scheme = scheme:lower()
		if scheme ~= "quic" and scheme ~= "tcp" and scheme ~= "wss" and scheme ~= "dynamic"
			and not (allow_udp and scheme == "udp") then
			if allow_udp then
				return nil, translate("直连节点地址协议仅支持 tcp、udp 或 dynamic")
			end
			return nil, translate("服务器地址协议仅支持 quic、tcp、wss 或 dynamic")
		end
		if scheme == "dynamic" then
			return value:match("^dynamic://.+$") and value or nil, translate("dynamic 地址不能为空")
		end
		address = value:gsub("^[a-zA-Z][a-zA-Z0-9+.-]*://", "")
	end

	if address:match("^%d+%.%d+%.%d+%.%d+:%d+$")
		or address:match("^%[[0-9a-fA-F:]+%]:%d+$")
		or address:match("^[%w._-]+:%d+$") then
		return value
	end

	return nil, translate("服务器地址格式错误，支持 host:port、IPv4:port、[IPv6]:port 或 quic://host:port 等格式")
end

local function validate_peer_address(self, value)
	if type(value) == "table" then
		local values = normalized_list_values(value)
		if #values == 0 then
			return {}
		end

		local result = {}
		for _, item in ipairs(values) do
			local valid, err = validate_server_item(item, true)
			if not valid then
				return nil, err
			end
			result[#result + 1] = valid
		end
		return result
	end

	value = trim(value)
	if value == "" then
		return value
	end

	return validate_server_item(value, true)
end

local function validate_server(self, value)
	if type(value) == "table" then
		local values = normalized_list_values(value)
		if #values == 0 then
			return nil, translate("服务器地址不能为空")
		end

		local result = {}
		for _, item in ipairs(values) do
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

	value = trim(value)
	if value == "" then
		return nil, translate("服务器地址不能为空")
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

local function socket_port(value)
	value = trim(value)
	local port = value:match("^%[[^%]]+%]:(%d+)$") or value:match("^[^:]+:(%d+)$")
	port = tonumber(port or "")
	if port and port >= 0 and port <= 65535 then
		return port
	end
	return nil
end

local function is_ipv4(value)
	local count = 0
	for part in value:gmatch("[^%.]+") do
		count = count + 1
		if not part:match("^%d+$") or #part > 3 or tonumber(part) > 255 then
			return false
		end
	end
	return count == 4 and not value:match("^%.") and not value:match("%.$")
end

local function valid_ipv6_part(part)
	if part == "" or part:match("^:") or part:match(":$") then
		return false, 0
	end

	local count = 0
	for group in part:gmatch("[^:]+") do
		if group ~= "v" and not group:match("^[0-9a-fA-F]+$") then
			return false, 0
		end
		if group ~= "v" and #group > 4 then
			return false, 0
		end
		count = count + 1
	end
	return count > 0, count
end

local function is_ipv6(value)
	if not value:find(":", 1, true) then
		return false
	end

	local normalized = value
	if value:find(".", 1, true) then
		local prefix, suffix = value:match("^(.*:)([^:]+)$")
		if not prefix or not is_ipv4(suffix) then
			return false
		end
		normalized = prefix .. "v:v"
	end

	local left, right = normalized:match("^(.-)::(.-)$")
	if left ~= nil then
		if normalized:match("::.*::") then
			return false
		end
		local left_ok, left_count = valid_ipv6_part(left)
		local right_ok, right_count = valid_ipv6_part(right)
		if (left ~= "" and not left_ok) or (right ~= "" and not right_ok) then
			return false
		end
		return (left_count + right_count) < 8
	end

	if normalized:match("^:") or normalized:match(":$") then
		return false
	end
	local ok, count = valid_ipv6_part(normalized)
	return ok and count == 8
end

local function is_domain(value)
	if #value == 0 or #value > 253 then
		return false
	end
	if value:find("..", 1, true) then
		return false
	end
	for label in value:gmatch("[^%.]+") do
		if #label > 63 or label:match("^-") or label:match("-$")
			or not label:match("^[A-Za-z0-9-]+$") then
			return false
		end
	end
	return not value:match("^%.") and not value:match("%.$")
end

local function validate_socket_addr(self, value)
	value = trim(value)
	if value == "" then
		return value
	end
	local port = socket_port(value)
	if not port then
		return nil, translate("地址格式错误，应为 IP:port 或 [IPv6]:port")
	end

	local host
	if value:match("^%[[^%]]+%]:%d+$") then
		host = value:match("^%[([^%]]+)%]:%d+$")
	elseif value:match("^[^:]+:%d+$") then
		host = value:match("^([^:]+):%d+$")
	else
		return nil, translate("地址格式错误，应为 IP:port 或 [IPv6]:port")
	end

	if not is_ipv4(host) and not is_ipv6(host) and not is_domain(host) then
		return nil, translate("地址格式错误，应为 IP:port 或 [IPv6]:port")
	end
	if port == 0 then
		return nil, translate("监听端口不能为 0")
	end
	return value
end

local function validate_ip_socket_addr(self, value)
	value = trim(value)
	if value == "" then
		return value
	end

	local port = socket_port(value)
	if not port then
		return nil, translate("地址格式错误，应为 IPv4:port 或 [IPv6]:port")
	end

	local host
	if value:match("^%[[^%]]+%]:%d+$") then
		host = value:match("^%[([^%]]+)%]:%d+$")
	elseif value:match("^[^:]+:%d+$") then
		host = value:match("^([^:]+):%d+$")
	else
		return nil, translate("地址格式错误，应为 IPv4:port 或 [IPv6]:port")
	end

	if not is_ipv4(host) and not is_ipv6(host) then
		return nil, translate("绑定地址必须为 IPv4 或 IPv6 地址")
	end
	if port == 0 then
		return nil, translate("监听端口不能为 0")
	end
	return value
end

local function validate_bind_addr(self, value)
	return validate_ip_socket_addr(self, value)
end

local function validate_tunnel_addr(self, value)
	local values = normalized_list_values(value)
	local seen_ipv4 = false
	local seen_ipv6 = false
	local common_port
	local result = {}

	for _, item in ipairs(values) do
		local ipv4, ipv6, port
		local host, host_port = item:match("^([^:]+):(%d+)$")
		if host then
			ipv4 = host:match("^%d+%.%d+%.%d+%.%d+$")
			port = tonumber(host_port)
		else
			host, host_port = item:match("^%[([^%]]+)%]:(%d+)$")
			ipv6 = host
			port = tonumber(host_port)
		end

		if ipv4 and not is_ipv4(ipv4) then
			ipv4 = nil
		end
		if ipv6 and not is_ipv6(ipv6) then
			ipv6 = nil
		end
		if not port or port < 0 or port > 65535 or (not ipv4 and not ipv6) then
			return nil, translate("隧道地址必须为 IPv4:port 或 [IPv6]:port，端口 0 表示自动分配")
		end
		if common_port and common_port ~= port then
			return nil, translate("所有隧道地址必须使用相同端口")
		end
		common_port = port
		if ipv4 then
			if seen_ipv4 then
				return nil, translate("隧道地址每种 IP 地址族最多填写一个地址")
			end
			seen_ipv4 = true
		else
			if seen_ipv6 then
				return nil, translate("隧道地址每种 IP 地址族最多填写一个地址")
			end
			seen_ipv6 = true
		end
		result[#result + 1] = item
	end

	return #result > 0 and result or value
end

local function validate_ipv4_item(self, value)
	value = trim(value)
	if value == "" or is_ipv4(value) then
		return value
	end
	return nil, translate("请输入 IPv4 地址")
end

local function current_option(self, option)
	local value
	local option_object = cbi_options[option]
	if option_object and type(option_object.formvalue) == "function" then
		local ok, result = pcall(option_object.formvalue, option_object, self.section)
		if ok then
			value = result
		end
	end
	if self.map and type(self.map.formvalue) == "function" then
		if value == nil then
			local ok, result = pcall(self.map.formvalue, self.map, self.section, option)
			if ok then
				value = result
			end
		end
	end
	if type(value) == "table" then
		value = value[1]
	end
	if value == nil then
		value = self.map.uci:get(self.map.config, self.section, option)
	end
	return trim(value)
end

local function validate_ikev2_bind(self, value)
	return validate_ip_socket_addr(self, value)
end

local function validate_ikev2_natt_bind(self, value)
	value = trim(value)
	local valid, err = validate_ip_socket_addr(self, value)
	if not valid then
		return nil, err
	end
	local other = current_option(self, "ikev2_ike_bind")
	if other ~= "" and socket_port(other) == socket_port(value) then
		return nil, translate("IKEv2 与 NAT-T 监听端口不能相同")
	end
	return valid
end

local function validate_ikev2_server_address(self, value)
	value = trim(value)
	local enabled = current_option(self, "ikev2_enabled") == "1"
	if enabled and value == "" then
		return nil, translate("启用 IKEv2 时服务端地址不能为空")
	end
	if value ~= "" and not is_ipv4(value) and not is_ipv6(value) and not is_domain(value) then
		return nil, translate("IKEv2 服务端地址必须为域名、IPv4 或 IPv6 地址")
	end
	return value
end

local function validate_ikev2_remote_id(self, value)
	value = trim(value)
	local enabled = current_option(self, "ikev2_enabled") == "1"
	if enabled and value == "" then
		return nil, translate("启用 IKEv2 时 Remote ID 不能为空")
	end
	if value ~= "" and not is_ipv4(value) and not is_domain(value) then
		return nil, translate("IKEv2 Remote ID 必须为域名或 IPv4 地址")
	end
	return value
end

local function validate_ikev2_cert(self, value)
	value = trim(value)
	local key = current_option(self, "ikev2_key")
	if (value == "") ~= (key == "") then
		return nil, translate("IKEv2 证书和私钥必须同时填写或同时留空")
	end
	return value
end

local function validate_ikev2_key(self, value)
	value = trim(value)
	local cert = current_option(self, "ikev2_cert")
	if (value == "") ~= (cert == "") then
		return nil, translate("IKEv2 证书和私钥必须同时填写或同时留空")
	end
	return value
end

local function validate_wireguard_endpoint(self, value)
	value = trim(value)
	local enabled = current_option(self, "wireguard_enabled") == "1"
	if enabled and value == "" then
		return nil, translate("启用 WireGuard 时 Endpoint 不能为空")
	end
	if value ~= "" and not validate_socket_addr(self, value) then
		return nil, translate("WireGuard Endpoint 必须为 host:port 或 [IPv6]:port")
	end
	if value ~= "" and socket_port(value) == 0 then
		return nil, translate("WireGuard Endpoint 端口不能为 0")
	end
	return value
end

local function validate_wireguard_private_key(self, value)
	value = trim(value)
	if value ~= "" and (#value ~= 44 or not value:match("^[A-Za-z0-9+/]+=$")) then
		return nil, translate("WireGuard 私钥 Base64 解码后必须为 32 字节")
	end
	return value
end

local function validate_wireguard_keepalive(self, value)
	value = trim(value)
	local n = tonumber(value)
	if value == "" then
		return "25"
	end
	if n and n >= 0 and n <= 65535 and math.floor(n) == n then
		return tostring(math.floor(n))
	end
	return nil, translate("WireGuard 保活间隔必须为 0~65535 的整数")
end

local function validate_cidr(self, value)
	value = trim(value)
	if value == "" then
		return value
	end

	local address, prefix = value:match("^(%d+%.%d+%.%d+%.%d+)/(%d+)$")
	if address and is_ipv4(address) and tonumber(prefix) <= 32 then
		return value
	end

	return nil, translate("CIDR 格式错误，例如 10.26.0.0/24")
end

local function validate_custom_net_item(value)
	value = trim(value)
	if value == "" then
		return value
	end

	local code, cidr = value:match("^([^,]+),([^,]+)$")
	if not code or not cidr then
		return nil, translate("格式错误，应为网络编号,CIDR，例如 office,10.27.0.0/24")
	end

	code = trim(code)
	cidr = trim(cidr)
	if code == "" or #code > 32 or not code:match("^[A-Za-z0-9_.-]+$") then
		return nil, translate("网络编号只能包含字母、数字、下划线、点和短横线，长度不超过 32")
	end
	if not validate_cidr(nil, cidr) then
		return nil, translate("附加网段必须为有效 CIDR")
	end
	return code .. "," .. cidr
end

local function validate_rule_pair(value, first_validator, message)
	value = trim(value)
	if value == "" then
		return value
	end
	local first, second = value:match("^([^,]+),([^,]+)$")
	if not first or not second or not first_validator(first) then
		return nil, translate(message)
	end
	return value
end

local function ipv4_network_key(value)
	local address, prefix = value:match("^(%d+%.%d+%.%d+%.%d+)/(%d+)$")
	local a, b, c, d = address:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	local ip = ((tonumber(a) * 256 + tonumber(b)) * 256 + tonumber(c)) * 256 + tonumber(d)
	local prefix_number = tonumber(prefix)
	local host_size = 2 ^ (32 - prefix_number)
	return math.floor(ip / host_size) * host_size .. "/" .. prefix
end

local function is_ipv4_or_cidr(value)
	return validate_cidr(nil, value) or trim(value):match("^%d+%.%d+%.%d+%.%d+$")
end

local function validate_turn_item(value)
	value = trim(value)
	if value == "" then
		return value
	end
	local target, relay = value:match("^([^,]+),([^,]+)$")
	if not target or not relay or not is_ipv4_or_cidr(target) or not is_ipv4(trim(relay)) then
		return nil, translate("格式错误，应为目标 IP/CIDR,转发服务器 IPv4 地址")
	end
	return value
end

local function validate_punch_model_item(value)
	value = trim(value)
	if value == "" then
		return value
	end
	local target, modes = value:match("^([^,]+),(.+)$")
	if not target or not is_ipv4_or_cidr(target) then
		return nil, translate("格式错误，应为目标 IP/CIDR,IPv4Tcp,IPv4Udp 等打洞模式")
	end
	for mode in modes:gmatch("[^,]+") do
		if mode ~= "IPv4Tcp" and mode ~= "IPv4Udp" and mode ~= "IPv6Tcp" and mode ~= "IPv6Udp" then
			return nil, translate("打洞模式仅支持 IPv4Tcp、IPv4Udp、IPv6Tcp、IPv6Udp")
		end
	end
	return value
end

local function validate_subnet_mapping_item(value)
	local valid = validate_rule_pair(value, function(item)
		return validate_cidr(nil, item)
	end, "格式错误，应为映射 CIDR,实际 CIDR")
	if not valid then
		return nil, translate("格式错误，应为映射 CIDR,实际 CIDR")
	end
	local first, second = valid:match("^([^,]+),([^,]+)$")
	if not validate_cidr(nil, second) then
		return nil, translate("格式错误，应为映射 CIDR,实际 CIDR")
	end
	local _, mapped_prefix = first:match("^(%d+%.%d+%.%d+%.%d+)/(%d+)$")
	local _, actual_prefix = second:match("^(%d+%.%d+%.%d+%.%d+)/(%d+)$")
	if tonumber(mapped_prefix) ~= tonumber(actual_prefix) then
		return nil, translate("映射 CIDR 与实际 CIDR 的前缀长度必须相同")
	end
	if ipv4_network_key(first) == ipv4_network_key(second) then
		return nil, translate("映射网段与实际网段不能相同")
	end
	return valid
end

local function validate_subnet_mapping(self, value)
	if type(value) ~= "table" then
		return validate_subnet_mapping_item(value)
	end

	local result = {}
	local mapped_to_actual = {}
	local actual_to_mapped = {}
	for _, item in ipairs(normalized_list_values(value)) do
		local valid, err = validate_subnet_mapping_item(item)
		if not valid then
			return nil, err
		end

		local mapped, actual = valid:match("^([^,]+),([^,]+)$")
		local mapped_address, mapped_prefix = mapped:match("^(%d+%.%d+%.%d+%.%d+)/(%d+)$")
		local actual_address, actual_prefix = actual:match("^(%d+%.%d+%.%d+%.%d+)/(%d+)$")
		local mapped_key = ipv4_network_key(mapped)
		local actual_key = ipv4_network_key(actual)
		if mapped_to_actual[mapped_key] and mapped_to_actual[mapped_key] ~= actual_key then
			return nil, translate("存在冲突的映射网段")
		end
		if actual_to_mapped[actual_key] and actual_to_mapped[actual_key] ~= mapped_key then
			return nil, translate("存在冲突的实际网段映射")
		end
		mapped_to_actual[mapped_key] = actual_key
		actual_to_mapped[actual_key] = mapped_key
		result[#result + 1] = valid
	end
	return result
end

local function validate_dynamic_items(item_validator)
	return function(self, value)
		if type(value) == "table" then
			local result = {}
			for _, item in ipairs(normalized_list_values(value)) do
				local valid, err = item_validator(item)
				if not valid then
					return nil, err
				end
				if valid ~= "" then
					result[#result + 1] = valid
				end
			end
			return result
		end
		return item_validator(value)
	end
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

local function bind_download_mirror(option)
	option:value("auto", translate("自动"))
	option:value("gh-proxy", "gh-proxy")
	option:value("github", "GitHub")
	-- Keep legacy values visible for existing UCI configurations; init normalizes them.
	option:value("gitee", "Gitee")
	option:value("gitlab", "GitLab")
	option:value("cloudflare", "Cloudflare R2")
	option:value("custom", translate("自定义"))
	option.default = "auto"
	option.rmempty = false
end

local function bind_custom_download_mirror(option, mirror_option)
	option:depends(mirror_option, "custom")
	option.placeholder = "https://gh-proxy.com/"
	option.description = translate("请输入镜像前缀，例如 https://gh-proxy.com/；下载时会将 GitHub 原始 URL 拼接到此前缀后，失败后回退 GitHub 原地址")
	option.validate = function(self, value)
		value = trim(value)
		if value == "" then
			return nil, translate("选择自定义镜像源时必须填写镜像源地址")
		end
		if not value:match("^https?://[^%s]+/?$") then
			return nil, translate("自定义镜像源地址必须以 http:// 或 https:// 开头，且不能包含空格")
		end
		return value
	end
end

local web_enabled_state = m.uci:get_first("vnt2", "vnt2_web", "enabled") == "1"
local web_running = web_enabled_state and process_running("vnt2_web")

-- ==================== vnt2_web ====================
;(function()
local w = m:section(TypedSection, "vnt2_web", translate("vnt2_web 客户端设置"))
w.anonymous = true
w.addremove = false

w:tab("general", translate("基本设置"))
w:tab("advanced", translate("高级设置"))
w:tab("upload", translate("上传程序"))

local web_enabled = w:taboption("general", Flag, "enabled", translate("启用web 客户端"))
web_enabled.rmempty = false
web_enabled.default = "0"
web_enabled.write = function(self, section, value)
	self.map.uci:set(self.map.config, section, self.option, value)
end

local web_restart = w:taboption("general", Button, "_restart_web", translate("重启客户端"))
web_restart.inputtitle = translate("重启")
web_restart.inputstyle = "apply"
web_restart.description = translate("在未修改参数时快速重启 vnt2_web")
web_restart:depends("enabled", "1")
web_restart.write = function()
	schedule_vnt2_restart()
end

local web_conf_path = w:taboption("advanced", DummyValue, "_web_conf_path", translate("配置文件路径"),
	translate("运行时配置文件位置固定为 /etc/config/vnt2.toml，不允许在页面中修改"))
web_conf_path.cfgvalue = function()
	return "/etc/config/vnt2.toml"
end

local auto_download_web = w:taboption("advanced", Flag, "auto_download", translate("自动下载程序"),
	translate("当本地缺少 vnt2_web 时，自动从所选镜像源的 Releases 下载匹配当前架构的发行包"))
auto_download_web.rmempty = false
auto_download_web.default = "1"

local download_mirror_web = w:taboption("advanced", ListValue, "download_mirror", translate("Web 下载镜像源"),
	translate("自动依次尝试 gh-proxy、GitHub、Gitee、GitLab、Cloudflare R2，每个源最多重试 3 次；客户端 ZIP 必须包含 vnt2_web"))
bind_download_mirror(download_mirror_web)
local custom_download_mirror_web = w:taboption("advanced", Value, "custom_download_mirror", translate("Web 自定义镜像地址"))
bind_custom_download_mirror(custom_download_mirror_web, "download_mirror")

local download_tag_web = w:taboption("advanced", Value, "download_tag", translate("Web 下载版本"),
	translate("填写 latest 表示始终获取最新版本，也可填写指定 Release 标签，如 v2.0.18"))
download_tag_web.placeholder = "latest"
download_tag_web.default = "latest"
download_tag_web.validate = validate_nonempty

local download_repo_web = w:taboption("advanced", Value, "download_repo", translate("Web 下载仓库"),
	translate("默认 vnt-dev/vnt；如需使用 Gitee、GitLab、Cloudflare 等镜像，建议保持默认仓库"))
download_repo_web.placeholder = "vnt-dev/vnt"
download_repo_web.default = "vnt-dev/vnt"
download_repo_web.validate = validate_nonempty

local vnt2_web_bin = w:taboption("general", Value, "vnt2_web_bin", translate("vnt2_web 程序路径"),
	translate("默认 /usr/bin/vnt2_web；若不存在，将优先尝试自动下载，失败后回退到已上传并安装到 /usr/bin 的程序"))
vnt2_web_bin.placeholder = "/usr/bin/vnt2_web"
vnt2_web_bin.validate = validate_nonempty

local web_host = w:taboption("general", Value, "web_host", translate("监听地址"),
	translate("默认监听 0.0.0.0，允许局域网或其他外部设备访问；如需限制仅本机访问，可改为 127.0.0.1"))
web_host.placeholder = "0.0.0.0"
web_host.default = "0.0.0.0"
web_host.datatype = "ipaddr"

local web_port = w:taboption("general", Value, "web_port", translate("监听端口"))
web_port.placeholder = "19099"
web_port.datatype = "port"

local web_wan = w:taboption("general", Flag, "web_wan", translate("允许 WAN 访问"),
	translate("默认启用；当监听地址为 0.0.0.0 或 :: 时会自动创建 WAN 放行规则"))
web_wan.rmempty = false
web_wan.default = "1"

local open_web = w:taboption("general", DummyValue, "_open_web", translate("打开 Web 页面"),
	translate("打开当前配置对应的 Web 管理页面，默认地址通常为 http://路由器IP:19099/"))
open_web.rawhtml = true
open_web.cfgvalue = function()
	return string.format(
		'<a class="btn cbi-button cbi-button-apply" href="%s" target="_blank" rel="noopener noreferrer">%s</a>',
		util.pcdata(dispatcher.build_url("admin", "vpn", "vnt2", "open_web")),
		util.pcdata(translate("打开 Web 页面"))
	)
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
web_upload.description = translate("支持上传 vnt2_web 二进制文件或包含 vnt2_web 的 .tar.gz 压缩包；文件会先暂存，再由后台上传 worker 校验并安装到 /usr/bin/；当自动下载失败时，系统会回退使用已经安装的有效程序。")

local web_upload_note = w:taboption("upload", DummyValue, "_upload_note_web")
web_upload_note.rawhtml = true
web_upload_note.template = "vnt2/other_dvalue"
cbi_options.web_upload_note = web_upload_note
end)()


add_file_upload_handler({
	cbi_options.web_upload_note
})

return m
