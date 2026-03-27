
local log = SimpleForm("log", translate("客户端日志"))
log.submit = false
log.reset = false

local log_data = ""
local files = {"/tmp/vnt2-cli.log"}
for i, file in ipairs(files) do
    if nixio.fs.access(file) then
        log_data = log_data .. io.open(file):read("*all")
    end
end

local log_view = log:field(DummyValue, "_log")
log_view.rawhtml = true
log_view.template = "vnt2/vnt2-cli_log"

return log
