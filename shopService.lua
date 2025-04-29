local component = require('component')
local itemUtils = require('ItemUtils')
local event = require('event')
local serialization = require("serialization")
local http = require("internet")
local json = require("json")

ShopService = {}

-- Конфигурация HTTP API
local HTTP_API_CONFIG = {
    baseUrl = "http://r-2-veteran.online/shop_api",
    endpoints = {
        player = "/player.php",
        transaction = "/transaction.php",
        item = "/item.php"
    },
    credentials = {
        username = "068004",
        password = "zZ53579"
    }
}

-- Улучшенная версия функции sendHttpRequest
local function sendHttpRequest(url, data)
    local success, response = pcall(function()
        local request = http.request(url, json.encode(data), {
            ["Content-Type"] = "application/json",
            ["Authorization"] = HTTP_API_CONFIG.credentials.username .. ":" .. HTTP_API_CONFIG.credentials.password
        })
        
        local result = ""
        for chunk in request do
            result = result .. chunk
        end
        
        return json.decode(result) or {}
    end)
    
    if not success then
        print("[HTTP ERROR] " .. tostring(response))
        return {success = false, error = response}
    end
    
    return response
end

-- Функция для работы с игроком
local function getPlayerData(nick)
    local url = HTTP_API_CONFIG.baseUrl .. HTTP_API_CONFIG.endpoints.player
    local response = sendHttpRequest(url, {
        action = "get",
        player_id = nick
    })
    
    if response and response.success then
        return {
            _id = nick,
            balance = tonumber(response.balance) or 0,
            items = response.items or {}
        }
    else
        -- Создаем нового игрока, если не найден
        sendHttpRequest(url, {
            action = "create",
            player_id = nick,
            balance = 0,
            items = {}
        })
        return {_id = nick, balance = 0, items = {}}
    end
end

-- Функция для обновления данных игрока
local function updatePlayerData(nick, data)
    local url = HTTP_API_CONFIG.baseUrl .. HTTP_API_CONFIG.endpoints.player
    local response = sendHttpRequest(url, {
        action = "update",
        player_id = nick,
        data = data
    })
    return response and response.success or false
end

-- Функция для работы с предметами
local function updatePlayerItem(nick, itemId, itemDmg, delta, action)
    local url = HTTP_API_CONFIG.baseUrl .. HTTP_API_CONFIG.endpoints.item
    local response = sendHttpRequest(url, {
        action = action or "update",
        player_id = nick,
        item_id = itemId,
        item_dmg = itemDmg,
        delta = delta
    })
    return response and response.success or false
end

-- Функция для логирования транзакций
local function logTransaction(player_id, transaction_type, item_data, amount)
    local url = HTTP_API_CONFIG.baseUrl .. HTTP_API_CONFIG.endpoints.transaction
    local data = {
        player_id = player_id,
        transaction_type = transaction_type,
        timestamp = os.time()
    }
    
    if item_data then
        data.item_id = item_data.id or item_data.item_id
        data.item_dmg = item_data.dmg or item_data.item_dmg
        data.item_name = item_data.label or item_data.item_name or item_data.id
        data.quantity = item_data.count or item_data.quantity or 0
    end
    
    if amount then
        data.amount = amount
    end
    
    sendHttpRequest(url, data)
end

event.shouldInterrupt = function()
    return false
end

local function printD(...) end

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

        self.currencies = {}
        self.currencies[1] = {
            item = {name = "minecraft:gold_nugget", damage = 0},
            money = 1000
        }
        self.currencies[2] = {
            item = {name = "minecraft:gold_ingot", damage = 0},
            money = 10000
        }
        self.currencies[3] = {
            item = {name = "minecraft:diamond", damage = 0},
            money = 100000
        }
        self.currencies[4] = {
            item = {name = "minecraft:emerald", damage = 0},
            money = 1000000
        }

        itemUtils.setCurrency(self.currencies)
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
        local playerData = getPlayerData(nick)
        return playerData.balance
    end

    function obj:getItemCount(nick)
        local playerData = getPlayerData(nick)
        return #playerData.items
    end

    function obj:getItems(nick)
        local playerData = getPlayerData(nick)
        return playerData.items
    end

    function obj:depositMoney(nick, count)
        local countOfMoney = itemUtils.takeMoney(count)
        if countOfMoney > 0 then
            local playerData = getPlayerData(nick)
            playerData.balance = playerData.balance + countOfMoney
            if updatePlayerData(nick, playerData) then
                logTransaction(nick, "deposit", nil, countOfMoney)
                printD(self.terminalName .. ": Игрок " .. nick .. " пополнил баланс на " .. countOfMoney .. " Текущий баланс " .. playerData.balance)
                return playerData.balance, "Баланс пополнен на " .. countOfMoney
            else
                return 0, "Ошибка сервера при обновлении баланса"
            end
        end
        return 0, "Нету монеток в инвентаре!"
    end

    function obj:withdrawMoney(nick, count)
        local playerData = getPlayerData(nick)
        if (playerData.balance < count) then
            return 0, "Не хватает денег на счету"
        end
        local countOfMoney = itemUtils.giveMoney(count)
        if (countOfMoney > 0) then
            playerData.balance = playerData.balance - countOfMoney
            if updatePlayerData(nick, playerData) then
                logTransaction(nick, "withdraw", nil, countOfMoney)
                printD(self.terminalName .. ": Игрок " .. nick .. " снял с баланса " .. countOfMoney .. ". Текущий баланс " .. playerData.balance)
                return countOfMoney, "C баланса списанно " .. countOfMoney
            else
                return 0, "Ошибка сервера при обновлении баланса"
            end
        end
        if (itemUtils.countOfAvailableSlots() > 0) then
            return 0, "Нету монеток в магазине!"
        else
            return 0, "Освободите инвентарь!"
        end
    end

    function obj:withdrawItem(nick, id, dmg, count)
        local playerData = getPlayerData(nick)
        for i, item in ipairs(playerData.items) do
            if (item.id == id and item.dmg == dmg) then
                local countToWithdraw = math.min(count, item.count)
                local withdrawedCount = itemUtils.giveItem(id, dmg, countToWithdraw)
                if withdrawedCount > 0 then
                    if updatePlayerItem(nick, id, dmg, -withdrawedCount, "withdraw") then
                        printD(self.terminalName .. ": Игрок " .. nick .. " забрал " .. id .. ":" .. dmg .. " в количестве " .. withdrawedCount)
                        logTransaction(nick, "withdraw_item", {id=id, dmg=dmg, count=withdrawedCount})
                        return withdrawedCount, "Выданно " .. withdrawedCount .. " вещей"
                    else
                        return 0, "Ошибка сервера при обновлении предметов"
                    end
                end
            end
        end
        return 0, "Вещей нету в наличии!"
    end

    function obj:sellItem(nick, itemCfg, count)
        local playerData = getPlayerData(nick)
        if (playerData.balance < count * itemCfg.price) then
            return false, "Не хватает денег на счету"
        end
        local itemsCount = itemUtils.giveItem(itemCfg.id, itemCfg.dmg, count, itemCfg.nbt)
        if (itemsCount > 0) then
            playerData.balance = playerData.balance - itemsCount * itemCfg.price
            if updatePlayerData(nick, playerData) then
                logTransaction(nick, "buy", {
                    id = itemCfg.id,
                    dmg = itemCfg.dmg,
                    label = itemCfg.label,
                    count = itemsCount,
                    price = itemCfg.price
                })
                printD(self.terminalName .. ": Игрок " .. nick .. " купил " .. itemCfg.id .. ":" .. itemCfg.dmg .. " в количестве " .. itemsCount .. " по цене " .. itemCfg.price .. " за шт. Текущий баланс " .. playerData.balance)
                return itemsCount, "Куплено " .. itemsCount .. " предметов!"
            else
                return 0, "Ошибка сервера при обновлении баланса"
            end
        end
        return 0, "Не удалось купить предметы"
    end

    function obj:buyItem(nick, itemCfg, count)
        print("[DEBUG] Попытка продажи:", nick, itemCfg.id, count)
        local itemsCount = itemUtils.takeItem(itemCfg.id, itemCfg.dmg, count)
        print("[DEBUG] Предметов принято:", itemsCount)
        if itemsCount > 0 then
            local playerData = getPlayerData(nick)
            local oldBalance = playerData.balance
            playerData.balance = oldBalance + (itemsCount * itemCfg.price)
            if updatePlayerData(nick, playerData) then
                logTransaction(nick, "sell", {
                    id = itemCfg.id,
                    dmg = itemCfg.dmg,
                    label = itemCfg.label,
                    count = itemsCount,
                    price = itemCfg.price
                })
                print("[DEBUG] Баланс изменён:", oldBalance, "->", playerData.balance)
                return itemsCount, "Продано "..itemsCount.." предметов"
            else
                print("[ERROR] Не удалось сохранить баланс!")
                return 0, "Ошибка сервера"
            end
        end
        return 0, "Не удалось принять предметы"
    end

    function obj:withdrawAll(nick)
        local playerData = getPlayerData(nick)
        local sum = 0
        
        for _, item in ipairs(playerData.items) do
            local withdrawedCount = itemUtils.giveItem(item.id, item.dmg, item.count)
            if withdrawedCount > 0 then
                sum = sum + withdrawedCount
                if updatePlayerItem(nick, item.id, item.dmg, -withdrawedCount, "withdraw_all") then
                    printD(self.terminalName .. ": Игрок " .. nick .. " забрал " .. item.id .. ":" .. item.dmg .. " в количестве " .. withdrawedCount)
                end
            end
        end
        
        if sum > 0 then
            logTransaction(nick, "withdraw_all", {count=sum})
            return sum, "Выданно " .. sum .. " вещей"
        else
            if (itemUtils.countOfAvailableSlots() > 0) then
                return sum, "Вещей нету в наличии!"
            else
                return sum, "Освободите инвентарь!"
            end
        end
    end

    function obj:exchangeAllOres(nick)
        local items = {}
        for _, itemConfig in pairs(self.oreExchangeList) do
            table.insert(items, {id = itemConfig.fromId, dmg = itemConfig.fromDmg})
        end
        
        local itemsTaken = itemUtils.takeItems(items)
        local sum = 0
        
        for _, item in ipairs(itemsTaken) do
            sum = sum + item.count
            local itemCfg
            for _, config in pairs(self.oreExchangeList) do
                if item.id == config.fromId and item.dmg == config.fromDmg then
                    itemCfg = config
                    break
                end
            end
            
            if itemCfg then
                local exchangeCount = item.count * itemCfg.toCount / itemCfg.fromCount
                if updatePlayerItem(nick, itemCfg.fromId, itemCfg.fromDmg, -item.count, "exchange_out") and
                   updatePlayerItem(nick, itemCfg.toId, itemCfg.toDmg, exchangeCount, "exchange_in") then
                    printD(self.terminalName .. ": Игрок " .. nick .. " обменял на слитки " .. 
                           itemCfg.fromId .. ":" .. itemCfg.fromDmg .. " в количестве " .. 
                           item.count .. " по курсу " .. itemCfg.fromCount .. "к" .. itemCfg.toCount)
                    logTransaction(nick, "ore_exchange", {
                        from_id = itemCfg.fromId,
                        from_dmg = itemCfg.fromDmg,
                        from_count = item.count,
                        to_id = itemCfg.toId,
                        to_dmg = itemCfg.toDmg,
                        to_count = exchangeCount
                    })
                end
            end
        end
        
        if sum == 0 then
            return 0, "Нету руд в инвентаре!"
        else
            return sum, "Обменяно " .. sum .. " руд на слитки.", "Заберите из корзины"
        end
    end

    function obj:exchangeOre(nick, itemConfig, count)
        local countOfItems = itemUtils.takeItem(itemConfig.fromId, itemConfig.fromDmg, count)
        if countOfItems > 0 then
            local exchangeCount = countOfItems * itemConfig.toCount / itemConfig.fromCount
            if updatePlayerItem(nick, itemConfig.fromId, itemConfig.fromDmg, -countOfItems, "exchange_out") and
               updatePlayerItem(nick, itemConfig.toId, itemConfig.toDmg, exchangeCount, "exchange_in") then
                printD(self.terminalName .. ": Игрок " .. nick .. " обменял " .. 
                       itemConfig.fromId .. ":" .. itemConfig.fromDmg .. " в количестве " .. 
                       countOfItems .. " по курсу " .. itemConfig.fromCount .. "к" .. itemConfig.toCount)
                logTransaction(nick, "ore_exchange", {
                    from_id = itemConfig.fromId,
                    from_dmg = itemConfig.fromDmg,
                    from_count = countOfItems,
                    to_id = itemConfig.toId,
                    to_dmg = itemConfig.toDmg,
                    to_count = exchangeCount
                })
                return countOfItems, "Обменяно " .. countOfItems .. " руд на слитки.", "Заберите из корзины"
            end
        end
        return 0, "Нету руд в инвентаре!"
    end

    function obj:exchange(nick, itemConfig, count)
        local countOfItems = itemUtils.takeItem(itemConfig.fromId, itemConfig.fromDmg, count * itemConfig.fromCount)
        local countOfExchanges = math.floor(countOfItems / itemConfig.fromCount)
        local left = math.floor(countOfItems % itemConfig.fromCount)
        
        if countOfExchanges > 0 then
            local exchangeCount = countOfExchanges * itemConfig.toCount
            local success = true
            
            if left > 0 then
                success = success and updatePlayerItem(nick, itemConfig.fromId, itemConfig.fromDmg, left, "exchange_left")
            end
            
            success = success and updatePlayerItem(nick, itemConfig.fromId, itemConfig.fromDmg, -countOfItems, "exchange_out")
            success = success and updatePlayerItem(nick, itemConfig.toId, itemConfig.toDmg, exchangeCount, "exchange_in")
            
            if success then
                printD(self.terminalName .. ": Игрок " .. nick .. " обменял " .. 
                       itemConfig.fromId .. ":" .. itemConfig.fromDmg .. " на " .. 
                       itemConfig.toId .. ":" .. itemConfig.toDmg .. " в количестве " .. 
                       countOfItems .. " по курсу " .. itemConfig.fromCount .. "к" .. itemConfig.toCount)
                logTransaction(nick, "item_exchange", {
                    from_id = itemConfig.fromId,
                    from_dmg = itemConfig.fromDmg,
                    from_count = countOfItems,
                    to_id = itemConfig.toId,
                    to_dmg = itemConfig.toDmg,
                    to_count = exchangeCount,
                    left = left
                })
                return countOfItems, "Обменяно " .. countOfItems .. " предметов.", "Заберите из корзины"
            end
        end
        return 0, "Нету вещей в инвентаре!"
    end

    obj:init()
    setmetatable(obj, self)
    self.__index = self
    return obj
end