local fs = require "nixio.fs"
local util = require "luci.util"
local nixio = require "nixio"

local M = {}

M.TOML_FILE = "/etc/config/vnt2.toml"

local LEGACY_DEFAULT_CLIENT_SERVER = "tcp://0.0.0.0:29872"
local DEFAULT_CLIENT_SERVER = "tcp://1.1.1.1:29872"

local client_defaults = {
	network_code = "123456",
	server = { "tcp://1.1.1.1:29872" },
	ip = "",
	device_id = "",
	device_name = "",
	password = "",
	tun_name = "vnt-tun",
	cert_mode = "skip",
	mtu = "1400",
	tunnel_port = "",
	device_mode = "tun",
	no_punch = "0",
	no_broadcast = "0",
	allow_ikev2 = "0",
	allow_wireguard = "0",
	rtx = "0",
	compress = "0",
	fec = "0",
	no_nat = "0",
	allow_mapping = "0",
	auto_sync_subnet = "0",
	outbound_interface = "",
	event_script = "",
	input = {},
	output = {},
	port_mapping = {},
	peer_address = {},
	turn = {},
	punch_model = {},
	subnet_mapping = {},
	tunnel_addr = {},
	udp_stun = {},
	tcp_stun = {}
}

local web_option_map = {
	network_code = "network_code",
	server = "server",
	peer_address = "peer_address",
	turn = "turn",
	punch_model = "punch_model",
	ip = "ip",
	device_id = "device_id",
	device_name = "device_name",
	password = "password",
	tun_name = "tun_name",
	cert_mode = "cert_mode",
	mtu = "mtu",
	tunnel_port = "tunnel_port",
	device_mode = "device_mode",
	no_punch = "no_punch",
	no_broadcast = "no_broadcast",
	allow_ikev2 = "allow_ikev2",
	allow_wireguard = "allow_wireguard",
	rtx = "rtx",
	compress = "compress",
	fec = "fec",
	no_nat = "no_nat",
	allow_mapping = "allow_mapping",
	subnet_mapping = "subnet_mapping",
	auto_sync_subnet = "auto_sync_subnet",
	outbound_interface = "outbound_interface",
	tunnel_addr = "tunnel_addr",
	event_script = "event_script",
	input = "input",
	output = "output",
	port_mapping = "port_mapping",
	udp_stun = "udp_stun",
	tcp_stun = "tcp_stun"
}

local web_order = {
	"network_code", "server", "peer_address", "turn", "punch_model", "ip", "device_id", "device_name", "password", "tun_name",
	"cert_mode", "mtu", "tunnel_port", "device_mode", "no_punch", "no_broadcast", "allow_ikev2", "allow_wireguard", "rtx", "compress",
	"fec", "no_nat", "allow_mapping", "subnet_mapping", "auto_sync_subnet", "outbound_interface", "tunnel_addr", "event_script",
	"input", "output", "port_mapping", "udp_stun", "tcp_stun"
}

local list_keys = {
	server = true,
	peer_address = true,
	turn = true,
	punch_model = true,
	input = true,
	output = true,
	port_mapping = true,
	udp_stun = true,
	tcp_stun = true,
	subnet_mapping = true,
	tunnel_addr = true
}

local bool_keys = {
	no_punch = true,
	no_broadcast = true,
	allow_ikev2 = true,
	allow_wireguard = true,
	rtx = true,
	compress = true,
	fec = true,
	no_nat = true,
	allow_mapping = true,
	auto_sync_subnet = true,
	device_mode = false
}

local number_keys = {
	mtu = true,
	tunnel_port = true
}

local required_string_keys = {
	network_code = true,
	tun_name = true,
	cert_mode = true
}

local legacy_key_aliases = {
	cmd_port = "ctrl_port",
	port = "tunnel_port",
	use_channel_type = "rtx",
	compressor = "compress",
	use_fec = "fec",
	no_proxy = "no_nat",
	allow_wire_guard = "allow_wireguard",
	in_ips = "input",
	out_ips = "output",
	mapping = "port_mapping",
	stun_server = "udp_stun",
	stun_server_tcp = "tcp_stun"
}

local function trim(v)
	return util.trim(tostring(v or ""))
end

local function is_list_key(key)
	return list_keys[key] == true
end

local function is_bool_key(key)
	return bool_keys[key] == true
end

local function is_number_key(key)
	return number_keys[key] == true
end

local function normalize_list(value)
	local out = {}

	if type(value) == "string" then
		value = { value }
	end

	if type(value) ~= "table" then
		return out
	end

	for _, item in ipairs(value) do
		item = trim(item)
		if item ~= "" then
			out[#out + 1] = item
		end
	end

	return out
end

local function normalize_client_server_list(value)
	local out = normalize_list(value)

	if #out == 1 then
		local first = out[1]
		if first == LEGACY_DEFAULT_CLIENT_SERVER then
			return { DEFAULT_CLIENT_SERVER }
		end
	end

	return out
end

local function toml_escape(s)
	return tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
end

local function toml_unescape(s)
	s = tostring(s or "")
	s = s:gsub('\\"', '"')
	s = s:gsub("\\\\", "\\")
	return s
end

local function parse_array(inner)
	local out = {}
	local pos = 1
	inner = trim(inner)
	if inner == "" then
		return out
	end

	while pos <= #inner do
		while pos <= #inner and inner:sub(pos, pos):match("[%s,]") do
			pos = pos + 1
		end
		if pos > #inner then
			break
		end

		if inner:sub(pos, pos) ~= '"' then
			return out
		end

		local start = pos + 1
		local i = start
		local escaped = false
		while i <= #inner do
			local char = inner:sub(i, i)
			if escaped then
				escaped = false
			elseif char == "\\" then
				escaped = true
			elseif char == '"' then
				break
			end
			i = i + 1
		end
		if i > #inner then
			return out
		end

		out[#out + 1] = toml_unescape(inner:sub(start, i - 1))
		pos = i + 1
	end

	return out
end

local function get_client_uci_value(uci, section, option)
	if not section then
		return nil
	end

	local value = uci:get("vnt2", section, option)
	if value ~= nil then
		return value
	end

	if option == "tunnel_port" then
		return uci:get("vnt2", section, "port")
	end

	if option == "device_mode" then
		local legacy = uci:get("vnt2", section, "no_tun")
		if legacy ~= nil then
			return (trim(legacy) == "1" or trim(legacy) == "true") and "no" or "tun"
		end
	end

	return nil
end

local function strip_toml_comment(line)
	local quoted = false
	local escaped = false
	for i = 1, #line do
		local char = line:sub(i, i)
		if quoted then
			if escaped then
				escaped = false
			elseif char == "\\" then
				escaped = true
			elseif char == '"' then
				quoted = false
			end
		elseif char == '"' then
			quoted = true
		elseif char == "#" then
			return line:sub(1, i - 1)
		end
	end
	return line
end

local function encode_value(key, value)
	if is_list_key(key) then
		local vals = normalize_list(value)
		local parts = {}
		for _, item in ipairs(vals) do
			parts[#parts + 1] = '"' .. toml_escape(item) .. '"'
		end
		return "[" .. table.concat(parts, ", ") .. "]"
	end

	value = trim(value)

	if is_bool_key(key) then
		if value == "1" or value == "true" then
			return "true"
		end
		return "false"
	end

	if is_number_key(key) then
		if value == "" then
			value = "0"
		end
		return tostring(tonumber(value) or 0)
	end

	return '"' .. toml_escape(value) .. '"'
end

local function parse_value(key, raw)
	raw = trim(raw)

	if is_list_key(key) then
		return parse_array(raw:match("^%[(.*)%]$") or "")
	end

	if is_bool_key(key) then
		return (raw == "true") and "1" or "0"
	end

	if is_number_key(key) then
		return trim(raw)
	end

	local quoted = raw:match('^"(.*)"$')
	if quoted ~= nil then
		return toml_unescape(quoted)
	end

	return raw
end

local function clone_defaults(src)
	local out = {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			out[k] = clone_defaults(v)
		else
			out[k] = v
		end
	end
	return out
end

function M.read_toml(path, defaults)
	local data = clone_defaults(defaults or {})
	local current_section = ""
	local canonical_seen = {}

	if not fs.access(path) then
		return data
	end

	local content = fs.readfile(path) or ""
	for line in content:gmatch("[^\r\n]+") do
		local clean = trim(strip_toml_comment(line))
		if clean ~= "" then
			local section = clean:match("^%[([%w_]+)%]$")
			if section then
				current_section = section
			else
				local key, raw = clean:match("^([%w_.%-]+)%s*=%s*(.-)%s*$")
				if not key then
					key, raw = clean:match('^"(.-)"%s*=%s*(.-)%s*$')
				end
				if key then
					if key == "no_tun" then
						local old_value = trim(raw)
						data.no_tun = (old_value == "true" or old_value == "1") and "1" or "0"
						canonical_seen.no_tun = true
					else
						local target_key = legacy_key_aliases[key] or key
						local is_legacy = target_key ~= key
						if not (is_legacy and canonical_seen[target_key]) then
							data[target_key] = parse_value(target_key, raw)
							if not is_legacy then
								canonical_seen[target_key] = true
							end
						end
					end
				end
			end
		end
	end
	if not canonical_seen.device_mode and canonical_seen.no_tun then
		data.device_mode = data.no_tun == "1" and "no" or "tun"
	end

	return data
end

local function ensure_toml_parent(path)
	local dir = path:match("^(.+)/[^/]+$")
	if dir and dir ~= "" then
		if not fs.mkdirr(dir) and not fs.access(dir) then
			return nil, "failed to create TOML parent directory"
		end
		if not fs.chmod(dir, "0755") then
			return nil, "failed to secure TOML parent directory"
		end
	end
	return true
end

local function secure_existing_toml(path)
	local parent_ok, parent_err = ensure_toml_parent(path)
	if not parent_ok then
		return nil, parent_err
	end
	if not fs.chmod(path, "0600") then
		return nil, "failed to secure existing TOML file"
	end
	return true
end

function M.write_toml(path, data, order)
	local parent_ok, parent_err = ensure_toml_parent(path)
	if not parent_ok then
		return nil, parent_err
	end

	local lines = {}
	for _, key in ipairs(order) do
		local value = data[key]
		if value ~= nil then
			local keep = true

			if not is_list_key(key) and not is_bool_key(key) and not is_number_key(key) then
				value = trim(value)
				if value == "" and not required_string_keys[key] then
					keep = false
				end
			end
			if key == "tunnel_port" and (trim(value) == "" or trim(value) == "0") then
				keep = false
			end

			if keep then
				lines[#lines + 1] = string.format("%s = %s", key, encode_value(key, value))
			end
		end
	end

	lines[#lines + 1] = ""
	local temp = string.format("%s.tmp.%s", path, tostring(nixio.getpid()))
	local content = table.concat(lines, "\n")
	if not fs.writefile(temp, content) then
		fs.remove(temp)
		return nil, "failed to write temporary TOML file"
	end
	if not fs.chmod(temp, "0600") then
		fs.remove(temp)
		return nil, "failed to secure temporary TOML file"
	end
	if not os.rename(temp, path) then
		fs.remove(temp)
		return nil, "failed to replace TOML file"
	end
	return true
end

local function ensure_section(uci, config, stype)
	local name = uci:get_first(config, stype)
	if name then
		return name
	end
	local created = uci:add(config, stype)
	return created
end

local function set_uci_scalar(uci, config, section, option, value)
	value = trim(value)
	if value == "" then
		uci:delete(config, section, option)
	else
		uci:set(config, section, option, value)
	end
end

local function set_uci_list(uci, config, section, option, value)
	local vals = normalize_list(value)
	uci:delete(config, section, option)
	if #vals > 0 then
		uci:set_list(config, section, option, vals)
	end
end

local function build_web_toml_data(uci)
	local data = clone_defaults(client_defaults)
	local section = uci:get_first("vnt2", "vnt2_web")

	for toml_key, uci_key in pairs(web_option_map) do
		if is_list_key(toml_key) then
			local val = section and uci:get_list("vnt2", section, uci_key) or data[toml_key]
			if toml_key == "server" then
				data[toml_key] = normalize_client_server_list(val)
			else
				data[toml_key] = normalize_list(val)
			end
		else
			local val = get_client_uci_value(uci, section, uci_key)
			if val ~= nil then
				data[toml_key] = trim(val)
			end
		end
	end
	if #normalize_list(data.tunnel_addr) > 0 then
		data.tunnel_port = nil
	end

	return data
end

function M.ensure_toml_file(uci)
	if fs.access(M.TOML_FILE) then
		return secure_existing_toml(M.TOML_FILE)
	end

	return M.write_toml(M.TOML_FILE, build_web_toml_data(uci), web_order)
end

function M.export_uci_to_toml(uci)
	local web = build_web_toml_data(uci)

	local ok, err = M.write_toml(M.TOML_FILE, web, web_order)
	if not ok then
		return nil, err
	end

	return web
end

function M.sync_toml_to_uci(uci)
	local web_section = ensure_section(uci, "vnt2", "vnt2_web")
	local web = M.read_toml(M.TOML_FILE, client_defaults)

	for toml_key, uci_key in pairs(web_option_map) do
		if is_list_key(toml_key) then
			if toml_key == "server" then
				set_uci_list(uci, "vnt2", web_section, uci_key, normalize_client_server_list(web[toml_key]))
			else
				set_uci_list(uci, "vnt2", web_section, uci_key, web[toml_key])
			end
		else
			set_uci_scalar(uci, "vnt2", web_section, uci_key, web[toml_key])
		end
	end
	uci:delete("vnt2", web_section, "no_tun")
	uci:delete("vnt2", web_section, "port")

	uci:save("vnt2")
	return web
end

function M.get_client_summary(uci)
	M.ensure_toml_file(uci)
	return M.read_toml(M.TOML_FILE, client_defaults)
end

function M.has_any_section(uci, config, stype)
	return uci:get_first(config, stype) ~= nil
end

return M
