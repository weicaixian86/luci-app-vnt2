module("luci.controller.vnt2", package.seeall)

local fs = require "nixio.fs"
local sys = require "luci.sys"
local http = require "luci.http"
local uci = require "luci.model.uci".cursor()
local toml = require "luci.model.vnt2_toml"
local textutil = require "luci.model.vnt2_text"
local LOG_DISPLAY_LINES = 300

function index()
	if not fs.access("/etc/config/vnt2") and not fs.access(toml.CLIENT_TOML) and not fs.access(toml.SERVER_TOML) then
		return
	end

	toml.ensure_toml_files(uci)

	entry({ "admin", "vpn", "vnt2" }, alias("admin", "vpn", "vnt2", "config"), _("VNT2"), 45).dependent = true
	entry({ "admin", "vpn", "vnt2", "config" }, cbi("vnt2"), _("基本设置"), 10).leaf = true
	entry({ "admin", "vpn", "vnt2", "client_log" }, cbi("vnt2_log"), _("CLI 日志"), 20).leaf = true
	entry({ "admin", "vpn", "vnt2", "web_log" }, cbi("vnt2_web_log"), _("Web 日志"), 30).leaf = true
	entry({ "admin", "vpn", "vnt2", "server_log" }, cbi("vnt2_server_log"), _("服务端日志"), 40).leaf = true
	entry({ "admin", "vpn", "vnt2", "download_log" }, cbi("vnt2_download_log"), _("下载日志"), 50).leaf = true

	entry({ "admin", "vpn", "vnt2", "status" }, call("act_status")).leaf = true
	entry({ "admin", "vpn", "vnt2", "get_client_log" }, call("get_client_log")).leaf = true
	entry({ "admin", "vpn", "vnt2", "clear_client_log" }, call("clear_client_log")).leaf = true
	entry({ "admin", "vpn", "vnt2", "get_web_log" }, call("get_web_log")).leaf = true
	entry({ "admin", "vpn", "vnt2", "clear_web_log" }, call("clear_web_log")).leaf = true
	entry({ "admin", "vpn", "vnt2", "get_server_log" }, call("get_server_log")).leaf = true
	entry({ "admin", "vpn", "vnt2", "clear_server_log" }, call("clear_server_log")).leaf = true
	entry({ "admin", "vpn", "vnt2", "get_download_log" }, call("get_download_log")).leaf = true
	entry({ "admin", "vpn", "vnt2", "clear_download_log" }, call("clear_download_log")).leaf = true

	entry({ "admin", "vpn", "vnt2", "vnt2_info" }, call("vnt2_info")).leaf = true
	entry({ "admin", "vpn", "vnt2", "vnt2_ips" }, call("vnt2_ips")).leaf = true
	entry({ "admin", "vpn", "vnt2", "vnt2_clients" }, call("vnt2_clients")).leaf = true
	entry({ "admin", "vpn", "vnt2", "vnt2_route" }, call("vnt2_route")).leaf = true
	entry({ "admin", "vpn", "vnt2", "vnt2_cmdline" }, call("vnt2_cmdline")).leaf = true
	entry({ "admin", "vpn", "vnt2", "vnt2_web_cmdline" }, call("vnt2_web_cmdline")).leaf = true
	entry({ "admin", "vpn", "vnt2", "vnts2_cmdline" }, call("vnts2_cmdline")).leaf = true
	entry({ "admin", "vpn", "vnt2", "open_web" }, call("open_web")).leaf = true
	entry({ "admin", "vpn", "vnt2", "open_server_web" }, call("open_server_web")).leaf = true
end

local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function shell_quote(s)
	s = tostring(s or "")
	return "'" .. s:gsub("'", [['"'"']]) .. "'"
end

local function json_write(data)
	http.prepare_content("application/json")
	http.write_json(data)
end

local function plain_write(data)
	http.prepare_content("text/plain; charset=utf-8")
	http.write(data or "")
end

local function uci_first(stype, opt, default)
	local v = uci:get_first("vnt2", stype, opt)
	if v == nil or v == "" then
		return default
	end
	return v
end

local function uci_list(stype, opt)
	local values = {}
	uci:foreach("vnt2", stype, function(s)
		local v = s[opt]
		if type(v) == "table" then
			for _, item in ipairs(v) do
				item = trim(item)
				if item ~= "" then
					values[#values + 1] = item
				end
			end
		elseif type(v) == "string" then
			v = trim(v)
			if v ~= "" then
				values[#values + 1] = v
			end
		end
	end)
	return values
end

local function file_exists(path)
	return path and path ~= "" and fs.access(path)
end

local function get_cli_bin()
	return uci_first("vnt2_cli", "vnt2_cli_bin", "/usr/bin/vnt2_cli")
end

local function get_ctrl_bin()
	return uci_first("vnt2_cli", "vnt2_ctrl_bin", "/usr/bin/vnt2_ctrl")
end

local function get_web_bin()
	return uci_first("vnt2_web", "vnt2_web_bin", "/usr/bin/vnt2_web")
end

local function get_server_bin()
	return uci_first("vnts2", "vnts2_bin", "/usr/bin/vnts2")
end

local function get_ctrl_port()
	local cfg = toml.get_client_summary(uci)
	return tonumber(cfg.ctrl_port or "11233") or 11233
end

local function get_web_port()
	return tonumber(uci_first("vnt2_web", "web_port", "19099")) or 19099
end

local function get_web_host()
	return uci_first("vnt2_web", "web_host", "0.0.0.0")
end

local function get_server_web_bind()
	return uci_first("vnts2", "web_bind", "[::]:29871")
end

local function get_client_conf()
	return toml.CLIENT_TOML
end

local function get_server_conf()
	return toml.SERVER_TOML
end

local function get_pid_by_name(name)
	local pid = trim(sys.exec("pidof " .. shell_quote(name) .. " 2>/dev/null | awk '{print $1}'"))
	if pid ~= "" then
		return pid
	end
	return nil
end

local function get_pid_by_path(path)
	local base = tostring(path or ""):match("([^/]+)$")
	if base and base ~= "" then
		local pid = get_pid_by_name(base)
		if pid then
			return pid
		end
	end

	local pid = trim(sys.exec("ps -w 2>/dev/null | grep " .. shell_quote(path or "") .. " | grep -v grep | awk 'NR==1{print $1}'"))
	if pid ~= "" then
		return pid
	end

	return nil
end

local function get_cli_pid()
	return get_pid_by_path(get_cli_bin())
end

local function get_web_pid()
	return get_pid_by_path(get_web_bin())
end

local function get_server_pid()
	return get_pid_by_name("vnts2") or get_pid_by_name("vnts") or get_pid_by_path(get_server_bin())
end

local function format_runtime(tag_file)
	local t = fs.readfile(tag_file)
	if not t then
		return ""
	end

	local start_ts = tonumber(trim(t))
	if not start_ts then
		return ""
	end

	local now_ts = os.time()
	if not now_ts or now_ts < start_ts then
		return ""
	end

	local delta = now_ts - start_ts
	local day = math.floor(delta / 86400)
	local hour = math.floor((delta % 86400) / 3600)
	local min = math.floor((delta % 3600) / 60)
	local sec = delta % 60

	if day > 0 then
		return string.format("%dd %02dh %02dm %02ds", day, hour, min, sec)
	end

	return string.format("%02dh %02dm %02ds", hour, min, sec)
end

local function get_clk_tck()
	local value = tonumber(trim(sys.exec("getconf CLK_TCK 2>/dev/null"))) or 100
	if value < 1 then
		value = 100
	end
	return value
end

local function get_page_size()
	local value = tonumber(trim(sys.exec("getconf PAGESIZE 2>/dev/null"))) or 4096
	if value < 1 then
		value = 4096
	end
	return value
end

local function get_cpu_count()
	local count = tonumber(trim(sys.exec([[awk '/^cpu[0-9]+ /{n++} END{print n?n:1}' /proc/stat 2>/dev/null]]))) or 1
	if count < 1 then
		count = 1
	end
	return count
end

local function get_cpu_usage(pid)
	pid = trim(pid)
	if pid == "" or not pid:match("^%d+$") then
		return ""
	end

	local stat = fs.readfile("/proc/" .. pid .. "/stat")
	if not stat or stat == "" then
		return ""
	end

	local right = stat:find("%)")
	if not right then
		return ""
	end

	local fields = {}
	for token in stat:sub(right + 2):gmatch("%S+") do
		fields[#fields + 1] = token
	end

	local utime = tonumber(fields[12] or "")
	local stime = tonumber(fields[13] or "")
	local starttime = tonumber(fields[20] or "")
	if not utime or not stime or not starttime then
		return ""
	end

	local uptime_line = trim(fs.readfile("/proc/uptime") or "")
	local uptime = tonumber((uptime_line:match("^([%d%.]+)") or ""))
	if not uptime or uptime <= 0 then
		return ""
	end

	local clk_tck = get_clk_tck()
	local cpu_count = get_cpu_count()
	local elapsed = uptime - (starttime / clk_tck)
	if elapsed <= 0 then
		return "0.00%"
	end

	local total = (utime + stime) / clk_tck
	local cpu = (total / elapsed) * 100
	if cpu_count > 1 then
		cpu = cpu / cpu_count
	end
	if cpu < 0 then
		cpu = 0
	end

	return string.format("%.2f%%", cpu)
end

local function get_mem_usage(pid)
	pid = trim(pid)
	if pid == "" or not pid:match("^%d+$") then
		return ""
	end

	local status = fs.readfile("/proc/" .. pid .. "/status") or ""
	local rss_kb = tonumber(status:match("VmRSS:%s*(%d+)"))
	if not rss_kb then
		local statm = fs.readfile("/proc/" .. pid .. "/statm") or ""
		local rss_pages = tonumber(statm:match("^%S+%s+(%d+)"))
		if rss_pages then
			rss_kb = (rss_pages * get_page_size()) / 1024
		end
	end

	if not rss_kb then
		return ""
	end

	return string.format("%.2f MB", rss_kb / 1024)
end

local function get_local_tag(bin_path, primary_state, fallback_state)
	if not file_exists(bin_path) then
		return ""
	end

	for _, state in ipairs({ primary_state, fallback_state }) do
		if state and (state.state == "success" or state.state == "cached") then
			local tag = trim(state.tag):gsub("^[vV]", "")
			if tag ~= "" then
				return tag
			end
		end
	end

	return ""
end

local function sanitize_cache_name(s)
	return tostring(s or ""):gsub("[^%w%._-]", "_")
end

local function normalize_download_mirror(mirror)
	mirror = trim(mirror):lower()
	if mirror == "gh-proxy" or mirror == "ghproxy" or mirror == "proxy" then
		return "gh-proxy"
	end
	if mirror == "" or mirror == "auto" or mirror == "cn" or mirror == "china" or mirror == "domestic" then
		return "auto"
	end
	if mirror == "github" then
		return mirror
	end
	if mirror == "gitee" or mirror == "gitlab" or mirror == "cloudflare" or mirror == "custom" then
		return mirror
	end
	return "auto"
end

local function normalize_custom_mirror_url(url)
	url = trim(url)
	if url == "" or not url:match("^https?://[^%s]+/?$") then
		return ""
	end
	return (url:gsub("/*$", "/"))
end

local function repo_to_mirror_project(repo)
	repo = trim(repo)
	if repo == "vnt-dev/vnt" then
		return "vnt"
	elseif repo == "vnt-dev/vnts" then
		return "vnts"
	end
	return nil
end

local function get_download_mirror_candidates(repo, mirror)
	repo = trim(repo)
	if repo == "" then
		repo = "vnt-dev/vnt"
	end

	mirror = normalize_download_mirror(mirror)
	if mirror == "auto" then
		return { "gh-proxy", "github", "gitee", "gitlab", "cloudflare" }
	elseif mirror == "gh-proxy" then
		return { "gh-proxy", "github" }
	elseif mirror == "github" then
		return { "github" }
	elseif mirror == "custom" then
		return { "custom", "github" }
	elseif mirror == "gitee" or mirror == "gitlab" or mirror == "cloudflare" then
		return { mirror, "github" }
	end
	return { "gh-proxy", "github", "gitee", "gitlab", "cloudflare" }
end

local function build_latest_release_endpoint_for_mirror(repo, mirror)
	repo = trim(repo)
	if repo == "" then
		repo = "vnt-dev/vnt"
	end

	mirror = normalize_download_mirror(mirror)
	if mirror == "github" or mirror == "gh-proxy" or mirror == "auto" then
		return string.format("https://api.github.com/repos/%s/releases", repo), mirror
	end
	if mirror == "custom" then
		return string.format("https://api.github.com/repos/%s/releases", repo), mirror
	end

	local proj = repo_to_mirror_project(repo)
	if not proj then
		return string.format("https://api.github.com/repos/%s/releases", repo), "github"
	end

	if mirror == "gitee" then
		return string.format("https://gitee.com/api/v5/repos/whzhni/%s/releases", proj), mirror
	elseif mirror == "gitlab" then
		return string.format("https://gitlab.com/api/v4/projects/whzhni%%2F%s/releases", proj), mirror
	elseif mirror == "cloudflare" then
		return string.format("https://pub-8a57d35d70d5423aac22a3316867e7ce.r2.dev/%s/releases", proj), mirror
	end

	return string.format("https://api.github.com/repos/%s/releases", repo), "github"
end

local function get_cached_latest_tag(repo, mirror, custom_mirror_url)
	repo = trim(repo)
	if repo == "" then
		repo = "vnt-dev/vnt"
	end

	local strategy = normalize_download_mirror(mirror)
	for _, candidate in ipairs(get_download_mirror_candidates(repo, mirror)) do
		local _, effective_mirror = build_latest_release_endpoint_for_mirror(repo, candidate)
		local cache_key = strategy .. "_" .. effective_mirror .. "_" .. repo
		if effective_mirror == "custom" then
			cache_key = cache_key .. "_" .. normalize_custom_mirror_url(custom_mirror_url)
		end
		local cache = "/tmp/vnt2_latest_v2_" .. sanitize_cache_name(cache_key) .. ".tag"

		if fs.access(cache) then
			local cached = trim(fs.readfile(cache) or "")
			if cached ~= "" then
				return cached
			end
		end
	end

	return ""
end

local function normalize_display_tag(tag)
	tag = trim(tag)
	if tag == "" then
		return ""
	end
	tag = tag:gsub("^[vV]", "")
	return tag
end

local function get_vnt2_latest_tag(repo, configured_tag, mirror, custom_mirror_url)
	repo = trim(repo)
	configured_tag = trim(configured_tag)

	if repo == "" then
		repo = "vnt-dev/vnt"
	end

	if repo == "vnt-dev/vnt" or repo == "vnt-dev/vnts" then
		if configured_tag ~= "" and configured_tag ~= "latest" then
			return normalize_display_tag(configured_tag)
		end

		local latest = normalize_display_tag(get_cached_latest_tag(repo, mirror, custom_mirror_url))
		if latest ~= "" then
			return latest
		end

		return repo == "vnt-dev/vnts" and "2.0.6" or "2.0.9"
	end

	if configured_tag ~= "" and configured_tag ~= "latest" then
		return normalize_display_tag(configured_tag)
	end

	return normalize_display_tag(get_cached_latest_tag(repo, mirror, custom_mirror_url))
end

local function sanitize_text_content(content)
	content = tostring(content or "")
	content = content:gsub("\27%[[%d;?]*[%a]", "")
	content = content:gsub("\27%][^\7]*\7", "")
	content = content:gsub("%z", "")
	content = content:gsub("\r", "")
	return content
end

local function looks_like_mojibake(content)
	content = tostring(content or "")
	return false
end

local function maybe_repair_mojibake(path, content)
	if not path or path == "" or not looks_like_mojibake(content) then
		return content
	end
	if sys.call("command -v iconv >/dev/null 2>&1") ~= 0 then
		return content
	end

	local repaired = sys.exec(string.format("iconv -f UTF-8 -t GB18030 %s 2>/dev/null", shell_quote(path)))
	if repaired and repaired ~= "" then
		return repaired
	end

	return content
end

local function get_log_content(path, max_lines)
	return textutil.read_log_file(path, max_lines)
end

local function parse_state_file(path)
	local out = {
		state = "",
		message = "",
		asset = "",
		tag = "",
		arch = "",
		path = "",
		time = ""
	}

	local content = fs.readfile(path)
	if not content or content == "" then
		return out
	end

	for line in content:gmatch("[^\r\n]+") do
		local k, v = line:match("^([%w_]+)=(.*)$")
		if k and out[k] ~= nil then
			out[k] = trim(v)
		end
	end

	out.state = textutil.sanitize_text(out.state)
	out.message = textutil.normalize_log_text(out.message)
	out.asset = textutil.sanitize_text(out.asset)
	out.tag = textutil.sanitize_text(out.tag)
	out.arch = textutil.sanitize_text(out.arch)
	out.path = textutil.sanitize_text(out.path)
	out.time = textutil.sanitize_text(out.time)

	return out
end

local function parse_help_for_port_mode(bin_path)
	if not file_exists(bin_path) then
		return ""
	end
	local help = sys.exec(string.format("timeout 2 %s -h 2>&1", shell_quote(bin_path))) or ""
	if help:match("%-%-port") or help:match("%-p, %-%-port") then
		return "--port"
	end
	if help:match("%-%-ctrl%-port") then
		return "--ctrl-port"
	end
	return ""
end

local function run_ctrl(subcmd)
	local ctrl_bin = get_ctrl_bin()
	local cli_bin = get_cli_bin()
	local ctrl_port = get_ctrl_port()
	local out = ""

	if file_exists(ctrl_bin) then
		local port_arg = parse_help_for_port_mode(ctrl_bin)
		if port_arg ~= "" then
			out = sys.exec(string.format("timeout 2 %s %s %s %d 2>&1", shell_quote(ctrl_bin), subcmd, port_arg, ctrl_port))
		else
			out = sys.exec(string.format("timeout 2 %s %s %d 2>&1", shell_quote(ctrl_bin), subcmd, ctrl_port))
		end
	end

	out = trim(out)
	if out == "" or out:match("not found") or out:match("unrecognized") or out:match("error:") then
		if file_exists(cli_bin) then
			out = sys.exec(string.format("timeout 2 %s %s 2>&1", shell_quote(cli_bin), subcmd))
		end
	end

	return trim(out or "")
end

local function get_cmdline(pid)
	if not pid then
		return ""
	end
	return trim(sys.exec("tr '\\000' ' ' </proc/" .. tostring(pid) .. "/cmdline 2>/dev/null"))
end

local function parse_bind_port(bind)
	bind = trim(bind)
	if bind == "" then
		return nil
	end

	local port = bind:match(":(%d+)$")
	return tonumber(port or "")
end

local function get_router_host()
	local http_host = trim(http.getenv("HTTP_HOST") or "")
	if http_host ~= "" then
		local host = http_host:match("^%[([^%]]+)%]") or http_host:match("^([^:]+)")
		host = trim(host)
		if host ~= "" then
			return host
		end
	end

	local server_addr = trim(http.getenv("SERVER_ADDR") or "")
	if server_addr ~= "" then
		return server_addr
	end

	local lan_ip = trim(sys.exec("uci -q get network.lan.ipaddr 2>/dev/null | head -n1"))
	if lan_ip ~= "" then
		return lan_ip
	end

	local web_host = get_web_host()
	if web_host == "0.0.0.0" or web_host == "::" or web_host == "127.0.0.1" or web_host == "::1" then
		return "192.168.1.1"
	end

	return web_host
end

local function build_web_url()
	local host = get_router_host()
	local port = get_web_port()

	if host:find(":", 1, true) and not host:match("^%[.*%]$") then
		host = "[" .. host .. "]"
	end

	return "http://" .. host .. ":" .. tostring(port) .. "/"
end

local function build_server_web_url()
	local host = get_router_host()
	local bind = get_server_web_bind()
	local port = parse_bind_port(bind) or 29871

	if host:find(":", 1, true) and not host:match("^%[.*%]$") then
		host = "[" .. host .. "]"
	end

	return "http://" .. host .. ":" .. tostring(port) .. "/"
end

local function summarize_cli_config()
	local cfg = toml.get_client_summary(uci)
	return {
		conf_file = get_client_conf(),
		servers = cfg.server or {},
		network_code = cfg.network_code or "",
		device_name = cfg.device_name or "",
		device_id = cfg.device_id or "",
		tun_name = cfg.tun_name or "vnt-tun",
		device_mode = cfg.device_mode or "tun",
		no_nat = trim(cfg.no_nat) ~= "" and cfg.no_nat or "0",
		peer_address = cfg.peer_address or {},
		turn = cfg.turn or {},
		punch_model = cfg.punch_model or {},
		no_broadcast = cfg.no_broadcast or "0",
		allow_ikev2 = cfg.allow_ikev2 or "0",
		allow_wireguard = cfg.allow_wireguard or "0",
		subnet_mapping = cfg.subnet_mapping or {},
		auto_sync_subnet = cfg.auto_sync_subnet or "0",
		outbound_interface = cfg.outbound_interface or "",
		tunnel_addr = cfg.tunnel_addr or {},
		event_script = cfg.event_script or "",
		ctrl_port = tonumber(cfg.ctrl_port or "11233") or 11233,
		auto_download = uci_first("vnt2_cli", "auto_download", "1"),
		download_repo = uci_first("vnt2_cli", "download_repo", "vnt-dev/vnt"),
		download_tag = uci_first("vnt2_cli", "download_tag", "latest"),
		download_mirror = uci_first("vnt2_cli", "download_mirror", "auto"),
		custom_download_mirror = uci_first("vnt2_cli", "custom_download_mirror", "")
	}
end

local function summarize_web_config()
	return {
		host = get_web_host(),
		port = get_web_port(),
		wan = uci_first("vnt2_web", "web_wan", "1"),
		log_level = uci_first("vnt2_web", "log_level", "info"),
		auto_download = uci_first("vnt2_web", "auto_download", "1"),
		download_repo = uci_first("vnt2_web", "download_repo", "vnt-dev/vnt"),
		download_tag = uci_first("vnt2_web", "download_tag", "latest"),
		download_mirror = uci_first("vnt2_web", "download_mirror", "auto"),
		custom_download_mirror = uci_first("vnt2_web", "custom_download_mirror", "")
	}
end

local function summarize_server_config()
	local cfg = toml.get_server_summary(uci)
	return {
		tcp_bind = cfg.tcp_bind or "[::]:29872",
		quic_bind = cfg.quic_bind or "[::]:29872",
		ws_bind = cfg.ws_bind or "[::]:29872",
		web_bind = cfg.web_bind or "[::]:29871",
		server_quic_bind = cfg.server_quic_bind or "",
		ikev2_enabled = cfg.ikev2 and cfg.ikev2.enabled or "0",
		ikev2_ike_bind = cfg.ikev2 and cfg.ikev2.ike_bind or "[::]:500",
		ikev2_natt_bind = cfg.ikev2 and cfg.ikev2.natt_bind or "[::]:4500",
		ikev2_server_address = cfg.ikev2 and cfg.ikev2.server_address or "",
		ikev2_remote_id = cfg.ikev2 and cfg.ikev2.remote_id or "",
		ikev2_dns = cfg.ikev2 and cfg.ikev2.dns or {},
		wireguard_enabled = cfg.wireguard and cfg.wireguard.enabled or "0",
		wireguard_bind = cfg.wireguard and cfg.wireguard.bind or "[::]:51820",
		wireguard_endpoint = cfg.wireguard and cfg.wireguard.endpoint or "",
		wireguard_persistent_keepalive = cfg.wireguard and cfg.wireguard.persistent_keepalive or "25",
		network = cfg.network or "10.26.0.0/24",
		lease_duration = cfg.lease_duration or "86400",
		persistence = cfg.persistence or "1",
		username = cfg.username or "admin",
		auto_download = uci_first("vnts2", "auto_download", "1"),
		download_repo = uci_first("vnts2", "download_repo", "vnt-dev/vnts"),
		download_tag = uci_first("vnts2", "download_tag", "latest"),
		download_mirror = uci_first("vnts2", "download_mirror", "auto"),
		custom_download_mirror = uci_first("vnts2", "custom_download_mirror", ""),
		white_list = cfg.white_list or {},
		peer_servers = cfg.peer_servers or {},
		custom_net = cfg.custom_nets or {},
		open_wan_tcp = uci_first("vnts2", "open_wan_tcp", "0"),
		open_wan_quic = uci_first("vnts2", "open_wan_quic", "0"),
		open_wan_server_quic = uci_first("vnts2", "open_wan_server_quic", "0"),
		open_wan_ws = uci_first("vnts2", "open_wan_ws", "0"),
		open_wan_web = uci_first("vnts2", "open_wan_web", "0"),
		open_wan_ikev2_ike = uci_first("vnts2", "open_wan_ikev2_ike", "0"),
		open_wan_ikev2_natt = uci_first("vnts2", "open_wan_ikev2_natt", "0"),
		open_wan_wireguard = uci_first("vnts2", "open_wan_wireguard", "0"),
		server_conf_file = get_server_conf()
	}
end

function act_status()
	local e = {}
	local cli_enabled = uci_first("vnt2_cli", "enabled", "0") == "1"
	local web_enabled = uci_first("vnt2_web", "enabled", "0") == "1"
	local server_enabled = uci_first("vnts2", "enabled", "0") == "1"

	local cli_pid = get_cli_pid()
	local web_pid = get_web_pid()
	local server_pid = get_server_pid()

	local cli_cfg = summarize_cli_config()
	local web_cfg = summarize_web_config()
	local server_cfg = summarize_server_config()

	local cli_dl = parse_state_file("/tmp/vnt2-download-cli.state")
	local web_dl = parse_state_file("/tmp/vnt2-download-web.state")
	local server_dl = parse_state_file("/tmp/vnt2-download-server.state")

	-- This endpoint is polled every five seconds. Keep it local-only so an
	-- unavailable process cannot hold the LuCI request open during apply.
	e.cli_running = cli_enabled and cli_pid ~= nil
	e.web_running = web_enabled and web_pid ~= nil
	e.server_running = server_enabled and server_pid ~= nil

	e.cli_pid = e.cli_running and cli_pid or ""
	e.web_pid = e.web_running and web_pid or ""
	e.server_pid = e.server_running and server_pid or ""

	e.cli_runtime = format_runtime("/tmp/vnt2_cli_time")
	e.web_runtime = format_runtime("/tmp/vnt2_web_time")
	e.server_runtime = format_runtime("/tmp/vnts2_time")

	e.cli_cpu = get_cpu_usage(cli_pid)
	e.cli_ram = get_mem_usage(cli_pid)
	e.web_cpu = get_cpu_usage(web_pid)
	e.web_ram = get_mem_usage(web_pid)
	e.server_cpu = get_cpu_usage(server_pid)
	e.server_ram = get_mem_usage(server_pid)

	-- Never execute managed binaries from this polling endpoint. A broken or
	-- blocked binary must not delay LuCI while an apply-triggered restart runs.
	e.cli_tag = get_local_tag(get_cli_bin(), cli_dl, web_dl)
	e.web_tag = get_local_tag(get_web_bin(), web_dl, cli_dl)
	e.server_tag = get_local_tag(get_server_bin(), server_dl)

	local latest_tag = get_vnt2_latest_tag(cli_cfg.download_repo, cli_cfg.download_tag, cli_cfg.download_mirror, cli_cfg.custom_download_mirror)
	if latest_tag == "" then
		latest_tag = get_vnt2_latest_tag(web_cfg.download_repo, web_cfg.download_tag, web_cfg.download_mirror, web_cfg.custom_download_mirror)
	end
	if latest_tag == "" then
		latest_tag = get_vnt2_latest_tag("vnt-dev/vnt", "latest", "auto")
	end

	local latest_server_tag = get_vnt2_latest_tag(server_cfg.download_repo, server_cfg.download_tag, server_cfg.download_mirror, server_cfg.custom_download_mirror)
	if latest_server_tag == "" then
		latest_server_tag = get_vnt2_latest_tag("vnt-dev/vnts", "latest", "auto")
	end

	e.latest_tag = latest_tag
	e.latest_server_tag = latest_server_tag

	e.ctrl_port = cli_cfg.ctrl_port
	e.web_host = get_web_host()
	e.web_port = get_web_port()
	e.web_url = build_web_url()

	e.cli_conf_file = cli_cfg.conf_file
	e.cli_conf_preview = get_log_content(cli_cfg.conf_file)
	e.cli_servers = cli_cfg.servers
	e.cli_network_code = cli_cfg.network_code
	e.cli_device_name = cli_cfg.device_name
	e.cli_device_id = cli_cfg.device_id
	e.cli_tun_name = cli_cfg.tun_name
	e.cli_device_mode = cli_cfg.device_mode
	e.cli_peer_address = cli_cfg.peer_address
	e.cli_turn = cli_cfg.turn
	e.cli_punch_model = cli_cfg.punch_model
	e.cli_no_broadcast = cli_cfg.no_broadcast
	e.cli_allow_ikev2 = cli_cfg.allow_ikev2
	e.cli_allow_wireguard = cli_cfg.allow_wireguard
	e.cli_subnet_mapping = cli_cfg.subnet_mapping
	e.cli_auto_sync_subnet = cli_cfg.auto_sync_subnet
	e.cli_outbound_interface = cli_cfg.outbound_interface
	e.cli_tunnel_addr = cli_cfg.tunnel_addr
	e.cli_event_script = cli_cfg.event_script
	e.cli_no_nat = cli_cfg.no_nat
	e.cli_auto_download = cli_cfg.auto_download
	e.cli_download_repo = cli_cfg.download_repo
	e.cli_download_tag = cli_cfg.download_tag
	e.cli_download_mirror = cli_cfg.download_mirror
	e.cli_custom_download_mirror = cli_cfg.custom_download_mirror

	e.web_log_level = web_cfg.log_level
	e.web_wan = web_cfg.wan
	e.web_auto_download = web_cfg.auto_download
	e.web_download_repo = web_cfg.download_repo
	e.web_download_tag = web_cfg.download_tag
	e.web_download_mirror = web_cfg.download_mirror
	e.web_custom_download_mirror = web_cfg.custom_download_mirror

	e.server_tcp_bind = server_cfg.tcp_bind
	e.server_quic_bind = server_cfg.quic_bind
	e.server_ws_bind = server_cfg.ws_bind
	e.server_web_bind = server_cfg.web_bind
	e.server_quic_proxy = server_cfg.server_quic_bind
	e.server_network = server_cfg.network
	e.server_lease_duration = server_cfg.lease_duration
	e.server_persistence = server_cfg.persistence
	e.server_username = server_cfg.username
	e.server_auto_download = server_cfg.auto_download
	e.server_download_repo = server_cfg.download_repo
	e.server_download_tag = server_cfg.download_tag
	e.server_download_mirror = server_cfg.download_mirror
	e.server_custom_download_mirror = server_cfg.custom_download_mirror
	e.server_white_list = server_cfg.white_list
	e.server_peer_servers = server_cfg.peer_servers
	e.server_custom_net = server_cfg.custom_net
	e.server_open_wan_tcp = server_cfg.open_wan_tcp
	e.server_open_wan_quic = server_cfg.open_wan_quic
	e.server_open_wan_server_quic = server_cfg.open_wan_server_quic
	e.server_open_wan_ws = server_cfg.open_wan_ws
	e.server_open_wan_web = server_cfg.open_wan_web
	e.server_ikev2_enabled = server_cfg.ikev2_enabled
	e.server_ikev2_ike_bind = server_cfg.ikev2_ike_bind
	e.server_ikev2_natt_bind = server_cfg.ikev2_natt_bind
	e.server_ikev2_server_address = server_cfg.ikev2_server_address
	e.server_ikev2_remote_id = server_cfg.ikev2_remote_id
	e.server_ikev2_dns = server_cfg.ikev2_dns
	e.server_wireguard_enabled = server_cfg.wireguard_enabled
	e.server_wireguard_bind = server_cfg.wireguard_bind
	e.server_wireguard_endpoint = server_cfg.wireguard_endpoint
	e.server_wireguard_persistent_keepalive = server_cfg.wireguard_persistent_keepalive
	e.server_open_wan_ikev2_ike = server_cfg.open_wan_ikev2_ike
	e.server_open_wan_ikev2_natt = server_cfg.open_wan_ikev2_natt
	e.server_open_wan_wireguard = server_cfg.open_wan_wireguard
	e.server_conf_file = server_cfg.server_conf_file
	e.server_conf_preview = get_log_content(server_cfg.server_conf_file)

	e.server_cmdline = get_cmdline(server_pid)

	e.download_log_size = #(get_log_content("/tmp/vnt2-download.log") or "")
	e.cli_download = cli_dl
	e.web_download = web_dl
	e.server_download = server_dl

	json_write(e)
end

local function clear_log_file(path)
	if not path or path == "" then
		return
	end
	fs.writefile(path, "")
end

function get_client_log()
	plain_write(get_log_content("/tmp/vnt2-cli.log", LOG_DISPLAY_LINES))
end

function clear_client_log()
	clear_log_file("/tmp/vnt2-cli.log")
	json_write({ ok = true })
end

function get_web_log()
	plain_write(get_log_content("/tmp/vnt2-web.log", LOG_DISPLAY_LINES))
end

function clear_web_log()
	clear_log_file("/tmp/vnt2-web.log")
	json_write({ ok = true })
end

function get_server_log()
	plain_write(get_log_content("/tmp/vnts2.log", LOG_DISPLAY_LINES))
end

function clear_server_log()
	clear_log_file("/tmp/vnts2.log")
	json_write({ ok = true })
end

function get_download_log()
	plain_write(get_log_content("/tmp/vnt2-download.log", LOG_DISPLAY_LINES))
end

function clear_download_log()
	clear_log_file("/tmp/vnt2-download.log")
	fs.remove("/tmp/vnt2-download-cli.state")
	fs.remove("/tmp/vnt2-download-web.state")
	fs.remove("/tmp/vnt2-download-server.state")
	json_write({ ok = true })
end

function vnt2_info()
	json_write({ info = run_ctrl("info") })
end

function vnt2_ips()
	json_write({ ips = run_ctrl("ips") })
end

function vnt2_clients()
	json_write({ clients = run_ctrl("clients") })
end

function vnt2_route()
	json_write({ route = run_ctrl("route") })
end

function vnt2_cmdline()
	local pid = get_pid_by_path(get_cli_bin())
	local cmdline = get_cmdline(pid)

	if cmdline == "" then
		cmdline = "错误：vnt2_cli 未运行。"
	end

	json_write({ cmdline = cmdline })
end

function vnt2_web_cmdline()
	local pid = get_pid_by_path(get_web_bin())
	local cmdline = get_cmdline(pid)

	if cmdline == "" then
		cmdline = "错误：vnt2_web 未运行。"
	end

	json_write({ cmdline = cmdline })
end

function vnts2_cmdline()
	local pid = get_server_pid()
	local cmdline = get_cmdline(pid)

	if cmdline == "" then
		cmdline = "错误：vnts2 未运行。"
	end

	json_write({ cmdline = cmdline })
end

function open_web()
	http.redirect(build_web_url())
end

function open_server_web()
	http.redirect(build_server_web_url())
end
