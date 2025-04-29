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
    
    local request, reason = internet.request(url, json.encode(data)), {
        ["Content-Type"] = "application/json",
        ["User-Agent"] = "OCShopSystem/1.0"
    }
    
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

-- Функция для логирования операций в MySQL
local function logOperation(operationType, playerId, data)
    local terminalAddress = component and component.computer and component.computer.address() or "unknown"
    local logData = {
        operation_type = operationType,
        player_id = playerId,
        terminal = terminalAddress,
        timestamp = os.time(),
        data = data or {}
    }
    
    if data and data.item_id then
        logData.item_id = data.item_id
        logData.item_dmg = data.item_dmg or 0
        logData.item_name = data.item_name or data.item_id
        logData.quantity = data.quantity or 0
        logData.price = data.price or 0
    end
    
    if data and data.amount then
        logData.amount = data.amount
    end
    
    local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.log, {
        action = "log",
        log_type = operationType,
        player_id = playerId,
        terminal_address = terminalAddress,
        log_data = logData
    })
    
    if not response or not response.success then
        logDebug("Failed to log operation:", operationType, "for player:", playerId, "Error:", response and response.error or "unknown")
    end
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
        self.oreExchangeList = self:loadConfig("/home/config/oreExchanger.cfg")
        self.exchangeList = self:loadConfig("/home/config/exchanger.cfg")
        
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

    function obj:getItems(nick)
        local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.item, {
            action = "get",
            player_id = nick
        })
        
        if response and response.success then
            return response.items or {}
        end
        return {}
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

    function obj:getOreExchangeList()
        if not self.oreExchangeList or #self.oreExchangeList == 0 then
            self.oreExchangeList = self:loadConfig("/home/config/oreExchanger.cfg")
        end
        return self.oreExchangeList
    end

    function obj:getExchangeList()
        if not self.exchangeList or #self.exchangeList == 0 then
            self.exchangeList = self:loadConfig("/home/config/exchanger.cfg")
        end
        return self.exchangeList
    end

    function obj:getItemCount(nick)
        local items = self:getItems(nick)
        return #items
    end

    function obj:depositMoney(nick, count)
        if not itemUtils or not itemUtils.takeMoney then
            logOperation("deposit_failed", nick, {error = "ItemUtils not initialized"})
            return 0, "ItemUtils not properly initialized"
        end
        
        local countOfMoney = itemUtils.takeMoney(count)
        if countOfMoney > 0 then
            logOperation("deposit_start", nick, {amount = countOfMoney})
            
            local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
                action = "update_balance",
                player_id = nick,
                amount = countOfMoney
            })
            
            if response and response.success then
                logDebug("Deposited money:", countOfMoney)
                logOperation("deposit_success", nick, {
                    amount = countOfMoney, 
                    new_balance = self:getBalance(nick)
                })
                return countOfMoney, "Баланс пополнен на " .. countOfMoney
            else
                itemUtils.giveMoney(countOfMoney)
                logOperation("deposit_failed", nick, {
                    amount = countOfMoney, 
                    error = response and response.error or "Balance update failed"
                })
                return 0, "Ошибка при пополнении баланса"
            end
        end
        
        logOperation("deposit_failed", nick, {amount = count, error = "No money in inventory"})
        return 0, "Нет монет в инвентаре!"
    end

    function obj:withdrawMoney(nick, count)
        local playerData = self:getPlayerData(nick)
        if playerData.balance < count then
            logOperation("withdraw_failed", nick, {
                amount = count, 
                error = "Insufficient balance", 
                current_balance = playerData.balance
            })
            return 0, "Не хватает денег на счету"
        end
        
        if not itemUtils or not itemUtils.giveMoney then
            logOperation("withdraw_failed", nick, {
                amount = count, 
                error = "ItemUtils not initialized"
            })
            return 0, "ItemUtils not properly initialized"
        end
        
        local countOfMoney = itemUtils.giveMoney(count)
        if countOfMoney > 0 then
            logOperation("withdraw_start", nick, {amount = countOfMoney})
            
            local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
                action = "update_balance",
                player_id = nick,
                amount = -countOfMoney
            })
            
            if response and response.success then
                logDebug("Withdrew money:", countOfMoney)
                logOperation("withdraw_success", nick, {
                    amount = countOfMoney, 
                    new_balance = self:getBalance(nick)
                })
                return countOfMoney, "Снято с баланса: " .. countOfMoney
            else
                itemUtils.takeMoney(countOfMoney)
                logOperation("withdraw_failed", nick, {
                    amount = countOfMoney, 
                    error = response and response.error or "Balance update failed"
                })
                return 0, "Не удалось обновить баланс"
            end
        end
        
        logOperation("withdraw_failed", nick, {
            amount = count, 
            error = "Failed to give money"
        })
        return 0, "Не удалось выдать деньги"
    end

    function obj:sellItem(nick, itemCfg, count)
        if not itemUtils or not itemUtils.takeItem then
            logOperation("sell_failed", nick, {
                item_id = itemCfg.id, 
                item_dmg = itemCfg.dmg, 
                quantity = count, 
                error = "ItemUtils not initialized"
            })
            return 0, "ItemUtils not properly initialized"
        end
        
        logDebug("Attempting to sell:", itemCfg.id, count)
        local itemsCount = itemUtils.takeItem(itemCfg.id, itemCfg.dmg, count)
        
        if itemsCount > 0 then
            local totalPrice = itemsCount * itemCfg.price
            
            logOperation("sell_start", nick, {
                item_id = itemCfg.id,
                item_dmg = itemCfg.dmg,
                item_name = itemCfg.label,
                quantity = itemsCount,
                price = itemCfg.price,
                total_price = totalPrice
            })
            
            local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
                action = "update_balance",
                player_id = nick,
                amount = totalPrice
            })
            
            if response and response.success then
                logDebug("Sold items:", itemsCount)
                logOperation("sell_success", nick, {
                    item_id = itemCfg.id,
                    item_dmg = itemCfg.dmg,
                    item_name = itemCfg.label,
                    quantity = itemsCount,
                    total_price = totalPrice,
                    new_balance = self:getBalance(nick)
                })
                return itemsCount, "Продано " .. itemsCount .. " предметов"
            else
                itemUtils.giveItem(itemCfg.id, itemCfg.dmg, itemsCount)
                logOperation("sell_failed", nick, {
                    item_id = itemCfg.id,
                    item_dmg = itemCfg.dmg,
                    item_name = itemCfg.label,
                    quantity = itemsCount,
                    error = response and response.error or "Balance update failed"
                })
                return 0, "Ошибка при обновлении баланса"
            end
        end
        
        logOperation("sell_failed", nick, {
            item_id = itemCfg.id,
            item_dmg = itemCfg.dmg,
            item_name = itemCfg.label,
            quantity = count,
            error = "Failed to take items"
        })
        return 0, "Не удалось продать предметы"
    end

    function obj:buyItem(nick, itemCfg, count)
        local playerData = self:getPlayerData(nick)
        local totalCost = count * itemCfg.price
        
        if playerData.balance < totalCost then
            logOperation("buy_failed", nick, {
                item_id = itemCfg.id,
                item_dmg = itemCfg.dmg,
                item_name = itemCfg.label,
                quantity = count,
                price = itemCfg.price,
                total_cost = totalCost,
                error = "Insufficient balance",
                current_balance = playerData.balance
            })
            return 0, "Не хватает денег на счету"
        end
        
        if not itemUtils or not itemUtils.giveItem then
            logOperation("buy_failed", nick, {
                item_id = itemCfg.id,
                item_dmg = itemCfg.dmg,
                item_name = itemCfg.label,
                quantity = count,
                error = "ItemUtils not initialized"
            })
            return 0, "ItemUtils not properly initialized"
        end
        
        local itemsCount = itemUtils.giveItem(itemCfg.id, itemCfg.dmg, count)
        if itemsCount > 0 then
            logOperation("buy_start", nick, {
                item_id = itemCfg.id,
                item_dmg = itemCfg.dmg,
                item_name = itemCfg.label,
                quantity = itemsCount,
                price = itemCfg.price,
                total_cost = totalCost
            })
            
            local balanceResponse = sendHttpRequest(HTTP_API_CONFIG.endpoints.player, {
                action = "update_balance",
                player_id = nick,
                amount = -totalCost
            })
            
            if balanceResponse and balanceResponse.success then
                logDebug("Bought items:", itemsCount)
                logOperation("buy_success", nick, {
                    item_id = itemCfg.id,
                    item_dmg = itemCfg.dmg,
                    item_name = itemCfg.label,
                    quantity = itemsCount,
                    total_cost = totalCost,
                    new_balance = self:getBalance(nick)
                })
                return itemsCount, "Куплено " .. itemsCount .. " предметов"
            else
                itemUtils.takeItem(itemCfg.id, itemCfg.dmg, itemsCount)
                logOperation("buy_failed", nick, {
                    item_id = itemCfg.id,
                    item_dmg = itemCfg.dmg,
                    item_name = itemCfg.label,
                    quantity = itemsCount,
                    error = balanceResponse and balanceResponse.error or "Balance update failed"
                })
                return 0, "Ошибка при обновлении баланса"
            end
        end
        
        logOperation("buy_failed", nick, {
            item_id = itemCfg.id,
            item_dmg = itemCfg.dmg,
            item_name = itemCfg.label,
            quantity = count,
            error = "Failed to give items"
        })
        return 0, "Не удалось купить предметы"
    end

    function obj:withdrawItem(nick, id, dmg, count)
        local items = self:getItems(nick)
        local itemToWithdraw = nil
        
        for _, item in ipairs(items) do
            if item.id == id and (not dmg or item.dmg == dmg) then
                itemToWithdraw = item
                break
            end
        end
        
        if not itemToWithdraw then
            logOperation("withdraw_item_failed", nick, {
                item_id = id,
                item_dmg = dmg,
                quantity = count,
                error = "Item not found in storage"
            })
            return 0, "Предмет не найден в хранилище"
        end
        
        if itemToWithdraw.count < count then
            logOperation("withdraw_item_failed", nick, {
                item_id = id,
                item_dmg = dmg,
                quantity = count,
                available = itemToWithdraw.count,
                error = "Not enough items in storage"
            })
            return 0, "Недостаточно предметов в хранилище"
        end
        
        if not itemUtils or not itemUtils.giveItem then
            logOperation("withdraw_item_failed", nick, {
                item_id = id,
                item_dmg = dmg,
                quantity = count,
                error = "ItemUtils not initialized"
            })
            return 0, "ItemUtils not properly initialized"
        end
        
        local itemsCount = itemUtils.giveItem(id, dmg or 0, count)
        if itemsCount > 0 then
            logOperation("withdraw_item_start", nick, {
                item_id = id,
                item_dmg = dmg,
                item_name = itemToWithdraw.item_name or id,
                quantity = itemsCount
            })
            
            local response = sendHttpRequest(HTTP_API_CONFIG.endpoints.item, {
                action = "update",
                player_id = nick,
                item_id = id,
                item_dmg = dmg or 0,
                delta = -itemsCount
            })
            
            if response and response.success then
                logOperation("withdraw_item_success", nick, {
                    item_id = id,
                    item_dmg = dmg,
                    item_name = itemToWithdraw.item_name or id,
                    quantity = itemsCount
                })
                return itemsCount, "Выдано " .. itemsCount .. " предметов"
            else
                itemUtils.takeItem(id, dmg or 0, itemsCount)
                logOperation("withdraw_item_failed", nick, {
                    item_id = id,
                    item_dmg = dmg,
                    quantity = itemsCount,
                    error = response and response.error or "Storage update failed"
                })
                return 0, "Ошибка при обновлении хранилища"
            end
        end
        
        logOperation("withdraw_item_failed", nick, {
            item_id = id,
            item_dmg = dmg,
            quantity = count,
            error = "Failed to give items"
        })
        return 0, "Не удалось выдать предметы"
    end

    function obj:withdrawAll(nick)
        local items = self:getItems(nick)
        local totalWithdrawn = 0
        
        logOperation("withdraw_all_start", nick, {
            item_count = #items
        })
        
        for _, item in ipairs(items) do
            if item.count > 0 then
                local count, _ = self:withdrawItem(nick, item.id, item.dmg, item.count)
                totalWithdrawn = totalWithdrawn + count
            end
        end
        
        if totalWithdrawn > 0 then
            logOperation("withdraw_all_success", nick, {
                total_withdrawn = totalWithdrawn
            })
            return totalWithdrawn, "Выдано " .. totalWithdrawn .. " предметов"
        end
        
        logOperation("withdraw_all_failed", nick, {
            error = "No items to withdraw"
        })
        return 0, "Нет предметов для выдачи"
    end

    function obj:exchangeOre(nick, item, count)
        if not item or not item.from or not item.to then
            logOperation("exchange_ore_failed", nick, {
                error = "Invalid exchange item"
            })
            return 0, "Неверный предмет для обмена", ""
        end
        
        if not itemUtils or not itemUtils.takeItem or not itemUtils.giveItem then
            logOperation("exchange_ore_failed", nick, {
                error = "ItemUtils not initialized"
            })
            return 0, "ItemUtils not properly initialized", ""
        end
        
        local totalTake = count * item.fromCount
        local totalGive = count * item.toCount
        
        logOperation("exchange_ore_start", nick, {
            from_item = item.from,
            from_dmg = item.fromDmg or 0,
            to_item = item.to,
            to_dmg = item.toDmg or 0,
            take_count = totalTake,
            give_count = totalGive
        })
        
        local taken = itemUtils.takeItem(item.from, item.fromDmg or 0, totalTake)
        if taken < totalTake then
            logOperation("exchange_ore_failed", nick, {
                from_item = item.from,
                from_dmg = item.fromDmg or 0,
                to_item = item.to,
                to_dmg = item.toDmg or 0,
                needed = totalTake,
                taken = taken,
                error = "Not enough items to take"
            })
            return 0, "Недостаточно предметов для обмена", string.format("Нужно %d, есть %d", totalTake, taken)
        end
        
        local given = itemUtils.giveItem(item.to, item.toDmg or 0, totalGive)
        if given < totalGive then
            itemUtils.giveItem(item.from, item.fromDmg or 0, taken)
            logOperation("exchange_ore_failed", nick, {
                from_item = item.from,
                from_dmg = item.fromDmg or 0,
                to_item = item.to,
                to_dmg = item.toDmg or 0,
                needed = totalGive,
                given = given,
                error = "Failed to give items"
            })
            return 0, "Не удалось выдать предметы", string.format("Нужно выдать %d", totalGive)
        end
        
        logOperation("exchange_ore_success", nick, {
            from_item = item.from,
            from_dmg = item.fromDmg or 0,
            to_item = item.to,
            to_dmg = item.toDmg or 0,
            take_count = totalTake,
            give_count = totalGive
        })
        
        return count, string.format("Обменяно %d на %d", totalTake, totalGive), ""
    end

    function obj:exchangeAllOres(nick)
        local items = self:getOreExchangeList()
        local totalExchanged = 0
        local messages = {}
        
        logOperation("exchange_all_ores_start", nick, {
            ore_types = #items
        })
        
        for _, item in ipairs(items) do
            local maxCount = math.floor(itemUtils.getItemCount(item.from, item.fromDmg or 0) / item.fromCount)
            if maxCount > 0 then
                local count, msg = self:exchangeOre(nick, item, maxCount)
                if count > 0 then
                    totalExchanged = totalExchanged + count
                    table.insert(messages, msg)
                end
            end
        end
        
        if totalExchanged > 0 then
            logOperation("exchange_all_ores_success", nick, {
                total_exchanged = totalExchanged,
                messages = messages
            })
            return totalExchanged, "Обмен завершен", table.concat(messages, "\n")
        end
        
        logOperation("exchange_all_ores_failed", nick, {
            error = "No items to exchange"
        })
        return 0, "Нет предметов для обмена", ""
    end

    function obj:exchange(nick, item, count)
        if not item or not item.from or not item.to then
            logOperation("exchange_failed", nick, {
                error = "Invalid exchange item"
            })
            return 0, "Неверный предмет для обмена", ""
        end
        
        if not itemUtils or not itemUtils.takeItem or not itemUtils.giveItem then
            logOperation("exchange_failed", nick, {
                error = "ItemUtils not initialized"
            })
            return 0, "ItemUtils not properly initialized", ""
        end
        
        local totalTake = count * item.fromCount
        local totalGive = count * item.toCount
        
        logOperation("exchange_start", nick, {
            from_item = item.from,
            from_dmg = item.fromDmg or 0,
            from_label = item.fromLabel,
            to_item = item.to,
            to_dmg = item.toDmg or 0,
            to_label = item.toLabel,
            take_count = totalTake,
            give_count = totalGive
        })
        
        local taken = itemUtils.takeItem(item.from, item.fromDmg or 0, totalTake)
        if taken < totalTake then
            logOperation("exchange_failed", nick, {
                from_item = item.from,
                from_dmg = item.fromDmg or 0,
                to_item = item.to,
                to_dmg = item.toDmg or 0,
                needed = totalTake,
                taken = taken,
                error = "Not enough items to take"
            })
            return 0, "Недостаточно предметов для обмена", string.format("Нужно %d, есть %d", totalTake, taken)
        end
        
        local given = itemUtils.giveItem(item.to, item.toDmg or 0, totalGive)
        if given < totalGive then
            itemUtils.giveItem(item.from, item.fromDmg or 0, taken)
            logOperation("exchange_failed", nick, {
                from_item = item.from,
                from_dmg = item.fromDmg or 0,
                to_item = item.to,
                to_dmg = item.toDmg or 0,
                needed = totalGive,
                given = given,
                error = "Failed to give items"
            })
            return 0, "Не удалось выдать предметы", string.format("Нужно выдать %d", totalGive)
        end
        
        logOperation("exchange_success", nick, {
            from_item = item.from,
            from_dmg = item.fromDmg or 0,
            from_label = item.fromLabel,
            to_item = item.to,
            to_dmg = item.toDmg or 0,
            to_label = item.toLabel,
            take_count = totalTake,
            give_count = totalGive
        })
        
        return count, string.format("Обменяно %d %s на %d %s", 
            totalTake, item.fromLabel or item.from, 
            totalGive, item.toLabel or item.to), ""
    end

    -- Инициализация
    obj:init()
    setmetatable(obj, self)
    self.__index = self
    return obj
end

return ShopService