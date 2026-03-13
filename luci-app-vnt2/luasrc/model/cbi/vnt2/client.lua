local m, s, o
local dsp = require "luci.dispatcher"

m = Map("vnt2", "vnt2-cli 客户端设置", "配置 vnt2-cli 客户端的所有参数，修改后点击「保存&应用」生效")

-- 基本设置 Tab
s = m:section(NamedSection, "client", "client", "基本设置")
s.anonymous = true

o = s:option(Flag, "enabled", "启用客户端")
o.default = 0
o.rmempty = false

o = s:option(Value, "token", "连接 Token")
o.password = true
o.description = "与服务端一致的认证 Token"

o = s:option(Value, "device_id", "设备 ID（虚拟IP）")
o.default = "10.10.10.3"
o.description = "客户端在虚拟局域网内的 IP 地址"

o = s:option(DynamicList, "route", "本地局域网路由")
o.description = "需要推送给其他客户端的本地网段，格式：192.168.1.0/24"
o.placeholder = "192.168.1.0/24"

o = s:option(Value, "server", "服务端地址")
o.default = "tcp://你的公网IP:29872"
o.description = "服务端地址，格式：tcp://IP:端口 或 tls://IP:端口"

-- 高级设置 Tab
s = m:section(NamedSection, "client", "client", "高级设置")
s.anonymous = true

o = s:option(Value, "interface", "虚拟网卡名称")
o.default = "vnt2"
o.description = "客户端创建的虚拟网卡名称"

o = s:option(Value, "mtu", "MTU 值")
o.default = "1400"
o.datatype = "uinteger"
o.description = "虚拟网卡的 MTU 值，默认 1400"

o = s:option(ListValue, "log_level", "日志级别")
o:value("info", "信息（info）")
o:value("debug", "调试（debug）")
o:value("error", "错误（error）")
o:value("warn", "警告（warn）")
o:value("trace", "追踪（trace）")
o.default = "info"
o.description = "程序输出的日志级别"

o = s:option(Value, "log_path", "日志文件路径")
o.default = "/tmp/vnt2.log"
o.description = "客户端日志保存路径"

o = s:option(Value, "custom_args", "自定义启动参数")
o.description = "额外的自定义启动参数，多个参数用空格分隔，高级用户使用"
o.placeholder = "--fingerprint xxx --crypto aes-gcm"

-- 连接信息 Tab
s = m:section(TypedSection, "client", "连接信息")
s.anonymous = true
s.addremove = false

function s.render(self, scope, ...)
    local html = [[
    <div class="cbi-section">
        <p>连接信息将在客户端启动后自动展示</p>
        <div id="conn-info">
            <p>客户端未运行，暂无连接信息</p>
        </div>
    </div>
    ]]
    luci.template.render_string(html)
end

-- 上传程序 Tab
s = m:section(NamedSection, "client", "client", "上传程序")
s.anonymous = true

function s.render(self, scope, ...)
    local html = [[
    <div class="cbi-section">
        <div class="cbi-section-node">
            <div class="form-group">
                <label class="cbi-value-title">上传程序</label>
                <div class="cbi-value-field">
                    <input type="file" id="bin-file" accept=".tar.gz,.gz,.bin">
                    <button class="cbi-button cbi-button-apply" id="upload-btn" style="margin-left:10px;">上传</button>
                </div>
                <div class="cbi-value-description">
                    可直接上传二进制程序 vnt2-cli 和 vnts2 或者以 .tar.gz 结尾的压缩包，上传新版本会自动覆盖旧版本<br>
                    官方下载地址：<a href="https://github.com/vnt-dev/vnt/releases" target="_blank">vnt-cli</a> | <a href="https://github.com/vnt-dev/vnts/releases" target="_blank">vnts</a><br>
                    上传的文件将保存在 /tmp 文件夹里，启动时会自动覆盖到程序路径
                </div>
            </div>

            <div class="form-group">
                <label class="cbi-value-title">在线更新</label>
                <div class="cbi-value-field">
                    <select id="update-type" style="width:150px;">
                        <option value="client">客户端</option>
                        <option value="server">服务端</option>
                    </select>
                    <input type="text" id="update-version" placeholder="指定版本号，留空为最新稳定版本" style="width:300px;margin-left:10px;">
                    <button class="cbi-button cbi-button-positive" id="update-btn" style="margin-left:10px;">更新</button>
                </div>
                <div class="cbi-value-description">
                    选择要更新的程序和版本，点击按钮开始检测更新，从 GitHub 下载已发布的程序
                </div>
            </div>

            <div id="msg-box" style="margin-top:15px;padding:10px;border-radius:4px;display:none;"></div>
        </div>
    </div>

    <script type="text/javascript">
        // 上传功能
        document.getElementById('upload-btn').addEventListener('click', function() {
            var fileInput = document.getElementById('bin-file');
            var file = fileInput.files[0];
            if (!file) {
                showMsg('请先选择要上传的文件', 'warning');
                return;
            }
            var uploadType = document.getElementById('update-type').value;

            var formData = new FormData();
            formData.append('bin_file', file);
            formData.append('upload_type', uploadType);

            var xhr = new XMLHttpRequest();
            xhr.open('POST', ']]..dsp.build_url("admin", "services", "vnt2", "api_upload")..[[', true);
            xhr.onload = function() {
                if (xhr.status === 200) {
                    var res = JSON.parse(xhr.responseText);
                    if (res.success) {
                        showMsg(res.msg, 'success');
                    } else {
                        showMsg(res.msg, 'error');
                    }
                } else {
                    showMsg('上传失败，服务器错误', 'error');
                }
            };
            xhr.send(formData);
        });

        // 更新功能
        document.getElementById('update-btn').addEventListener('click', function() {
            var updateType = document.getElementById('update-type').value;
            var version = document.getElementById('update-version').value.trim();

            var xhr = new XMLHttpRequest();
            xhr.open('POST', ']]..dsp.build_url("admin", "services", "vnt2", "api_update")..[[', true);
            xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
            xhr.onload = function() {
                if (xhr.status === 200) {
                    var res = JSON.parse(xhr.responseText);
                    if (res.success) {
                        showMsg(res.msg, 'success');
                    } else {
                        showMsg(res.msg, 'error');
                    }
                } else {
                    showMsg('更新失败，服务器错误', 'error');
                }
            };
            xhr.send('update_type=' + encodeURIComponent(updateType) + '&version=' + encodeURIComponent(version));
        });

        function showMsg(msg, type) {
            var msgBox = document.getElementById('msg-box');
            msgBox.innerText = msg;
            msgBox.style.display = 'block';
            if (type === 'success') {
                msgBox.style.backgroundColor = '#dff0d8';
                msgBox.style.color = '#3c763d';
            } else if (type === 'error') {
                msgBox.style.backgroundColor = '#f2dede';
                msgBox.style.color = '#a94442';
            } else if (type === 'warning') {
                msgBox.style.backgroundColor = '#fcf8e3';
                msgBox.style.color = '#8a6d3b';
            }
            setTimeout(function() {
                msgBox.style.display = 'none';
            }, 5000);
        }
    </script>
    ]]
    luci.template.render_string(html)
end

-- 保存后自动重启服务
m.on_after_commit = function(self)
    luci.sys.exec("/etc/init.d/vnt2 restart")
end

return m
