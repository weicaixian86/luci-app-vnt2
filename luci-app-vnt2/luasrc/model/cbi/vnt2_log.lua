-- LuCI CBI 配置文件：VNT 日志查看页面（重命名为vnt2_log.lua）
-- 路径：/luasrc/model/cbi/vnt2_log.lua
local SimpleForm = require "luci.model.cbi".SimpleForm
local Template = require "luci.template".Template

-- 创建表单，标题可根据需要调整
local f = SimpleForm("vnt", translate("VNT Client Log"), translate("View real-time and historical logs of VNT client"))

-- 禁用重置/提交按钮
f.reset = false
f.submit = false

-- 嵌入日志模板（模板文件名仍为vnt-cli_log.htm，无需同步改名）
f:append(Template("vnt/vnt-cli_log"))

return f
