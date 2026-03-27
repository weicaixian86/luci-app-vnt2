module("luci.controller.vnt2", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/vnt2") then
		return
	end
	
 entry({"admin", "vpn", "vnt2"}, alias("admin", "vpn", "vnt2", "vnt2"),_("VNT2"), 44).dependent = true
	entry({"admin", "vpn", "vnt2", "vnt2"}, cbi("vnt2"),_("VNT2"), 45).leaf = true
	entry({"admin", "vpn", "vnt2", "vnt2_log"}, form("vnt2_log"),_("客户端日志"), 46).leaf = true
	entry({"admin", "vpn", "vnt2", "get_log"}, call("get_log")).leaf = true
	entry({"admin", "vpn", "vnt2", "clear_log"}, call("clear_log")).leaf = true
	entry({"admin", "vpn", "vnt2", "status"}, call("act_status")).leaf = true
	entry({"admin", "vpn", "vnt2", "vnt2_info"}, call("vnt2_info")).leaf = true
    entry({"admin", "vpn", "vnt2", "vnt2_all"}, call("vnt2_all")).leaf = true
    entry({"admin", "vpn", "vnt2", "vnt2_list"}, call("vnt2_list")).leaf = true
    entry({"admin", "vpn", "vnt2", "vnt2_route"}, call("vnt2_route")).leaf = true
    entry({"admin", "vpn", "vnt2", "vnt2_cmd"}, call("vnt2_cmd")).leaf = true
end

function act_status()
	local e = {}
	local sys  = require "luci.sys"
	local uci  = require "luci.model.uci".cursor()
	e.crunning = luci.sys.call("pgrep vnt2_cli >/dev/null") == 0
	e.srunning = luci.sys.call("pgrep vnt2_web >/dev/null") == 0
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
    local command2 = io.popen('test ! -z "`pidof vnt2_cli`" && (top -b -n1 | grep -E "$(pidof vnt2_cli)" 2>/dev/null | grep -v grep | awk \'{for (i=1;i<=NF;i++) {if ($i ~ /vnt2_cli/) break; else cpu=i}} END {print $cpu}\')')
	e.vnt2cpu = command2:read("*all")
	command2:close()
    local command3 = io.popen("test ! -z `pidof vnt2_cli` && (cat /proc/$(pidof vnt2_cli | awk '{print $NF}')/status | grep -w VmRSS | awk '{printf \"%.2f MB\", $2/1024}')")
	e.vnt2ram = command3:read("*all")
	command3:close()
    local command4 = io.popen("([ -s /tmp/vnt2.tag ] && cat /tmp/vnt2.tag ) || (echo `$(uci -q get vnt2.@vnt2_cli[0].clibin) -h 2>&1 | grep -i version | head -1 | awk '{print $1,$2}'` > /tmp/vnt2.tag && cat /tmp/vnt2.tag)")
	e.vnt2tag = command4:read("*all")
	command4:close()
    local command5 = io.popen("([ -s /tmp/vnt2new.tag ] && cat /tmp/vnt2new.tag ) || ( curl -L -k -s --connect-timeout 3 --user-agent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36' https://api.github.com/repos/vnt-2/vnt-2/releases/latest | grep tag_name | sed 's/[^0-9.]*//g' >/tmp/vnt2new.tag && cat /tmp/vnt2new.tag )")
	e.vnt2newtag = command5:read("*all")
	command5:close()

	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end

function get_log()
    local log = ""
    local files = {"/tmp/vnt2_cli.log"}
    for i, file in ipairs(files) do
        if luci.sys.call("[ -f '" .. file .. "' ]") == 0 then
            log = log .. luci.sys.exec("cat " .. file)
        end
    end
    luci.http.write(log)
end

function clear_log()
	luci.sys.call("rm -rf /tmp/vnt2_cli*.log")
end

function vnt2_info()
  os.execute("rm -rf /tmp/vnt2_cli_info")
  local info = luci.sys.exec("$(uci -q get vnt2.@vnt2_cli[0].clibin) info 2>&1")
  info = info:gsub("Connection status", "连接状态")
  info = info:gsub("Virtual ip", "虚拟IP")
  info = info:gsub("Virtual gateway", "虚拟网关")
  info = info:gsub("Virtual netmask", "虚拟网络掩码")
  info = info:gsub("NAT type", "NAT类型")
  info = info:gsub("Relay server", "服务器地址")
  info = info:gsub("Public ips", "外网IP")
  info = info:gsub("Local addr", "WAN口IP")

  luci.http.prepare_content("application/json")
  luci.http.write_json({ info = info })
end

function vnt2_all()
  os.execute("rm -rf /tmp/vnt2_cli_all")
  local all = luci.sys.exec("$(uci -q get vnt2.@vnt2_cli[0].clibin) list 2>&1")
  all = all:gsub("Virtual Ip", "虚拟IP")
  all = all:gsub("NAT Type", "NAT类型")
  all = all:gsub("Public Ips", "外网IP")
  all = all:gsub("Local Ip", "WAN口IP")
  local rows = {} 
  for line in all:gmatch("[^\r\n]+") do
    local cols = {} 
    for col in line:gmatch("%S+") do
      table.insert(cols, col)
    end
    table.insert(rows, cols) 
  end

 local html_table = "<table>"
for i, row in ipairs(rows) do
  html_table = html_table .. "<tr>"
  for j, col in ipairs(row) do
 
    local colors = {"#FFA500", "#800000", "#00BFFF", "#3CB371", "#DAA520", "#48D1CC", "#66CC00", "#2F4F4F"}
    local color = colors[(j % 8) + 1] 
    html_table = html_table .. "<td><font color='" .. color .. "'>" .. col .. "</font></td>"
  end
  html_table = html_table .. "</tr>"
end
html_all = html_table .. "</table>"

  luci.http.prepare_content("application/json")
  luci.http.write_json({ all = html_all })
end

function vnt2_route()
 os.execute("rm -rf /tmp/vnt2_cli_route")
  local route = luci.sys.exec("$(uci -q get vnt2.@vnt2_cli[0].clibin) route 2>&1")
  route = route:gsub("Next Hop", "下一跳地址")
  route = route:gsub("Interface", "连接地址")
  local rows = {} 
  for line in route:gmatch("[^\r\n]+") do
    local cols = {} 
    for col in line:gmatch("%S+") do
      table.insert(cols, col)
    end
    table.insert(rows, cols) 
  end

 local html_table = "<table>"
for i, row in ipairs(rows) do
  html_table = html_table .. "<tr>"
  for j, col in ipairs(row) do
 
    local colors = {"#FFA500", "#800000", "#00BFFF", "#3CB371", "#DAA520"} 
    local color = colors[(j % 5) + 1] 
    html_table = html_table .. "<td><font color='" .. color .. "'>" .. col .. "</font></td>"
  end
  html_table = html_table .. "</tr>"
end
html_route = html_table .. "</table>"

  luci.http.prepare_content("application/json")
  luci.http.write_json({ route = html_route })
end

function vnt2_list()
 os.execute("rm -rf /tmp/vnt2_cli_list")
  local list = luci.sys.exec("$(uci -q get vnt2.@vnt2_cli[0].clibin) list 2>&1")
  list = list:gsub("Virtual Ip", "虚拟IP")
  local rows = {} 
  for line in list:gmatch("[^\r\n]+") do
    local cols = {} 
    for col in line:gmatch("%S+") do
      table.insert(cols, col)
    end
    table.insert(rows, cols) 
  end

 local html_table = "<table>"
for i, row in ipairs(rows) do
  html_table = html_table .. "<tr>"
  for j, col in ipairs(row) do
 
    local colors = {"#FFA500", "#800000", "#00BFFF", "#3CB371", "#DAA520"} 
    local color = colors[(j % 5) + 1] 
    html_table = html_table .. "<td><font color='" .. color .. "'>" .. col .. "</font></td>"
  end
  html_table = html_table .. "</tr>"
end
html_table = html_table .. "</table>"

  luci.http.prepare_content("application/json")
  luci.http.write_json({ list = html_table })
end

function vnt2_cmd()
  os.execute("rm -rf /tmp/vnt2*_cmd")
  local html_cmd= luci.sys.exec("echo $(cat /proc/$(pidof vnt2_cli)/cmdline | tr '\\0' ' ') 2>&1")
  html_cmd = html_cmd:gsub("--server", "服务器")
  html_cmd = html_cmd:gsub("--network-code", "网络编号")
  html_cmd = html_cmd:gsub("--ip", "虚拟IP")
  html_cmd = html_cmd:gsub("--password", "密码")
  html_cmd = html_cmd:gsub("--rtx", "QUIC优化")
  html_cmd = html_cmd:gsub("--compress", "压缩")
  html_cmd = html_cmd:gsub("--fec", "FEC纠错")
  html_cmd = html_cmd:gsub("--no-punch", "禁用打洞")
  html_cmd = html_cmd:gsub("--no-nat", "禁用NAT")
  html_cmd = html_cmd:gsub("--no-tun", "禁用TUN")
  html_cmd = html_cmd:gsub("--mtu", "MTU")
  html_cmd = html_cmd:gsub("--tun-name", "网卡名")
  html_cmd = html_cmd:gsub("--device-name", "设备名")
  html_cmd = html_cmd:gsub("--device-id", "设备ID")
  html_cmd = html_cmd:gsub("--ctrl-port", "控制端口")
  html_cmd = html_cmd:gsub("--tunnel-port", "隧道端口")
  html_cmd = html_cmd:gsub("--cert-mode", "证书模式")
  luci.http.prepare_content("application/json")
  luci.http.write_json({ cmd = html_cmd })
end
