local component = require("component")
local itemUtils = require("ItemUtils")
local event = require("event")
local serialization = require("serialization")
local internet = require("internet")
local json = require("json")
local filesystem = require("filesystem")

ShopService = {}

-- Конфигурация HTTP API
local HTTP_API_CONFIG = {
    baseUrl = "http://r-2-veteran.online/www/r-2-veteran.online/shop_api/",
    endpoints = {
        player = "player.php",
        transaction = "transaction.php",
        item = "item.php"
    },
    credentials = {
        username = "068004",
        password = "zZ53579"
    }
}

-- Функция для безопасного логирования
local function logDebug(...)
    local args = {...}
    local message = ""
    for i, v in ipairs(args) do
        message = message .. (i > 1 and "\t" or "") .. tostring(v)
    end
    print("[DEBUG] " .. message)
end

-- Функция кодирования Base64
local function base64encode(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x) 
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i-1) > 0 and '1' or '0') end
        return r
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i,i) == '1' and 2^(6-i) or 0) end
        return b:sub(c+1, c+1)
    end)..({ '', '==', '=' })[#data % 3 + 1])
end

-- Улучшенная функция отправки HTTP запроса
local function sendHttpRequest(endpoint, data)
    local url = HTTP_API_CONFIG.baseUrl .. endpoint .. 
               "?auth_user=" .. HTTP_API_CONFIG.credentials.username ..
               "&auth_pass=" .. HTTP_API_CONFIG.credentials.password
    
    logDebug("Sending request to:", url)
    logDebug("Request data:", serialization.serialize(data))
    
    local request, reason = internet.request(url, json.encode(data), {
        ["Content-Type"] = "application/json",
        ["User-Agent"] = "OCShopSystem/1.0"
    })
    
    if not request then
        logDebug("HTTP request failed:", reason)
        return {success = false, error = "HTTP request failed: " .. (reason or "unknown reason")}
    end
    
    local result = ""
    for chunk in request do
        result = result .. chunk
    end
    
    logDebug("Raw response:", result)
    
    local success, response = pcall(json.decode, result)
    if not success then
        logDebug("JSON decode failed:", response)
        return {success = false, error = "JSON decode failed: " .. response}
    end
    
    if not response.success then
        logDebug("Server returned error:", response.error or "Unknown error")
        return {success = false, error = response.error or "Unknown error"}
    end
    
    return response
end

-- Функция чтения файла конфигурации
local function readObjectFromFile(path)
    if not filesystem.exists(path) then
        logDebug("File not found:", path)
        return nil
    end
    
    local file = io.open(path, "r")
    if not file then
        logDebug("Failed to open file:", path)
        return nil
    end
    
    local content = file:read("*a")
    file:close()
    
    local success, obj = pcall(serialization.unserialize, content)
    if not success then
        logDebug("Failed to unserialize content from file:", path)
        return nil
    end
    
    return obj
end

function ShopService:new(terminalName)
    local obj = {}
    
    function obj:init()
        self.terminalName = terminalName or "Unknown"
        
        -- Создаем папку USERS если ее нет
        if not filesystem.exists("/home/USERS") then
            filesystem.makeDirectory("/home/USERS")
            logDebug("Created USERS directory")
        end
        
        -- Загрузка конфигураций
        self.oreExchangeList = readObjectFromFile("/home/config/oreExchanger.cfg") or {}
        self.exchangeList = readObjectFromFile("/home/config/exchanger.cfg") or {}
        self.sellShopList = readObjectFromFile("/home/config/sellShop.cfg") or {}
        self.buyShopList = readObjectFromFile("/home/config/buyShop.cfg") or {}

        -- Настройка валюты
        self.currencies = {
            {item = {name = "minecraft:gold_nugget", damage = 0}, money = 1000},
            {item = {name = "minecraft:gold_ingot", damage = 0}, money = 10000},
            {item = {name = "minecraft:diamond", damage = 0}, money = 100000},
            {item = {name = "minecraft:emerald", damage = 0}, money = 1000000}
        }

        itemUtils.setCurrency(self.currencies)
    end

    -- Основные методы магазина
    
    function obj:getOreExchangeList()
        return self.oreExchangeList
    end

    function obj:getExchangeList()
        return self.exchangeList
    end

    function obj:getSellShopList(category)
        local categorySellShopList = {}
        for i, sellConfig in pairs(self.sellShopList) do
            if sellConfig.category == category then
                table.insert(categorySellShopList, sellConfig)
            end
        end
        itemUtils.populateCount(categorySellShopList)
        return categorySellShopList
    end

    function obj:getBuyShopList()
        itemUtils.populateUserCount(self.buyShopList)
        return self.buyShopList
    end

    function obj:getBalance(nick)
        local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
            action = "get",
            player_id = nick
        })
        
        if response and response.success then
            return response.balance or 0
        end
        return 0
    end

    function obj:depositMoney(nick, count)
        local countOfMoney = itemUtils.takeMoney(count)
        if countOfMoney > 0 then
            local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
                action = "update",
                player_id = nick,
                data = {balance = countOfMoney}
            })
            
            if response and response.success then
                logDebug("Deposited money:", countOfMoney)
                return countOfMoney, "Баланс пополнен на " .. countOfMoney
            end
        end
        return 0, "Нет монет в инвентаре!"
    end

    function obj:withdrawMoney(nick, count)
        local playerData = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
            action = "get",
            player_id = nick
        })
        
        if not playerData or playerData.balance < count then
            return 0, "Не хватает денег на счету"
        end
        
        local countOfMoney = itemUtils.giveMoney(count)
        if countOfMoney > 0 then
            local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
                action = "update",
                player_id = nick,
                data = {balance = -countOfMoney}
            })
            
            if response and response.success then
                logDebug("Withdrew money:", countOfMoney)
                return countOfMoney, "Снято с баланса: " .. countOfMoney
            end
        end
        return 0, "Не удалось выдать деньги"
    end

    function obj:buyItem(nick, itemCfg, count)
        logDebug("Attempting to buy:", itemCfg.id, count)
        local itemsCount = itemUtils.takeItem(itemCfg.id, itemCfg.dmg, count)
        
        if itemsCount > 0 then
            local totalPrice = itemsCount * itemCfg.price
            local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
                action = "update",
                player_id = nick,
                data = {balance = totalPrice}
            })
            
            if response and response.success then
                logDebug("Sold items:", itemsCount)
                return itemsCount, "Продано " .. itemsCount .. " предметов"
            end
        end
        return 0, "Не удалось продать предметы"
    end

    function obj:sellItem(nick, itemCfg, count)
        local playerData = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
            action = "get",
            player_id = nick
        })
        
        if not playerData or playerData.balance < count * itemCfg.price then
            return 0, "Не хватает денег на счету"
        end
        
        local itemsCount = itemUtils.giveItem(itemCfg.id, itemCfg.dmg, count)
        if itemsCount > 0 then
            local totalCost = itemsCount * itemCfg.price
            local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
                action = "update",
                player_id = nick,
                data = {balance = -totalCost}
            })
            
            if response and response.success then
                logDebug("Bought items:", itemsCount)
                return itemsCount, "Куплено " .. itemsCount .. " предметов"
            end
        end
        return 0, "Не удалось купить предметы"
    end

    -- Инициализация
    obj:init()
    setmetatable(obj, self)
    self.__index = self
    return obj
end

return ShopService