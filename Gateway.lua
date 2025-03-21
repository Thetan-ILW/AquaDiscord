local class = require("class")

local Request = require("aqua.web.http.Request")
local Response = require("aqua.web.http.Response")
local Websocket = require("aqua.web.ws.Websocket")
local HttpClient = require("aqua.web.http.HttpClient")
local LsTcpSocket = require("aqua.web.luasocket.LsTcpSocket")

local copas = require("copas")
local socket = require("socket")
local socket_url = require("socket.url")
local json = require("cjson")

local Opcode = require("discord.GatewayOpcode")

---@alias discord.Gateway.State
---| "not_authorized"
---| "ready"

---@class discord.Gateway
---@overload fun(bot_token: string, intents: discord.Gateway.Intents): discord.Gateway
---@field state discord.Gateway.State
---@field resumeGatewayUrl string?
---@field sessionId integer?
---@field sequence integer? Last sequence number from `d` field in payloads
local Gateway = class()

---@class discord.Gateway.Payload
---@field op discord.Gateway.Opcode Gateway opcode, which indicates the payload type
---@field s integer? Sequence number of event used for resuming sessions and heartbeating. Nil when opcode is not `Opcode.Dispatch`
---@field t string? Event name. Nil when opcode is not `Opcode.Dispatch`
---@field d {[string]: any}? Event data

---@class discord.Gateway.GatewayMetadata.SessionStartLimit
---@field total integer Total number of session starts the current user is allowed
---@field remaining integer Remaining number of session starts the current user is allowed
---@field reset_after integer Number of milliseconds after which the limit resets
---@field max_concurrency integer Number of identify requests allowed per 5 seconds

---@class discord.Gateway.GatewayMetadata
---@field url string WSS URL that can be used for connecting to the Gateway
---@field shards integer Recommended number of shards to use when connecting
---@field session_start_limit discord.Gateway.GatewayMetadata.SessionStartLimit

Gateway.sslParams = {
	wrap = {
		mode = "client",
		protocol = "any",  -- not really secure...
	},
}

---@param bot_token string
---@param intents discord.Gateway.Intents
function Gateway:new(bot_token, intents)
	self.botToken = bot_token
	self.intents = intents
	self.state = "not_authorized"
	self.heartbeatInterval = math.huge
	self.nextHeartbeatTime = math.huge
	self.heartbeats = 0
	self.heartbeatAcks = 0
	self.eventBindings = {}
end

---@param object table
---@param method function
---@param event_name string
function Gateway:bindEvent(object, method, event_name)

end

---@return discord.Gateway.GatewayMetadata?
---@return string? error
function Gateway:getGatewayMetadata()
	local soc = LsTcpSocket()
	local http_client = HttpClient(soc)
	http_client.headers:add("Authorization", ("Bot %s"):format(self.botToken))
	http_client.headers:add("Content-Type", "application/json")

	local req, res = http_client:connect("https://discord.com/api/v10/gateway/bot")
	req:send("")

	local text = res:receive("*a")
	local decoded = json.decode(text)

	if decoded.url then
		return decoded, nil
	end

	return nil, decoded.message or text or "Can't get gateway metadata."
end

---@private
---@return web.Websocket
function Gateway:connect(host, port)
	local sock = copas.wrap(socket.tcp(), self.sslParams)
	copas.setsocketname("my_TCP_client", sock)

	local parsed_url = socket_url.parse(host, {
		path = "/",
		scheme = "ws",
	})

	assert(sock:connect(parsed_url.host, port))

	local req = Request(sock)

	req.uri = socket_url.build({
		path = parsed_url.path,
		params = parsed_url.params,
		query = parsed_url.query,
	})

	req.headers:set("Host", parsed_url.host)
	local res = Response(sock)

	return Websocket(sock, req, res, "client")
end

-- Connects to the server and starts copas threads
function Gateway:start()
	copas.addthread(function ()
		local metadata, err = self:getGatewayMetadata()

		if not metadata then
			print(err)
			return
		end

		self.ws = self:connect(
			metadata.url .. "/?v=10&encoding=json",
			443
		)

		function self.ws.protocol.text(_, payload)
			print(payload)
			self:handleEvent(json.decode(payload))
		end

		assert(self.ws:handshake())
		assert(self.ws:loop())
		print("Loop stopped")
		self:stop()
	end)

	copas.addthread(function ()
		while true do
			if copas.exiting() then
				return
			end

			self:heartbeat()
			copas.step()
		end
	end)

	copas()
	print("Threads stopped")
end

function Gateway:stop()
	self.ws:send_close()
	copas.exit()
end

---@param opcode discord.Gateway.Opcode
---@param data {[string]: any}?
function Gateway:send(opcode, data)
	local t = {}
	t.op = opcode
	t.d = data or {}
	t.d.s = self.sequence
	self.ws:send("text", json.encode(t))
end

---@param event discord.Gateway.Payload
---@private
function Gateway:handleEvent(event)
	local op = event.op

	if self.state == "not_authorized" then
		if op == Opcode.Hello then
			self.heartbeatInterval = event.d.heartbeat_interval * 0.001
			self.nextHeartbeatTime = copas.gettime() + (self.heartbeatInterval * math.random())
		elseif op == Opcode.HeartbeatAck then
			self.heartbeatAcks = self.heartbeatAcks + 1
			self:send(Opcode.Identify, {
				token = self.botToken,
				intents = self.intents,
				properties = {
					os = "linux",
					browser = "this_is_why_lua_is_better",
					device = "this_is_why_lua_is_better",
				}
			})
		elseif op == Opcode.Dispatch then
			if event.t ~= "READY" then
				print("Failed to authorize.")
				self:stop()
				return
			end

			self.state = "ready"
			self.resumeGatewayUrl = event.d.resume_gateway_url
			self.sessionId = event.d.session_id
		else
			print(("[%s][%i] Unknown opcode"):format(self.state, op))
		end
	elseif self.state == "ready" then
		if op == Opcode.HeartbeatAck then
			self.heartbeatAcks = self.heartbeatAcks + 1
		end
	end
end

---@private
function Gateway:heartbeat()
	local current_time = copas.gettime()
	if current_time < self.nextHeartbeatTime then
		return
	end

	if self.heartbeats ~= self.heartbeatAcks then
		print("Not receiving heartbeat ACKs, reconnecting.")
		self:stop()
		return
	end

	self:send(Opcode.Heartbeat)
	self.nextHeartbeatTime = current_time + self.heartbeatInterval
	self.heartbeats = self.heartbeats + 1
end

return Gateway
