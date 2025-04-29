local component = require('component')
local itemUtils = require('ItemUtils')
local event = require('event')
local serialization = require("serialization")
local internet = require("internet")
local json = require("json")

ShopService = {}

-- Конфигурация HTTP API
local HTTP_API_CONFIG = {
    baseUrl = "http://r-2-veteran.online/www/r-2-veteran.online/shop_api/",
    endpoints = {
        player = "player.php",
        transaction = "transaction.php",
        item = "item.php",
        log = "log.php"
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

-- Функция для логирования транзакций
local function logTransaction(playerId, operationType, itemData, amount, oldBalance, newBalance)
    local logData = {
        player_id = playerId,
        operation_type = operationType,
        timestamp = os.time(),
        old_balance = oldBalance,
        new_balance = newBalance,
        amount = amount
    }
    
    if itemData then
        logData.item_id = itemData.id
        logData.item_dmg = itemData.dmg or 0
        logData.item_name = itemData.label or itemData.id
        logData.quantity = itemData.count or 1
        logData.price = itemData.price or 0
    end
    
    local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.log, {
        action = "log",
        log_data = logData
    })
    
    if not response or not response.success then
        logDebug("Failed to log transaction:", operationType, "for player:", playerId)
    end
end

local function readObjectFromFile(path)
    local file, err = io.open(path, "r")
    if not file then
        return nil, "Failed to open file: " .. (err or "unknown error")
    end
  
    local content = file:read("*a")
    file:close()
  
    local obj = serialization.unserialize(content)
    if not obj then
        return nil, "Failed to unserialize content from file"
    end
  
    return obj
end

function ShopService:new(terminalName)
    local obj = {}
    
    function obj:init()
        self.terminalName = terminalName or "Unknown"
        self.oreExchangeList = readObjectFromFile("/home/config/oreExchanger.cfg") or {}
        self.exchangeList = readObjectFromFile("/home/config/exchanger.cfg") or {}
        self.sellShopList = readObjectFromFile("/home/config/sellShop.cfg") or {}
        self.buyShopList = readObjectFromFile("/home/config/buyShop.cfg") or {}

        self.currencies = {
            {item = {name = "minecraft:gold_nugget", damage = 0}, money = 1000},
            {item = {name = "minecraft:gold_ingot", damage = 0}, money = 10000},
            {item = {name = "minecraft:diamond", damage = 0}, money = 100000},
            {item = {name = "minecraft:emerald", damage = 0}, money = 1000000}
        }

        itemUtils.setCurrency(self.currencies)
    end

    function obj:dbClause(fieldName, fieldValue, typeOfClause)
        local clause = {}
        clause.column = fieldName
        clause.value = fieldValue
        clause.operation = typeOfClause
        return clause
    end

    function obj:getOreExchangeList()
        return self.oreExchangeList
    end

    function obj:getExchangeList()
        return self.exchangeList
    end

    function obj:getSellShopList(category)
        local categorySellShopList = {}
        for i, sellConfig in pairs(self.sellShopList) do
            if (sellConfig.category == category) then
                table.insert(categorySellShopList, sellConfig)
            end
        end
        itemUtils.populateCount(categorySellShopList)
        return categorySellShopList
    end

    function obj:getBuyShopList()
        local categoryBuyShopList = self.buyShopList
        itemUtils.populateUserCount(categoryBuyShopList)
        return categoryBuyShopList
    end

    function obj:getBalance(nick)
        local playerData = self:getPlayerData(nick)
        if (playerData) then
            return playerData.balance
        end
        return 0
    end

    function obj:getItemCount(nick)
        local playerData = self:getPlayerData(nick)
        if (playerData) then
            return #playerData.items
        end
        return 0
    end

    function obj:getItems(nick)
        local playerData = self:getPlayerData(nick)
        if (playerData) then
            return playerData.items
        end
        return {}
    end

    function obj:getPlayerData(nick)
        local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
            action = "get",
            player_id = nick
        })
        
        if response and response.success then
            return {
                balance = tonumber(response.balance) or 0,
                items = response.items or {}
            }
        end
        
        return {balance = 0, items = {}}
    end

    function obj:depositMoney(nick, count)
        local countOfMoney = itemUtils.takeMoney(count)
        if countOfMoney > 0 then
            local playerData = self:getPlayerData(nick)
            local oldBalance = playerData.balance
            playerData.balance = oldBalance + countOfMoney
            
            local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
                action = "update",
                player_id = nick,
                data = {balance = countOfMoney}
            })
            
            if response and response.success then
                logTransaction(nick, "deposit", nil, countOfMoney, oldBalance, playerData.balance)
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
        
        local countOfMoney = itemUtils.giveMoney(count)
        if countOfMoney > 0 then
            local oldBalance = playerData.balance
            playerData.balance = oldBalance - countOfMoney
            
            local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
                action = "update",
                player_id = nick,
                data = {balance = -countOfMoney}
            })
            
            if response and response.success then
                logTransaction(nick, "withdraw", nil, countOfMoney, oldBalance, playerData.balance)
                return countOfMoney, "Снято с баланса: " .. countOfMoney
            else
                itemUtils.takeItem("minecraft:gold_nugget", 0, countOfMoney / 1000)
                return 0, "Ошибка при обновлении баланса"
            end
        end
        
        if itemUtils.countOfAvailableSlots() > 0 then
            return 0, "Нет монет в магазине!"
        else
            return 0, "Освободите инвентарь!"
        end
    end

    function obj:buyItem(nick, itemCfg, count)
        local playerData = self:getPlayerData(nick)
        local totalCost = count * itemCfg.price
        
        if playerData.balance < totalCost then
            return 0, "Не хватает денег на счету"
        end
        
        local itemsCount = itemUtils.giveItem(itemCfg.id, itemCfg.dmg or 0, count)
        if itemsCount > 0 then
            local oldBalance = playerData.balance
            playerData.balance = oldBalance - totalCost
            
            -- Обновляем баланс
            local balanceResponse = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
                action = "update",
                player_id = nick,
                data = {balance = -totalCost}
            })
            
            -- Логируем предмет
            local itemResponse = sendHttpRequest(HTTP_API_CONFIG.endpoints.item, {
                action = "update",
                player_id = nick,
                item_id = itemCfg.id,
                item_dmg = itemCfg.dmg or 0,
                item_name = itemCfg.label or itemCfg.id,
                delta = itemsCount
            })
            
            if balanceResponse and balanceResponse.success then
                logTransaction(nick, "buy", {
                    id = itemCfg.id,
                    dmg = itemCfg.dmg or 0,
                    label = itemCfg.label or itemCfg.id,
                    count = itemsCount,
                    price = itemCfg.price
                }, totalCost, oldBalance, playerData.balance)
                
                return itemsCount, "Куплено " .. itemsCount .. " предметов"
            else
                itemUtils.takeItem(itemCfg.id, itemCfg.dmg or 0, itemsCount)
                return 0, "Ошибка при обновлении баланса"
            end
        end
        return 0, "Не удалось купить предметы"
    end

    function obj:sellItem(nick, itemCfg, count)
        local itemsCount = itemUtils.takeItem(itemCfg.id, itemCfg.dmg or 0, count)
        if itemsCount > 0 then
            local playerData = self:getPlayerData(nick)
            local oldBalance = playerData.balance
            local totalPrice = itemsCount * itemCfg.price
            playerData.balance = oldBalance + totalPrice
            
            -- Обновляем баланс
            local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
                action = "update",
                player_id = nick,
                data = {balance = totalPrice}
            })
            
            if response and response.success then
                logTransaction(nick, "sell", {
                    id = itemCfg.id,
                    dmg = itemCfg.dmg or 0,
                    label = itemCfg.label or itemCfg.id,
                    count = itemsCount,
                    price = itemCfg.price
                }, totalPrice, oldBalance, playerData.balance)
                
                return itemsCount, "Продано " .. itemsCount .. " предметов"
            else
                itemUtils.giveItem(itemCfg.id, itemCfg.dmg or 0, itemsCount)
                return 0, "Ошибка при обновлении баланса"
            end
        end
        return 0, "Не удалось продать предметы"
    end

    function obj:withdrawAll(nick)
        local playerData = self:getPlayerData(nick)
        local toRemove = {}
        local sum = 0
        for i = 1, #playerData.items do
            local item = playerData.items[i]
            local withdrawedCount = itemUtils.giveItem(item.id, item.dmg, item.count)
            sum = sum + withdrawedCount
            item.count = item.count - withdrawedCount
            if (item.count == 0) then
                table.insert(toRemove, i)
            end
            if (withdrawedCount > 0) then
                printD(terminalName .. ": Игрок " .. nick .. " забрал " .. item.id .. ":" .. item.dmg .. " в количестве " .. withdrawedCount)
            end
        end
        for i = #toRemove, 1, -1 do
            table.remove(playerData.items, toRemove[i])
        end
        self.db:update(nick, playerData)
        if (sum == 0) then
            if (itemUtils.countOfAvailableSlots() > 0) then
                return sum, "Вещей нету в наличии!"
            else
                return sum, "Освободите инвентарь!"
            end
        end
        return sum, "Выданно " .. sum .. " вещей"
    end

    function obj:exchangeAllOres(nick)
        local items = {}
        for i, itemConfig in pairs(self.oreExchangeList) do
            local item = {}
            item.id = itemConfig.fromId
            item.dmg = itemConfig.fromDmg
            table.insert(items, item)
        end
        local itemsTaken = itemUtils.takeItems(items)
        local playerData = self:getPlayerData(nick)
        local sum = 0
        for i, item in pairs(itemsTaken) do
            sum = sum + item.count
            local itemCfg
            for j, itemConfig in pairs(self.oreExchangeList) do
                if (item.id == itemConfig.fromId and item.dmg == itemConfig.fromDmg) then
                    itemCfg = itemConfig
                    break
                end
            end
            printD(terminalName .. ": Игрок " .. nick .. " обменял на слитки " .. itemCfg.fromId .. ":" .. itemCfg.fromDmg .. " в количестве " .. item.count .. " по курсу " .. itemCfg.fromCount .. "к" .. itemCfg.toCount)
            local itemAlreadyInFile = false
            for i = 1, #playerData.items do
                local itemP = playerData.items[i]
                if (itemP.id == itemCfg.toId and itemP.dmg == itemCfg.toDmg) then
                    itemP.count = itemP.count + item.count * itemCfg.toCount / itemCfg.fromCount
                    itemAlreadyInFile = true
                    break
                end
            end
            if (not itemAlreadyInFile) then
                local newItem = {}
                newItem.id = itemCfg.toId
                newItem.dmg = itemCfg.toDmg
                newItem.label = itemCfg.toLabel
                newItem.count = item.count * itemCfg.toCount / itemCfg.fromCount
                table.insert(playerData.items, newItem)
            end
        end
        self.db:update(nick, playerData)
        if (sum == 0) then
            return 0, "Нету руд в инвентаре!"
        else
            return sum, " Обменяно " .. sum .. " руд на слитки.", "Заберите из корзины"
        end
    end

    function obj:exchangeOre(nick, itemConfig, count)
        local countOfItems = itemUtils.takeItem(itemConfig.fromId, itemConfig.fromDmg, count)
        if (countOfItems > 0) then
            local playerData = self:getPlayerData(nick)
            local itemAlreadyInFile = false
            for i = 1, #playerData.items do
                local item = playerData.items[i]
                if (item.id == itemConfig.toId and item.dmg == itemConfig.toDmg) then
                    item.count = item.count + countOfItems * itemConfig.toCount / itemConfig.fromCount
                    itemAlreadyInFile = true
                    break
                end
            end
            if (not itemAlreadyInFile) then
                local item = {}
                item.id = itemConfig.toId
                item.dmg = itemConfig.toDmg
                item.label = itemConfig.toLabel
                item.count = countOfItems * itemConfig.toCount / itemConfig.fromCount
                table.insert(playerData.items, item)
            end
            self.db:update(nick, playerData)
            printD(terminalName .. ": Игрок " .. nick .. " обменял " .. itemConfig.fromId .. ":" .. itemConfig.fromDmg .. " в количестве " .. countOfItems .. " по курсу " .. itemConfig.fromCount .. "к" .. itemConfig.toCount)
            return countOfItems, " Обменяно " .. countOfItems .. " руд на слитки.", "Заберите из корзины"
        end
        return 0, "Нету руд в инвентаре!"
    end

    function obj:exchange(nick, itemConfig, count)
        local countOfItems = itemUtils.takeItem(itemConfig.fromId, itemConfig.fromDmg, count * itemConfig.fromCount)
        local countOfExchanges = math.floor(countOfItems / itemConfig.fromCount)
        local left = math.floor(countOfItems % itemConfig.fromCount)
        local save = false
        local playerData = self:getPlayerData(nick)
        if (left > 0) then
            save = true
            local itemAlreadyInFile = false
            for i = 1, #playerData.items do
                local item = playerData.items[i]
                if (item.id == itemConfig.fromId and item.dmg == itemConfig.fromDmg) then
                    item.count = item.count + left
                    itemAlreadyInFile = true
                    break
                end
            end
            if (not itemAlreadyInFile) then
                local item = {}
                item.id = itemConfig.fromId
                item.dmg = itemConfig.fromDmg
                item.label = itemConfig.fromLabel
                item.count = left
                table.insert(playerData.items, item)
            end
            self.db:update(nick, playerData)
        end
        if (countOfExchanges > 0) then
            save = true
            local itemAlreadyInFile = false
            for i = 1, #playerData.items do
                local item = playerData.items[i]
                if (item.id == itemConfig.toId and item.dmg == itemConfig.toDmg) then
                    item.count = item.count + countOfExchanges * itemConfig.toCount
                    itemAlreadyInFile = true
                    break
                end
            end
            if (not itemAlreadyInFile) then
                local item = {}
                item.id = itemConfig.toId
                item.dmg = itemConfig.toDmg
                item.label = itemConfig.toLabel
                item.count = countOfExchanges * itemConfig.toCount
                table.insert(playerData.items, item)
            end
            printD(terminalName .. ": Игрок " .. nick .. " обменял " .. itemConfig.fromId .. ":" .. itemConfig.fromDmg .. " на " .. itemConfig.toId .. ":" .. itemConfig.toDmg .. " в количестве " .. countOfItems .. " по курсу " .. itemConfig.fromCount .. "к" .. itemConfig.toCount)
        end
        if(save) then
            self.db:update(nick, playerData)
            if (countOfExchanges > 0) then
                return countOfItems, " Обменяно " .. countOfItems .. " предметов.", "Заберите из корзины"
            end
        end
        return 0, "Нету вещей в инвентаре!"
    end

    obj:init()
    setmetatable(obj, self)
    self.__index = self
    return obj
end
