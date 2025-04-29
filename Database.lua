local component = require("component")
local internet = require("internet")
local json = require("json")
local serialization = require("serialization")

Database = {}

function Database:new(dbName)
    local obj = {
        dbName = dbName,
        baseUrl = "http://r-2-veteran.online/shop_api/",
        credentials = {
            username = "068004",
            password = "zZ53579"
        }
    }
    
    setmetatable(obj, self)
    self.__index = self
    return obj
end

local function sendRequest(self, endpoint, data)
    data = data or {}
    data.auth_user = self.credentials.username
    data.auth_pass = self.credentials.password
    
    local url = self.baseUrl .. endpoint
    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json"
    }
    
    local request, reason = internet.request(url, json.encode(data), headers)
    if not request then
        return nil, "HTTP request failed: " .. (reason or "unknown error")
    end
    
    local result = ""
    for chunk in request do
        result = result .. chunk
    end
    
    local success, response = pcall(json.decode, result)
    if not success then
        return nil, "JSON decode failed: " .. response
    end
    
    return response
end

function Database:select(query)
    local response, err = sendRequest(self, "player.php", {
        action = "get",
        player_id = query[1].value
    })
    
    if not response then
        return nil, err
    end
    
    if response.success then
        return {{
            _id = response.player_id,
            balance = tonumber(response.balance) or 0,
            items = response.items or {}
        }}
    else
        return {}
    end
end

function Database:insert(key, value)
    local response, err = sendRequest(self, "player.php", {
        action = "update",
        player_id = key,
        balance = value.balance,
        items = value.items
    })
    
    return response and response.success or false, err
end

function Database:update(key, value)
    return self:insert(key, value)
end

function Database:logTransaction(data)
    sendRequest(self, "transaction.php", {
        action = "log",
        transaction_data = data
    })
end

return Database