local fs = require "nixio.fs"

local log = SimpleForm("log", translate("服务端日志"))
log.submit = false
log.reset = false

local log_data = ""
local files = { "/tmp/vnts2.log" }
for _, file in ipairs(files) do
	if fs.access(file) then
		log_data = log_data .. (fs.readfile(file) or "")
	end
end

local log_view = log:field(DummyValue, "_log")
log_view.rawhtml = true
log_view.template = "vnt2/vnts2_log"

return log
