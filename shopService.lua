local component = require('component')
local itemUtils = require('ItemUtils')
local event = require('event')
local Database = dofile('/home/Database.lua')
local serialization = require("serialization")

ShopService = {}

local telegramLog_buy = require('TelegramLog'):new({telegramToken = "", message_thread_id = 00, chatId = 000})
local telegramLog_sell = require('TelegramLog'):new({telegramToken = "", message_thread_id = 00, chatId = 000})
local telegramLog_OreExchange = require('TelegramLog'):new({telegramToken = "", message_thread_id = 00, chatId = 000})

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
        self.telegramLoggers = {
            telegramLog_buy = telegramLog_buy, 
            telegramLog_sell = telegramLog_sell, 
            telegramLog_OreExchange = telegramLog_OreExchange 
        }

        self.oreExchangeList = readObjectFromFile("/home/config/oreExchanger.cfg") or {}
        self.exchangeList = readObjectFromFile("/home/config/exchanger.cfg") or {}
        self.sellShopList = readObjectFromFile("/home/config/sellShop.cfg") or {}
        self.buyShopList = readObjectFromFile("/home/config/buyShop.cfg") or {}

        self.db = Database:new("USERS")
        self.transactionsDb = Database:new("TRANSACTIONS")
        
        self.currencies = {
            {item = {name = "minecraft:gold_nugget", damage = 0}, money = 1000},
            {item = {name = "minecraft:gold_ingot", damage = 0}, money = 10000},
            {item = {name = "minecraft:diamond", damage = 0}, money = 100000},
            {item = {name = "minecraft:emerald", damage = 0}, money = 1000000}
        }

        itemUtils.setCurrency(self.currencies)
    end

    function obj:logTransaction(playerId, operationType, itemData, amount, oldBalance, newBalance)
        local transaction = {
            player_id = playerId,
            operation_type = operationType,
            timestamp = os.time(),
            old_balance = oldBalance,
            new_balance = newBalance,
            amount = amount
        }
        
        if itemData then
            transaction.item_id = itemData.id
            transaction.item_dmg = itemData.dmg or 0
            transaction.item_name = itemData.label or itemData.id
            transaction.quantity = itemData.count or 1
            transaction.price = itemData.price or 0
        end
        
        self.transactionsDb:insert(os.time().."_"..math.random(1000,9999), transaction)
    end

    function obj:dbClause(fieldName, fieldValue, typeOfClause)
        return {
            column = fieldName,
            value = fieldValue,
            operation = typeOfClause
        }
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
        local playerData = self:getPlayerData(nick)
        return playerData and playerData.balance or 0
    end

    function obj:getItemCount(nick)
        local playerData = self:getPlayerData(nick)
        return playerData and #playerData.items or 0
    end

    function obj:getItems(nick)
        local playerData = self:getPlayerData(nick)
        return playerData and playerData.items or {}
    end

    function obj:depositMoney(nick, count)
        local countOfMoney = itemUtils.takeMoney(count)
        if countOfMoney > 0 then
            local playerData = self:getPlayerData(nick)
            local oldBalance = playerData.balance
            playerData.balance = oldBalance + countOfMoney
            self.db:insert(nick, playerData)
            self:logTransaction(nick, "deposit", nil, countOfMoney, oldBalance, playerData.balance)
            printD(terminalName..": Игрок "..nick.." пополнил баланс на "..countOfMoney)
            return playerData.balance, "Баланс пополнен на "..countOfMoney
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
            self.db:insert(nick, playerData)
            self:logTransaction(nick, "withdraw", nil, countOfMoney, oldBalance, playerData.balance)
            printD(terminalName..": Игрок "..nick.." снял с баланса "..countOfMoney)
            return countOfMoney, "С баланса списано "..countOfMoney
        end
        
        return 0, itemUtils.countOfAvailableSlots() > 0 and "Нет монет в магазине!" or "Освободите инвентарь!"
    end

    function obj:getPlayerData(nick)
        print("[DEBUG] Загрузка данных для", nick)
        local playerDataList = self.db:select({self:dbClause("_id", nick, "=")})
        
        if not playerDataList or #playerDataList == 0 then
            print("[DEBUG] Создание нового игрока", nick)
            local newPlayer = {
                _id = nick, 
                balance = 0, 
                items = {},
                created = os.time()
            }
            if not self.db:insert(nick, newPlayer) then
                error("Не удалось создать запись для нового игрока")
            end
            return newPlayer
        end
        
        print("[DEBUG] Найден игрок:", serialization.serialize(playerDataList[1]))
        return playerDataList[1]
    end

    function obj:withdrawItem(nick, id, dmg, count)
        local playerData = self:getPlayerData(nick)
        for i = 1, #playerData.items do
            local item = playerData.items[i]
            if item.id == id and item.dmg == dmg then
                local countToWithdraw = math.min(count, item.count)
                local withdrawedCount = itemUtils.giveItem(id, dmg, countToWithdraw)
                item.count = item.count - withdrawedCount
                
                if item.count == 0 then
                    table.remove(playerData.items, i)
                end
                
                self.db:update(nick, playerData)
                
                if withdrawedCount > 0 then
                    self:logTransaction(nick, "withdraw_item", {
                        id = id,
                        dmg = dmg,
                        count = withdrawedCount
                    }, 0, playerData.balance, playerData.balance)
                    printD(terminalName..": Игрок "..nick.." забрал "..id..":"..dmg.." x"..withdrawedCount)
                    return withdrawedCount, "Выдано "..withdrawedCount.." предметов"
                end
                break
            end
        end
        return 0, "Предметы не найдены!"
    end

    function obj:buyItem(nick, itemCfg, count)
        local playerData = self:getPlayerData(nick)
        local totalCost = count * itemCfg.price
        
        if playerData.balance < totalCost then
            return false, "Не хватает денег на счету"
        end
        
        local itemsCount = itemUtils.giveItem(itemCfg.id, itemCfg.dmg, count)
        if itemsCount > 0 then
            local oldBalance = playerData.balance
            playerData.balance = oldBalance - totalCost
            self.db:update(nick, playerData)
            
            self:logTransaction(nick, "buy", {
                id = itemCfg.id,
                dmg = itemCfg.dmg,
                label = itemCfg.label or itemCfg.id,
                count = itemsCount,
                price = itemCfg.price
            }, totalCost, oldBalance, playerData.balance)
            
            printD(terminalName..": Игрок "..nick.." купил "..itemCfg.id.." x"..itemsCount.." за "..totalCost)
            return itemsCount, "Куплено "..itemsCount.." предметов!"
        end
        
        return 0, "Не удалось выдать предметы"
    end

    function obj:sellItem(nick, itemCfg, count)
        local itemsCount = itemUtils.takeItem(itemCfg.id, itemCfg.dmg, count)
        if itemsCount > 0 then
            local playerData = self:getPlayerData(nick)
            local oldBalance = playerData.balance
            local totalPrice = itemsCount * itemCfg.price
            playerData.balance = oldBalance + totalPrice
            self.db:update(nick, playerData)
            
            self:logTransaction(nick, "sell", {
                id = itemCfg.id,
                dmg = itemCfg.dmg,
                label = itemCfg.label or itemCfg.id,
                count = itemsCount,
                price = itemCfg.price
            }, totalPrice, oldBalance, playerData.balance)
            
            printD(terminalName..": Игрок "..nick.." продал "..itemCfg.id.." x"..itemsCount.." за "..totalPrice)
            return itemsCount, "Продано "..itemsCount.." предметов!"
        end
        
        return 0, "Не удалось принять предметы"
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
            
            if withdrawedCount > 0 then
                self:logTransaction(nick, "withdraw_item", {
                    id = item.id,
                    dmg = item.dmg,
                    count = withdrawedCount
                }, 0, playerData.balance, playerData.balance)
                printD(terminalName..": Игрок "..nick.." забрал "..item.id.." x"..withdrawedCount)
            end
            
            if item.count == 0 then
                table.insert(toRemove, i)
            end
        end
        
        for i = #toRemove, 1, -1 do
            table.remove(playerData.items, toRemove[i])
        end
        
        self.db:update(nick, playerData)
        
        if sum == 0 then
            return 0, itemUtils.countOfAvailableSlots() > 0 and "Предметы не найдены!" or "Освободите инвентарь!"
        end
        
        return sum, "Выдано "..sum.." предметов"
    end

    function obj:exchangeAllOres(nick)
        local items = {}
        for _, itemConfig in pairs(self.oreExchangeList) do
            table.insert(items, {id = itemConfig.fromId, dmg = itemConfig.fromDmg})
        end
        
        local itemsTaken = itemUtils.takeItems(items)
        local playerData = self:getPlayerData(nick)
        local sum = 0
        
        for _, item in pairs(itemsTaken) do
            if item.count > 0 then
                sum = sum + item.count
                local itemCfg
                
                for _, config in pairs(self.oreExchangeList) do
                    if config.fromId == item.id and config.fromDmg == item.dmg then
                        itemCfg = config
                        break
                    end
                end
                
                if itemCfg then
                    local exchangeCount = item.count * itemCfg.toCount / itemCfg.fromCount
                    local itemExists = false
                    
                    for _, playerItem in ipairs(playerData.items) do
                        if playerItem.id == itemCfg.toId and playerItem.dmg == itemCfg.toDmg then
                            playerItem.count = playerItem.count + exchangeCount
                            itemExists = true
                            break
                        end
                    end
                    
                    if not itemExists then
                        table.insert(playerData.items, {
                            id = itemCfg.toId,
                            dmg = itemCfg.toDmg,
                            label = itemCfg.toLabel,
                            count = exchangeCount
                        })
                    end
                    
                    self:logTransaction(nick, "ore_exchange", {
                        id = item.id,
                        dmg = item.dmg,
                        count = item.count,
                        price = 0
                    }, 0, playerData.balance, playerData.balance)
                    
                    printD(terminalName..": Обмен руды "..item.id.." x"..item.count.." на "..itemCfg.toId.." x"..exchangeCount)
                end
            end
        end
        
        self.db:update(nick, playerData)
        
        if sum == 0 then
            return 0, "Нет руды в инвентаре!"
        else
            return sum, "Обменяно "..sum.." руды", "Заберите из корзины"
        end
    end

    function obj:exchangeOre(nick, itemConfig, count)
        local countOfItems = itemUtils.takeItem(itemConfig.fromId, itemConfig.fromDmg, count)
        if countOfItems > 0 then
            local playerData = self:getPlayerData(nick)
            local exchangeCount = countOfItems * itemConfig.toCount / itemConfig.fromCount
            local itemExists = false
            
            for _, item in ipairs(playerData.items) do
                if item.id == itemConfig.toId and item.dmg == itemConfig.toDmg then
                    item.count = item.count + exchangeCount
                    itemExists = true
                    break
                end
            end
            
            if not itemExists then
                table.insert(playerData.items, {
                    id = itemConfig.toId,
                    dmg = itemConfig.toDmg,
                    label = itemConfig.toLabel,
                    count = exchangeCount
                })
            end
            
            self.db:update(nick, playerData)
            self:logTransaction(nick, "ore_exchange", {
                id = itemConfig.fromId,
                dmg = itemConfig.fromDmg,
                count = countOfItems,
                price = 0
            }, 0, playerData.balance, playerData.balance)
            
            printD(terminalName..": Обмен руды "..itemConfig.fromId.." x"..countOfItems.." на "..itemConfig.toId.." x"..exchangeCount)
            return countOfItems, "Обменяно "..countOfItems.." руды", "Заберите из корзины"
        end
        
        return 0, "Нет руды в инвентаре!"
    end

    function obj:exchange(nick, itemConfig, count)
        local countOfItems = itemUtils.takeItem(itemConfig.fromId, itemConfig.fromDmg, count * itemConfig.fromCount)
        local countOfExchanges = math.floor(countOfItems / itemConfig.fromCount)
        local left = countOfItems % itemConfig.fromCount
        local playerData = self:getPlayerData(nick)
        local exchanged = false
        
        if left > 0 then
            local itemExists = false
            for _, item in ipairs(playerData.items) do
                if item.id == itemConfig.fromId and item.dmg == itemConfig.fromDmg then
                    item.count = item.count + left
                    itemExists = true
                    break
                end
            end
            
            if not itemExists then
                table.insert(playerData.items, {
                    id = itemConfig.fromId,
                    dmg = itemConfig.fromDmg,
                    label = itemConfig.fromLabel,
                    count = left
                })
            end
            exchanged = true
        end
        
        if countOfExchanges > 0 then
            local itemExists = false
            for _, item in ipairs(playerData.items) do
                if item.id == itemConfig.toId and item.dmg == itemConfig.toDmg then
                    item.count = item.count + countOfExchanges * itemConfig.toCount
                    itemExists = true
                    break
                end
            end
            
            if not itemExists then
                table.insert(playerData.items, {
                    id = itemConfig.toId,
                    dmg = itemConfig.toDmg,
                    label = itemConfig.toLabel,
                    count = countOfExchanges * itemConfig.toCount
                })
            end
            
            self:logTransaction(nick, "item_exchange", {
                id = itemConfig.fromId,
                dmg = itemConfig.fromDmg,
                count = countOfItems,
                price = 0
            }, 0, playerData.balance, playerData.balance)
            
            printD(terminalName..": Обмен "..itemConfig.fromId.." x"..countOfItems.." на "..itemConfig.toId.." x"..(countOfExchanges * itemConfig.toCount))
            exchanged = true
        end
        
        if exchanged then
            self.db:update(nick, playerData)
            if countOfExchanges > 0 then
                return countOfItems, "Обменяно "..countOfItems.." предметов", "Заберите из корзины"
            end
        end
        
        return 0, "Нет предметов в инвентаре!"
    end

    obj:init()
    setmetatable(obj, self)
    self.__index = self
    return obj
end