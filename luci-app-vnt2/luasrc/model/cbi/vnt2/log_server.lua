local m, s, o

m = Map("vnt2", "服务端日志", "vnts2 运行日志")

s = m:section(TypedSection, "server", "日志内容")
s.anonymous = true
s.addremove = false

function s.render(self, scope, ...)
    local log_path = luci.model.uci.cursor():get("vnt2", "server", "log_path") or "/tmp/vnts2.log"
    local log_content = luci.sys.exec("cat "..log_path.." 2>/dev/null | tail -200")
    if log_content == "" then
        log_content = "暂无日志内容，请先启用服务端并开启日志"
    end

    local html = [[
    <div class="cbi-section">
        <div class="cbi-section-node">
            <div style="margin-bottom:10px;">
                <button class="cbi-button cbi-button-reload" id="refresh-log">刷新日志</button>
                <button class="cbi-button cbi-button-negative" id="clear-log">清空日志</button>
                <span style="margin-left:10px;color:#666;">日志文件路径：]]..log_path..[[</span>
            </div>
            <textarea id="log-content" style="width:100%;height:500px;font-family:Monaco,monospace;font-size:12px;line-height:1.5;padding:10px;" readonly>]]..luci.util.pcdata(log_content)..[[</textarea>
        </div>
    </div>

    <script type="text/javascript">
        document.getElementById('refresh-log').addEventListener('click', function() {
            location.reload();
        });

        document.getElementById('clear-log').addEventListener('click', function() {
            if (confirm('确定要清空日志吗？')) {
                var xhr = new XMLHttpRequest();
                xhr.open('POST', '<%=luci.dispatcher.build_url("admin", "services", "vnt2", "api_clear_log")%>', true);
                xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
                xhr.onload = function() {
                    location.reload();
                };
                xhr.send('type=server');
            }
        });
    </script>
    ]]
    luci.template.render_string(html)
end

return m
