-- LuCI 控制器：VNT2 隧道服务管理
-- 路径：/luasrc/controller/vnt2.lua
-- 适配 OpenWRT/LEDE LuCI 框架，支持 VNT2 客户端/服务端日志分离、服务启停控制
module("luci.controller.vnt2", package.seeall)

-- 加载依赖库
local uci = require "luci.model.uci".cursor()
local sys = require "luci.sys"
local http = require "luci.http"
local nixio = require "nixio"
local translate = require "luci.i18n".translate

-- 菜单入口初始化（LuCI 页面加载时执行）
function index()
    -- 前置校验：检查 VNT 可执行文件是否存在，避免空菜单
    if not nixio.fs.access("/usr/bin/vnt-cli") or not nixio.fs.access("/usr/bin/vnts") then
        return
    end

    -- 一级菜单：VNT2 Tunnel（归属“服务”分类）
    -- 参数说明：路径、别名、显示名称、排序值（90 表示在服务列表靠后）
    entry({"admin", "services", "vnt2"},
        alias("admin", "services", "vnt2", "config"),
        translate("VNT2 Tunnel"), 90).dependent = true

    -- 子菜单1：基础配置（核心配置页面）
    entry({"admin", "services", "vnt2", "config"},
        cbi("vnt2_config"),                -- 指向配置页面 cbi 文件
        translate("Basic Settings"), 10).leaf = true

    -- 子菜单2：客户端日志（关联 vnt2_log.lua）
    entry({"admin", "services", "vnt2", "log"},
        cbi("vnt2_log"),                   -- 指向客户端日志文件
        translate("Client Log"), 20).leaf = true

    -- 子菜单3：服务端日志（关联 vnt2_log2.lua）
    entry({"admin", "services", "vnt2", "log2"},
        cbi("vnt2_log2"),                  -- 指向服务端日志文件
        translate("Server Log"), 30).leaf = true

    -- 子菜单4：服务控制（启停/重启/状态查询，AJAX 调用）
    entry({"admin", "services", "vnt2", "action"},
        call("vnt2_action"),               -- 指向服务控制函数
        translate("Service Control"), 40).leaf = true
end

-- 核心函数：VNT2 服务控制（启停/重启/状态查询）
function vnt2_action()
    -- 获取前端传递的操作类型（start/stop/restart/status）
    local action = http.formvalue("action")
    -- 初始化返回结果
    local result = {
        status = "error",
        message = translate("Invalid operation type")
    }

    -- 操作逻辑分支
    if action == "start" then
        -- 启动 VNT 服务
        sys.call("/etc/init.d/vnt start >/dev/null 2>&1")
        result = {
            status = "success",
            message = translate("VNT2 service started successfully")
        }
    elseif action == "stop" then
        -- 停止 VNT 服务
        sys.call("/etc/init.d/vnt stop >/dev/null 2>&1")
        result = {
            status = "success",
            message = translate("VNT2 service stopped successfully")
        }
    elseif action == "restart" then
        -- 重启 VNT 服务
        sys.call("/etc/init.d/vnt restart >/dev/null 2>&1")
        result = {
            status = "success",
            message = translate("VNT2 service restarted successfully")
        }
    elseif action == "status" then
        -- 查询服务运行状态（检查 vnt-cli 和 vnts 进程是否存在）
        local cli_running = sys.call("pgrep vnt-cli >/dev/null 2>&1") == 0
        local srv_running = sys.call("pgrep vnts >/dev/null 2>&1") == 0
        
        if cli_running and srv_running then
            result = {
                status = "running",
                message = translate("VNT2 client and server are running")
            }
        elseif cli_running then
            result = {
                status = "partial",
                message = translate("Only VNT2 client is running")
            }
        elseif srv_running then
            result = {
                status = "partial",
                message = translate("Only VNT2 server is running")
            }
        else
            result = {
                status = "stopped",
                message = translate("VNT2 service is stopped")
            }
        end
    end

    -- 返回 JSON 格式结果（供前端 AJAX 调用）
    http.prepare_content("application/json")
    http.write_json(result)
end
