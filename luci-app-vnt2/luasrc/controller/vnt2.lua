module("luci.controller.vnt2", package.seeall)

function index()
    entry({"admin", "network", "vnt2"}, cbi("vnt2"), _("VNT2 Network"), 60).dependent = true
    entry({"admin", "network", "vnt2", "status"}, call("action_status")).leaf = true
    entry({"admin", "network", "vnt2", "log"}, call("action_log")).leaf = true
end

-- 获取VNT运行状态
function action_status()
    local status = {
        running = luci.sys.call("pgrep vnt-cli >/dev/null 2>&1") == 0,
        version = luci.sys.exec("/usr/sbin/vnt-cli --version 2>/dev/null")
    }
    luci.http.prepare_content("application/json")
    luci.http.write_json(status)
end

-- 获取VNT日志
function action_log()
    local log = luci.sys.exec("logread | grep vnt-cli")
    luci.http.write(log)
end
