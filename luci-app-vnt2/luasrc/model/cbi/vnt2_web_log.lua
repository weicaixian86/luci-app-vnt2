local f = SimpleForm("vnt2", translate("Web 日志"))
f.description = translate("实时查看 vnt2_web 运行日志")
f.reset = false
f.submit = false
f:append(Template("vnt2/vnt2_web_log"))

return f
