module("luci.controller.vnt2", package.seeall)

function index()
    -- 主菜单入口
    entry({"admin", "services", "vnt2"}, firstchild(), "VNT2", 50).dependent = false
    -- 子菜单/页面
    entry({"admin", "services", "vnt2", "status"}, template("vnt2/status"), "运行状态", 1)
    entry({"admin", "services", "vnt2", "client"}, cbi("vnt2/client"), "客户端设置", 2)
    entry({"admin", "services", "vnt2", "server"}, cbi("vnt2/server"), "服务端设置", 3)
    entry({"admin", "services", "vnt2", "log_client"}, cbi("vnt2/log_client"), "客户端日志", 4)
    entry({"admin", "services", "vnt2", "log_server"}, cbi("vnt2/log_server"), "服务端日志", 5)
    -- 状态API（给状态页AJAX调用）
    entry({"admin", "services", "vnt2", "api_status"}, call("api_get_status")).leaf = true
    -- 上传/更新程序API
    entry({"admin", "services", "vnt2", "api_upload"}, call("api_upload_bin")).leaf = true
    entry({"admin", "services", "vnt2", "api_update"}, call("api_update_bin")).leaf = true
end

-- 获取运行状态API
function api_get_status()
    local result = {
        client = {
            running = false,
            uptime = "0秒",
            cpu = "0%",
            mem = "0 MB",
            cur_version = "未知",
            latest_version = "未知"
        },
        server = {
            running = false,
            uptime = "0秒",
            cpu = "0%",
            mem = "0 MB",
            cur_version = "未知",
            latest_version = "未知"
        }
    }

    -- 客户端状态
    local cli_pid = luci.sys.exec("pgrep -f vnt2-cli | head -1 | tr -d '\n'")
    if cli_pid ~= "" and nixio.fs.access("/proc/"..cli_pid) then
        result.client.running = true
        -- 运行时长
        local uptime_sec = tonumber(luci.sys.exec("ps -o etimes= -p "..cli_pid.." 2>/dev/null | tr -d ' \n'") or 0)
        if uptime_sec then
            local day = math.floor(uptime_sec / 86400)
            local hour = math.floor((uptime_sec % 86400) / 3600)
            local min = math.floor((uptime_sec % 3600) / 60)
            local sec = uptime_sec % 60
            if day > 0 then
                result.client.uptime = string.format("%d天%d小时%d分%d秒", day, hour, min, sec)
            elseif hour > 0 then
                result.client.uptime = string.format("%d小时%d分%d秒", hour, min, sec)
            elseif min > 0 then
                result.client.uptime = string.format("%d分%d秒", min, sec)
            else
                result.client.uptime = string.format("%d秒", sec)
            end
        end
        -- CPU/内存
        local stat = luci.sys.exec("ps -o %cpu=,rss= -p "..cli_pid.." 2>/dev/null | tr -d '\n'")
        if stat then
            local cpu, rss = stat:match("^%s*(%d+%.?%d*)%s+(%d+)")
            if cpu then result.client.cpu = cpu.."%" end
            if rss then result.client.mem = string.format("%.2f MB", tonumber(rss)/1024) end
        end
        -- 版本号
        result.client.cur_version = luci.sys.exec("/usr/bin/vnt2-cli --version 2>/dev/null | head -1 | awk '{print $2}' | tr -d '\n'")
    end

    -- 服务端状态
    local srv_pid = luci.sys.exec("pgrep -f vnts2 | head -1 | tr -d '\n'")
    if srv_pid ~= "" and nixio.fs.access("/proc/"..srv_pid) then
        result.server.running = true
        -- 运行时长
        local uptime_sec = tonumber(luci.sys.exec("ps -o etimes= -p "..srv_pid.." 2>/dev/null | tr -d ' \n'") or 0)
        if uptime_sec then
            local day = math.floor(uptime_sec / 86400)
            local hour = math.floor((uptime_sec % 86400) / 3600)
            local min = math.floor((uptime_sec % 3600) / 60)
            local sec = uptime_sec % 60
            if day > 0 then
                result.server.uptime = string.format("%d天%d小时%d分%d秒", day, hour, min, sec)
            elseif hour > 0 then
                result.server.uptime = string.format("%d小时%d分%d秒", hour, min, sec)
            elseif min > 0 then
                result.server.uptime = string.format("%d分%d秒", min, sec)
            else
                result.server.uptime = string.format("%d秒", sec)
            end
        end
        -- CPU/内存
        local stat = luci.sys.exec("ps -o %cpu=,rss= -p "..srv_pid.." 2>/dev/null | tr -d '\n'")
        if stat then
            local cpu, rss = stat:match("^%s*(%d+%.?%d*)%s+(%d+)")
            if cpu then result.server.cpu = cpu.."%" end
            if rss then result.server.mem = string.format("%.2f MB", tonumber(rss)/1024) end
        end
        -- 版本号
        result.server.cur_version = luci.sys.exec("/usr/bin/vnts2 --version 2>/dev/null | head -1 | awk '{print $2}' | tr -d '\n'")
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- 上传二进制文件API
function api_upload_bin()
    local util = require "luci.util"
    local http = require "luci.http"
    local nixio = require "nixio"

    local upload_type = http.formvalue("upload_type")
    local file = http.fileupload("bin_file")

    if not file or not file.content then
        http.write_json({success = false, msg = "未获取到上传文件"})
        return
    end

    local save_path
    if upload_type == "client" then
        save_path = "/usr/bin/vnt2-cli"
    elseif upload_type == "server" then
        save_path = "/usr/bin/vnts2"
    else
        http.write_json({success = false, msg = "无效的上传类型"})
        return
    end

    -- 写入文件
    local f = nixio.open(save_path, "w", 755)
    if not f then
        http.write_json({success = false, msg = "无法写入文件，权限不足"})
        return
    end
    f:write(file.content)
    f:close()

    -- 停止服务
    luci.sys.exec("/etc/init.d/vnt2 stop")
    http.write_json({success = true, msg = "上传成功，已覆盖程序文件"})
end

-- 在线更新API
function api_update_bin()
    local http = require "luci.http"
    local update_type = http.formvalue("update_type")
    local version = http.formvalue("version") or ""

    local arch = luci.sys.exec("uname -m | tr -d '\n'")
    local arch_map = {
        ["x86_64"] = "x86_64-unknown-linux-musl",
        ["aarch64"] = "aarch64-unknown-linux-musl",
        ["armv7l"] = "armv7-unknown-linux-musleabi",
        ["armv6l"] = "arm-unknown-linux-musleabi",
        ["mips"] = "mips-unknown-linux-musl",
        ["mipsel"] = "mipsel-unknown-linux-musl",
        ["i686"] = "i686-unknown-linux-musl",
        ["i386"] = "i686-unknown-linux-musl"
    }
    local target_arch = arch_map[arch]
    if not target_arch then
        http.write_json({success = false, msg = "不支持的架构: "..arch})
        return
    end

    local download_url, save_path
    if update_type == "client" then
        save_path = "/usr/bin/vnt2-cli"
        if version == "" then
            -- 获取最新版本
            local latest_tag = luci.sys.exec("curl -s https://api.github.com/repos/vnt-dev/vnt/releases/latest | grep 'tag_name' | awk -F '\"' '{print $4}' | tr -d '\n'")
            if latest_tag == "" then
                http.write_json({success = false, msg = "获取最新版本失败"})
                return
            end
            version = latest_tag:gsub("^v", "")
        end
        download_url = string.format("https://github.com/vnt-dev/vnt/releases/download/v%s/vnt-%s-v%s.tar.gz", version, target_arch, version)
    elseif update_type == "server" then
        save_path = "/usr/bin/vnts2"
        if version == "" then
            local latest_tag = luci.sys.exec("curl -s https://api.github.com/repos/vnt-dev/vnts/releases/latest | grep 'tag_name' | awk -F '\"' '{print $4}' | tr -d '\n'")
            if latest_tag == "" then
                http.write_json({success = false, msg = "获取最新版本失败"})
                return
            end
            version = latest_tag:gsub("^v", "")
        end
        -- 处理i386的特殊版本号
        if arch == "i386" or arch == "i686" then
            download_url = string.format("https://github.com/vnt-dev/vnts/releases/download/%s/vnts-%s-%s.tar.gz", version, target_arch, version)
        else
            download_url = string.format("https://github.com/vnt-dev/vnts/releases/download/v%s/vnts-%s-v%s.tar.gz", version, target_arch, version)
        end
    else
        http.write_json({success = false, msg = "无效的更新类型"})
        return
    end

    -- 下载并解压
    local tmp_dir = "/tmp/vnt2_update"
    luci.sys.exec("rm -rf "..tmp_dir.." && mkdir -p "..tmp_dir)
    local dl_cmd = string.format("wget --no-check-certificate -q -O %s/update.tar.gz '%s' 2>&1", tmp_dir, download_url)
    luci.sys.exec(dl_cmd)
    if not nixio.fs.access(tmp_dir.."/update.tar.gz") then
        http.write_json({success = false, msg = "下载文件失败，请检查网络"})
        return
    end

    -- 解压
    luci.sys.exec("tar -xzf "..tmp_dir.."/update.tar.gz -C "..tmp_dir)
    local bin_name = update_type == "client" and "vnt-cli" or "vnts"
    if not nixio.fs.access(tmp_dir.."/"..bin_name) then
        http.write_json({success = false, msg = "解压失败，未找到二进制文件"})
        return
    end

    -- 替换文件
    luci.sys.exec("cp -f "..tmp_dir.."/"..bin_name.." "..save_path)
    luci.sys.exec("chmod 755 "..save_path)
    luci.sys.exec("rm -rf "..tmp_dir)
    -- 停止服务
    luci.sys.exec("/etc/init.d/vnt2 stop")

    http.write_json({success = true, msg = "更新成功，版本: "..version})
end

-- 清空日志API
function api_clear_log()
    local http = require "luci.http"
    local log_type = http.formvalue("type")
    local log_path

    if log_type == "client" then
        log_path = luci.model.uci.cursor():get("vnt2", "client", "log_path") or "/tmp/vnt2.log"
    elseif log_type == "server" then
        log_path = luci.model.uci.cursor():get("vnt2", "server", "log_path") or "/tmp/vnts2.log"
    else
        http.write_json({success = false, msg = "无效的日志类型"})
        return
    end

    luci.sys.exec("echo '' > "..log_path)
    http.write_json({success = true, msg = "日志已清空"})
end
