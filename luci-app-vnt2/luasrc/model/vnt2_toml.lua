local fs = require "nixio.fs"
local util = require "luci.util"

local M = {}

M.DEFAULT_CLIENT_TOML = "/etc/config/vnt2.toml"
M.DEFAULT_SERVER_TOML = "/etc/config/vnts2.toml"
M.CLIENT_TOML = M.DEFAULT_CLIENT_TOML
M.SERVER_TOML = M.DEFAULT_SERVER_TOML

local LEGACY_DEFAULT_CLIENT_SERVER = "tcp://0.0.0.0:29872"
local DEPRECATED_DEFAULT_CLIENT_SERVER = "tcp://0.0.0.0:29872"

local client_defaults = {
	network_code = "123456",
	server = { "tcp://0.0.0.0:29872" },
	ip = "",
	device_id = "",
	device_name = "",
	password = "",
	tun_name = "vnt-tun",
	cert_mode = "skip",
	mtu = "1400",
	cmd_port = "11233",
	port = "0",
	no_punch = "0",
	use_channel_type = "0",
	compressor = "0",
	use_fec = "0",
	no_proxy = "0",
	no_tun = "0",
	allow_wire_guard = "0",
	in_ips = {},
	out_ips = {},
	mapping = {},
	stun_server = {},
	stun_server_tcp = {}
}

local server_defaults = {
	tcp_bind = "0.0.0.0:29872",
	quic_bind = "0.0.0.0:29872",
	ws_bind = "0.0.0.0:29872",
	web_bind = "0.0.0.0:29871",
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
	custom_nets = {}
}

local client_option_map = {
	network_code = "network_code",
	server = "server",
	ip = "ip",
	device_id = "device_id",
	device_name = "device_name",
	password = "password",
	tun_name = "tun_name",
	cert_mode = "cert_mode",
	mtu = "mtu",
	cmd_port = "ctrl_port",
	port = "tunnel_port",
	no_punch = "no_punch",
	use_channel_type = "rtx",
	compressor = "compress",
	use_fec = "fec",
	no_proxy = "no_nat",
	no_tun = "no_tun",
	allow_wire_guard = "allow_mapping",
	in_ips = "input",
	out_ips = "output",
	mapping = "port_mapping",
	stun_server = "udp_stun",
	stun_server_tcp = "tcp_stun"
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
	white_list = "white_token",
	peer_servers = "server_address",
	custom_nets = "custom_net"
}

local client_order = {
	"network_code", "server", "ip", "device_id", "device_name", "password", "tun_name",
	"cert_mode", "mtu", "cmd_port", "port", "no_punch", "use_channel_type", "compressor",
	"use_fec", "no_proxy", "no_tun", "allow_wire_guard", "in_ips", "out_ips", "mapping",
	"stun_server", "stun_server_tcp"
}

local server_order = {
	"tcp_bind", "quic_bind", "ws_bind", "web_bind", "server_quic_bind", "cert", "key", "network", "lease_duration",
	"persistence", "username", "password", "server_token", "white_list", "peer_servers", "custom_nets"
}

local list_keys = {
	server = true,
	in_ips = true,
	out_ips = true,
	mapping = true,
	stun_server = true,
	stun_server_tcp = true,
	white_list = true,
	peer_servers = true,
	custom_nets = true
}

local bool_keys = {
	no_punch = true,
	use_channel_type = true,
	compressor = true,
	use_fec = true,
	no_proxy = true,
	no_tun = true,
	allow_wire_guard = true,
	persistence = true
}

local number_keys = {
	mtu = true,
	cmd_port = true,
	port = true,
	lease_duration = true
}

local required_string_keys = {
	network_code = true,
	tun_name = true,
	cert_mode = true,
	tcp_bind = true,
	quic_bind = true,
	ws_bind = true,
	web_bind = true,
	network = true,
	username = true
}

local function trim(v)
	return util.trim(tostring(v or ""))
end

local function resolve_client_toml_path(uci)
	local path = trim(uci:get_first("vnt2", "vnt2_cli", "client_conf_file"))
	if path == "" then
		path = M.DEFAULT_CLIENT_TOML
	end
	M.CLIENT_TOML = path
	return path
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
		if first == LEGACY_DEFAULT_CLIENT_SERVER or first == DEPRECATED_DEFAULT_CLIENT_SERVER then
			return {}
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
	inner = trim(inner)
	if inner == "" then
		return out
	end

	for item in inner:gmatch('"(.-)"') do
		out[#out + 1] = toml_unescape(item)
	end

	return out
end

local function encode_custom_nets(value)
	local vals = normalize_list(value)
	local lines = { "[custom_nets]" }

	for idx, item in ipairs(vals) do
		lines[#lines + 1] = string.format('net%d = "%s"', idx, toml_escape(item))
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
			local t = {}
			for _, item in ipairs(v) do
				t[#t + 1] = item
			end
			out[k] = t
		else
			out[k] = v
		end
	end
	return out
end

function M.read_toml(path, defaults)
	local data = clone_defaults(defaults or {})
	local current_section = ""

	if not fs.access(path) then
		return data
	end

	local content = fs.readfile(path) or ""
	for line in content:gmatch("[^\r\n]+") do
		local clean = trim(line:gsub("#.*$", ""))
		if clean ~= "" then
			local section = clean:match("^%[([%w_]+)%]$")
			if section then
				current_section = section
			else
				local key, raw = clean:match("^([%w_]+)%s*=%s*(.-)%s*$")
				if key then
					if current_section == "custom_nets" then
						data.custom_nets = data.custom_nets or {}
						local value = parse_value("custom_nets", raw)
						value = trim(value)
						if value ~= "" then
							data.custom_nets[#data.custom_nets + 1] = value
						end
					else
						data[key] = parse_value(key, raw)
					end
				end
			end
		end
	end

	return data
end

function M.write_toml(path, data, order)
	local lines = {}
	for _, key in ipairs(order) do
		local value = data[key]
		if value ~= nil then
			local keep = true

			if key == "custom_nets" then
				value = normalize_list(value)
				if #value > 0 then
					if #lines > 0 and lines[#lines] ~= "" then
						lines[#lines + 1] = ""
					end
					lines[#lines + 1] = encode_custom_nets(value)
				end
			else
				if not is_list_key(key) and not is_bool_key(key) and not is_number_key(key) then
					value = trim(value)
					if value == "" and not required_string_keys[key] then
						keep = false
					end
				end

				if keep then
					lines[#lines + 1] = string.format("%s = %s", key, encode_value(key, value))
				end
			end
		end
	end
	lines[#lines + 1] = ""
	fs.writefile(path, table.concat(lines, "\n"))
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

	if fs.access(client_toml) then
		return
	end

	local data = clone_defaults(client_defaults)
	for toml_key, uci_key in pairs(client_option_map) do
		if is_list_key(toml_key) then
			local val = uci:get_list("vnt2", uci:get_first("vnt2", "vnt2_cli"), uci_key) or data[toml_key]
			if toml_key == "server" then
				data[toml_key] = normalize_client_server_list(val)
			else
				data[toml_key] = normalize_list(val)
			end
		else
			local val = uci:get_first("vnt2", "vnt2_cli", uci_key)
			if val ~= nil then
				data[toml_key] = trim(val)
			end
		end
	end

	M.write_toml(client_toml, data, client_order)
end

function M.ensure_server_toml_from_uci(uci)
	local server_toml = resolve_server_toml_path(uci)

	if fs.access(server_toml) then
		return
	end

	local data = clone_defaults(server_defaults)
	for toml_key, uci_key in pairs(server_option_map) do
		if is_list_key(toml_key) then
			local val = uci:get_list("vnt2", uci:get_first("vnt2", "vnts2"), uci_key) or data[toml_key]
			data[toml_key] = normalize_list(val)
		else
			local val = uci:get_first("vnt2", "vnts2", uci_key)
			if val ~= nil then
				data[toml_key] = trim(val)
			end
		end
	end

	M.write_toml(server_toml, data, server_order)
end

function M.ensure_toml_files(uci)
	M.ensure_client_toml_from_uci(uci)
	M.ensure_server_toml_from_uci(uci)
end

function M.export_uci_to_toml(uci)
	local client_toml = resolve_client_toml_path(uci)
	local server_toml = resolve_server_toml_path(uci)
	local cli = clone_defaults(client_defaults)
	local server = clone_defaults(server_defaults)

	for toml_key, uci_key in pairs(client_option_map) do
		if is_list_key(toml_key) then
			if toml_key == "server" then
				cli[toml_key] = normalize_client_server_list(
					uci:get_list("vnt2", uci:get_first("vnt2", "vnt2_cli"), uci_key)
				)
			else
				cli[toml_key] = normalize_list(uci:get_list("vnt2", uci:get_first("vnt2", "vnt2_cli"), uci_key))
			end
		else
			local val = uci:get_first("vnt2", "vnt2_cli", uci_key)
			if val ~= nil then
				cli[toml_key] = trim(val)
			end
		end
	end

	for toml_key, uci_key in pairs(server_option_map) do
		if is_list_key(toml_key) then
			server[toml_key] = normalize_list(uci:get_list("vnt2", uci:get_first("vnt2", "vnts2"), uci_key))
		else
			local val = uci:get_first("vnt2", "vnts2", uci_key)
			if val ~= nil then
				server[toml_key] = trim(val)
			end
		end
	end

	M.write_toml(client_toml, cli, client_order)
	M.write_toml(server_toml, server, server_order)

	return cli, server
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

	for toml_key, uci_key in pairs(server_option_map) do
		if is_list_key(toml_key) then
			set_uci_list(uci, "vnt2", server_section, uci_key, server[toml_key])
		else
			set_uci_scalar(uci, "vnt2", server_section, uci_key, server[toml_key])
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

return M
