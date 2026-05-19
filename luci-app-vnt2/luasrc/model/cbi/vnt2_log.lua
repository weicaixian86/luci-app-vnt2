local f = SimpleForm("vnt2", translate("CLI 日志"))
f.description = translate("实时查看 vnt2_cli 运行日志")
f.reset = false
f.submit = false
f:append(Template("vnt2/vnt2-cli_log"))

return f
