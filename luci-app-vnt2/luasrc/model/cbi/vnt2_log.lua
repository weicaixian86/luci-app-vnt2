local SimpleForm = require "luci.model.cbi".SimpleForm
local Template = require "luci.template".Template
local translate = require "luci.i18n".translate

local f = SimpleForm("vnt2",
    translate("VNT2 Client Log"),
    translate("View vnt2-cli runtime log")
)
f.reset = false
f.submit = false
f:append(Template("vnt2/vnt-cli_log"))
return f
