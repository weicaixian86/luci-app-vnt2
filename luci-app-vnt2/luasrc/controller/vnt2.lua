module("luci.controller.vnt2", package.seeall)

local uci = require "luci.model.uci".cursor()
local sys = require "luci.sys"
local http = require "luci.http"
local nixio = require "nixio"
local translate = require "luci.i18n".translate

function index()
    if not nixio.fs.access("/usr/bin/vnt2-cli") then return end

    entry({"admin", "vpn", "vnt2"},
        alias("admin", "vpn", "vnt2", "config"),
        translate("VNT2"), 60).dependent = true

    entry({"admin", "vpn", "vnt2", "config"},
        cbi("vnt2_config"),
        translate("Settings"), 10).leaf = true

    entry({"admin", "vpn", "vnt2", "log"},
        cbi("vnt2_log"),
        translate("Client Log"), 20).leaf = true

    entry({"admin", "vpn", "vnt2", "log2"},
        cbi("vnt2_log2"),
        translate("Server Log"), 30).leaf = true

    entry({"admin", "vpn", "vnt2", "action"},
        call("vnt2_action"),
        nil).leaf = true
end

function vnt2_action()
    local action = http.formvalue("action")
    local result = {status = "error", message = translate("Invalid action")}

    if action == "start" then
        sys.call("/etc/init.d/vnt2 start >/dev/null 2>&1")
        result = {status = "success", message = translate("VNT2 started")}
    elseif action == "stop" then
        sys.call("/etc/init.d/vnt2 stop >/dev/null 2>&1")
        result = {status = "success", message = translate("VNT2 stopped")}
    elseif action == "restart" then
        sys.call("/etc/init.d/vnt2 restart >/dev/null 2>&1")
        result = {status = "success", message = translate("VNT2 restarted")}
    elseif action == "status" then
        local cli = sys.call("pgrep vnt2-cli >/dev/null 2>&1") == 0
        local srv = sys.call("pgrep vnts2 >/dev/null 2>&1") == 0
        if cli and srv then
            result = {status = "running", message = translate("Client & Server running")}
        elseif cli then
            result = {status = "running", message = translate("Only client running")}
        elseif srv then
            result = {status = "running", message = translate("Only server running")}
        else
            result = {status = "stopped", message = translate("VNT2 stopped")}
        end
    end

    http.prepare_content("application/json")
    http.write_json(result)
end
