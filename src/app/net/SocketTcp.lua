local socket = require "socket"
local scheduler = require("app.utils.scheduler") 
local ByteArray = require("app.utils.ByteArray")


local SOCKET_TICK_TIME 				= 0.1		-- check socket data interval
local SOCKET_RECONNECT_TIME 		= 5			-- socket reconnect try interval
local SOCKET_CONNECT_FAIL_TIMEOUT 	= 3			-- socket failure timeout 

local STATUS_CLOSED 				= "closed" 						   	 
local STATUS_TIMEOUT 				= "timeout" 						 
local STATUS_NOT_CONNECTED 			= "Socket is not connected"
local STATUS_ALREADY_CONNECTED 		= "already connected"
local STATUS_ALREADY_IN_PROGRESS 	= "Operation already in progress"

local SocketTCP = class("SocketTCP") 

SocketTCP.EVENT_DATA 				= "SOCKET_TCP_DATA"
SocketTCP.EVENT_CLOSE 				= "SOCKET_TCP_CLOSE"
SocketTCP.EVENT_CLOSED 				= "SOCKET_TCP_CLOSED"
SocketTCP.EVENT_CONNECTED 			= "SOCKET_TCP_CONNECTED"
SocketTCP.EVENT_CONNECT_FAILURE 	= "SOCKET_TCP_CONNECT_FAILURE"

SocketTCP._DEBUG 	= socket._DEBUG
SocketTCP._VERSION 	= socket._VERSION
 
function SocketTCP.getTime()
	return socket.gettime()
end

function SocketTCP:ctor(__host, __port, __retryConnect)
    self.host = __host 						--连接地址
    self.port = __port 						--连接端口
	self.tcp = nil 							--当前tcp连接
	self.name = 'SocketTCP'  				--当前连接名字
	self.tickScheduler = nil				--检查数据接收schedule
	self.reconnectScheduler = nil			--重连schedule
	self.connectTimeTickScheduler = nil		--超时
	self.isRetryConnect = __retryConnect 	--失败是否自动重连
	self.isConnected = false 				--是否已经连接标识
end

--[[
	设置当前连接名字
]]--
function SocketTCP:setName( __name )
	self.name = __name
	return self
end

--[[
	设置检测数据间隔时间
]]--
function SocketTCP:setTickTime(__time)
	SOCKET_TICK_TIME = __time
	return self
end

--[[
	设置重连时间
]]--
function SocketTCP:setReconnTime(__time)
	SOCKET_RECONNECT_TIME = __time
	return self
end

--[[
	设置连接失败超时时间
]]--
function SocketTCP:setConnFailTime(__time)
	SOCKET_CONNECT_FAIL_TIMEOUT = __time
	return self
end

--[[
	连接
]]--
function SocketTCP:connect(__host, __port, __retryConnectWhenFailure)
	if __host then self.host = __host end
	if __port then self.port = __port end
	if __retryConnectWhenFailure ~= nil then self.isRetryConnect = __retryConnectWhenFailure end
	assert(self.host or self.port, "Host and port are necessary!") 
	self.tcp = socket.tcp()
	self.tcp:settimeout(0)

	local function __checkConnect()
		local __succ = self:_connect()
		if __succ then
			self:_onConnected()
		end
		return __succ
	end

	if not __checkConnect() then
		-- check whether connection is success
		-- the connection is failure if socket isn't connected after SOCKET_CONNECT_FAIL_TIMEOUT seconds
		local __connectTimeTick = function ()
			--printInfo("%s.connectTimeTick", self.name)
			if self.isConnected then return end
			self.waitConnect = self.waitConnect or 0
			self.waitConnect = self.waitConnect + SOCKET_TICK_TIME
			if self.waitConnect >= SOCKET_CONNECT_FAIL_TIMEOUT then
				self.waitConnect = nil
				self:close()
				self:_connectFailure()
			end
			__checkConnect()
		end
		self.connectTimeTickScheduler = scheduler.scheduleGlobal(__connectTimeTick, SOCKET_TICK_TIME)
	end
end

--[[
	发送消息
]]--
function SocketTCP:send(__data)
	assert(self.isConnected, self.name .. " is not connected.")
	self.tcp:send(__data)
end

--[[
	关闭连接
]]--
function SocketTCP:close( ... ) 
	self.tcp:close();
	if self.connectTimeTickScheduler then scheduler.unscheduleGlobal(self.connectTimeTickScheduler) end
	if self.tickScheduler then scheduler.unscheduleGlobal(self.tickScheduler) end
	self:dispatchEvent({name=SocketTCP.EVENT_CLOSE})
end
 
--[[
	断开连接不重连
]]--
function SocketTCP:disconnect()
	self:_disconnect()
	self.isRetryConnect = false -- initiative to disconnect, no reconnect.
end

--[[
	编译数据
	@typeId 类型ID
	@msgId 消息ID
	@model 对应的消息类protobuf模型
	@data  对应的消息
]]--
function SocketTCP:onEncodeData(typeId,msgId,model,data)
	local _data = protobuf.encode(model,data)  --编译成protobuf
	--长度
	local len = string.len( _data ) 		
    local bt = ByteArray.new(ByteArray.ENDIAN_BIG) 
    bt:writeInt(typeId)   
    bt:writeInt(msgId)
    bt:writeInt(len + 8) 
    for i=1, len do
        bt:writeByte(string.byte(_data, i)) 
    end  
    bt:setPos(1)
	return bt
end

function SocketTCP:onDecodeData(data)
	local ba = ByteArray.new(ByteArray.ENDIAN_BIG)
	ba:writeBuf(data)
	ba:setPos(1)
	--  有连包的情况，所以要读取数据
	while ba:getAvailable() <= ba:getLen() do 
		local typeId = ba:readInt()  
		local msgId = ba:readInt() 
		local length = ba:readInt()
		local body = ba:readString(length - 8)   
		if ba:getAvailable() == 0 then
			return {typeId = typeId,msgId = msgId,length = length ,body = body}
		end
	end
end

--------------------
-- private
--------------------

--- When connect a connected socket server, it will return "already connected"
-- @see: http://lua-users.org/lists/lua-l/2009-10/msg00584.html

function SocketTCP:_connect()
	local __succ, __status = self.tcp:connect(self.host, self.port)
	-- print("SocketTCP._connect:", __succ, __status)
	return __succ == 1 or __status == STATUS_ALREADY_CONNECTED
end

function SocketTCP:_disconnect()
	self.isConnected = false
	self.tcp:shutdown()
	self:dispatchEvent({name=SocketTCP.EVENT_CLOSED})
end

function SocketTCP:_onDisconnect() 
	self.isConnected = false
	self:dispatchEvent({name=SocketTCP.EVENT_CLOSED})
	self:_reconnect();
end

-- connecte success, cancel the connection timerout timer
function SocketTCP:_onConnected() 
	self.isConnected = true
	self:dispatchEvent({name=SocketTCP.EVENT_CONNECTED})
	if self.connectTimeTickScheduler then scheduler.unscheduleGlobal(self.connectTimeTickScheduler) end

	local __tick = function()
		while true do
			-- if use "*l" pattern, some buffer will be discarded, why?
			local __body, __status, __partial = self.tcp:receive("*a")	-- read the package body  
    	    if __status == STATUS_CLOSED or __status == STATUS_NOT_CONNECTED then
		    	self:close()
		    	if self.isConnected then
		    		self:_onDisconnect()
		    	else
		    		self:_connectFailure()
		    	end
		   		return
	    	end
		    if 	(__body and string.len(__body) == 0) or
				(__partial and string.len(__partial) == 0)
			then return end
			if __body and __partial then 
				__body = __body .. __partial 
			end
			local data = self:onDecodeData( __partial or __body )
			self:dispatchEvent({name=SocketTCP.EVENT_DATA, data = data, partial=__partial, body=__body})
		end
	end 
	-- start to read TCP data
	self.tickScheduler = scheduler.scheduleGlobal(__tick, SOCKET_TICK_TIME)
end

function SocketTCP:_connectFailure(status) 
	self:dispatchEvent({name=SocketTCP.EVENT_CONNECT_FAILURE})
	self:_reconnect();
end

-- if connection is initiative, do not reconnect
function SocketTCP:_reconnect(__immediately)
	if not self.isRetryConnect then return end 
	if __immediately then self:connect() return end
	if self.reconnectScheduler then scheduler.unscheduleGlobal(self.reconnectScheduler) end
	local __doReConnect = function ()
		self:connect()
	end
	self.reconnectScheduler = scheduler.performWithDelayGlobal(__doReConnect, SOCKET_RECONNECT_TIME)
end

return SocketTCP
