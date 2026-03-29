module("luci.controller.vnt2", package.seeall)

local fs = require "nixio.fs"
local sys = require "luci.sys"
local http = require "luci.http"
local uci = require "luci.model.uci".cursor()

function index()
	if not fs.access("/etc/config/vnt2") then
		return
	end

	entry({ "admin", "vpn", "vnt2" }, alias("admin", "vpn", "vnt2", "config"), _("VNT2"), 45).dependent = true
	entry({ "admin", "vpn", "vnt2", "config" }, cbi("vnt2"), _("基本设置"), 46).leaf = true
	entry({ "admin", "vpn", "vnt2", "client_log" }, cbi("vnt2_log"), _("客户端日志"), 47).leaf = true
	entry({ "admin", "vpn", "vnt2", "web_log" }, cbi("vnt2_web_log"), _("Web 日志"), 48).leaf = true

	entry({ "admin", "vpn", "vnt2", "status" }, call("act_status")).leaf = true
	entry({ "admin", "vpn", "vnt2", "get_client_log" }, call("get_client_log")).leaf = true
	entry({ "admin", "vpn", "vnt2", "clear_client_log" }, call("clear_client_log")).leaf = true
	entry({ "admin", "vpn", "vnt2", "get_web_log" }, call("get_web_log")).leaf = true
	entry({ "admin", "vpn", "vnt2", "clear_web_log" }, call("clear_web_log")).leaf = true

	entry({ "admin", "vpn", "vnt2", "vnt2_info" }, call("vnt2_info")).leaf = true
	entry({ "admin", "vpn", "vnt2", "vnt2_ips" }, call("vnt2_ips")).leaf = true
	entry({ "admin", "vpn", "vnt2", "vnt2_clients" }, call("vnt2_clients")).leaf = true
	entry({ "admin", "vpn", "vnt2", "vnt2_route" }, call("vnt2_route")).leaf = true
	entry({ "admin", "vpn", "vnt2", "vnt2_cmdline" }, call("vnt2_cmdline")).leaf = true
	entry({ "admin", "vpn", "vnt2", "vnt2_web_cmdline" }, call("vnt2_web_cmdline")).leaf = true
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
				if trim(item) ~= "" then
					values[#values + 1] = trim(item)
				end
			end
		elseif type(v) == "string" and trim(v) ~= "" then
			values[#values + 1] = trim(v)
		end
	end)
	return values
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

local function get_ctrl_port()
	return tonumber(uci_first("vnt2_cli", "ctrl_port", "11233")) or 11233
end

local function get_web_port()
	return tonumber(uci_first("vnt2_web", "web_port", "19099")) or 19099
end

local function get_web_host()
	return uci_first("vnt2_web", "web_host", "127.0.0.1")
end

local function file_exists(path)
	return path and path ~= "" and fs.access(path)
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
	local cmd = string.format([[top -bn1 2>/dev/null | awk '$1=="%s" {print $9; exit}']], tostring(pid))
	return trim(sys.exec(cmd))
end

local function get_mem_usage(pid)
	if not pid then
		return ""
	end
	local cmd = string.format([[awk '/VmRSS/ {printf "%.2f MB", $2/1024}' /proc/%s/status 2>/dev/null]], tostring(pid))
	return trim(sys.exec(cmd))
end

local function get_local_tag(bin_path)
	if not file_exists(bin_path) then
		return ""
	end
	local cmd = string.format([[ %s -h 2>&1 | sed -n 's/.*version[: ][[:space:]]*\([^ ,;)]*\).*/\1/p' | head -n1 ]], shell_quote(bin_path))
	return trim(sys.exec(cmd))
end

local function get_cached_latest_tag()
	local cache = "/tmp/vnt2_latest.tag"
	local now = os.time() or 0

	if fs.access(cache) then
		local mtime = fs.stat(cache, "mtime") or 0
		if now > 0 and mtime > 0 and (now - mtime) < 21600 then
			return trim(fs.readfile(cache) or "")
		end
	end

	local cmd = [[curl -fsSL --connect-timeout 4 https://api.github.com/repos/vnt-dev/vnt/releases/latest 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1]]
	local tag = trim(sys.exec(cmd))
	if tag ~= "" then
		fs.writefile(cache, tag)
	end
	return tag
end

local function get_log_content(path)
	return fs.readfile(path) or ""
end

local function parse_help_for_port_mode(bin_path)
	if not file_exists(bin_path) then
		return ""
	end
	local help = sys.exec(string.format("%s -h 2>&1", shell_quote(bin_path))) or ""
	if help:match("%-%-port") then
		return "--port"
	end
	if help:match("%-p, %-%-port") then
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

local function build_web_url()
	local host = get_web_host()
	local port = get_web_port()
	return "http://" .. host .. ":" .. tostring(port) .. "/"
end

local function summarize_cli_config()
	return {
		servers = uci_list("vnt2_cli", "server"),
		network_code = uci_first("vnt2_cli", "network_code", ""),
		device_name = uci_first("vnt2_cli", "device_name", ""),
		tun_name = uci_first("vnt2_cli", "tun_name", "vnt-tun"),
		no_tun = uci_first("vnt2_cli", "no_tun", "0"),
		ctrl_port = get_ctrl_port()
	}
end

function act_status()
	local e = {}
	local cli_pid = get_pid_by_path(get_cli_bin())
	local web_pid = get_pid_by_path(get_web_bin())
	local cli_cfg = summarize_cli_config()

	e.cli_running = (cli_pid ~= nil)
	e.web_running = (web_pid ~= nil)
	e.cli_pid = cli_pid or ""
	e.web_pid = web_pid or ""
	e.cli_runtime = format_runtime("/tmp/vnt2_cli_time")
	e.web_runtime = format_runtime("/tmp/vnt2_web_time")
	e.cli_cpu = get_cpu_usage(cli_pid)
	e.cli_ram = get_mem_usage(cli_pid)
	e.web_cpu = get_cpu_usage(web_pid)
	e.web_ram = get_mem_usage(web_pid)
	e.cli_tag = get_local_tag(get_cli_bin())
	e.web_tag = get_local_tag(get_web_bin())
	e.latest_tag = get_cached_latest_tag()
	e.ctrl_port = get_ctrl_port()
	e.web_host = get_web_host()
	e.web_port = get_web_port()
	e.web_url = build_web_url()
	e.cli_servers = cli_cfg.servers
	e.cli_network_code = cli_cfg.network_code
	e.cli_device_name = cli_cfg.device_name
	e.cli_tun_name = cli_cfg.tun_name
	e.cli_no_tun = cli_cfg.no_tun
	e.cli_info_preview = e.cli_running and run_ctrl("info") or ""

	json_write(e)
end

function get_client_log()
	plain_write(get_log_content("/tmp/vnt2-cli.log"))
end

function clear_client_log()
	sys.call("rm -f /tmp/vnt2-cli*.log >/dev/null 2>&1")
	json_write({ ok = true })
end

function get_web_log()
	plain_write(get_log_content("/tmp/vnt2-web.log"))
end

function clear_web_log()
	sys.call("rm -f /tmp/vnt2-web*.log >/dev/null 2>&1")
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

function open_web()
	http.redirect(build_web_url())
end
