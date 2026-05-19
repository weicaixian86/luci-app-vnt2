local f = SimpleForm("vnt2", translate("服务端日志"))
f.description = translate("实时查看 vnts2 服务端运行日志")
f.reset = false
f.submit = false
f:append(Template("vnt2/vnts2_log"))

return f
