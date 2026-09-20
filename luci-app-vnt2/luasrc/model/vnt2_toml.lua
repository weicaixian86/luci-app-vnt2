local fs = require "nixio.fs"
local util = require "luci.util"
local nixio = require "nixio"

local M = {}

M.DEFAULT_CLIENT_WEB_TOML = "/vnt_config/vnt2_cli_web.toml"
M.DEFAULT_CLIENT_TOML = M.DEFAULT_CLIENT_WEB_TOML
M.DEFAULT_WEB_TOML = M.DEFAULT_CLIENT_WEB_TOML
M.DEFAULT_SERVER_TOML = "/etc/config/vnts2.toml"
M.CLIENT_TOML = M.DEFAULT_CLIENT_TOML
M.WEB_TOML = M.DEFAULT_WEB_TOML
M.SERVER_TOML = M.DEFAULT_SERVER_TOML

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
	ctrl_port = "11233",
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

local server_defaults = {
	tcp_bind = "[::]:29872",
	quic_bind = "[::]:29872",
	ws_bind = "[::]:29872",
	web_bind = "[::]:29871",
	server_quic_bind = "",
	cert = "",
	key = "",
	network = "10.26.0.0/24",
	lease_duration = "86400",
	persistence = "1",
	username = "admin",
	password = "admin",
	server_token = "",
	white_list = {},
	peer_servers = {},
	custom_nets = {},
	ikev2 = {
		enabled = "0",
		ike_bind = "[::]:500",
		natt_bind = "[::]:4500",
		server_address = "",
		remote_id = "",
		cert = "",
		key = "",
		dns = {}
	},
	wireguard = {
		enabled = "0",
		bind = "[::]:51820",
		endpoint = "",
		private_key = "",
		persistent_keepalive = "25"
	}
}

local client_option_map = {
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
	ctrl_port = "ctrl_port",
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

local server_option_map = {
	tcp_bind = "tcp_bind",
	quic_bind = "quic_bind",
	ws_bind = "ws_bind",
	web_bind = "web_bind",
	server_quic_bind = "server_quic_bind",
	cert = "cert",
	key = "key",
	network = "network",
	lease_duration = "lease_duration",
	persistence = "persistence",
	username = "username",
	password = "password",
	server_token = "server_token",
	white_list = "white_list",
	peer_servers = "peer_servers",
	custom_nets = "custom_net"
}

local server_nested_option_map = {
	ikev2 = {
		enabled = "ikev2_enabled",
		ike_bind = "ikev2_ike_bind",
		natt_bind = "ikev2_natt_bind",
		server_address = "ikev2_server_address",
		remote_id = "ikev2_remote_id",
		cert = "ikev2_cert",
		key = "ikev2_key",
		dns = "ikev2_dns"
	},
	wireguard = {
		enabled = "wireguard_enabled",
		bind = "wireguard_bind",
		endpoint = "wireguard_endpoint",
		private_key = "wireguard_private_key",
		persistent_keepalive = "wireguard_persistent_keepalive"
	}
}

local client_order = {
	"network_code", "server", "peer_address", "turn", "punch_model", "ip", "device_id", "device_name", "password", "tun_name",
	"cert_mode", "mtu", "ctrl_port", "tunnel_port", "device_mode", "no_punch", "no_broadcast", "allow_ikev2", "allow_wireguard", "rtx", "compress",
	"fec", "no_nat", "allow_mapping", "subnet_mapping", "auto_sync_subnet", "outbound_interface", "tunnel_addr", "event_script",
	"input", "output", "port_mapping", "udp_stun", "tcp_stun"
}

local web_order = {
	"network_code", "server", "peer_address", "turn", "punch_model", "ip", "device_id", "device_name", "password", "tun_name",
	"cert_mode", "mtu", "tunnel_port", "device_mode", "no_punch", "no_broadcast", "allow_ikev2", "allow_wireguard", "rtx", "compress",
	"fec", "no_nat", "allow_mapping", "subnet_mapping", "auto_sync_subnet", "outbound_interface", "tunnel_addr", "event_script",
	"input", "output", "port_mapping", "udp_stun", "tcp_stun"
}

local server_order = {
	"tcp_bind", "quic_bind", "ws_bind", "web_bind", "server_quic_bind", "cert", "key", "network", "lease_duration",
	"persistence", "username", "password", "server_token", "white_list", "peer_servers", "custom_nets"
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
	tunnel_addr = true,
	white_list = true,
	peer_servers = true,
	custom_nets = true
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
	device_mode = false,
	ikev2_enabled = true,
	wireguard_enabled = true,
	persistence = true
}

local number_keys = {
	mtu = true,
	ctrl_port = true,
	tunnel_port = true,
	lease_duration = true
}

local required_string_keys = {
	network_code = true,
	tun_name = true,
	cert_mode = true,
	network = true
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

local function resolve_client_web_toml_path(uci)
	local client_path = trim(uci:get_first("vnt2", "vnt2_cli", "client_conf_file"))
	local web_path = trim(uci:get_first("vnt2", "vnt2_web", "web_conf_file"))
	local path = client_path

	if path == "" then
		path = web_path
	end
	if path == "" then
		path = M.DEFAULT_CLIENT_WEB_TOML
	end

	M.CLIENT_TOML = path
	M.WEB_TOML = path
	return path
end

local function resolve_client_toml_path(uci)
	return resolve_client_web_toml_path(uci)
end

local function resolve_web_toml_path(uci)
	return resolve_client_web_toml_path(uci)
end

local function resolve_server_toml_path(uci)
	local path = trim(uci:get_first("vnt2", "vnts2", "server_conf_file"))
	if path == "" then
		path = M.DEFAULT_SERVER_TOML
	end
	M.SERVER_TOML = path
	return path
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

local function encode_custom_nets(value)
	local vals = normalize_list(value)
	local lines = { "[custom_nets]" }
	local seen = {}

	for idx, item in ipairs(vals) do
		local code, cidr = item:match("^([^,]+),(.+)$")
		code = trim(code or ("net" .. idx))
		cidr = trim(cidr or item)
		if code ~= "" and cidr ~= "" and not seen[code] then
			seen[code] = true
			lines[#lines + 1] = string.format('"%s" = "%s"', toml_escape(code), toml_escape(cidr))
		end
	end

	return table.concat(lines, "\n")
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

local function encode_nested_value(section, key, value)
	if section == "ikev2" and key == "dns" then
		local parts = {}
		for _, item in ipairs(normalize_list(value)) do
			parts[#parts + 1] = '"' .. toml_escape(item) .. '"'
		end
		return "[" .. table.concat(parts, ", ") .. "]"
	end
	if key == "enabled" then
		return (trim(value) == "1" or trim(value) == "true") and "true" or "false"
	end
	if section == "wireguard" and key == "persistent_keepalive" then
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

local function parse_nested_value(section, key, raw)
	raw = trim(raw)
	if section == "ikev2" and key == "dns" then
		return parse_array(raw:match("^%[(.*)%]$") or "")
	end
	if key == "enabled" then
		return raw == "true" and "1" or "0"
	end
	local quoted = raw:match('^"(.*)"$')
	return quoted ~= nil and toml_unescape(quoted) or raw
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
					if current_section == "custom_nets" then
						data.custom_nets = data.custom_nets or {}
						-- custom_nets is a TOML table of named string values, not an array.
						key = toml_unescape(key)
						local value = raw:match('^"(.*)"$')
						if value ~= nil then
							value = toml_unescape(value)
						else
							value = raw
						end
						value = trim(value)
						key = trim(key)
						if key ~= "" and value ~= "" then
							data.custom_nets[#data.custom_nets + 1] = key .. "," .. value
						end
					elseif server_nested_option_map[current_section]
						and server_nested_option_map[current_section][key] then
						data[current_section] = data[current_section] or {}
						data[current_section][key] = parse_nested_value(current_section, key, raw)
						canonical_seen[current_section .. "." .. key] = true
					else
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
		if not fs.chmod(dir, 493) then
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
	if not fs.chmod(path, 384) then
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

			if key == "custom_nets" then
				value = normalize_list(value)
				if #lines > 0 and lines[#lines] ~= "" then
					lines[#lines + 1] = ""
				end
				lines[#lines + 1] = encode_custom_nets(value)
			else
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
	end

	if order == server_order then
		for _, section in ipairs({ "ikev2", "wireguard" }) do
			local nested = data[section] or {}
			if #lines > 0 and lines[#lines] ~= "" then
				lines[#lines + 1] = ""
			end
			lines[#lines + 1] = "[" .. section .. "]"
			local keys
			if section == "ikev2" then
				keys = { "enabled", "ike_bind", "natt_bind", "server_address", "remote_id", "cert", "key", "dns" }
			else
				keys = { "enabled", "bind", "endpoint", "private_key", "persistent_keepalive" }
			end
			for _, nested_key in ipairs(keys) do
				local value = nested[nested_key]
				if value ~= nil then
					local keep = nested_key == "enabled"
						or (section == "ikev2" and nested_key == "server_address")
						or (section == "ikev2" and nested_key == "remote_id")
						or (section == "ikev2" and nested_key == "dns")
						or (section == "wireguard" and nested_key == "persistent_keepalive")
						or trim(value) ~= ""
					if keep then
						lines[#lines + 1] = string.format("%s = %s", nested_key,
							encode_nested_value(section, nested_key, value))
					end
				end
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
	if not fs.chmod(temp, 384) then
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

function M.ensure_client_toml_from_uci(uci)
	local client_toml = resolve_client_toml_path(uci)
	local section = uci:get_first("vnt2", "vnt2_cli")

	if fs.access(client_toml) then
		return secure_existing_toml(client_toml)
	end

	local data = clone_defaults(client_defaults)
	for toml_key, uci_key in pairs(client_option_map) do
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

	return M.write_toml(client_toml, data, client_order)
end

function M.ensure_web_toml_from_uci(uci)
	local web_toml = resolve_web_toml_path(uci)
	local client_toml = resolve_client_toml_path(uci)
	local section = uci:get_first("vnt2", "vnt2_cli")

	if web_toml == client_toml then
		return M.ensure_client_toml_from_uci(uci)
	end

	if fs.access(web_toml) then
		return secure_existing_toml(web_toml)
	end

	local data = clone_defaults(client_defaults)
	data.ctrl_port = nil
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

	return M.write_toml(web_toml, data, web_order)
end

function M.ensure_server_toml_from_uci(uci)
	local server_toml = resolve_server_toml_path(uci)
	local section = uci:get_first("vnt2", "vnts2")

	if fs.access(server_toml) then
		return secure_existing_toml(server_toml)
	end

	local data = clone_defaults(server_defaults)
	for toml_key, uci_key in pairs(server_option_map) do
		if is_list_key(toml_key) then
			local val = section and uci:get_list("vnt2", section, uci_key) or data[toml_key]
			data[toml_key] = normalize_list(val)
		else
			local val = section and uci:get("vnt2", section, uci_key) or nil
			if val ~= nil then
				data[toml_key] = trim(val)
			end
		end
	end
	for nested_section, nested_map in pairs(server_nested_option_map) do
		local nested = data[nested_section] or {}
		for toml_key, uci_key in pairs(nested_map) do
			if toml_key == "dns" then
				local val = section and uci:get_list("vnt2", section, uci_key) or nil
				if val ~= nil then
					nested[toml_key] = normalize_list(val)
				end
			else
				local val = section and uci:get("vnt2", section, uci_key) or nil
				if val ~= nil then
					nested[toml_key] = trim(val)
				end
			end
		end
		data[nested_section] = nested
	end

	return M.write_toml(server_toml, data, server_order)
end

function M.ensure_toml_files(uci)
	local ok, err = M.ensure_client_toml_from_uci(uci)
	if not ok then
		return nil, err
	end
	ok, err = M.ensure_web_toml_from_uci(uci)
	if not ok then
		return nil, err
	end
	return M.ensure_server_toml_from_uci(uci)
end

function M.export_uci_to_toml(uci)
	local client_toml = resolve_client_toml_path(uci)
	local web_toml = resolve_web_toml_path(uci)
	local server_toml = resolve_server_toml_path(uci)
	local cli = clone_defaults(client_defaults)
	local web = clone_defaults(client_defaults)
	local server = clone_defaults(server_defaults)
	local cli_section = uci:get_first("vnt2", "vnt2_cli")
	local server_section = uci:get_first("vnt2", "vnts2")

	for toml_key, uci_key in pairs(client_option_map) do
		if is_list_key(toml_key) then
			if toml_key == "server" then
				cli[toml_key] = normalize_client_server_list(
					cli_section and uci:get_list("vnt2", cli_section, uci_key) or {}
				)
			else
				cli[toml_key] = normalize_list(cli_section and uci:get_list("vnt2", cli_section, uci_key) or {})
			end
		else
			local val = get_client_uci_value(uci, cli_section, uci_key)
			if val ~= nil then
				cli[toml_key] = trim(val)
			end
		end
	end

	for toml_key, uci_key in pairs(web_option_map) do
		if is_list_key(toml_key) then
			if toml_key == "server" then
				web[toml_key] = normalize_client_server_list(
					cli_section and uci:get_list("vnt2", cli_section, uci_key) or {}
				)
			else
				web[toml_key] = normalize_list(cli_section and uci:get_list("vnt2", cli_section, uci_key) or {})
			end
		else
			local val = get_client_uci_value(uci, cli_section, uci_key)
			if val ~= nil then
				web[toml_key] = trim(val)
			end
		end
	end
	web.ctrl_port = nil
	if #normalize_list(web.tunnel_addr) > 0 then
		web.tunnel_port = nil
	end

	for toml_key, uci_key in pairs(server_option_map) do
		if is_list_key(toml_key) then
			server[toml_key] = normalize_list(server_section and uci:get_list("vnt2", server_section, uci_key) or {})
		else
			local val = server_section and uci:get("vnt2", server_section, uci_key) or nil
			if val ~= nil then
				server[toml_key] = trim(val)
			end
		end
	end
	if #normalize_list(cli.tunnel_addr) > 0 then
		cli.tunnel_port = nil
	end
	for nested_section, nested_map in pairs(server_nested_option_map) do
		local nested = server[nested_section] or {}
		for toml_key, uci_key in pairs(nested_map) do
			if toml_key == "dns" then
				nested[toml_key] = normalize_list(server_section and uci:get_list("vnt2", server_section, uci_key) or {})
			else
				local val = server_section and uci:get("vnt2", server_section, uci_key) or nil
				if val ~= nil then
					nested[toml_key] = trim(val)
				end
			end
		end
		server[nested_section] = nested
	end

	local ok, err = M.write_toml(client_toml, cli, client_order)
	if not ok then
		return nil, err
	end
	if web_toml ~= client_toml then
		ok, err = M.write_toml(web_toml, web, web_order)
		if not ok then
			return nil, err
		end
	end
	ok, err = M.write_toml(server_toml, server, server_order)
	if not ok then
		return nil, err
	end

	return cli, web, server
end

function M.sync_toml_to_uci(uci)
	local cli_section = ensure_section(uci, "vnt2", "vnt2_cli")
	local server_section = ensure_section(uci, "vnt2", "vnts2")
	local client_toml = resolve_client_toml_path(uci)
	local server_toml = resolve_server_toml_path(uci)

	local cli = M.read_toml(client_toml, client_defaults)
	local server = M.read_toml(server_toml, server_defaults)

	for toml_key, uci_key in pairs(client_option_map) do
		if is_list_key(toml_key) then
			if toml_key == "server" then
				set_uci_list(uci, "vnt2", cli_section, uci_key, normalize_client_server_list(cli[toml_key]))
			else
				set_uci_list(uci, "vnt2", cli_section, uci_key, cli[toml_key])
			end
		else
			set_uci_scalar(uci, "vnt2", cli_section, uci_key, cli[toml_key])
		end
	end
	uci:delete("vnt2", cli_section, "no_tun")
	uci:delete("vnt2", cli_section, "port")

	for toml_key, uci_key in pairs(server_option_map) do
		if is_list_key(toml_key) then
			set_uci_list(uci, "vnt2", server_section, uci_key, server[toml_key])
		else
			set_uci_scalar(uci, "vnt2", server_section, uci_key, server[toml_key])
		end
	end
	for nested_section, nested_map in pairs(server_nested_option_map) do
		local nested = server[nested_section] or {}
		for toml_key, uci_key in pairs(nested_map) do
			if toml_key == "dns" then
				set_uci_list(uci, "vnt2", server_section, uci_key, nested[toml_key])
			else
				set_uci_scalar(uci, "vnt2", server_section, uci_key, nested[toml_key])
			end
		end
	end

	uci:save("vnt2")
	return cli, server
end

function M.get_client_summary(uci)
	local client_toml = resolve_client_toml_path(uci)
	M.ensure_toml_files(uci)
	return M.read_toml(client_toml, client_defaults)
end

function M.get_server_summary(uci)
	local server_toml = resolve_server_toml_path(uci)
	M.ensure_toml_files(uci)
	return M.read_toml(server_toml, server_defaults)
end

function M.has_any_section(uci, config, stype)
	return uci:get_first(config, stype) ~= nil
end

return M
