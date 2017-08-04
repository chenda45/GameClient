
local MainScene = class("MainScene", cc.load("mvc").ViewBase) 
local ByteArray = require("app.utils.ByteArray")
function MainScene:onCreate()
     local tcp = require("app.net.LoginTcp").new("localhost",7777)
end

return MainScene
