local SimpleForm = require "luci.model.cbi".SimpleForm
local Template = require "luci.template".Template
local translate = require "luci.i18n".translate

local f = SimpleForm("vnt2",
    translate("VNT2 Server Log"),
    translate("View vnts2 runtime log")
)
f.reset = false
f.submit = false
f:append(Template("vnt2/vnts2_log"))
return f
