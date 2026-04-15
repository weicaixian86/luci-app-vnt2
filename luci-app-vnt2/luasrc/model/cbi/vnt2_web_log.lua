local f = SimpleForm("vnt2")
f.reset = false
f.submit = false
f:append(Template("vnt2/vnt2_web_log"))

return f
