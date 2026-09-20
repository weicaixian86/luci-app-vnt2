local http = require "luci.http"
local fs = require "nixio.fs"
local nixio = require "nixio"
local util = require "luci.util"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()
local dispatcher = require "luci.dispatcher"
local toml = require "luci.model.vnt2_toml"

local RESTART_PENDING_FILE = "/tmp/vnt2-restart.pending"

toml.ensure_toml_files(uci)

local m = Map("vnt2", translate("VNT2"))
m.description = translate(
	'VNT2 是一个简单、高效、可快速组建虚拟局域网的工具。<br>官网：<a href="https://rustvnt.com/" target="_blank">rustvnt.com</a>&nbsp;&nbsp;项目：<a href="https://github.com/vnt-dev/vnt" target="_blank">github.com/vnt-dev/vnt</a>&nbsp;&nbsp;当前 LuCI 适配同时覆盖 vnt2_cli / vnt2_ctrl / vnt2_web / vnts2，适用于 OpenWrt 24.10，其中 CLI 与 Web 共用同一个配置文件 /vnt_config/vnt2_cli_web.toml，服务端配置文件为 /etc/config/vnts2.toml。'
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

local function split_words(value)
	local items = {}

	if type(value) == "table" then
		for _, item in ipairs(value) do
			item = trim(item)
			for word in item:gmatch("%S+") do
				word = trim(word)
				if word ~= "" then
					items[#items + 1] = word
				end
			end
		end
		return items
	end

	value = trim(value)
	if value == "" then
		return items
	end

	for item in value:gmatch("%S+") do
		item = trim(item)
		if item ~= "" then
			items[#items + 1] = item
		end
	end

	return items
end

local function read_uci_list_or_words(cursor, config, section, option)
	local value = cursor:get_list(config, section, option)
	if type(value) == "table" and #value > 0 then
		return split_words(value)
	end

	return split_words(cursor:get(config, section, option))
end

local function write_uci_list(cursor, config, section, option, value)
	local items = split_words(value)

	cursor:delete(config, section, option)
	if #items > 0 then
		cursor:set_list(config, section, option, items)
	end
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

local function set_sections_option_by_type(config, stype, option, value)
	m.uci:foreach(config, stype, function(section)
		m.uci:set(config, section[".name"], option, value)
	end)
end

local function render_mutual_exclusion_script()
	return [[
<script type="text/javascript">
(function() {
	function textOf(node) {
		return (node && (node.textContent || node.innerText) || "").replace(/\s+/g, " ").trim();
	}

	function findCheckboxByLabel(labelText) {
		var labels = document.querySelectorAll("label");
		for (var i = 0; i < labels.length; i++) {
			if (textOf(labels[i]) === labelText) {
				var forId = labels[i].getAttribute("for");
				if (forId) {
					var input = document.getElementById(forId);
					if (input && input.type === "checkbox") {
						return input;
					}
				}
				var nested = labels[i].querySelector('input[type="checkbox"]');
				if (nested) {
					return nested;
				}
			}
		}
		return null;
	}

	function bindExclusive(a, b) {
		if (!a || !b || a._vnt2ExclusiveBound) {
			return;
		}
		a._vnt2ExclusiveBound = true;
		a.addEventListener("change", function() {
			if (a.checked) {
				b.checked = false;
			}
		});
	}

	function initExclusive() {
		var cli = findCheckboxByLabel("启用cli 客户端");
		var web = findCheckboxByLabel("启用web 客户端");
		bindExclusive(cli, web);
		bindExclusive(web, cli);
	}

	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", initExclusive);
	} else {
		initExclusive();
	}
})();
</script>
]]
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

local function cli_running_now()
	return process_running("vnt2_cli")
end

local function get_cli_ctrl_port()
	local port = trim(m.uci:get_first("vnt2", "vnt2_cli", "ctrl_port"))
	if port == "" then
		port = "11233"
	end
	return port
end

local function run_cli_info_command(subcmd, out_file)
	local port = get_cli_ctrl_port()
	local ctrl_bin = trim(m.uci:get_first("vnt2", "vnt2_cli", "vnt2_ctrl_bin"))
	if ctrl_bin == "" then
		ctrl_bin = "/usr/bin/vnt2_ctrl"
	end

	local cmd
	if port == "" or port == "0" then
		cmd = util.shellquote(ctrl_bin) .. " " .. subcmd
	else
		cmd = util.shellquote(ctrl_bin) .. " --port " .. util.shellquote(port) .. " " .. subcmd
	end

	sys.call(cmd .. " >" .. util.shellquote(out_file) .. " 2>&1")
end

local function translate_info_labels(content)
	local mapping = {
		["Connection status"] = "连接状态",
		["Virtual ip"] = "虚拟IP",
		["Virtual gateway"] = "虚拟网关",
		["Virtual netmask"] = "虚拟网络掩码",
		["NAT type"] = "NAT类型",
		["Nat Type"] = "NAT类型",
		["Relay server"] = "服务器地址",
		["Public ips"] = "外网IP",
		["Public ip"] = "外网IP",
		["Public Ipv4"] = "公网IPv4",
		["Ipv6"] = "公网IPv6",
		["Local addr"] = "本地地址",
		["Local address"] = "本地地址",
		["Device name"] = "设备名称",
		["Device id"] = "设备ID",
		["Name"] = "名称",
		["Id"] = "设备ID",
		["Version"] = "版本",
		["IP"] = "虚拟IP",
		["Total Clients"] = "总节点",
		["Online Clients"] = "在线节点",
		["Offline Clients"] = "离线节点",
		["P2P Clients"] = "P2P节点",
		["Last Connected Time"] = "上次连接时间",
		["Server"] = "服务器",
		["Connect server"] = "连接服务器",
		["Current device"] = "当前设备",
		["Peers"] = "对端设备",
		["Node list"] = "节点列表",
		["Protocol"] = "协议",
		["Interface"] = "接口",
		["Next Hop"] = "下一跳",
		["Destination"] = "目标网段",
		["Destination IP"] = "目标IP",
		["Metric"] = "跃点",
		["Remote Address"] = "远端地址",
		["RTT (ms)"] = "RTT(ms)",
		["RTT"] = "RTT(ms)",
		["Online"] = "在线",
		["P2P"] = "直连",
		["Route"] = "路由",
		["Status"] = "状态"
	}

	for en, zh in pairs(mapping) do
		content = content:gsub(en, zh)
	end

	return content
end

local function strip_ansi_sequences(content)
	content = tostring(content or "")
	content = content:gsub("\27%[[%d;?]*[%a]", "")
	content = content:gsub("\27%][^\7]*\7", "")
	return content
end

local function normalize_cli_output(content)
	return strip_ansi_sequences(content):gsub("\r", "")
end

local function html_escape_keep_br(value)
	return util.pcdata(value or ""):gsub("\n", "<br />")
end

local function render_key_value_table(content, title)
	content = trim(normalize_cli_output(content))
	if content == "" then
		return "<div class='cbi-value-description'>" .. translate("暂无数据") .. "</div>"
	end

	content = translate_info_labels(content)

	local rows = {}
	for line in content:gmatch("[^\r\n]+") do
		local key, value = line:match("^%s*([^:：]+)%s*[:：]%s*(.-)%s*$")
		if key and value then
			rows[#rows + 1] = "<tr><td style='white-space:nowrap;font-weight:bold;width:180px;'>" .. util.pcdata(key)
				.. "</td><td>" .. html_escape_keep_br(value) .. "</td></tr>"
		elseif trim(line) ~= "" then
			rows[#rows + 1] = "<tr><td colspan='2'>" .. html_escape_keep_br(line) .. "</td></tr>"
		end
	end

	if #rows == 0 then
		return "<pre style='white-space:pre-wrap;word-break:break-all;'>" .. util.pcdata(content) .. "</pre>"
	end

	local caption = ""
	if title and title ~= "" then
		caption = "<div class='cbi-value-title' style='margin-bottom:6px;'>" .. util.pcdata(title) .. "</div>"
	end

	return caption
		.. "<table class='table cbi-section-table' style='width:100%;'><tbody>"
		.. table.concat(rows)
		.. "</tbody></table>"
end

local function render_whitespace_table(content, title)
	content = trim(normalize_cli_output(content))
	if content == "" then
		return "<div class='cbi-value-description'>" .. translate("暂无数据") .. "</div>"
	end

	content = translate_info_labels(content)

	local lines = {}
	for line in content:gmatch("[^\r\n]+") do
		if trim(line) ~= "" then
			lines[#lines + 1] = line
		end
	end

	if #lines == 0 then
		return "<div class='cbi-value-description'>" .. translate("暂无数据") .. "</div>"
	end

	local function split_cols(line)
		local cols = {}
		for col in line:gmatch("%S+") do
			cols[#cols + 1] = col
		end
		return cols
	end

	local header = split_cols(lines[1])
	if #header < 2 then
		return "<pre style='white-space:pre-wrap;word-break:break-all;'>" .. util.pcdata(content) .. "</pre>"
	end

	local parts = {}
	if title and title ~= "" then
		parts[#parts + 1] = "<div class='cbi-value-title' style='margin-bottom:6px;'>" .. util.pcdata(title) .. "</div>"
	end

	parts[#parts + 1] = "<table class='table cbi-section-table' style='width:100%;'><thead><tr>"
	for _, col in ipairs(header) do
		parts[#parts + 1] = "<th>" .. util.pcdata(col) .. "</th>"
	end
	parts[#parts + 1] = "</tr></thead><tbody>"

	for i = 2, #lines do
		local row = split_cols(lines[i])
		if #row > 0 then
			parts[#parts + 1] = "<tr>"
			for idx = 1, #header do
				parts[#parts + 1] = "<td>" .. util.pcdata(row[idx] or "") .. "</td>"
			end
			parts[#parts + 1] = "</tr>"
		end
	end

	parts[#parts + 1] = "</tbody></table>"
	return table.concat(parts)
end

local function first_nonempty(...)
	for i = 1, select("#", ...) do
		local value = trim(select(i, ...))
		if value ~= "" and value ~= "N/A" then
			return value
		end
	end
	return ""
end

local function parse_positive_int(value)
	local num = tonumber(trim(value))
	if num and num >= 0 then
		return math.floor(num)
	end
	return nil
end

local function get_first_uci_section(config, stype)
	local found
	m.uci:foreach(config, stype, function(section)
		found = section
		return false
	end)
	return found or {}
end

local function as_list(value)
	if type(value) == "table" then
		return value
	end

	value = trim(value)
	if value == "" then
		return {}
	end

	return { value }
end

local function humanize_cli_value(value)
	value = trim(value)
	if value == "" or value == "N/A" then
		return "-"
	end
	if value == "Never" then
		return "从未"
	end
	if value == "Unknown" then
		return "未知"
	end
	if value == "true" then
		return "是"
	end
	if value == "false" then
		return "否"
	end
	if value == "Online" then
		return "在线"
	end
	if value == "Offline" then
		return "离线"
	end
	if value == "Connected" then
		return "已连接"
	end
	if value == "Disconnected" then
		return "未连接"
	end
	value = value:gsub("^Online%s+", "在线 ")
	value = value:gsub("^Offline%s+", "离线 ")
	value = value:gsub("%(Key Mismatch%)", "（密钥不一致）")
	return value
end

local function get_cli_info_context()
	local cfg = get_first_uci_section("vnt2", "vnt2_cli")
	local features = {}

	if trim(cfg.compress) == "1" then
		features[#features + 1] = "压缩"
	end
	if trim(cfg.fec) == "1" then
		features[#features + 1] = "FEC"
	end
	if trim(cfg.rtx) == "1" then
		features[#features + 1] = "RTX"
	end

	return {
		device_name = trim(cfg.device_name),
		device_id = trim(cfg.device_id),
		network_code = trim(cfg.network_code),
		mtu = trim(cfg.mtu),
		tun_name = trim(cfg.tun_name),
		device_mode = trim(cfg.device_mode) ~= "" and trim(cfg.device_mode) or "tun",
		no_nat = trim(cfg.no_nat) ~= "" and trim(cfg.no_nat) or "0",
		servers = as_list(cfg.server),
		features = features
	}
end

local function render_two_column_table(rows, title)
	if #rows == 0 then
		return "<div class='cbi-value-description'>" .. translate("暂无数据") .. "</div>"
	end

	local parts = {}
	if title and title ~= "" then
		parts[#parts + 1] = "<div class='cbi-value-title' style='margin-bottom:6px;'>" .. util.pcdata(title) .. "</div>"
	end

	parts[#parts + 1] = "<table class='table cbi-section-table' style='width:100%;'><tbody>"
	for _, row in ipairs(rows) do
		parts[#parts + 1] = "<tr><td style='white-space:nowrap;font-weight:bold;width:180px;'>"
			.. util.pcdata(row[1] or "")
			.. "</td><td>"
			.. html_escape_keep_br(humanize_cli_value(row[2] or ""))
			.. "</td></tr>"
	end
	parts[#parts + 1] = "</tbody></table>"
	return table.concat(parts)
end

local function render_html_table(headers, rows, title, note)
	if #rows == 0 then
		return "<div class='cbi-value-description'>" .. translate("暂无数据") .. "</div>"
	end

	local parts = {}
	if title and title ~= "" then
		parts[#parts + 1] = "<div class='cbi-value-title' style='margin-bottom:6px;'>" .. util.pcdata(title) .. "</div>"
	end
	if note and note ~= "" then
		parts[#parts + 1] = "<div class='cbi-value-description' style='margin-bottom:6px;'>" .. util.pcdata(note) .. "</div>"
	end

	parts[#parts + 1] = "<table class='table cbi-section-table' style='width:100%;'><thead><tr>"
	for _, header in ipairs(headers) do
		parts[#parts + 1] = "<th>" .. util.pcdata(header) .. "</th>"
	end
	parts[#parts + 1] = "</tr></thead><tbody>"

	for _, row in ipairs(rows) do
		parts[#parts + 1] = "<tr>"
		for i = 1, #headers do
			parts[#parts + 1] = "<td>" .. html_escape_keep_br(humanize_cli_value(row[i] or "")) .. "</td>"
		end
		parts[#parts + 1] = "</tr>"
	end

	parts[#parts + 1] = "</tbody></table>"
	return table.concat(parts)
end

local function cleanup_table_border_chars(line)
	return (line or "")
		:gsub("┌", "")
		:gsub("┐", "")
		:gsub("└", "")
		:gsub("┘", "")
		:gsub("├", "")
		:gsub("┤", "")
		:gsub("┬", "")
		:gsub("┴", "")
		:gsub("┼", "")
		:gsub("─", "")
		:gsub("│", "")
		:gsub("╔", "")
		:gsub("╗", "")
		:gsub("╚", "")
		:gsub("╝", "")
		:gsub("╠", "")
		:gsub("╣", "")
		:gsub("╦", "")
		:gsub("╩", "")
		:gsub("╬", "")
		:gsub("═", "")
		:gsub("║", "")
end

-- CBI validators may need values from sibling fields in the same form post.
local cbi_options = {}

local function is_table_border_line(line)
	local simplified = cleanup_table_border_chars(line)
	simplified = simplified:gsub("[%s%+%-=]", "")
	return simplified == ""
end

local function split_render_table_line(line)
	local sep
	if line:find("│", 1, true) then
		sep = "│"
	elseif line:find("|", 1, true) then
		sep = "|"
	else
		return nil
	end

	local cells = {}
	local text = line
	if text:sub(1, #sep) == sep then
		text = text:sub(#sep + 1)
	end

	for cell in (text .. sep):gmatch("(.-)" .. sep) do
		cells[#cells + 1] = trim(cell)
	end

	while #cells > 0 and cells[1] == "" do
		table.remove(cells, 1)
	end
	while #cells > 0 and cells[#cells] == "" do
		table.remove(cells, #cells)
	end

	return #cells > 0 and cells or nil
end

local function parse_cli_box_table(content)
	local headers
	local rows = {}

	for line in normalize_cli_output(content):gmatch("[^\n]+") do
		local text = trim(line)
		if text ~= "" and not text:match("^%-%-%-") and not is_table_border_line(text) then
			local cells = split_render_table_line(text)
			if cells and #cells > 1 then
				if not headers then
					headers = cells
				else
					rows[#rows + 1] = cells
				end
			end
		end
	end

	return headers, rows
end

local function translate_table_header(header)
	local mapping = {
		["IP"] = "虚拟IP",
		["Online"] = "在线",
		["P2P"] = "直连",
		["RTT"] = "RTT(ms)",
		["RTT (ms)"] = "RTT(ms)",
		["Name"] = "名称",
		["Version"] = "版本",
		["Loss"] = "丢包率",
		["Last Connected Time"] = "上次连接时间",
		["Destination IP"] = "目标IP",
		["Metric"] = "跃点",
		["Remote Address"] = "远端地址"
	}

	return mapping[header] or translate_info_labels(header)
end

local function normalize_table_cell(header, value)
	local raw = trim(value)
	local lower = raw:lower()

	if header == "Online" then
		if lower == "true" then
			return "在线"
		elseif lower == "false" then
			return "离线"
		end
	elseif header == "P2P" then
		if lower == "true" then
			return "是"
		elseif lower == "false" then
			return "否"
		end
	end

	return humanize_cli_value(raw)
end

local function extract_table_note(kind, content, rows)
	if kind == "route" then
		local total = content:match("%-%-%-%s*All Routes List%s*%(%s*Total:%s*(%d+)%s*%)")
		if total then
			return "共 " .. total .. " 条路由"
		end
	elseif kind == "clients" then
		local count = content:match("%-%-%-%s*Client List%s*%((%d+)%)")
		if count then
			return "共 " .. count .. " 个设备"
		end
	elseif kind == "ips" then
		local count = content:match("%-%-%-%s*Client List%s*%((%d+)%)")
		if count then
			return "共 " .. count .. " 个节点"
		end
	end

	if rows and #rows > 0 then
		return "共 " .. #rows .. " 条记录"
	end

	return ""
end

local function render_cli_info_panel(content)
	local normalized = trim(normalize_cli_output(content))
	if normalized == "" then
		return "<div class='cbi-value-description'>" .. translate("暂无数据") .. "</div>"
	end

	local fields = {}
	local servers = {}

	for line in normalized:gmatch("[^\n]+") do
		local text = trim(line)
		if text ~= "" and not text:match("^%-%-%-") and not text:match("^[-=]+$") then
			local key, value = text:match("^([^:]+):%s*(.*)$")
			if key then
				key = trim(key)
				value = trim(value)
				if key == "Server" or key == "Connect server" or key == "Relay server" then
					local server_name, status = value:match("^(.-)%s*%((.-)%)$")
					servers[#servers + 1] = {
						server = first_nonempty(server_name, value),
						status = trim(status)
					}
				elseif key == "Last Connected Time" then
					if #servers > 0 then
						servers[#servers].last_connected = value
					else
						fields[key] = value
					end
				else
					fields[key] = value
				end
			end
		end
	end

	local ctx = get_cli_info_context()
	local total_clients = parse_positive_int(first_nonempty(fields["Total Clients"]))
	local online_clients = parse_positive_int(first_nonempty(fields["Online Clients"]))
	local offline_clients = first_nonempty(fields["Offline Clients"])
	if offline_clients == "" and total_clients and online_clients and total_clients >= online_clients then
		offline_clients = tostring(total_clients - online_clients)
	end

	local features = (#ctx.features > 0) and table.concat(ctx.features, " / ") or ""
	local rows = {}
	local function add_row(label, value)
		value = humanize_cli_value(value)
		if value ~= "" and value ~= "-" then
			rows[#rows + 1] = { label, value }
		end
	end

	add_row("名称", first_nonempty(fields["Name"], fields["Device name"], fields["Current device"], ctx.device_name))
	add_row("虚拟IP", first_nonempty(fields["IP"], fields["Virtual ip"]))
	add_row("虚拟网关", first_nonempty(fields["Virtual gateway"]))
	add_row("连接状态", first_nonempty(fields["Connection status"]))
	add_row("NAT类型", first_nonempty(fields["Nat Type"], fields["NAT type"]))
	add_row("MTU", ctx.mtu)
	add_row("网络代码", ctx.network_code)
	add_row("公网IPv4", first_nonempty(fields["Public Ipv4"], fields["Public ips"], fields["Public ip"]))
	add_row("公网IPv6", first_nonempty(fields["Ipv6"]))
	add_row("版本", first_nonempty(fields["Version"]))
	add_row("在线节点", first_nonempty(fields["Online Clients"]))
	add_row("离线节点", offline_clients)
	add_row("P2P节点", first_nonempty(fields["P2P Clients"]))
	add_row("设备ID", first_nonempty(fields["Id"], fields["Device id"], ctx.device_id))
	add_row("本地地址", first_nonempty(fields["Local addr"], fields["Local address"]))
	local mode_label = {
		no = "无虚拟网卡",
		tun = "TUN",
		tap = "TAP"
	}
	add_row("虚拟网卡", mode_label[ctx.device_mode] or ctx.device_mode)
	add_row("内置子网 NAT", ctx.no_nat == "1" and "关闭" or "开启")
	add_row("IP转发模式", ctx.no_nat == "1" and "OpenWrt 系统转发" or "VNT2 内置 IP 转发")
	add_row("功能", features)

	if #rows == 0 then
		return render_pre_content(normalized)
	end

	local server_rows = {}
	for _, item in ipairs(servers) do
		server_rows[#server_rows + 1] = {
			item.server or "-",
			humanize_cli_value(item.status or ""),
			humanize_cli_value(item.last_connected or "")
		}
	end
	if #server_rows == 0 then
		for _, server in ipairs(ctx.servers) do
			server_rows[#server_rows + 1] = {
				server,
				"-",
				"-"
			}
		end
	end

	local parts = {
		render_two_column_table(rows, translate("本机设备信息"))
	}
	if #server_rows > 0 then
		parts[#parts + 1] = "<div style='height:12px;'></div>"
		parts[#parts + 1] = render_html_table(
			{ "服务器", "连接状态", "上次连接时间" },
			server_rows,
			translate("服务端列表")
		)
	end

	return table.concat(parts)
end

local function render_cli_table_panel(content, title, kind)
	local normalized = trim(normalize_cli_output(content))
	if normalized == "" then
		return "<div class='cbi-value-description'>" .. translate("暂无数据") .. "</div>"
	end

	local headers, rows = parse_cli_box_table(normalized)
	if not headers or #headers == 0 then
		return render_pre_content(normalized)
	end

	local translated_headers = {}
	for i, header in ipairs(headers) do
		translated_headers[i] = translate_table_header(header)
	end

	local normalized_rows = {}
	for _, row in ipairs(rows) do
		local current = {}
		for i, header in ipairs(headers) do
			current[i] = normalize_table_cell(header, row[i] or "")
		end
		normalized_rows[#normalized_rows + 1] = current
	end

	return render_html_table(translated_headers, normalized_rows, title, extract_table_note(kind, normalized, normalized_rows))
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
	local upload_dir = "/tmp/vnt2-upload/"
	local install_dir = "/usr/bin/"
	local fd
	local uploaded_name

	local function is_elf_binary(path)
		local file = nixio.open(path, "r")
		if not file then
			return false
		end

		local magic = file:read(4)
		file:close()
		return magic == "\127ELF"
	end

	local function install_uploaded_binary(src_path, raw_name)
		local name = trim(raw_name)
		local target_name

		if name == "vnt2_cli" or name == "vnt2_ctrl" or name == "vnt2_web" or name == "vnts2" then
			target_name = name
		elseif name == "vnts" then
			target_name = "vnts2"
		else
			return nil, translate("未识别的程序文件名，仅支持 vnt2_cli / vnt2_ctrl / vnt2_web / vnts2 / vnts")
		end
		if not is_elf_binary(src_path) then
			return nil, translate("上传文件不是有效的 ELF 可执行程序")
		end

		local target_path = install_dir .. target_name
		if sys.call("cp -f " .. util.shellquote(src_path) .. " " .. util.shellquote(target_path) .. " >/dev/null 2>&1") ~= 0 then
			return nil, translate("复制到 /usr/bin 失败")
		end
		if sys.call("chmod 755 " .. util.shellquote(target_path) .. " >/dev/null 2>&1") ~= 0 then
			return nil, translate("设置执行权限失败")
		end
		return target_path, nil
	end

	local function find_extracted_binary(root, name)
		local cmd = "find " .. util.shellquote(root) .. " -type f \\( -name "
			.. util.shellquote(name)
			.. " -o -name " .. util.shellquote(name .. ".bin")
			.. " -o -name " .. util.shellquote(name .. "-*")
			.. " -o -name " .. util.shellquote(name .. "_*")
			.. " \\) 2>/dev/null | head -n1"
		return trim(sys.exec(cmd))
	end

	local function archive_is_safe(path)
		local quoted = util.shellquote(path)
		if sys.call("tar -tzf " .. quoted .. " >/dev/null 2>&1") ~= 0 then
			return false
		end

		local entries = sys.exec("tar -tzf " .. quoted .. " 2>/dev/null") or ""
		for entry in entries:gmatch("[^\r\n]+") do
			entry = entry:gsub("\\", "/"):gsub("^%./", "")
			if entry:match("^/") or entry:match("^[A-Za-z]:/") or entry == ".."
				or entry:match("^%.%./") or entry:match("/%.%./") or entry:match("/%.%.$") then
				return false
			end
		end

		return sys.call("tar -tvzf " .. quoted .. " 2>/dev/null | awk '"
			.. 'BEGIN { bad = 0 } '
			.. '{ type = substr($0, 1, 1); if (type != "-" && type != "d") bad = 1 } '
			.. 'END { exit bad }' .. "'") == 0
	end

	fs.mkdirr(upload_dir)
	fs.mkdir(install_dir)

	http.setfilehandler(function(meta, chunk, eof)
		if not fd then
			if not meta then
				return
			end

			local raw_name = tostring(meta.file or "")
			uploaded_name = raw_name:match("([^/\\]+)$") or raw_name
			if uploaded_name == "" then
				return
			end

			fd = nixio.open(upload_dir .. uploaded_name, "w")
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

			local full = upload_dir .. uploaded_name
			local msg = translate("上传文件已接收") .. " " .. util.pcdata(full)

			if uploaded_name:sub(-7) == ".tar.gz" then
				local extract_dir = upload_dir .. "extract/"
				local installed = {}

				sys.call("rm -rf " .. util.shellquote(extract_dir) .. " >/dev/null 2>&1")
				fs.mkdirr(extract_dir)

				if archive_is_safe(full)
					and sys.call("tar -xzf " .. util.shellquote(full) .. " -C " .. util.shellquote(extract_dir) .. " >/dev/null 2>&1") == 0 then
					for _, bin in ipairs({ "vnt2_cli", "vnt2_ctrl", "vnt2_web", "vnts2", "vnts" }) do
						local found = find_extracted_binary(extract_dir, bin)
						if found ~= "" then
							local installed_path = install_uploaded_binary(found, bin)
							if installed_path then
								installed[#installed + 1] = installed_path
							end
						end
					end

					if #installed > 0 then
						msg = msg .. "<br />" .. translate("已安装到 /usr/bin 并赋予执行权限：")
						for _, path in ipairs(installed) do
							msg = msg .. "<br />- " .. util.pcdata(path)
						end
					else
						msg = msg .. "<br />" .. translate("压缩包中未找到可安装的 vnt2/vnts2 程序文件")
					end
				else
					msg = msg .. "<br />" .. translate("压缩包解压失败")
				end
			else
				local installed_path, err = install_uploaded_binary(full, uploaded_name)
				if installed_path then
					msg = msg .. "<br />- " .. util.pcdata(installed_path) .. " " .. translate("已安装到 /usr/bin 并赋予执行权限")
				else
					msg = msg .. "<br />- " .. util.pcdata(err or translate("安装失败"))
				end
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

local function validate_file_path(self, value)
	value = trim(value)
	if value == "" then
		return nil, translate("路径不能为空")
	end
	if value:sub(1, 1) ~= "/" then
		return nil, translate("请输入绝对路径，例如 /vnt_config/vnt2_cli_web.toml")
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

local cli_enabled = m.uci:get_first("vnt2", "vnt2_cli", "enabled") == "1"
local web_enabled_state = m.uci:get_first("vnt2", "vnt2_web", "enabled") == "1"
local server_enabled_state = m.uci:get_first("vnt2", "vnts2", "enabled") == "1"

local cli_running = cli_enabled and process_running("vnt2_cli")
local web_running = web_enabled_state and process_running("vnt2_web")
local server_running = server_enabled_state and (process_running("vnts2") or process_running("vnts"))

-- ==================== vnt2_cli ====================
-- Keep each configuration section scoped separately for Lua 5.1 local limits.
;(function()
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

local mutual_exclusion_tip = s:taboption("general", DummyValue, "_mutual_exclusion_tip")
mutual_exclusion_tip.rawhtml = true
mutual_exclusion_tip.cfgvalue = function()
	return [[
<div class="cbi-value-description">CLI 客户端与 Web 客户端互斥，启用其中一个时会自动取消另一个。</div>
]] .. render_mutual_exclusion_script()
end

local enabled = s:taboption("general", Flag, "enabled", translate("启用cli 客户端"))
enabled.rmempty = false
enabled.default = "0"
enabled.write = function(self, section, value)
	self.map.uci:set(self.map.config, section, self.option, value)
	if value == "1" then
		set_sections_option_by_type(self.map.config, "vnt2_web", "enabled", "0")
	end
end

local restart_btn = s:taboption("general", Button, "_restart_cli", translate("重启客户端"))
restart_btn.inputtitle = translate("重启")
restart_btn.inputstyle = "apply"
restart_btn.description = translate("在未修改参数时快速重启 vnt2_cli")
restart_btn:depends("enabled", "1")
restart_btn.write = function()
	schedule_vnt2_restart()
end

local network_code = s:taboption("general", Value, "network_code", translate("网络编号"),
	translate("同一服务器下，使用相同网络编号的客户端会加入同一虚拟局域网"))
network_code.rmempty = false
network_code.placeholder = "123456"
network_code.validate = function(self, value)
	value = trim(value)
	if value ~= "" and #value >= 1 and #value <= 32 then
		return value
	end
	return nil, translate("网络编号必须为 1~63 个字符")
end

local server = s:taboption("general", DynamicList, "server", translate("服务器地址"),
	translate("支持 quic://、tcp://、wss://、dynamic:// 等格式，可填写多个以实现容灾或负载均衡"))
server.rmempty = false
server.placeholder = "tcp://1.1.1.1:29872"
server.default = "tcp://1.1.1.1:29872"
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
compress.default = "0"

local fec = s:taboption("security", Flag, "fec", translate("启用 FEC 前向纠错"),
	translate("在弱网环境下提升稳定性，但会增加带宽开销"))
fec.rmempty = false
fec.default = "0"

local rtx = s:taboption("security", Flag, "rtx", translate("启用 QUIC 优化传输"),
	translate("适用于需要提升链路稳定性的场景"))
rtx.rmempty = false
rtx.default = "0"

local no_punch = s:taboption("security", Flag, "no_punch", translate("禁用 P2P 打洞"),
	translate("开启后将优先通过中继或服务端转发"))
no_punch.rmempty = false
no_punch.default = "0"

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
allow_mapping.default = "0"

local no_nat = s:taboption("network", Flag, "no_nat", translate("关闭内置子网 NAT"),
	translate("勾选后关闭 VNT2 内置 IP 转发，改用 OpenWrt 系统转发/NAT；不勾选则继续使用 VNT2 内置 IP 转发"))
no_nat.rmempty = false
no_nat.default = "0"

local device_mode = s:taboption("network", ListValue, "device_mode", translate("虚拟网卡模式"),
	translate("启用后不创建虚拟网卡，仅适用于端口映射或流量出口类场景"))
device_mode:value("tun", "TUN")
device_mode:value("tap", "TAP")
device_mode:value("no", translate("无虚拟网卡"))
device_mode.default = "tun"
device_mode.rmempty = false

local no_broadcast = s:taboption("network", Flag, "no_broadcast", translate("禁用广播/组播"))
no_broadcast.rmempty = false
no_broadcast.default = "0"

local allow_ikev2 = s:taboption("network", Flag, "allow_ikev2", translate("允许 IKEv2 转发"))
allow_ikev2.rmempty = false
allow_ikev2.default = "0"

local allow_wireguard = s:taboption("network", Flag, "allow_wireguard", translate("允许 WireGuard 转发"))
allow_wireguard.rmempty = false
allow_wireguard.default = "0"

local auto_sync_subnet = s:taboption("network", Flag, "auto_sync_subnet", translate("自动同步子网"))
auto_sync_subnet.rmempty = false
auto_sync_subnet.default = "0"

local peer_address = s:taboption("network", DynamicList, "peer_address", translate("直连节点地址"),
	translate("支持 host:port、tcp://、udp:// 或 dynamic:// 地址"))
peer_address.placeholder = "192.168.1.10:29873"
peer_address.validate = validate_peer_address
bind_dynamiclist(peer_address)

local turn = s:taboption("network", DynamicList, "turn", translate("强制中转规则"),
	translate("格式：目标 IP/CIDR,中转服务器 IPv4"))
turn.placeholder = "10.26.0.0/24,10.26.0.2"
turn.validate = validate_dynamic_items(validate_turn_item)
bind_dynamiclist(turn)

local punch_model = s:taboption("network", DynamicList, "punch_model", translate("打洞模式规则"),
	translate("格式：目标 IP/CIDR,IPv4Tcp,IPv4Udp 等"))
punch_model.placeholder = "10.26.0.0/24,IPv4Tcp,IPv4Udp"
punch_model.validate = validate_dynamic_items(validate_punch_model_item)
bind_dynamiclist(punch_model)

local subnet_mapping = s:taboption("network", DynamicList, "subnet_mapping", translate("子网映射"),
	translate("格式：映射 CIDR,实际 CIDR"))
subnet_mapping.placeholder = "192.168.2.0/24,192.168.1.0/24"
subnet_mapping.validate = validate_subnet_mapping
bind_dynamiclist(subnet_mapping)

local vnt2_forward = s:taboption("network", MultiValue, "vnt2_forward", translate("访问控制 / 防火墙转发"),
	translate("按需自动创建 OpenWrt 防火墙区域与转发规则"))
vnt2_forward:value("vnt2fwlan", translate("允许从 VNT2 到 LAN"))
vnt2_forward:value("vnt2fwwan", translate("允许从 VNT2 到 WAN"))
vnt2_forward:value("lanfwvnt2", translate("允许从 LAN 到 VNT2"))
vnt2_forward:value("wanfwvnt2", translate("允许从 WAN 到 VNT2"))
vnt2_forward.widget = "checkbox"
vnt2_forward.cfgvalue = function(self, section)
	return read_uci_list_or_words(self.map.uci, self.map.config, section, self.option)
end
vnt2_forward.write = function(self, section, value)
	write_uci_list(self.map.uci, self.map.config, section, self.option, value)
end
vnt2_forward.remove = function(self, section)
	self.map.uci:delete(self.map.config, section, self.option)
end

local udp_stun = s:taboption("stun", DynamicList, "udp_stun", translate("UDP STUN 列表"),
	translate("不带端口时通常默认使用 3478"))
udp_stun.placeholder = "stun.chat.bilibili.com:3478"
bind_dynamiclist(udp_stun)

local tcp_stun = s:taboption("stun", DynamicList, "tcp_stun", translate("TCP STUN 列表"),
	translate("适用于 TCP / TLS / WSS 环境探测"))
tcp_stun.placeholder = "stun.nextcloud.com:443"
bind_dynamiclist(tcp_stun)

local auto_download_cli = s:taboption("advanced", Flag, "auto_download", translate("自动下载程序"),
	translate("当本地缺少 vnt2_cli / vnt2_ctrl 时，自动从所选镜像源的 Releases 下载匹配当前架构的发行包"))
auto_download_cli.rmempty = false
auto_download_cli.default = "1"

local download_mirror_cli = s:taboption("advanced", ListValue, "download_mirror", translate("客户端下载镜像源"),
	translate("选择自动时依次尝试 gh-proxy、GitHub、Gitee、GitLab、Cloudflare R2，每个源最多重试 3 次；latest 会先识别 Release tag，再匹配当前架构的精确资源文件名"))
bind_download_mirror(download_mirror_cli)
local custom_download_mirror_cli = s:taboption("advanced", Value, "custom_download_mirror", translate("客户端自定义镜像地址"))
bind_custom_download_mirror(custom_download_mirror_cli, "download_mirror")

local download_tag_cli = s:taboption("advanced", Value, "download_tag", translate("客户端下载版本"),
	translate("填写 latest 表示始终获取最新版本，也可填写指定 Release 标签，如 v2.0.18"))
download_tag_cli.placeholder = "latest"
download_tag_cli.default = "latest"
download_tag_cli.validate = validate_nonempty

local download_repo_cli = s:taboption("advanced", Value, "download_repo", translate("客户端下载仓库"),
	translate("默认 vnt-dev/vnt；如需使用 Gitee、GitLab、Cloudflare 等镜像，建议保持默认仓库"))
download_repo_cli.placeholder = "vnt-dev/vnt"
download_repo_cli.default = "vnt-dev/vnt"
download_repo_cli.validate = validate_nonempty

local vnt2_cli_bin = s:taboption("advanced", Value, "vnt2_cli_bin", translate("vnt2_cli 程序路径"),
	translate("默认 /usr/bin/vnt2_cli；若不存在，将优先尝试自动下载，失败后回退到已上传并安装到 /usr/bin 的程序"))
vnt2_cli_bin.placeholder = "/usr/bin/vnt2_cli"
vnt2_cli_bin.validate = validate_nonempty

local vnt2_ctrl_bin = s:taboption("advanced", Value, "vnt2_ctrl_bin", translate("vnt2_ctrl 程序路径"),
	translate("用于读取运行状态、节点信息、路由信息；自动下载成功后会自动写入实际路径"))
vnt2_ctrl_bin.placeholder = "/usr/bin/vnt2_ctrl"
vnt2_ctrl_bin.validate = validate_nonempty

local cli_conf_path = s:taboption("advanced", Value, "client_conf_file", translate("CLI 配置文件路径"),
	translate("vnt2_cli 使用的 TOML 配置文件绝对路径"))
cli_conf_path.placeholder = "/vnt_config/vnt2_cli_web.toml"
cli_conf_path.default = "/vnt_config/vnt2_cli_web.toml"
cli_conf_path.validate = validate_file_path

local cli_conf_shared_tip = s:taboption("advanced", DummyValue, "_cli_conf_shared_tip")
cli_conf_shared_tip.rawhtml = true
cli_conf_shared_tip.cfgvalue = function()
	return [[
<div class="cbi-value-description">vnt2_cli 与 vnt2_web 为互斥运行方式，但共用同一个 TOML 配置文件 /vnt_config/vnt2_cli_web.toml；若目录不存在，启动时会自动创建，配置文件权限设置为 600。</div>
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

local tunnel_addr = s:taboption("advanced", DynamicList, "tunnel_addr", translate("Tunnel addresses"),
	translate("用于 P2P 通信，0 表示自动分配"))
tunnel_addr.placeholder = "192.168.1.10:29873"
tunnel_addr.validate = validate_tunnel_addr
bind_dynamiclist(tunnel_addr)

local outbound_interface = s:taboption("advanced", Value, "outbound_interface", translate("Outbound interface"),
	translate("Network interface used for outbound VNT traffic; leave empty for system routing"))
outbound_interface.placeholder = "eth0"

local event_script = s:taboption("advanced", Value, "event_script", translate("Event script"),
	translate("Absolute path to a script executed when the connection state changes"))
event_script.placeholder = "/etc/vnt2-event.sh"
event_script.validate = function(self, value)
	value = trim(value)
	if value ~= "" and value:sub(1, 1) ~= "/" then
		return nil, translate("Event script must be an absolute path")
	end
	return value
end

local bind_dev = s:taboption("advanced", ListValue, "bind_dev", translate("绑定出口网卡"),
	translate("当前以环境变量形式传递给启动脚本，适合需要指定出口链路的场景"))
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
	<div>1. 面板模式会把 vnt2_cli / vnt2_ctrl 的输出尽量转换为更适合 LuCI 阅读的结构化展示。</div>
	<div>2. 原始输出模式保留命令行原文，适合排障或对照上游输出格式。</div>
	<div>3. 如需最新数据，请先点击对应刷新按钮；服务端状态、日志和参数请结合“服务端设置”与“服务端日志”菜单查看。</div>
</div>
]]
end

local panel_info_btn = s:taboption("infos", Button, "_info_panel_btn", translate("刷新本机设备信息（面板）"))
panel_info_btn.inputtitle = translate("刷新本机设备信息")
panel_info_btn.inputstyle = "apply"
panel_info_btn:depends("info_mode", "panel")
panel_info_btn.write = function()
	if cli_running_now() then
		run_cli_info_command("info", "/tmp/vnt2-cli_info")
	else
		sys.call("echo '错误：程序未运行！请先启动 vnt2_cli。' >/tmp/vnt2-cli_info")
	end
end

local panel_info = s:taboption("infos", DummyValue, "_info_panel_view", translate("本机设备信息"))
panel_info.rawhtml = true
panel_info:depends("info_mode", "panel")
panel_info.cfgvalue = function()
	return render_cli_info_panel(fs.readfile("/tmp/vnt2-cli_info") or "")
end

local panel_ips_btn = s:taboption("infos", Button, "_ips_panel_btn", translate("刷新所有节点列表（面板）"))
panel_ips_btn.inputtitle = translate("刷新所有节点列表")
panel_ips_btn.inputstyle = "apply"
panel_ips_btn:depends("info_mode", "panel")
panel_ips_btn.write = function()
	if cli_running_now() then
		run_cli_info_command("ips", "/tmp/vnt2-cli_ips")
	else
		sys.call("echo '错误：程序未运行！请先启动 vnt2_cli。' >/tmp/vnt2-cli_ips")
	end
end

local panel_ips = s:taboption("infos", DummyValue, "_ips_panel_view", translate("所有节点列表"))
panel_ips.rawhtml = true
panel_ips:depends("info_mode", "panel")
panel_ips.cfgvalue = function()
	return render_cli_table_panel(fs.readfile("/tmp/vnt2-cli_ips") or "", translate("所有节点列表"), "ips")
end

local panel_clients_btn = s:taboption("infos", Button, "_clients_panel_btn", translate("刷新所有设备详情（面板）"))
panel_clients_btn.inputtitle = translate("刷新所有设备详情")
panel_clients_btn.inputstyle = "apply"
panel_clients_btn:depends("info_mode", "panel")
panel_clients_btn.write = function()
	if cli_running_now() then
		run_cli_info_command("clients", "/tmp/vnt2-cli_clients")
	else
		sys.call("echo '错误：程序未运行！请先启动 vnt2_cli。' >/tmp/vnt2-cli_clients")
	end
end

local panel_clients = s:taboption("infos", DummyValue, "_clients_panel_view", translate("所有设备详情"))
panel_clients.rawhtml = true
panel_clients:depends("info_mode", "panel")
panel_clients.cfgvalue = function()
	return render_cli_table_panel(fs.readfile("/tmp/vnt2-cli_clients") or "", translate("所有设备详情"), "clients")
end

local panel_route_btn = s:taboption("infos", Button, "_route_panel_btn", translate("刷新路由转发信息（面板）"))
panel_route_btn.inputtitle = translate("刷新路由转发信息")
panel_route_btn.inputstyle = "apply"
panel_route_btn:depends("info_mode", "panel")
panel_route_btn.write = function()
	if cli_running_now() then
		run_cli_info_command("route", "/tmp/vnt2-cli_route")
	else
		sys.call("echo '错误：程序未运行！请先启动 vnt2_cli。' >/tmp/vnt2-cli_route")
	end
end

local panel_route = s:taboption("infos", DummyValue, "_route_panel_view", translate("路由转发信息"))
panel_route.rawhtml = true
panel_route:depends("info_mode", "panel")
panel_route.cfgvalue = function()
	return render_cli_table_panel(fs.readfile("/tmp/vnt2-cli_route") or "", translate("路由转发信息"), "route")
end

local panel_cmd_btn = s:taboption("infos", Button, "_cmd_panel_btn", translate("刷新本机启动参数（面板）"))
panel_cmd_btn.inputtitle = translate("刷新本机启动参数")
panel_cmd_btn.inputstyle = "apply"
panel_cmd_btn:depends("info_mode", "panel")
panel_cmd_btn.write = function()
	if cli_running_now() then
		sys.call("tr '\\000' ' ' </proc/$(pidof vnt2_cli | awk '{print $1}')/cmdline >/tmp/vnt2-cli_cmd 2>/dev/null")
	else
		sys.call("echo '错误：程序未运行！请先启动 vnt2_cli。' >/tmp/vnt2-cli_cmd")
	end
end

local panel_cmd = s:taboption("infos", DummyValue, "_cmd_panel_view", translate("本机启动参数"))
panel_cmd.rawhtml = true
panel_cmd:depends("info_mode", "panel")
panel_cmd.cfgvalue = function()
	return render_pre("/tmp/vnt2-cli_cmd")
end

local btn1 = s:taboption("infos", Button, "_info_raw", translate("本机设备信息"))
btn1.inputtitle = translate("刷新本机设备信息")
btn1.inputstyle = "apply"
btn1:depends("info_mode", "raw")
btn1.write = function()
	if cli_running_now() then
		run_cli_info_command("info", "/tmp/vnt2-cli_info")
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
	if cli_running_now() then
		run_cli_info_command("ips", "/tmp/vnt2-cli_ips")
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
	if cli_running_now() then
		run_cli_info_command("clients", "/tmp/vnt2-cli_clients")
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
	if cli_running_now() then
		run_cli_info_command("route", "/tmp/vnt2-cli_route")
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
	if cli_running_now() then
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
upload.description = translate("支持上传 vnt2_cli / vnt2_ctrl / vnt2_web 二进制文件，或包含这些文件的 .tar.gz 压缩包。上传后会自动安装到 /usr/bin/ 并赋予执行权限，重启服务后生效；当自动下载失败时，系统会自动回退使用这里上传并安装的程序。")

local upload_note = s:taboption("upload", DummyValue, "_upload_note")
upload_note.rawhtml = true
upload_note.template = "vnt2/other_dvalue"
cbi_options.upload_note = upload_note
end)()

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
	if value == "1" then
		set_sections_option_by_type(self.map.config, "vnt2_cli", "enabled", "0")
	end
end

local web_restart = w:taboption("general", Button, "_restart_web", translate("重启客户端"))
web_restart.inputtitle = translate("重启")
web_restart.inputstyle = "apply"
web_restart.description = translate("在未修改参数时快速重启 vnt2_web")
web_restart:depends("enabled", "1")
web_restart.write = function()
	schedule_vnt2_restart()
end

local auto_download_web = w:taboption("general", Flag, "auto_download", translate("自动下载程序"),
	translate("当本地缺少 vnt2_web 时，自动从所选镜像源的 Releases 下载匹配当前架构的发行包"))
auto_download_web.rmempty = false
auto_download_web.default = "1"

local download_mirror_web = w:taboption("general", ListValue, "download_mirror", translate("Web 下载镜像源"),
	translate("自动依次尝试 gh-proxy、GitHub、Gitee、GitLab、Cloudflare R2，每个源最多重试 3 次；客户端 ZIP 必须包含 vnt2_cli、vnt2_ctrl、vnt2_web"))
bind_download_mirror(download_mirror_web)
local custom_download_mirror_web = w:taboption("general", Value, "custom_download_mirror", translate("Web 自定义镜像地址"))
bind_custom_download_mirror(custom_download_mirror_web, "download_mirror")

local download_tag_web = w:taboption("general", Value, "download_tag", translate("Web 下载版本"),
	translate("填写 latest 表示始终获取最新版本，也可填写指定 Release 标签，如 v2.0.18"))
download_tag_web.placeholder = "latest"
download_tag_web.default = "latest"
download_tag_web.validate = validate_nonempty

local download_repo_web = w:taboption("general", Value, "download_repo", translate("Web 下载仓库"),
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

local open_web = w:taboption("general", DummyValue, "_open_web", translate("打开页面"),
	translate("打开当前配置对应的 Web 管理页面，默认地址通常为 http://路由器IP:19099/"))
open_web.rawhtml = true
open_web.cfgvalue = function()
	return string.format(
		'<a class="btn cbi-button cbi-button-apply" href="%s" target="_blank" rel="noopener noreferrer">%s</a>',
		util.pcdata(dispatcher.build_url("admin", "vpn", "vnt2", "open_web")),
		util.pcdata(translate("打开页面"))
	)
end

local web_conf_path = w:taboption("advanced", Value, "web_conf_file", translate("Web 配置文件路径"),
	translate("vnt2_web 使用的 TOML 配置文件绝对路径"))
web_conf_path.placeholder = "/vnt_config/vnt2_cli_web.toml"
web_conf_path.default = "/vnt_config/vnt2_cli_web.toml"
web_conf_path.validate = validate_file_path

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
web_upload.description = translate("支持上传 vnt2_web 二进制文件或包含 vnt2_web 的 .tar.gz 压缩包；上传后会自动安装到 /usr/bin/ 并赋予执行权限；当自动下载失败时，系统会自动回退使用这里上传并安装的程序。")

local web_upload_note = w:taboption("upload", DummyValue, "_upload_note_web")
web_upload_note.rawhtml = true
web_upload_note.template = "vnt2/other_dvalue"
cbi_options.web_upload_note = web_upload_note
end)()

-- ==================== vnts2 ====================
;(function()
local v = m:section(TypedSection, "vnts2", translate("vnts2 服务端设置"))
v.anonymous = true
v.addremove = false

v:tab("general", translate("基本设置"))
v:tab("listen", translate("监听与认证"))
v:tab("cluster", translate("集群与网络"))
v:tab("advanced", translate("高级设置"))
v:tab("infos", translate("服务信息"))
v:tab("upload", translate("上传程序"))

local server_enabled = v:taboption("general", Flag, "enabled", translate("启用vnts2 服务端"))
server_enabled.rmempty = false
server_enabled.default = "0"

local server_restart = v:taboption("general", Button, "_restart_server", translate("重启服务端"))
server_restart.inputtitle = translate("重启")
server_restart.inputstyle = "apply"
server_restart.description = translate("快速重启 vnts2")
server_restart:depends("enabled", "1")
server_restart.write = function()
	schedule_vnt2_restart()
end

local auto_download_server = v:taboption("general", Flag, "auto_download", translate("自动下载程序"),
	translate("当本地缺少 vnts2 时，自动从所选镜像源的 Releases 下载匹配当前架构的发行包"))
auto_download_server.rmempty = false
auto_download_server.default = "1"

local download_mirror_server = v:taboption("general", ListValue, "download_mirror", translate("服务端下载镜像源"),
	translate("自动依次尝试 gh-proxy、GitHub、Gitee、GitLab、Cloudflare R2，每个源最多重试 3 次；服务端资源为无扩展名 ELF 文件"))
bind_download_mirror(download_mirror_server)
local custom_download_mirror_server = v:taboption("general", Value, "custom_download_mirror", translate("服务端自定义镜像地址"))
bind_custom_download_mirror(custom_download_mirror_server, "download_mirror")

local download_tag_server = v:taboption("general", Value, "download_tag", translate("服务端下载版本"),
	translate("填写 latest 表示始终获取最新版本，也可填写指定 Release 标签"))
download_tag_server.placeholder = "latest"
download_tag_server.default = "latest"
download_tag_server.validate = validate_nonempty

local download_repo_server = v:taboption("general", Value, "download_repo", translate("服务端下载仓库"),
	translate("默认 vnt-dev/vnts；如需使用 Gitee、GitLab、Cloudflare 等镜像，建议保持默认仓库"))
download_repo_server.placeholder = "vnt-dev/vnts"
download_repo_server.default = "vnt-dev/vnts"
download_repo_server.validate = validate_nonempty

local vnts2_bin = v:taboption("general", Value, "vnts2_bin", translate("vnts2 程序路径"),
	translate("默认 /usr/bin/vnts2；若不存在，将优先尝试自动下载，失败后回退到已上传并安装到 /usr/bin 的程序"))
vnts2_bin.placeholder = "/usr/bin/vnts2"
vnts2_bin.validate = validate_nonempty

local tcp_bind = v:taboption("listen", Value, "tcp_bind", translate("TCP 监听地址"),
	translate("例如 0.0.0.0:29872"))
tcp_bind.placeholder = "0.0.0.0:29872"
tcp_bind.validate = validate_bind_addr

local quic_bind = v:taboption("listen", Value, "quic_bind", translate("QUIC 监听地址"),
	translate("例如 0.0.0.0:29872"))
quic_bind.placeholder = "0.0.0.0:29872"
quic_bind.validate = validate_bind_addr

local ws_bind = v:taboption("listen", Value, "ws_bind", translate("WS/WSS 监听地址"),
	translate("例如 0.0.0.0:29872"))
ws_bind.placeholder = "0.0.0.0:29872"
ws_bind.validate = validate_bind_addr

local web_bind = v:taboption("listen", Value, "web_bind", translate("管理页面监听地址"),
	translate("例如 0.0.0.0:29871"))
web_bind.placeholder = "0.0.0.0:29871"
web_bind.validate = validate_bind_addr

local server_quic_bind = v:taboption("listen", Value, "server_quic_bind", translate("服务端互联 QUIC 地址"),
	translate("用于多服务端互联，留空则不启动该 UDP 监听"))
server_quic_bind.placeholder = "0.0.0.0:29900"
server_quic_bind.validate = validate_bind_addr

local cert = v:taboption("listen", Value, "cert", translate("TLS 证书路径"),
	translate("启用 TLS / WSS / QUIC TLS 时所用证书"))
cert.placeholder = "/etc/ssl/vnts.crt"

local key = v:taboption("listen", Value, "key", translate("TLS 私钥路径"),
	translate("与证书配套使用"))
key.placeholder = "/etc/ssl/vnts.key"

local username = v:taboption("listen", Value, "username", translate("管理用户名"),
	translate("用于 vnts2 内置 Web 管理页登录"))
username.placeholder = "admin"

local password_server = v:taboption("listen", Value, "password", translate("管理密码"),
	translate("用于 vnts2 内置 Web 管理页登录"))
password_server.password = true
password_server.placeholder = "admin"

local server_token = v:taboption("listen", Value, "server_token", translate("服务端令牌"),
	translate("多服务端互联或上游鉴权场景可用，留空则不启用"))
server_token.password = true

local open_wan_tcp = v:taboption("listen", Flag, "open_wan_tcp", translate("允许 WAN 访问 TCP 端口"))
open_wan_tcp.rmempty = false
open_wan_tcp.default = "0"

local open_wan_quic = v:taboption("listen", Flag, "open_wan_quic", translate("允许 WAN 访问 QUIC 端口"))
open_wan_quic.rmempty = false
open_wan_quic.default = "0"

local open_wan_server_quic = v:taboption("listen", Flag, "open_wan_server_quic", translate("允许 WAN 访问服务端互联 QUIC 端口"),
	translate("仅放行服务端互联 QUIC 地址对应的 UDP 端口；留空监听地址时不会创建规则"))
open_wan_server_quic.rmempty = false
open_wan_server_quic.default = "0"

local open_wan_ws = v:taboption("listen", Flag, "open_wan_ws", translate("允许 WAN 访问 WS/WSS 端口"))
open_wan_ws.rmempty = false
open_wan_ws.default = "0"

local open_wan_web = v:taboption("listen", Flag, "open_wan_web", translate("允许 WAN 访问管理页面端口"))
open_wan_web.rmempty = false
open_wan_web.default = "0"

local ikev2_enabled = v:taboption("listen", Flag, "ikev2_enabled", translate("启用 IKEv2"),
	translate("启用 IKEv2 VPN 访问；必须填写服务器地址和 Remote ID"))
ikev2_enabled.rmempty = false
ikev2_enabled.default = "0"

local ikev2_ike_bind = v:taboption("listen", Value, "ikev2_ike_bind", translate("IKEv2 绑定地址"),
	translate("IKE 监听地址，通常使用 UDP 500 端口"))
ikev2_ike_bind.placeholder = "[::]:500"
ikev2_ike_bind.validate = validate_ikev2_bind

local ikev2_natt_bind = v:taboption("listen", Value, "ikev2_natt_bind", translate("IKEv2 NAT-T 绑定地址"),
	translate("NAT-T 监听地址，通常使用 UDP 4500 端口，必须与 IKE 使用不同端口"))
ikev2_natt_bind.placeholder = "[::]:4500"
ikev2_natt_bind.validate = validate_ikev2_natt_bind

local ikev2_server_address = v:taboption("listen", Value, "ikev2_server_address", translate("IKEv2 服务器地址"),
	translate("IKEv2 客户端使用的公网 DNS 名称或 IPv4 地址"))
ikev2_server_address.placeholder = "vpn.example.com"
ikev2_server_address.validate = validate_ikev2_server_address

local ikev2_remote_id = v:taboption("listen", Value, "ikev2_remote_id", translate("IKEv2 Remote ID"),
	translate("IKEv2 身份标识，通常填写服务器 DNS 名称"))
ikev2_remote_id.placeholder = "vpn.example.com"
ikev2_remote_id.validate = validate_ikev2_remote_id

local ikev2_cert = v:taboption("listen", Value, "ikev2_cert", translate("IKEv2 证书路径"),
	translate("证书路径；证书和私钥必须同时填写"))
ikev2_cert.placeholder = "/etc/vnt2/ikev2.crt"
ikev2_cert.validate = validate_ikev2_cert

local ikev2_key = v:taboption("listen", Value, "ikev2_key", translate("IKEv2 私钥路径"),
	translate("私钥路径；证书和私钥必须同时填写"))
ikev2_key.placeholder = "/etc/vnt2/ikev2.key"
ikev2_key.password = true
ikev2_key.validate = validate_ikev2_key

local ikev2_dns = v:taboption("listen", DynamicList, "ikev2_dns", translate("IKEv2 DNS"),
	translate("IPv4 DNS addresses handed to IKEv2 clients"))
ikev2_dns.placeholder = "1.1.1.1"
ikev2_dns.validate = validate_dynamic_items(validate_ipv4_item)
bind_dynamiclist(ikev2_dns)

local wireguard_enabled = v:taboption("listen", Flag, "wireguard_enabled", translate("启用 WireGuard"),
	translate("启用 WireGuard 访问"))
wireguard_enabled.rmempty = false
wireguard_enabled.default = "0"

local wireguard_bind = v:taboption("listen", Value, "wireguard_bind", translate("WireGuard 绑定地址"),
	translate("WireGuard UDP 监听地址，通常使用 51820 端口"))
wireguard_bind.placeholder = "[::]:51820"
wireguard_bind.validate = validate_ip_socket_addr

local wireguard_endpoint = v:taboption("listen", Value, "wireguard_endpoint", translate("WireGuard 端点"),
	translate("启用 WireGuard 时必填，格式为 host:port 或 [IPv6]:port"))
wireguard_endpoint.placeholder = "vpn.example.com:51820"
wireguard_endpoint.validate = validate_wireguard_endpoint

local wireguard_private_key = v:taboption("listen", Value, "wireguard_private_key", translate("WireGuard 私钥"),
	translate("Base64 编码的 32 字节私钥"))
wireguard_private_key.password = true
wireguard_private_key.validate = validate_wireguard_private_key

local wireguard_persistent_keepalive = v:taboption("listen", Value, "wireguard_persistent_keepalive", translate("WireGuard 持久保活"),
	translate("保活间隔秒数，范围 0 到 65535"))
wireguard_persistent_keepalive.placeholder = "25"
wireguard_persistent_keepalive.validate = validate_wireguard_keepalive

local open_wan_ikev2_ike = v:taboption("listen", Flag, "open_wan_ikev2_ike", translate("允许 WAN 访问 IKEv2"))
open_wan_ikev2_ike.rmempty = false
open_wan_ikev2_ike.default = "0"

local open_wan_ikev2_natt = v:taboption("listen", Flag, "open_wan_ikev2_natt", translate("允许 WAN 访问 IKEv2 NAT-T"))
open_wan_ikev2_natt.rmempty = false
open_wan_ikev2_natt.default = "0"

local open_wan_wireguard = v:taboption("listen", Flag, "open_wan_wireguard", translate("允许 WAN 访问 WireGuard"))
open_wan_wireguard.rmempty = false
open_wan_wireguard.default = "0"

cbi_options.ikev2_enabled = ikev2_enabled
cbi_options.ikev2_ike_bind = ikev2_ike_bind
cbi_options.ikev2_natt_bind = ikev2_natt_bind
cbi_options.ikev2_server_address = ikev2_server_address
cbi_options.ikev2_remote_id = ikev2_remote_id
cbi_options.ikev2_cert = ikev2_cert
cbi_options.ikev2_key = ikev2_key
cbi_options.wireguard_enabled = wireguard_enabled

local open_server_web = v:taboption("listen", DummyValue, "_open_server_web", translate("打开页面"),
	translate("打开当前配置对应的 vnts2 管理页面，默认地址通常为 http://路由器IP:29871/"))
open_server_web.rawhtml = true
open_server_web.cfgvalue = function()
	return string.format(
		'<a class="btn cbi-button cbi-button-apply" href="%s" target="_blank" rel="noopener noreferrer">%s</a>',
		util.pcdata(dispatcher.build_url("admin", "vpn", "vnt2", "open_server_web")),
		util.pcdata(translate("打开页面"))
	)
end

local network = v:taboption("cluster", Value, "network", translate("虚拟网段"),
	translate("服务端负责分配的虚拟地址池，例如 10.26.0.0/24"))
network.placeholder = "10.26.0.0/24"
network.validate = validate_cidr

local lease_duration = v:taboption("cluster", Value, "lease_duration", translate("租约时长（秒）"),
	translate("客户端虚拟地址租约时长"))
lease_duration.placeholder = "86400"
lease_duration.datatype = "uinteger"

local persistence = v:taboption("cluster", Flag, "persistence", translate("启用持久化"),
	translate("开启后服务端会持久化地址租约和相关状态"))
persistence.rmempty = false
persistence.default = "1"

local white_list = v:taboption("cluster", DynamicList, "white_list", translate("白名单令牌"),
	translate("用于限制允许接入的 token 列表"))
white_list.placeholder = "demo-token"
bind_dynamiclist(white_list)

local peer_servers = v:taboption("cluster", DynamicList, "peer_servers", translate("上游/同伴服务端"),
	translate("用于多服务端互联，格式一般为 host:port"))
peer_servers.placeholder = "1.2.3.4:29872"
peer_servers.validate = validate_server
bind_dynamiclist(peer_servers)

local custom_net = v:taboption("cluster", DynamicList, "custom_net", translate("附加网段列表"),
	translate("格式为网络编号,CIDR，例如 office,10.27.0.0/24"))
custom_net.placeholder = "office,10.27.0.0/24"
custom_net.validate = validate_dynamic_items(validate_custom_net_item)
bind_dynamiclist(custom_net)

local server_conf_path = v:taboption("advanced", Value, "server_conf_file", translate("配置文件路径"),
	translate("vnts2 服务端使用的 TOML 配置文件绝对路径"))
server_conf_path.placeholder = "/etc/config/vnts2.toml"
server_conf_path.default = "/etc/config/vnts2.toml"
server_conf_path.validate = validate_file_path

local server_tip = v:taboption("advanced", DummyValue, "_server_tip", translate("说明"))
server_tip.rawhtml = true
server_tip.cfgvalue = function()
	return [[
<div class="cbi-value-description">
	<div>1. 当前 LuCI 会将 CLI 与 Web 配置共同持久化到同一个 TOML 文件（默认 /vnt_config/vnt2_cli_web.toml），服务端则单独持久化到对应的 TOML 文件，并自动同步到 UCI 表单显示。</div>
	<div>2. TCP / QUIC / WS/WSS / Web 管理页均可独立监听，并可按需开放 WAN 防火墙规则。</div>
	<div>3. 若启用自动下载，默认会从服务端仓库 Releases 中选择匹配当前架构的压缩包。</div>
</div>
]]
end

local server_cmd = v:taboption("infos", Button, "_server_cmd", translate("读取服务端启动参数"))
server_cmd.inputtitle = translate("刷新")
server_cmd.inputstyle = "apply"
server_cmd.write = function()
	if server_running then
		sys.call("tr '\\000' ' ' </proc/$(pidof vnts2 2>/dev/null | awk '{print $1}')/cmdline >/tmp/vnts2_cmd 2>/dev/null || tr '\\000' ' ' </proc/$(pidof vnts 2>/dev/null | awk '{print $1}')/cmdline >/tmp/vnts2_cmd 2>/dev/null")
	else
		sys.call("echo '错误：程序未运行！请先启动 vnts2。' >/tmp/vnts2_cmd")
	end
end

local server_cmd_content = v:taboption("infos", DummyValue, "_server_cmd_content")
server_cmd_content.rawhtml = true
server_cmd_content.cfgvalue = function()
	return render_pre("/tmp/vnts2_cmd")
end

local server_conf_preview = v:taboption("infos", DummyValue, "_server_conf_preview", translate("当前服务端配置预览"))
server_conf_preview.rawhtml = true
server_conf_preview.cfgvalue = function()
	return render_pre(trim(m.uci:get_first("vnt2", "vnts2", "server_conf_file")) ~= ""
		and trim(m.uci:get_first("vnt2", "vnts2", "server_conf_file"))
		or toml.DEFAULT_SERVER_TOML)
end

local server_upload = v:taboption("upload", FileUpload, "upload_server")
server_upload.optional = true
server_upload.default = ""
server_upload.template = "vnt2/other_upload"
server_upload.description = translate("支持上传 vnts2 / vnts 二进制文件，或包含这些文件的 .tar.gz 压缩包；上传后会自动安装到 /usr/bin/ 并赋予执行权限；当自动下载失败时，系统会自动回退使用这里上传并安装的程序。")

local server_upload_note = v:taboption("upload", DummyValue, "_upload_note_server")
server_upload_note.rawhtml = true
server_upload_note.template = "vnt2/other_dvalue"
cbi_options.server_upload_note = server_upload_note
end)()

add_file_upload_handler({
	cbi_options.upload_note,
	cbi_options.web_upload_note,
	cbi_options.server_upload_note
})

return m
