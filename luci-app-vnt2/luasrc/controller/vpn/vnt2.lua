module("luci.controller.vpn.vnt2", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/vnt2") then
        return
    end

    entry({"admin", "vpn", "vnt2"}, cbi("vnt2/vnt"), _("VNT2 异地组网"), 60).dependent = true
    -- 新增 V2 状态接口
    entry({"admin", "vpn", "vnt2", "status"}, call("action_status")).leaf = true
end

function action_status()
    local e = {}
    local uci = require "luci.model.uci".cursor()
    
    -- 读取 V2 配置（关键：vnt2）
    local vnts_web = uci:get("vnt2", "vnts", "web") or 0
    local vnts_port = uci:get("vnt2", "vnts", "web_port") or 29870

    -- 获取 vnt-cli 运行状态（V2）
    e.crunning = luci.sys.call("pgrep -f 'vnt-cli -c /etc/config/vnt2' >/dev/null") == 0
    -- 获取 vnts 运行状态（V2）
    e.srunning = luci.sys.call("pgrep -f 'vnts -c /etc/config/vnt2' >/dev/null") == 0
    
    -- 填充其他状态数据（运行时长、CPU/内存占用、版本等，逻辑与 V1 一致）
    if e.crunning then
        e.vntsta = luci.sys.exec("ps -o etimes= -p $(pgrep -f 'vnt-cli -c /etc/config/vnt2') | awk '{print int($1/3600)\"小时\"int($1%3600/60)\"分钟\"$1%60\"秒\"}'") or "未知"
        e.vntcpu = luci.sys.exec("ps -o pcpu= -p $(pgrep -f 'vnt-cli -c /etc/config/vnt2') | awk '{print $1\"%\"}'") or "0%"
        e.vntram = luci.sys.exec("ps -o rss= -p $(pgrep -f 'vnt-cli -c /etc/config/vnt2') | awk '{print int($1/1024)\"MB\"}'") or "0MB"
        e.vnttag = luci.sys.exec("/usr/bin/vnt-cli --version 2>/dev/null | grep -o 'v[0-9.]*'") or "未知"
        e.vntnewtag = luci.sys.exec("wget -q -O - https://api.github.com/repos/vnt-dev/vnt/releases/latest | grep -o '\"tag_name\":\"v[0-9.]*\"' | cut -d'\"' -f4") or "未知"
    end
    
    if e.srunning then
        e.vntsta2 = luci.sys.exec("ps -o etimes= -p $(pgrep -f 'vnts -c /etc/config/vnt2') | awk '{print int($1/3600)\"小时\"int($1%3600/60)\"分钟\"$1%60\"秒\"}'") or "未知"
        e.vntscpu = luci.sys.exec("ps -o pcpu= -p $(pgrep -f 'vnts -c /etc/config/vnt2') | awk '{print $1\"%\"}'") or "0%"
        e.vntsram = luci.sys.exec("ps -o rss= -p $(pgrep -f 'vnts -c /etc/config/vnt2') | awk '{print int($1/1024)\"MB\"}'") or "0MB"
        e.vntstag = luci.sys.exec("/usr/bin/vnts --version 2>/dev/null | grep -o 'v[0-9.]*'") or "未知"
        e.vntsnewtag = luci.sys.exec("wget -q -O - https://api.github.com/repos/vnt-dev/vnts/releases/latest | grep -o '\"tag_name\":\"v[0-9.]*\"' | cut -d'\"' -f4") or "未知"
        e.web = vnts_web
        e.port = vnts_port
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json(e)
end
