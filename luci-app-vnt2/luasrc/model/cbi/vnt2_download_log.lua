local f = SimpleForm("vnt2", translate("下载日志"))
f.description = translate("实时查看程序下载与安装日志")
f.reset = false
f.submit = false
f:append(Template("vnt2/vnt2_download_log"))

return f
