module("luci.controller.vnt2", package.seeall)

local fs = require "nixio.fs"
local sys = require "luci.sys"
local http = require "luci.http"
local uci = require "luci.model.uci".cursor()
local toml = require "luci.model.vnt2_toml"

function index()
	if not fs.access("/etc/config/vnt2") and not fs.access(toml.CLIENT_TOML) and not fs.access(toml.SERVER_TOML) then
		return
	end

	toml.ensure_toml_files(uci)

	entry({ "admin", "vpn", "vnt2" }, alias("admin", "vpn", "vnt2", "config"), _("VNT2"), 45).dependent = true
	entry({ "admin", "vpn", "vnt2", "config" }, cbi("vnt2"), _("基本设置"), 10).leaf = true
	entry({ "admin", "vpn", "vnt2", "client_log" }, cbi("vnt2_log"), _("客户端日志"), 20).leaf = true
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
	return tonumber(cfg.cmd_port or "11233") or 11233
end

local function get_web_port()
	return tonumber(uci_first("vnt2_web", "web_port", "19099")) or 19099
end

local function get_web_host()
	return uci_first("vnt2_web", "web_host", "127.0.0.1")
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
		return string.format("%d天 %02d小时%02d分%02d秒", day, hour, min, sec)
	end

	return string.format("%02d小时%02d分%02d秒", hour, min, sec)
end

local function get_cpu_usage(pid)
	if not pid then
		return ""
	end
	local cmd = string.format([=[top -bn1 2>/dev/null | awk '$1=="%s" {print $9; exit}']=], tostring(pid))
	return trim(sys.exec(cmd))
end

local function get_mem_usage(pid)
	if not pid then
		return ""
	end
	local cmd = string.format([=[awk '/VmRSS/ {printf "%.2f MB", $2/1024}' /proc/%s/status 2>/dev/null]=], tostring(pid))
	return trim(sys.exec(cmd))
end

local function get_local_tag(bin_path)
	if not file_exists(bin_path) then
		return ""
	end
	local cmd = string.format([=[ %s -h 2>&1 | sed -n 's/.*version[: ][[:space:]]*\([^ ,;)]*\).*/\1/p' | head -n1 ]=], shell_quote(bin_path))
	return trim(sys.exec(cmd))
end

local function sanitize_cache_name(s)
	return tostring(s or ""):gsub("[^%w%._-]", "_")
end

local function get_cached_latest_tag(repo)
	repo = trim(repo)
	if repo == "" then
		repo = "vnt-dev/vnt"
	end

	local cache = "/tmp/vnt2_latest_" .. sanitize_cache_name(repo) .. ".tag"
	local now = os.time() or 0

	if fs.access(cache) then
		local mtime = fs.stat(cache, "mtime") or 0
		if now > 0 and mtime > 0 and (now - mtime) < 21600 then
			return trim(fs.readfile(cache) or "")
		end
	end

	local cmd = string.format(
		[=[curl -fsSL --connect-timeout 4 "https://api.github.com/repos/%s/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1]=],
		repo
	)
	local tag = trim(sys.exec(cmd))
	if tag ~= "" then
		fs.writefile(cache, tag)
	end
	return tag
end

local function normalize_display_tag(tag)
	tag = trim(tag)
	if tag == "" then
		return ""
	end
	tag = tag:gsub("^[vV]", "")
	return tag
end

local function get_vnt2_latest_tag(repo, configured_tag)
	repo = trim(repo)
	configured_tag = trim(configured_tag)

	if repo == "" then
		repo = "vnt-dev/vnt"
	end

	if repo == "vnt-dev/vnt" or repo == "vnt-dev/vnts" then
		if configured_tag ~= "" and configured_tag ~= "latest" then
			return normalize_display_tag(configured_tag)
		end
		return "2.0.0"
	end

	if configured_tag ~= "" and configured_tag ~= "latest" then
		return normalize_display_tag(configured_tag)
	end

	return normalize_display_tag(get_cached_latest_tag(repo))
end

local function get_log_content(path)
	return fs.readfile(path) or ""
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

	return out
end

local function parse_help_for_port_mode(bin_path)
	if not file_exists(bin_path) then
		return ""
	end
	local help = sys.exec(string.format("%s -h 2>&1", shell_quote(bin_path))) or ""
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
			out = sys.exec(string.format("%s %s %s %d 2>&1", shell_quote(ctrl_bin), subcmd, port_arg, ctrl_port))
		else
			out = sys.exec(string.format("%s %s %d 2>&1", shell_quote(ctrl_bin), subcmd, ctrl_port))
		end
	end

	out = trim(out)
	if out == "" or out:match("not found") or out:match("unrecognized") or out:match("error:") then
		if file_exists(cli_bin) then
			out = sys.exec(string.format("%s %s 2>&1", shell_quote(cli_bin), subcmd))
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

local function summarize_cli_config()
	local cfg = toml.get_client_summary(uci)
	return {
		conf_file = get_client_conf(),
		servers = cfg.server or {},
		network_code = cfg.network_code or "",
		device_name = cfg.device_name or "",
		device_id = cfg.device_id or "",
		tun_name = cfg.tun_name or "vnt-tun",
		no_tun = cfg.no_tun or "0",
		no_nat = cfg.no_proxy or "0",
		ctrl_port = tonumber(cfg.cmd_port or "11233") or 11233,
		auto_download = uci_first("vnt2_cli", "auto_download", "1"),
		download_repo = uci_first("vnt2_cli", "download_repo", "vnt-dev/vnt"),
		download_tag = uci_first("vnt2_cli", "download_tag", "latest")
	}
end

local function summarize_web_config()
	return {
		host = get_web_host(),
		port = get_web_port(),
		wan = uci_first("vnt2_web", "web_wan", "0"),
		log_level = uci_first("vnt2_web", "log_level", "info"),
		auto_download = uci_first("vnt2_web", "auto_download", "1"),
		download_repo = uci_first("vnt2_web", "download_repo", "vnt-dev/vnt"),
		download_tag = uci_first("vnt2_web", "download_tag", "latest")
	}
end

local function summarize_server_config()
	local cfg = toml.get_server_summary(uci)
	return {
		tcp_bind = cfg.tcp or "0.0.0.0:29872",
		quic_bind = cfg.quic or "0.0.0.0:29872",
		ws_bind = cfg.ws or "0.0.0.0:29872",
		web_bind = cfg.web or "0.0.0.0:29871",
		server_quic_bind = cfg.quic_proxy or "",
		network = cfg.network or "10.26.0.0/24",
		lease_duration = cfg.lease_duration or "86400",
		persistence = cfg.persistence or "1",
		username = cfg.username or "admin",
		auto_download = uci_first("vnts2", "auto_download", "1"),
		download_repo = uci_first("vnts2", "download_repo", "vnt-dev/vnts"),
		download_tag = uci_first("vnts2", "download_tag", "latest"),
		white_list = cfg.white_token or {},
		peer_servers = cfg.server_address or {},
		custom_net = cfg.cidr or {},
		open_wan_tcp = uci_first("vnts2", "open_wan_tcp", "0"),
		open_wan_quic = uci_first("vnts2", "open_wan_quic", "0"),
		open_wan_ws = uci_first("vnts2", "open_wan_ws", "0"),
		open_wan_web = uci_first("vnts2", "open_wan_web", "0"),
		server_conf_file = get_server_conf()
	}
end

function act_status()
	local e = {}
	local cli_pid = get_pid_by_path(get_cli_bin())
	local web_pid = get_pid_by_path(get_web_bin())
	local server_pid = get_server_pid()

	local cli_cfg = summarize_cli_config()
	local web_cfg = summarize_web_config()
	local server_cfg = summarize_server_config()

	local cli_dl = parse_state_file("/tmp/vnt2-download-cli.state")
	local web_dl = parse_state_file("/tmp/vnt2-download-web.state")
	local server_dl = parse_state_file("/tmp/vnt2-download-server.state")

	e.cli_running = (cli_pid ~= nil)
	e.web_running = (web_pid ~= nil)
	e.server_running = (server_pid ~= nil)

	e.cli_pid = cli_pid or ""
	e.web_pid = web_pid or ""
	e.server_pid = server_pid or ""

	e.cli_runtime = format_runtime("/tmp/vnt2_cli_time")
	e.web_runtime = format_runtime("/tmp/vnt2_web_time")
	e.server_runtime = format_runtime("/tmp/vnts2_time")

	e.cli_cpu = get_cpu_usage(cli_pid)
	e.cli_ram = get_mem_usage(cli_pid)
	e.web_cpu = get_cpu_usage(web_pid)
	e.web_ram = get_mem_usage(web_pid)
	e.server_cpu = get_cpu_usage(server_pid)
	e.server_ram = get_mem_usage(server_pid)

	e.cli_tag = get_local_tag(get_cli_bin())
	e.web_tag = get_local_tag(get_web_bin())
	e.server_tag = get_local_tag(get_server_bin())

	local latest_tag = get_vnt2_latest_tag(cli_cfg.download_repo, cli_cfg.download_tag)
	if latest_tag == "" then
		latest_tag = get_vnt2_latest_tag(web_cfg.download_repo, web_cfg.download_tag)
	end
	if latest_tag == "" then
		latest_tag = get_vnt2_latest_tag("vnt-dev/vnt", "latest")
	end

	local latest_server_tag = get_vnt2_latest_tag(server_cfg.download_repo, server_cfg.download_tag)
	if latest_server_tag == "" then
		latest_server_tag = get_vnt2_latest_tag("vnt-dev/vnts", "latest")
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
	e.cli_no_tun = cli_cfg.no_tun
	e.cli_no_nat = cli_cfg.no_nat
	e.cli_auto_download = cli_cfg.auto_download
	e.cli_download_repo = cli_cfg.download_repo
	e.cli_download_tag = cli_cfg.download_tag

	e.web_log_level = web_cfg.log_level
	e.web_wan = web_cfg.wan
	e.web_auto_download = web_cfg.auto_download
	e.web_download_repo = web_cfg.download_repo
	e.web_download_tag = web_cfg.download_tag

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
	e.server_white_list = server_cfg.white_list
	e.server_peer_servers = server_cfg.peer_servers
	e.server_custom_net = server_cfg.custom_net
	e.server_open_wan_tcp = server_cfg.open_wan_tcp
	e.server_open_wan_quic = server_cfg.open_wan_quic
	e.server_open_wan_ws = server_cfg.open_wan_ws
	e.server_open_wan_web = server_cfg.open_wan_web
	e.server_conf_file = server_cfg.server_conf_file
	e.server_conf_preview = get_log_content(server_cfg.server_conf_file)

	e.cli_info_preview = e.cli_running and run_ctrl("info") or ""
	e.cli_ips_preview = e.cli_running and run_ctrl("ips") or ""
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
	plain_write(get_log_content("/tmp/vnt2-cli.log"))
end

function clear_client_log()
	clear_log_file("/tmp/vnt2-cli.log")
	json_write({ ok = true })
end

function get_web_log()
	plain_write(get_log_content("/tmp/vnt2-web.log"))
end

function clear_web_log()
	clear_log_file("/tmp/vnt2-web.log")
	json_write({ ok = true })
end

function get_server_log()
	plain_write(get_log_content("/tmp/vnts2.log"))
end

function clear_server_log()
	clear_log_file("/tmp/vnts2.log")
	json_write({ ok = true })
end

function get_download_log()
	plain_write(get_log_content("/tmp/vnt2-download.log"))
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
		cmdline = "错误：程序未运行！请先启动 vnt2_cli。"
	end

	json_write({ cmdline = cmdline })
end

function vnt2_web_cmdline()
	local pid = get_pid_by_path(get_web_bin())
	local cmdline = get_cmdline(pid)

	if cmdline == "" then
		cmdline = "错误：程序未运行！请先启动 vnt2_web。"
	end

	json_write({ cmdline = cmdline })
end

function vnts2_cmdline()
	local pid = get_server_pid()
	local cmdline = get_cmdline(pid)

	if cmdline == "" then
		cmdline = "错误：程序未运行！请先启动 vnts2。"
	end

	json_write({ cmdline = cmdline })
end

function open_web()
	http.redirect(build_web_url())
end
