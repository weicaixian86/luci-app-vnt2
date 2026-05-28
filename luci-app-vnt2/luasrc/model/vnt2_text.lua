local fs = require "nixio.fs"
local sys = require "luci.sys"
local util = require "luci.util"

local M = {}
local tail_available = sys.call("command -v tail >/dev/null 2>&1") == 0

local mojibake_markers = {
	string.char(233, 150, 186, 63),
	string.char(233, 151, 129, 63),
	string.char(230, 191, 160, 63),
	string.char(230, 191, 158, 63),
	string.char(230, 191, 161, 63),
	string.char(233, 151, 130, 63),
	string.char(233, 150, 187, 63),
	string.char(231, 188, 130, 63),
	string.char(233, 150, 184, 63),
	string.char(231, 128, 185, 63),
	string.char(229, 169, 181, 63),
	string.char(233, 144, 160, 63),
	string.char(231, 188, 129, 63)
}

local function iconv_available()
	return sys.call("command -v iconv >/dev/null 2>&1") == 0
end

local function run_iconv_command(cmd)
	if not iconv_available() then
		return nil
	end

	local repaired = sys.exec(cmd)
	if repaired and repaired ~= "" then
		return repaired
	end

	return nil
end

local log_message_exact_map = {
	["legacy default server detected, cleared client server list"] = "检测到旧默认服务器地址，已清空客户端服务器列表",
	["client config missing network_code"] = "客户端配置缺少 network_code",
	["client config server list format is invalid"] = "客户端配置中的服务器地址列表格式无效",
	["start requested"] = "收到启动请求",
	["start command submitted"] = "启动命令已提交",
	["client runtime preparation failed"] = "客户端运行环境准备失败",
	["not enabled, skip start"] = "未启用，跳过启动",
	["start failed: missing executable vnt2_web"] = "启动失败：缺少可执行文件 vnt2_web",
	["start failed: client TOML validation failed"] = "启动失败：客户端 TOML 配置校验失败",
	["start failed: client network runtime preparation failed"] = "启动失败：客户端网络运行环境准备失败",
	["vnts2 disabled, skip start"] = "vnts2 未启用，跳过启动",
	["start failed: missing usable vnts2 binary"] = "启动失败：缺少可用的 vnts2 程序",
	["server runtime preparation failed"] = "服务端运行环境准备失败",
	["service start flow begin"] = "服务启动流程开始",
	["UCI to TOML export completed"] = "UCI 到 TOML 导出完成",
	["UCI to TOML export failed, continue with existing config"] = "UCI 到 TOML 导出失败，继续使用现有配置",
	["vnt2_cli config section not found"] = "未找到 vnt2_cli 配置节",
	["vnt2_web config section not found"] = "未找到 vnt2_web 配置节",
	["vnts2 config section not found"] = "未找到 vnts2 配置节",
	["start_service finished"] = "服务启动流程结束",
	["service stop flow begin"] = "服务停止流程开始",
	["service stopped"] = "服务已停止",
	["existing CLI/CTRL incomplete, trying auto-download or uploaded fallback"] = "现有 CLI/CTRL 不完整，正在尝试自动下载或回退到已上传程序",
	["start failed: missing vnt2_cli or vnt2_ctrl"] = "启动失败：缺少 vnt2_cli 或 vnt2_ctrl",
	["start failed: vnt2_ctrl missing after recovery"] = "启动失败：恢复后仍缺少 vnt2_ctrl",
	["vnt2_cli disabled, skip start"] = "vnt2_cli 未启用，跳过启动",
	["bundle missing vnt2_cli or vnt2_ctrl"] = "压缩包中缺少 vnt2_cli 或 vnt2_ctrl",
	["install CLI bundle to /usr/bin failed"] = "安装 CLI 程序包到 /usr/bin 失败",
	["bundle missing vnt2_web"] = "压缩包中缺少 vnt2_web",
	["install web bundle to /usr/bin failed"] = "安装 Web 程序包到 /usr/bin 失败",
	["bundle missing usable vnts2 or vnts"] = "压缩包中缺少可用的 vnts2 或 vnts",
	["install server bundle to /usr/bin failed"] = "安装服务端程序包到 /usr/bin 失败"
}

local log_message_pattern_rules = {
	{ "^client config file missing: (.+)$", "客户端配置文件不存在：%1" },
	{ "^server config file missing: (.+)$", "服务端配置文件不存在：%1" },
	{ "^existing CLI/CTRL detected: cli=(.+) ctrl=(.+)$", "检测到现有 CLI/CTRL：cli=%1 ctrl=%2" },
	{ "^starting (.+) with config (.+)$", "正在启动 %1，配置文件：%2" },
	{ "^using (.+) on (.+), conf=(.+)$", "使用 %1 监听 %2，配置文件：%3" },
	{ "^checking (.+) releases list: (.+)$", "正在检查 %1 的 Releases 列表：%2" },
	{ "^checking release endpoint: (.+)$", "正在检查发布接口：%1" },
	{ "^checking releases list: (.+)$", "正在检查 Releases 列表：%1" },
	{ "^failed to create install directory (.+)$", "创建安装目录失败：%1" },
	{ "^failed to copy uploaded binary to (.+) from (.+)$", "复制已上传程序失败：目标=%1 来源=%2" },
	{ "^failed to chmod uploaded binary (.+)$", "设置已上传程序执行权限失败：%1" },
	{ "^uploaded binary not found after install (.+)$", "安装后未找到已上传程序：%1" },
	{ "^mirror (.+) not supported for repo (.+), fallback to (.+)$", "镜像 %1 不支持仓库 %2，已回退到 %3" },
	{ "^mirror strategy (.+) not supported for repo (.+), fallback to github$", "镜像策略 %1 不支持仓库 %2，已回退到 GitHub" },
	{ "^cached bundle found for (.+), reuse (.+)$", "发现 %1 的缓存程序包，复用目录：%2" },
	{ "^query target release repo=(.+) tag=(.+) arch=(.+) scope=(.+)$", "准备查询发行版：repo=%1 tag=%2 arch=%3 scope=%4" },
	{ "^querying (.+) release repo=(.+) tag=(.+) mirror=(.+) strategy=(.+) arch=(.+)$", "正在查询 %1 发行版：repo=%2 tag=%3 mirror=%4 strategy=%5 arch=%6" },
	{ "^querying (.+) release repo=(.+) tag=(.+) mirror=(.+) arch=(.+)$", "正在查询 %1 发行版：repo=%2 tag=%3 mirror=%4 arch=%5" },
	{ "^release query failed repo=(.+) tag=(.+) mirror=(.+)$", "发行版查询失败：repo=%1 tag=%2 mirror=%3" },
	{ "^release query ok: (.+)$", "发行版查询成功：%1" },
	{ "^no release asset matched arch=(.+) scope=(.+) mirror=(.+)$", "未找到匹配的发行资源：arch=%1 scope=%2 mirror=%3" },
	{ "^no release asset matched arch=(.+) scope=(.+)$", "未找到匹配的发行资源：arch=%1 scope=%2" },
	{ "^selected asset (.+) mirror=(.+)$", "已选择发行资源：%1 mirror=%2" },
	{ "^selected asset (.+)$", "已选择发行资源：%1" },
	{ "^reusing downloaded asset (.+)$", "复用已下载资源：%1" },
	{ "^cached asset invalid, remove and redownload (.+)$", "缓存资源无效，已删除并重新下载：%1" },
	{ "^asset download failed tool=(.+) mirror=(.+) url=(.+)$", "资源下载失败：工具=%1 mirror=%2 地址=%3" },
	{ "^asset download failed tool=(.+) url=(.+)$", "资源下载失败：工具=%1 地址=%2" },
	{ "^downloaded asset invalid or corrupted (.+)$", "已下载资源无效或已损坏：%1" },
	{ "^extract failed, remove cache and retry (.+)$", "解压失败，已删除缓存并重试：%1" },
	{ "^retry asset download failed tool=(.+) mirror=(.+) url=(.+)$", "重试下载资源失败：工具=%1 mirror=%2 地址=%3" },
	{ "^retry asset download failed tool=(.+) url=(.+)$", "重试下载资源失败：工具=%1 地址=%2" },
	{ "^retried asset still invalid (.+)$", "重试后资源仍然无效：%1" },
	{ "^extract asset failed (.+)$", "解压资源失败：%1" },
	{ "^bundle missing vnt2_cli or vnt2_ctrl mirror=(.+)$", "压缩包中缺少 vnt2_cli 或 vnt2_ctrl：mirror=%1" },
	{ "^bundle missing vnt2_web mirror=(.+)$", "压缩包中缺少 vnt2_web：mirror=%1" },
	{ "^bundle missing usable vnts2 or vnts mirror=(.+)$", "压缩包中缺少可用的 vnts2 或 vnts：mirror=%1" },
	{ "^CLI installed: cli=(.+) ctrl=(.+) mirror=(.+)$", "CLI 安装完成：cli=%1 ctrl=%2 mirror=%3" },
	{ "^CLI installed: cli=(.+) ctrl=(.+)$", "CLI 安装完成：cli=%1 ctrl=%2" },
	{ "^web installed: web=(.+) mirror=(.+)$", "Web 安装完成：web=%1 mirror=%2" },
	{ "^web installed: web=(.+)$", "Web 安装完成：web=%1" },
	{ "^server installed: server=(.+) mirror=(.+)$", "服务端安装完成：server=%1 mirror=%2" },
	{ "^server installed: server=(.+)$", "服务端安装完成：server=%1" },
	{ "^all download mirrors failed repo=(.+) tag=(.+) strategy=(.+) arch=(.+) scope=(.+)$", "所有下载镜像均失败：repo=%1 tag=%2 strategy=%3 arch=%4 scope=%5" },
	{ "^(.+) auto download failed, fallback to uploaded binary (.+)$", "%1 自动下载失败，已回退到已上传程序：%2" }
}

function M.sanitize_text(content)
	content = tostring(content or "")
	content = content:gsub("\27%[[%d;?]*[%a]", "")
	content = content:gsub("\27%][^\7]*\7", "")
	content = content:gsub("%z", "")
	content = content:gsub("\r", "")
	return content
end

function M.translate_log_message(message)
	message = tostring(message or "")
	if message == "" then
		return message
	end

	if log_message_exact_map[message] then
		return log_message_exact_map[message]
	end

	for _, rule in ipairs(log_message_pattern_rules) do
		local translated, count = message:gsub(rule[1], rule[2])
		if count > 0 then
			return translated
		end
	end

	return message
end

function M.translate_log_text(content)
	content = tostring(content or "")
	if content == "" then
		return content
	end

	local has_trailing_newline = content:sub(-1) == "\n"
	local lines = {}

	for line in (content .. "\n"):gmatch("(.-)\n") do
		local prefix, message = line:match("^(.- : )(.*)$")
		if prefix then
			lines[#lines + 1] = prefix .. M.translate_log_message(message)
		else
			lines[#lines + 1] = M.translate_log_message(line)
		end
	end

	local translated = table.concat(lines, "\n")
	if not has_trailing_newline and translated:sub(-1) == "\n" then
		translated = translated:sub(1, -2)
	end
	return translated
end

function M.looks_like_mojibake(content)
	content = tostring(content or "")
	if content == "" then
		return false
	end

	for _, marker in ipairs(mojibake_markers) do
		if content:find(marker, 1, true) then
			return true
		end
	end

	return false
end

function M.repair_mojibake_text(content)
	content = tostring(content or "")
	if content == "" or not M.looks_like_mojibake(content) then
		return content
	end

	local repaired = run_iconv_command(string.format(
		"printf '%%s' %s | iconv -f UTF-8 -t GB18030 2>/dev/null",
		util.shellquote(content)
	))
	return repaired or content
end

function M.read_text_file(path)
	local content = path and path ~= "" and fs.access(path) and (fs.readfile(path) or "") or ""
	if content ~= "" and path and path ~= "" and M.looks_like_mojibake(content) then
		local repaired = run_iconv_command(string.format(
			"iconv -f UTF-8 -t GB18030 %s 2>/dev/null",
			util.shellquote(path)
		))
		if repaired then
			content = repaired
		end
	end

	return M.sanitize_text(content)
end

function M.normalize_text(content)
	return M.sanitize_text(M.repair_mojibake_text(content))
end

function M.normalize_log_text(content)
	return M.translate_log_text(M.normalize_text(content))
end

local function keep_last_lines(content, max_lines)
	content = tostring(content or "")
	max_lines = tonumber(max_lines or 0) or 0
	if max_lines <= 0 or content == "" then
		return content
	end

	local has_trailing_newline = content:sub(-1) == "\n"
	local lines = {}
	for line in (content .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end

	if has_trailing_newline and lines[#lines] == "" then
		table.remove(lines, #lines)
	end

	if #lines <= max_lines then
		return table.concat(lines, "\n") .. (has_trailing_newline and #lines > 0 and "\n" or "")
	end

	local start_idx = #lines - max_lines + 1
	local out = {}
	for i = start_idx, #lines do
		out[#out + 1] = lines[i]
	end

	return table.concat(out, "\n") .. (has_trailing_newline and #out > 0 and "\n" or "")
end

function M.read_log_file(path, max_lines)
	local limit = tonumber(max_lines or 0) or 0
	if limit <= 0 then
		return M.normalize_log_text(M.read_text_file(path))
	end

	local content = ""
	if path and path ~= "" and fs.access(path) then
		if tail_available then
			content = sys.exec(string.format("tail -n %d %s 2>/dev/null", limit, util.shellquote(path))) or ""
		end
		if content == "" then
			content = keep_last_lines(M.read_text_file(path), limit)
			return M.normalize_log_text(content)
		end
	end

	return M.normalize_log_text(content)
end

return M
