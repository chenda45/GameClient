local LoginTcp = class("LoginTcp")
local Tcp = require("app.net.SocketTcp")
local ByteArray = require("app.utils.ByteArray")
function LoginTcp:ctor(ip,port) 
	local socket = Tcp.new()
	cc.load("event").new():bind(socket)
	socket:setName("LoginTcp")
	socket:setTickTime(0.01)
	socket:setReconnTime(6)
	socket:setConnFailTime(4)
	socket:addEventListener(Tcp.EVENT_DATA, handler(self,self.onReceiveData))
	socket:addEventListener(Tcp.EVENT_CLOSE, handler(self,self.onClose))
	socket:addEventListener(Tcp.EVENT_CLOSED,handler(self,self.onClosed))
	socket:addEventListener(Tcp.EVENT_CONNECTED, handler(self,self.onTcpConnected))
	socket:addEventListener(Tcp.EVENT_CONNECT_FAILURE, handler(self,self.onConnectError))
	self.socket = socket
	socket:connect(ip,port) 
end
  
function LoginTcp:onReceiveData(event)
	print("##############onReceiveData################") 
	local person = protobuf.decode("Person",event.data.body) 
 	dump(person)
end

function LoginTcp:decodeByte( byte )
    local tmp = bit.band(bit.bnot(bit.band(byte,255)),255)
    tmp = bit.band((tmp + 256 - 80),255)
    return tmp
end

function LoginTcp:onClose(event)
	print("##############onClose################")
end

function LoginTcp:onClosed(event)
	print("##############onClosed################")
end

function LoginTcp:onTcpConnected(event)
	print("##############onTcpConnected################")
	local pbFilePath = cc.FileUtils:getInstance():fullPathForFilename("MsgProtocol.pb")
    release_print("PB file path: "..pbFilePath)
    
    local buffer = read_protobuf_file_c(pbFilePath)
    protobuf.register(buffer) --注:protobuf 是因为在protobuf.lua里面使用module(protobuf)来修改全局名字

    local bt = self.socket:onEncodeData(1,1,"Person",{      
            name = "Alice",      
            id = 12345,      
            phone = {      
                {      
                    number = "87654321"      
                },      
            }      
        })  
    self.socket:send(bt:getPack())
end

function LoginTcp:onConnectError(event)
	print("##############onConnectError################")
end
 
return LoginTcp
