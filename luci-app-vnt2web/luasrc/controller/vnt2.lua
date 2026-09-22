module("luci.controller.vnt2", package.seeall)

local fs = require "nixio.fs"
local sys = require "luci.sys"
local http = require "luci.http"
local uci = require "luci.model.uci".cursor()
local toml = require "luci.model.vnt2_toml"
local textutil = require "luci.model.vnt2_text"
local LOG_DISPLAY_LINES = 300
local VERSION_CHECK_PENDING_FILE = "/tmp/vnt2-version-check.pending"
local VERSION_STATE_FILE = "/etc/config/vnt2-web.version"

function index()
	if not fs.access("/etc/config/vnt2") and not fs.access(toml.TOML_FILE) then
		return
	end

	toml.ensure_toml_file(uci)

	entry({ "admin", "vpn", "vnt2" }, alias("admin", "vpn", "vnt2", "config"), _("VNT2"), 45).dependent = true
	entry({ "admin", "vpn", "vnt2", "config" }, cbi("vnt2"), _("基本设置"), 10).leaf = true
	entry({ "admin", "vpn", "vnt2", "web_log" }, cbi("vnt2_web_log"), _("Web 日志"), 30).leaf = true
	entry({ "admin", "vpn", "vnt2", "download_log" }, cbi("vnt2_download_log"), _("下载日志"), 50).leaf = true

	entry({ "admin", "vpn", "vnt2", "status" }, call("act_status")).leaf = true
	entry({ "admin", "vpn", "vnt2", "check_latest" }, call("act_check_latest")).leaf = true
	entry({ "admin", "vpn", "vnt2", "get_web_log" }, call("get_web_log")).leaf = true
	entry({ "admin", "vpn", "vnt2", "clear_web_log" }, call("clear_web_log")).leaf = true
	entry({ "admin", "vpn", "vnt2", "get_download_log" }, call("get_download_log")).leaf = true
	entry({ "admin", "vpn", "vnt2", "clear_download_log" }, call("clear_download_log")).leaf = true

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



local function get_web_bin()
	return uci_first("vnt2_web", "vnt2_web_bin", "/usr/bin/vnt2_web")
end



local function get_web_port()
	return tonumber(uci_first("vnt2_web", "web_port", "19099")) or 19099
end

local function get_web_host()
	return uci_first("vnt2_web", "web_host", "0.0.0.0")
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


local function get_web_pid()
	return get_pid_by_path(get_web_bin())
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

local CLK_TCK = get_clk_tck()
local PAGE_SIZE = get_page_size()
local CPU_COUNT = get_cpu_count()

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

	local elapsed = uptime - (starttime / CLK_TCK)
	if elapsed <= 0 then
		return "0.00%"
	end

	local total = (utime + stime) / CLK_TCK
	local cpu = (total / elapsed) * 100
	if CPU_COUNT > 1 then
		cpu = cpu / CPU_COUNT
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
			rss_kb = (rss_pages * PAGE_SIZE) / 1024
		end
	end

	if not rss_kb then
		return ""
	end

	return string.format("%.2f MB", rss_kb / 1024)
end

local function parse_version_state(path)
	local out = {
		tag = "",
		source = "",
		arch = "",
		asset = "",
		mtime = "",
		size = "",
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

local function stat_value_matches(actual, expected)
	expected = trim(expected)
	if expected == "" then
		return true
	end

	local value = tonumber(actual)
	return value ~= nil and string.format("%.0f", value) == expected
end

local function get_local_tag(bin_path)
	if not file_exists(bin_path) then
		return ""
	end

	local state = parse_version_state(VERSION_STATE_FILE)
	if state.tag == "" or state.path == "" or state.path ~= bin_path then
		return ""
	end

	local stat = fs.stat(bin_path)
	if not stat or stat.type ~= "reg" then
		return ""
	end
	if not stat_value_matches(stat.size, state.size)
		or not stat_value_matches(stat.mtime, state.mtime) then
		return ""
	end

	return state.tag:gsub("^[vV]", "")
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

local function get_cached_latest_tag(repo, mirror, custom_mirror_url)
	repo = trim(repo)
	if repo == "" then
		repo = "vnt-dev/vnt"
	end

	local strategy = normalize_download_mirror(mirror)
	local canonical_key = strategy .. "_" .. repo
	if strategy == "custom" then
		canonical_key = canonical_key .. "_" .. normalize_custom_mirror_url(custom_mirror_url)
	end
	local canonical_cache = "/tmp/vnt2_latest_v3_" .. sanitize_cache_name(canonical_key) .. ".tag"
	if fs.access(canonical_cache) then
		local cached = trim(fs.readfile(canonical_cache) or "")
		if cached ~= "" then
			return cached
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

local function get_vnt2_latest_tag(repo, mirror, custom_mirror_url)
	repo = trim(repo)

	if repo == "" then
		repo = "vnt-dev/vnt"
	end

	local latest = normalize_display_tag(get_cached_latest_tag(repo, mirror, custom_mirror_url))
	if latest ~= "" then
		return latest
	end

	return ""
end

function act_check_latest()
	local stat = fs.readfile("/proc/self/stat") or ""
	local pid = stat:match("^(%d+)") or tostring(os.time())
	local temp = string.format("%s.%s", VERSION_CHECK_PENDING_FILE, pid)
	local value = tostring(os.time()) .. "\n"
	local ok = fs.writefile(temp, value)

	if ok then
		ok = os.rename(temp, VERSION_CHECK_PENDING_FILE) and true or false
	end
	if not ok then
		fs.remove(temp)
	end

	json_write({ ok = ok and true or false })
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


function act_status()
	local e = {}
	local web_enabled = uci_first("vnt2_web", "enabled", "0") == "1"

	local web_pid = get_web_pid()
	local web_cfg = summarize_web_config()
	local web_dl = parse_state_file("/tmp/vnt2-download-web.state")

	-- This endpoint is polled every five seconds. Keep it local-only so an
	-- unavailable process cannot hold the LuCI request open during apply.
	e.web_running = web_enabled and web_pid ~= nil
	e.web_pid = e.web_running and web_pid or ""
	e.web_runtime = format_runtime("/tmp/vnt2_web_time")
	e.web_cpu = get_cpu_usage(web_pid)
	e.web_ram = get_mem_usage(web_pid)

	-- Never execute managed binaries from this polling endpoint. A broken or
	-- blocked binary must not delay LuCI while an apply-triggered restart runs.
	e.web_tag = get_local_tag(get_web_bin())
	e.latest_web_tag = get_vnt2_latest_tag(web_cfg.download_repo, web_cfg.download_mirror, web_cfg.custom_download_mirror)

	e.web_host = get_web_host()
	e.web_port = get_web_port()
	e.web_url = build_web_url()

	e.web_log_level = web_cfg.log_level
	e.web_wan = web_cfg.wan
	e.web_auto_download = web_cfg.auto_download
	e.web_download_repo = web_cfg.download_repo
	e.web_download_tag = web_cfg.download_tag
	e.web_download_mirror = web_cfg.download_mirror
	e.web_custom_download_mirror = web_cfg.custom_download_mirror

	e.download_log_size = #(get_log_content("/tmp/vnt2-download.log") or "")
	e.web_download = web_dl

	json_write(e)
end

local function clear_log_file(path)
	if not path or path == "" then
		return
	end
	fs.writefile(path, "")
end



function get_web_log()
	plain_write(get_log_content("/tmp/vnt2-web.log", LOG_DISPLAY_LINES))
end

function clear_web_log()
	clear_log_file("/tmp/vnt2-web.log")
	json_write({ ok = true })
end



function get_download_log()
	plain_write(get_log_content("/tmp/vnt2-download.log", LOG_DISPLAY_LINES))
end

function clear_download_log()
	clear_log_file("/tmp/vnt2-download.log")
	fs.remove("/tmp/vnt2-download-web.state")
	json_write({ ok = true })
end






function vnt2_web_cmdline()
	local pid = get_pid_by_path(get_web_bin())
	local cmdline = get_cmdline(pid)

	if cmdline == "" then
		cmdline = "错误：vnt2_web 未运行。"
	end

	json_write({ cmdline = cmdline })
end


function open_web()
	http.redirect(build_web_url())
end
