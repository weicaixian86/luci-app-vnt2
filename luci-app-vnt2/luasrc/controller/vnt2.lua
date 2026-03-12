-- LuCI 控制器：VNT2 服务管理
-- 路径：/luasrc/controller/vnt2.lua
module("luci.controller.vnt2", package.seeall)

-- 加载依赖库
local uci = require "luci.model.uci".cursor()
local sys = require "luci.sys"
local http = require "luci.http"

-- 定义菜单入口（页面加载时执行）
function index()
    -- 检查是否安装 VNT 可执行文件（避免菜单空显示）
    if not nixio.fs.access("/usr/bin/vnt-cli") or not nixio.fs.access("/usr/bin/vnts") then
        return
    end

    -- 添加一级菜单（服务分类下）
    entry({"admin", "services", "vnt2"},
        alias("admin", "services", "vnt2", "config"),
        _("VNT2 Tunnel"), 90).dependent = true

    -- 子菜单1：VNT2 主配置页面
    entry({"admin", "services", "vnt2", "config"},
        cbi("vnt2_config"),  -- 指向配置页面的CBI文件（vnt2_config.lua）
        _("Basic Settings"), 10).leaf = true

    -- 子菜单2：VNT2 日志查看页面（关联你重命名的vnt2_log.lua）
    entry({"admin", "services", "vnt2", "log"},
        cbi("vnt2_log"),     -- 指向日志页面的CBI文件（vnt2_log.lua）
        _("Log View"), 20).leaf = true

    -- 子菜单3：VNT2 服务控制（启停/重启，无独立页面，通过AJAX调用）
    entry({"admin", "services", "vnt2", "action"},
        call("vnt2_action"),
        _("Service Control"), 30).leaf = true
end

-- 定义服务控制逻辑（启停/重启VNT2服务）
function vnt2_action()
    local action = http.formvalue("action")
    local result = {status = "error", message = "Invalid action"}

    -- 验证操作类型
    if action == "start" then
        sys.call("/etc/init.d/vnt start >/dev/null 2>&1")
        result = {status = "success", message = "VNT2 service started"}
    elseif action == "stop" then
        sys.call("/etc/init.d/vnt stop >/dev/null 2>&1")
        result = {status = "success", message = "VNT2 service stopped"}
    elseif action == "restart" then
        sys.call("/etc/init.d/vnt restart >/dev/null 2>&1")
        result = {status = "success", message = "VNT2 service restarted"}
    elseif action == "status" then
        -- 获取服务运行状态
        local status = sys.call("pgrep vnt-cli >/dev/null 2>&1 && pgrep vnts >/dev/null 2>&1")
        if status == 0 then
            result = {status = "running", message = "VNT2 service is running"}
        else
            result = {status = "stopped", message = "VNT2 service is stopped"}
        end
    end

    -- 返回JSON格式结果（供前端AJAX调用）
    http.prepare_content("application/json")
    http.write_json(result)
end
