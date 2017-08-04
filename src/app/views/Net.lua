local net = require("framework.cc.net.init")
local ByteArray = require("framework.cc.utils.ByteArray")
require("framework.cc.utils.bit")

function scnet.init(  )
    local time = net.SocketTCP.getTime()
    print("socket time:" .. time)
    
    local socket = net.SocketTCP.new()
    socket:setName("HeroGameTcp")
    socket:setTickTime(1)
    socket:setReconnTime(6)
    socket:setConnFailTime(4)
    socket:addEventListener(net.SocketTCP.EVENT_DATA, scnet.receive)
    socket:addEventListener(net.SocketTCP.EVENT_CLOSE, scnet.tcpClose)
    socket:addEventListener(net.SocketTCP.EVENT_CLOSED, scnet.tcpClosed)
    socket:addEventListener(net.SocketTCP.EVENT_CONNECTED, scnet.tcpConnected)
    socket:addEventListener(net.SocketTCP.EVENT_CONNECT_FAILURE, scnet.error)
    scnet.socket = socket
end

function scnet.send( msgid,data )
    --  encodeData 此方法是根据需要发送的数据安装与服务器定义好的消息格式去write
    local _ba = scnet.encodeData(msgid,data) 
    _ba:setPos(1)
    -- local byteList = {}
    -- local byteCount = 0
    -- --把数据读出来，加密
    -- for i=1,#_ba._buf do
    --     local tmpBit = string.byte(_ba:readRawByte())
    --     byteCount = byteCount + tmpBit
    --     tmpBit = bit.band(tmpBit + 80,255)
    --     tmpBit = bit.band(bit.bnot(bit.band(tmpBit,255)),255)
    --     byteList[i] = tmpBit
    -- end

    -- byteCount = byteCount % 256
    --最后再组成一个新的ByteArray
    local result = ByteArray.new(ByteArray.ENDIAN_BIG)
    result:writeShort(_ba:getLen() + 3)
    result:writeByte(byteCount)
    for i=1,#byteList do
        result:writeByte(byteList[i])
    end
    -- 把数据发送给服务器
    scnet.socket:send(result:getPack())
end

function scnet.encodeData( msgid,data )
    if msgid then
        local ba = ByteArray.new(ByteArray.ENDIAN_BIG)
        local fmt = InfoUtil:getMsgFmt(msgid)  -- 此处为读取消息格式 看下面的MessageType里面会有定义
        ba:writeStringUShort("token")  -- 此处为用户token,没有就为""，此处可以判断用户是否重新登陆啊等等.......
        for i = 1 , #fmt do
            scnet.writeData(ba,fmt[i],data)
        end
        local baLength = ba:getLen()
        local bt = ByteArray.new(ByteArray.ENDIAN_BIG)
        bt:writeShort(baLength + 4)   -- 2为message length  2为message type
        bt:writeShort(msgid)
        bt:writeBytes(ba)
        return bt
    end
end


function scnet.writeData( ba,msg_type,data ) 
    local key = msg_type.key
    print("scnet.writeData","key",key)
    if key and data[key] then
        local _type = msg_type["fmt"]
        if type(_type) == "string" then
            if _type == "string" then
                ba:writeStringUShort(data[key])
            elseif _type == "number" then
                ba:writeLuaNumber(data[key])
            elseif _type == "int" then
                ba:writeInt(data[key])
            elseif _type == "short" then
                ba:writeShort(data[key])
            end
        else
            ba:writeShort(#data[key])
            for k,v in pairs(data[key]) do
                for i=1,#_type do
                    scnet.writeData(ba,_type[i],v)
                end
            end
        end
    else
        print("找不到对应的 key",msg_type.key,msg_type,data)
    end
end


function scnet.receive( event )
    local ba = ByteArray.new(ByteArray.ENDIAN_BIG)
    ba:writeBuf(event.data)
    ba:setPos(1)
    --  有连包的情况，所以要读取数据
    while ba:getAvailable() <= ba:getLen() do 
        scnet.decodeData(ba)
        if ba:getAvailable() == 0 then
            break
        end
    end
end

function scnet.decodeData( ba )
    local len = ba:readShort() -- 读数据总长度
    local total = ba:readByte() -- 一个用于验证的数子
    local byteList = {}
    local tmpTotal = 0
    for i=1,len - 3 do  -- 去除前两个长度
        local tmpBit = ba:readByte()
        local enByte = scnet.decodeByte(tmpBit)
        tmpTotal = tmpTotal + enByte
        byteList[i] = enByte
    end
 
    local result = ByteArray.new(ByteArray.ENDIAN_BIG)
    for i=1,#byteList do
        result:writeRawByte(string.char(byteList[i]))
    end
    result:setPos(1)
    if (tmpTotal % 256) == total then
        scnet.decodeMsg(result)
    else
        print("scnet.decodeData  total   error")
    end
end

function scnet.decodeMsg( byteArray )
    local rData = {}
    local len = byteArray:readShort()
    local msgid = byteArray:readShort()
    local roleString = byteArray:readStringUShort()
    local fmt = InfoUtil:getMsgFmt(msgid)
    for i=1,#fmt do
        scnet.readData(byteArray,fmt[i],rData)
    end
    if rData["result"] ~= 0 then
        print("result  handler is here  ",rData[key])
        return
    else
        NetManager:receiveMsg(msgid,rData)
    end
end

-- readData
function scnet.readData( ba,msg_type,data)
    local key = msg_type.key
    if key then
        data[key] = data[key] or {}
        local _type = msg_type["fmt"]
        if type(_type) == "string" then
            if _type == "string" then
                data[key] = ba:readStringUShort()
            elseif _type == "number" then
                data[key] = ba:readLuaNumber()
            elseif _type == "int" then
                data[key] = ba:readInt()
            elseif _type == "short" then
                data[key] = ba:readShort()
            end
    
            if key == "result" then  -- 当结果不为零的时候，说明有错误 
                if data[key] ~= 0 then
                    print("result  handler is here  ",data[key])
                    return
                end
            end 
        else
            local _len = ba:readShort() -- 读取数组长度
            for i=1,_len do
            local tmp = {}
            for j=1,#_type do
            scnet.readData(ba,_type[j],tmp)
            end
            table.insert(data[key],tmp)
            end
        end
    else
        print("找不到对应的 key  scnet.readData",msg_type.key,msg_type,data)
    end
end

function scnet.decodeByte( byte )
    local tmp = bit.band(bit.bnot(bit.band(byte,255)),255)
    tmp = bit.band((tmp + 256 - 80),255)
    return tmp
end


function Test()
    -- add background image
    display.newSprite("HelloWorld.png")
        :move(display.center)
        :addTo(self)

    -- add HelloWorld label
    cc.Label:createWithSystemFont("Hello World", "Arial", 40)
        :move(display.cx, display.cy + 200)
        :addTo(self)

    local loginSocket = socket.tcp()
    loginSocket:connect("localhost",7777)
    loginSocket:settimeout(0)
 --    loginSocket:send("Hello\n") 
 --    while true  do  
	--     local response, receive_status = loginSocket:receive("*l")  
	-- 	print("receive return:",response or "nil" ,receive_status or "nil")  
	-- 	if receive_status ~= "closed" then  
	-- 	    if response then  
	-- 	        print("receive:"..response)  
	-- 	    end  
	-- 	else  
	-- 	    break  
	-- 	end  
	-- end  
    local pbFilePath = cc.FileUtils:getInstance():fullPathForFilename("MsgProtocol.pb")
    release_print("PB file path: "..pbFilePath)
    
    local buffer = read_protobuf_file_c(pbFilePath)
    protobuf.register(buffer) --注:protobuf 是因为在protobuf.lua里面使用module(protobuf)来修改全局名字
    
    local stringbuffer = protobuf.encode("Person",      
        {      
            name = "Alice",      
            id = 12345,      
            phone = {      
                {      
                    number = "87654321"      
                },      
            }      
        })           
     
    local slen = string.len(stringbuffer)
    release_print("slen = "..slen)

    local result = ByteArray.new(ByteArray.ENDIAN_BIG)
    for i=1, slen do
        result:writeByte(string.byte(stringbuffer, i)) 
    end  

    local bt = ByteArray.new(ByteArray.ENDIAN_BIG) 
    bt:writeInt(1)   
    bt:writeInt(1)
    bt:writeInt(slen + 8) 
    for i=1, slen do
        bt:writeByte(string.byte(stringbuffer, i)) 
    end  
    bt:setPos(1)
    loginSocket:send(bt:getPack())

    -- local temp = ""
end

