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
local function readConfigFile(path)
    if not filesystem.exists(path) then
        logDebug("File not found:", path)
        return {}
    end
    
    local file = io.open(path, "r")
    if not file then
        logDebug("Failed to open file:", path)
        return {}
    end
    
    local content = file:read("*a")
    file:close()
    
    -- Обработка конфигурационных файлов
    if path:find("sellShop.cfg") or path:find("buyShop.cfg") then
        local success, result = pcall(serialization.unserialize, content)
        if not success then
            logDebug("Failed to unserialize content from file:", path)
            return {}
        end
        return result
    end
    
    return {}
end

-- Функция преобразования формата предметов
local function convertItemFormat(item)
    return {
        id = item.id,
        dmg = item.dmg or 0,
        price = item.price or 0,
        label = item.label or item.id,
        category = item.category or "default",
        nbt = item.nbt
    }
end

function ShopService:new(terminalName)
    local obj = {}
    
    function obj:init()
        self.terminalName = terminalName or "Unknown"
        
        -- Загрузка конфигураций
        self.sellShopList = self:loadConfig("/home/config/sellShop.cfg")
        self.buyShopList = self:loadConfig("/home/config/buyShop.cfg")
        
        -- Настройка валюты
        self.currencies = {
            {item = {name = "minecraft:gold_nugget", damage = 0}, money = 1000},
            {item = {name = "minecraft:gold_ingot", damage = 0}, money = 10000},
            {item = {name = "minecraft:diamond", damage = 0}, money = 100000},
            {item = {name = "minecraft:emerald", damage = 0}, money = 1000000}
        }

        if itemUtils and itemUtils.setCurrency then
            itemUtils.setCurrency(self.currencies)
        end
    end

    -- Функция загрузки конфига
    function obj:loadConfig(path)
        local config = readConfigFile(path) or {}
        local converted = {}
        
        for _, item in ipairs(config) do
            table.insert(converted, convertItemFormat(item))
        end
        
        return converted
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

    function obj:getSellShopList(category)
        if not self.sellShopList or #self.sellShopList == 0 then
            self.sellShopList = self:loadConfig("/home/config/sellShop.cfg")
        end
        
        local filtered = {}
        for _, item in ipairs(self.sellShopList) do
            if not category or item.category == category then
                table.insert(filtered, item)
            end
        end
        
        if itemUtils and itemUtils.populateCount then
            itemUtils.populateCount(filtered)
        end
        
        return filtered
    end

    function obj:getBuyShopList(category)
        if not self.buyShopList or #self.buyShopList == 0 then
            self.buyShopList = self:loadConfig("/home/config/buyShop.cfg")
        end
        
        local filtered = {}
        for _, item in ipairs(self.buyShopList) do
            if not category or item.category == category then
                table.insert(filtered, item)
            end
        end
        
        if itemUtils and itemUtils.populateUserCount then
            itemUtils.populateUserCount(filtered)
        end
        
        return filtered
    end

    function obj:depositMoney(nick, count)
        if not itemUtils or not itemUtils.takeMoney then
            return 0, "ItemUtils not properly initialized"
        end
        
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
            else
                itemUtils.giveMoney(countOfMoney)
                return 0, "Ошибка при пополнении баланса"
            end
        end
        return 0, "Нет монет в инвентаре!"
    end

    function obj:withdrawMoney(nick, count)
        local playerData = self:getPlayerData(nick)
        if playerData.balance < count then
            return 0, "Не хватает денег на счету"
        end
        
        if not itemUtils or not itemUtils.giveMoney then
            return 0, "ItemUtils not properly initialized"
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

    function obj:sellItem(nick, itemCfg, count)
        if not itemUtils or not itemUtils.takeItem then
            return 0, "ItemUtils not properly initialized"
        end
        
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
            else
                itemUtils.giveItem(itemCfg.id, itemCfg.dmg, itemsCount)
                return 0, "Ошибка при обновлении баланса"
            end
        end
        return 0, "Не удалось продать предметы"
    end

    function obj:buyItem(nick, itemCfg, count)
        local playerData = self:getPlayerData(nick)
        local totalCost = count * itemCfg.price
        
        if playerData.balance < totalCost then
            return 0, "Не хватает денег на счету"
        end
        
        if not itemUtils or not itemUtils.giveItem then
            return 0, "ItemUtils not properly initialized"
        end
        
        local itemsCount = itemUtils.giveItem(itemCfg.id, itemCfg.dmg, count)
        if itemsCount > 0 then
            -- Логируем предмет
            local itemResponse = sendHttpRequest(HTTP_API_CONFIG.endpoints.item, {
                action = "update",
                player_id = nick,
                item_id = itemCfg.id,
                item_dmg = itemCfg.dmg,
                item_name = itemCfg.label,
                delta = itemsCount
            })
            
            -- Логируем транзакцию
            local transactionResponse = sendHttpRequest(HTTP_API_CONFIG.endpoints.transaction, {
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
            local balanceResponse = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
                action = "update",
                player_id = nick,
                data = {balance = -totalCost}
            })
            
            if balanceResponse and balanceResponse.success then
                logDebug("Bought items:", itemsCount)
                return itemsCount, "Куплено " .. itemsCount .. " предметов"
            else
                itemUtils.takeItem(itemCfg.id, itemCfg.dmg, itemsCount)
                return 0, "Ошибка при обновлении баланса"
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