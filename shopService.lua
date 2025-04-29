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

-- Функция преобразования в число
local function toNumber(value)
    if type(value) == "number" then
        return value
    end
    return tonumber(value) or 0
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
    
    return response or {success = false, error = "Invalid server response"}
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
    
    function obj:getPlayerData(nick)
        local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
            action = "get",
            player_id = nick
        })
        
        if response and response.success then
            response.balance = toNumber(response.balance)
            return response
        end
        return {balance = 0, items = {}}
    end

    function obj:getBalance(nick)
        local playerData = self:getPlayerData(nick)
        return playerData.balance
    end

    function obj:depositMoney(nick, count)
        local countOfMoney = itemUtils.takeMoney(count)
        if countOfMoney > 0 then
            -- Логируем транзакцию
            sendHttpRequest(HTTP_API_CONFIG.endpoints.transaction, {
                player_id = nick,
                transaction_type = "deposit",
                amount = countOfMoney,
                timestamp = os.time()
            })
            
            -- Обновляем баланс
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
        local playerData = self:getPlayerData(nick)
        if playerData.balance < count then
            return 0, "Не хватает денег на счету"
        end
        
        local countOfMoney = itemUtils.giveMoney(count)
        if countOfMoney > 0 then
            -- Логируем транзакцию
            sendHttpRequest(HTTP_API_CONFIG.endpoints.transaction, {
                player_id = nick,
                transaction_type = "withdraw",
                amount = countOfMoney,
                timestamp = os.time()
            })
            
            -- Обновляем баланс
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
        logDebug("Attempting to sell:", itemCfg.id, count)
        local itemsCount = itemUtils.takeItem(itemCfg.id, itemCfg.dmg, count)
        
        if itemsCount > 0 then
            local totalPrice = itemsCount * itemCfg.price
            
            -- Логируем транзакцию
            sendHttpRequest(HTTP_API_CONFIG.endpoints.transaction, {
                player_id = nick,
                transaction_type = "sell_item",
                item_id = itemCfg.id,
                item_dmg = itemCfg.dmg,
                item_name = itemCfg.label,
                quantity = itemsCount,
                amount = totalPrice,
                timestamp = os.time()
            })
            
            -- Обновляем баланс
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
        local playerData = self:getPlayerData(nick)
        local totalCost = count * itemCfg.price
        
        if playerData.balance < totalCost then
            return 0, "Не хватает денег на счету"
        end
        
        local itemsCount = itemUtils.giveItem(itemCfg.id, itemCfg.dmg, count)
        if itemsCount > 0 then
            -- Логируем транзакцию
            sendHttpRequest(HTTP_API_CONFIG.endpoints.transaction, {
                player_id = nick,
                transaction_type = "buy_item",
                item_id = itemCfg.id,
                item_dmg = itemCfg.dmg,
                item_name = itemCfg.label,
                quantity = itemsCount,
                amount = totalCost,
                timestamp = os.time()
            })
            
            -- Обновляем баланс
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