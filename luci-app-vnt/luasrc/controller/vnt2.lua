module("luci.controller.vnt2", package.seeall)

function index()
    if not nixio.fs.access("/usr/bin/vnt2") then
        return
    end

    entry({"admin", "network", "vnt2"}, cbi("vnt2"), _("VNT2 Virtual Network Tunnel"), 60).dependent = true
    entry({"admin", "network", "vnt2", "status"}, call("action_status")).leaf = true
end

function action_status()
    local status = {
        running = false,
        pid = 0,
        log = ""
    }

    local pid = luci.sys.exec("pidof vnt2")
    if pid and pid ~= "" then
        status.running = true
        status.pid = pid
    end

    if nixio.fs.access("/var/log/vnt2.log") then
        status.log = luci.sys.exec("tail -20 /var/log/vnt2.log")
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json(status)
end
