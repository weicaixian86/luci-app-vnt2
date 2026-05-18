local fs = require "nixio.fs"
local sys = require "luci.sys"
local util = require "luci.util"

local M = {}

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

function M.sanitize_text(content)
	content = tostring(content or "")
	content = content:gsub("\27%[[%d;?]*[%a]", "")
	content = content:gsub("\27%][^\7]*\7", "")
	content = content:gsub("%z", "")
	content = content:gsub("\r", "")
	return content
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

return M
