local fs = require "nixio.fs"
local util = require "luci.util"

local M = {}

M.CLIENT_TOML = "/etc/config/vnt2.toml"
M.SERVER_TOML = "/etc/config/vnts2.toml"

local client_defaults = {
	network_code = "123456",
	server = { "quic://101.35.230.139:6660" },
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
	tcp = "0.0.0.0:29872",
	quic = "0.0.0.0:29872",
	ws = "0.0.0.0:29872",
	web = "0.0.0.0:29871",
	quic_proxy = "",
	cert = "",
	key = "",
	network = "10.26.0.0/24",
	lease_duration = "86400",
	persistence = "1",
	username = "admin",
	password = "admin",
	token = "",
	white_token = {},
	server_address = {},
	cidr = {}
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
	tcp = "tcp_bind",
	quic = "quic_bind",
	ws = "ws_bind",
	web = "web_bind",
	quic_proxy = "server_quic_bind",
	cert = "cert",
	key = "key",
	network = "network",
	lease_duration = "lease_duration",
	persistence = "persistence",
	username = "username",
	password = "password",
	token = "server_token",
	white_token = "white_list",
	server_address = "peer_servers",
	cidr = "custom_net"
}

local client_order = {
	"network_code", "server", "ip", "device_id", "device_name", "password", "tun_name",
	"cert_mode", "mtu", "cmd_port", "port", "no_punch", "use_channel_type", "compressor",
	"use_fec", "no_proxy", "no_tun", "allow_wire_guard", "in_ips", "out_ips", "mapping",
	"stun_server", "stun_server_tcp"
}

local server_order = {
	"tcp", "quic", "ws", "web", "quic_proxy", "cert", "key", "network", "lease_duration",
	"persistence", "username", "password", "token", "white_token", "server_address", "cidr"
}

local list_keys = {
	server = true,
	in_ips = true,
	out_ips = true,
	mapping = true,
	stun_server = true,
	stun_server_tcp = true,
	white_token = true,
	server_address = true,
	cidr = true
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

	if not fs.access(path) then
		return data
	end

	local content = fs.readfile(path) or ""
	for line in content:gmatch("[^\r\n]+") do
		local clean = trim(line:gsub("#.*$", ""))
		if clean ~= "" then
			local key, raw = clean:match("^([%w_]+)%s*=%s*(.-)%s*$")
			if key then
				data[key] = parse_value(key, raw)
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
			lines[#lines + 1] = string.format("%s = %s", key, encode_value(key, value))
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
	if fs.access(M.CLIENT_TOML) then
		return
	end

	local data = clone_defaults(client_defaults)
	for toml_key, uci_key in pairs(client_option_map) do
		if is_list_key(toml_key) then
			local val = uci:get_list("vnt2", uci:get_first("vnt2", "vnt2_cli"), uci_key) or data[toml_key]
			data[toml_key] = normalize_list(val)
		else
			local val = uci:get_first("vnt2", "vnt2_cli", uci_key)
			if val ~= nil then
				data[toml_key] = trim(val)
			end
		end
	end

	M.write_toml(M.CLIENT_TOML, data, client_order)
end

function M.ensure_server_toml_from_uci(uci)
	if fs.access(M.SERVER_TOML) then
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

	M.write_toml(M.SERVER_TOML, data, server_order)
end

function M.ensure_toml_files(uci)
	M.ensure_client_toml_from_uci(uci)
	M.ensure_server_toml_from_uci(uci)
end

function M.export_uci_to_toml(uci)
	local cli = clone_defaults(client_defaults)
	local server = clone_defaults(server_defaults)

	for toml_key, uci_key in pairs(client_option_map) do
		if is_list_key(toml_key) then
			cli[toml_key] = normalize_list(uci:get_list("vnt2", uci:get_first("vnt2", "vnt2_cli"), uci_key))
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

	M.write_toml(M.CLIENT_TOML, cli, client_order)
	M.write_toml(M.SERVER_TOML, server, server_order)

	return cli, server
end

function M.sync_toml_to_uci(uci)
	local cli_section = ensure_section(uci, "vnt2", "vnt2_cli")
	local server_section = ensure_section(uci, "vnt2", "vnts2")

	local cli = M.read_toml(M.CLIENT_TOML, client_defaults)
	local server = M.read_toml(M.SERVER_TOML, server_defaults)

	for toml_key, uci_key in pairs(client_option_map) do
		if is_list_key(toml_key) then
			set_uci_list(uci, "vnt2", cli_section, uci_key, cli[toml_key])
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
	M.ensure_toml_files(uci)
	return M.read_toml(M.CLIENT_TOML, client_defaults)
end

function M.get_server_summary(uci)
	M.ensure_toml_files(uci)
	return M.read_toml(M.SERVER_TOML, server_defaults)
end

return M
