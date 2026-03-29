local fs = require "nixio.fs"

local log = SimpleForm("log", translate("Web 日志"))
log.submit = false
log.reset = false

local log_data = ""
local files = { "/tmp/vnt2-web.log" }
for _, file in ipairs(files) do
	if fs.access(file) then
		log_data = log_data .. io.open(file):read("*all")
	end
end

local log_view = log:field(DummyValue, "_log")
log_view.rawhtml = true
log_view.template = "vnt2/vnt2-web_log"

return log
