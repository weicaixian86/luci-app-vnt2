-- LuCI CBI 配置文件：VNT 服务端（vnts）日志查看页面（重命名版）
-- 路径：/luasrc/model/cbi/vnt2_log2.lua
-- 适配 OpenWRT/LEDE LuCI 框架，支持多语言、无交互按钮

-- 加载 LuCI 核心依赖库
local SimpleForm = require "luci.model.cbi".SimpleForm
local Template = require "luci.template".Template
local translate = require "luci.i18n".translate

-- 创建简单表单，关联 vnt UCI 配置（仅作为标识，不修改配置）
local f = SimpleForm("vnt",
    translate("VNT2 Server Log"),  -- 标题适配 vnt2 命名
    translate("View real-time and historical logs of VNT2 Server (vnts).")
)

-- 关键配置：禁用提交/重置按钮（日志页面只读）
f.reset = false  -- 隐藏「重置」按钮，避免误操作
f.submit = false -- 隐藏「提交」按钮，无配置项需提交

-- 嵌入 VNT 服务端日志模板文件（模板文件名不变，仅页面框架改名）
f:append(Template("vnt/vnts_log"))

-- 返回表单对象，供 LuCI 界面渲染
return f
