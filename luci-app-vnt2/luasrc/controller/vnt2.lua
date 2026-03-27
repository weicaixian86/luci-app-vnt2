
module("luci.controller.vnt2", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/vnt2") then
		return
	end

	entry({"admin", "vpn", "vnt2"}, alias("admin", "vpn", "vnt2", "vnt2"),_("VNT2"), 45).dependent = true
	entry({"admin", "vpn", "vnt2", "vnt2"}, cbi("vnt2"),_("VNT2设置"), 46).leaf = true
	entry({"admin", "vpn", "vnt2", "vnt2_log"}, form("vnt2_log"),_("客户端日志"), 47).leaf = true
	entry({"admin", "vpn", "vnt2", "get_log"}, call("get_log")).leaf = true
entry({"admin", "vpn", "vnt2", "clear_log"}, call("clear_log")).leaf = true
	entry({"admin", "vpn", "vnt2", "vnts2_log"}, form("vnt2/vnts2_log"),_("服务端日志"), 48).leaf = true
	entry({"admin", "vpn", "vnt2", "get_vnts2_log"}, call("get_vnts2_log")).leaf = true
	entry({"admin", "vpn", "vnt2", "clear_vnts2_log"}, call("clear_vnts2_log")).leaf = true
	entry({"admin", "vpn", "vnt2", "status"}, call("act_status")).leaf = true
	entry({"admin", "vpn", "vnt2", "vnt2_info"}, call("vnt2_info")).leaf = true
	entry({"admin", "vpn", "vnt2", "vnt2_ips"}, call("vnt2_ips")).leaf = true
	entry({"admin", "vpn", "vnt2", "vnt2_clients"}, call("vnt2_clients")).leaf = true
	entry({"admin", "vpn", "vnt2", "vnt2_route"}, call("vnt2_route")).leaf = true
end

function act_status()
	local e = {}
	local uci  = require "luci.model.uci".cursor()
	local ctrl_port = tonumber(uci:get_first("vnt2", "vnt2_cli", "ctrl_port"))
	e.ctrl_port = (ctrl_port or 11233)
	e.crunning = luci.sys.call("pgrep vnt2-cli >/dev/null") == 0
	e.vnts2running = luci.sys.call("pgrep vnts2 >/dev/null") == 0

	local tagfile = io.open("/tmp/vnt2_time", "r")
	if tagfile then
		local tagcontent = tagfile:read("*all")
		tagfile:close()
		if tagcontent and tagcontent ~= "" then
			os.execute("start_time=$(cat /tmp/vnt2_time) && time=$(($(date +%s)-start_time)) && day=$((time/86400)) && [ $day -eq 0 ] && day='' || day=${day}天 && time=$(date -u -d @${time} +'%H小时%M分%S秒') && echo $day $time > /tmp/command_vnt2 2>&1")
			local command_output_file = io.open("/tmp/command_vnt2", "r")
			if command_output_file then
				e.vnt2sta = command_output_file:read("*all")
				command_output_file:close()
			end
		end
	end

	local command2 = io.popen('test ! -z "`pidof vnt2-cli`" && (top -b -n1 | grep -E "$(pidof vnt2-cli)" 2>/dev/null | grep -v grep | awk '{for (i=1;i<=NF;i++) {if ($i ~ /vnt2-cli/) break; else cpu=i}} END {print $cpu}')')
	e.vnt2cpu = command2:read("*all")
	command2:close()

	local command3 = io.popen("test ! -z `pidof vnt2-cli` && (cat /proc/$(pidof vnt2-cli | awk '{print $NF}')/status | grep -w VmRSS | awk '{printf "%.2f MB", $2/1024}')")
	e.vnt2ram = command3:read("*all")
	command3:close()

	local command4 = io.popen("([ -s /tmp/vnt2.tag ] && cat /tmp/vnt2.tag ) || ( echo `$(uci -q get vnt2.@vnt2_cli[0].vnt2_cli_bin) -h |grep 'version'| awk -F 'version:' '{print $2}'` > /tmp/vnt2.tag && cat /tmp/vnt2.tag )")
	e.vnt2tag = command4:read("*all")
	command4:close()

local command5 = io.popen("([ -s /tmp/vnt2new.tag ] && cat /tmp/vnt2new.tag ) || ( curl -L -k -s --connect-timeout 3 --user-agent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36' https://api.github.com/repos/vnt-dev/vnt/releases/latest | grep tag_name | sed 's/[^0-9.]*//g' >/tmp/vnt2new.tag && cat /tmp/vnt2new.tag )")
	e.vnt2newtag = command5:read("*all")
	command5:close()

	-- vnts2状态
	local tagfile2 = io.open("/tmp/vnts2_time", "r")
	if tagfile2 then
		local tagcontent2 = tagfile2:read("*all")
		tagfile2:close()
		if tagcontent2 and tagcontent2 ~= "" then
			os.execute("start_time=$(cat /tmp/vnts2_time) && time=$(($(date +%s)-start_time)) && day=$((time/86400)) && [ $day -eq 0 ] && day='' || day=${day}天 && time=$(date -u -d @${time} +'%H小时%M分%S秒') && echo $day $time > /tmp/command_vnts2 2>&1")
			local command_output_file2 = io.open("/tmp/command_vnts2", "r")
			if command_output_file2 then
				e.vnts2sta = command_output_file2:read("*all")
				command_output_file2:close()
			end
		end
	end

	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end

function get_log()
    local log = ""
    local files = {"/tmp/vnt2-cli.log"}
    for i, file in ipairs(files) do
        if luci.sys.call("[ -f '" .. file .. "' ]") == 0 then
            log = log .. luci.sys.exec("cat " .. file)
        end
    end
    luci.http.write(log)
end

function clear_log()
	luci.sys.call("rm -rf /tmp/vnt2-cli*.log")
end

function get_vnts2_log()
    local log = ""
    local files = {"/tmp/vnts2.log"}
    for i, file in ipairs(files) do
        if luci.sys.call("[ -f '" .. file .. "' ]") == 0 then
            log = log .. luci.sys.exec("cat " .. file)
        end
    end
    luci.http.write(log)
end

function clear_vnts2_log()
	luci.sys.call("rm -rf /tmp/vnts2*.log")
end

function vnt2_info()
	local uci  = require "luci.model.uci".cursor()
	local ctrl_port = tonumber(uci:get_first("vnt2", "vnt2_cli", "ctrl_port")) or 11233
	local vnt2_cli_bin = uci:get_first("vnt2", "vnt2_cli", "vnt2_cli_bin") or "/usr/bin/vnt2_cli"
	local info = luci.sys.exec(vnt2_cli_bin .. " info --port " .. ctrl_port .. " 2>&1")

	luci.http.prepare_content("application/json")
	luci.http.write_json({ info = info })
end

function vnt2_ips()
	local uci  = require "luci.model.uci".cursor()
	local ctrl_port = tonumber(uci:get_first("vnt2", "vnt2_cli", "ctrl_port")) or 11233
	local vnt2_cli_bin = uci:get_first("vnt2", "vnt2_cli", "vnt2_cli_bin") or "/usr/bin/vnt2_cli"
	local ips = luci.sys.exec(vnt2_cli_bin .. " ips --port " .. ctrl_port .. " 2>&1")

	luci.http.prepare_content("application/json")
	luci.http.write_json({ ips = ips })
end

function vnt2_clients()
	local uci  = require "luci.model.uci".cursor()
	local ctrl_port = tonumber(uci:get_first("vnt2", "vnt2_cli", "ctrl_port")) or 11233
	local vnt2_cli_bin = uci:get_first("vnt2", "vnt2_cli", "vnt2_cli_bin") or "/usr/bin/vnt2_cli"
	local clients = luci.sys.exec(vnt2_cli_bin .. " clients --port " .. ctrl_port .. " 2>&1")

	luci.http.prepare_content("application/json")
	luci.http.write_json({ clients = clients })
end

function vnt2_route()
	local uci  = require "luci.model.uci".cursor()
	local ctrl_port = tonumber(uci:get_first("vnt2", "vnt2_cli", "ctrl_port")) or 11233
	local vnt2_cli_bin = uci:get_first("vnt2", "vnt2_cli", "vnt2_cli_bin") or "/usr/bin/vnt2_cli"
	local route = luci.sys.exec(vnt2_cli_bin .. " route --port " .. ctrl_port .. " 2>&1")

	luci.http.prepare_content("application/json")
	luci.http.write_json({ route = route })
end
