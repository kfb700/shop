local component = require('component')
local itemUtils = require('ItemUtils')
local event = require('event')
local internet = require('internet')
local serialization = require("serialization")

ShopService = {}

-- Конфигурация Discord Webhook
local DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/1366871469526745148/oW2yVyCNevcBHrXAmvKM1506GIWWFKkQ3oqwa2nNjd_KNDTbDR_c6_6le9TBewpjnTqy"
local DISCORD_HEADERS = {
    ["Content-Type"] = "application/json",
    ["User-Agent"] = "OC-Minecraft-Shop/1.0"
}

event.shouldInterrupt = function()
    return false
end

-- Функция для отправки сообщений в Discord
local function sendToDiscord(message)
    local success, err = pcall(function()
        local jsonMessage = serialization.serialize({content = message})
        local request = internet.request(DISCORD_WEBHOOK_URL, jsonMessage, DISCORD_HEADERS, "POST")
        local response = request.finishConnect()
        return response ~= nil
    end)
    
    if not success then
        print("[DISCORD ERROR] " .. tostring(err))
    end
end

local function printD(message)
    -- Логирование в консоль и Discord
    print(message)
    sendToDiscord(message)
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
        self.terminalName = terminalName or "Unknown Terminal"
        
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
        
        -- Инициализация базы данных
        self.db = Database:new("USERS")
        
        printD("🔄 " .. self.terminalName .. " инициализирован")
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

    function obj:depositMoney(nick, count)
        local countOfMoney = itemUtils.takeMoney(count)
        if (countOfMoney > 0) then
            local playerData = self:getPlayerData(nick)
            playerData.balance = playerData.balance + countOfMoney
            self.db:insert(nick, playerData)
            printD("💰 " .. nick .. " пополнил баланс на " .. countOfMoney .. " в " .. self.terminalName .. ". Баланс: " .. playerData.balance)
            return playerData.balance, "Баланс пополнен на " .. countOfMoney
        end
        return 0, "Нет монет в инвентаре!"
    end

    function obj:withdrawMoney(nick, count)
        local playerData = self:getPlayerData(nick)
        if (playerData.balance < count) then
            return 0, "Не хватает денег на счету"
        end
        local countOfMoney = itemUtils.giveMoney(count)
        if (countOfMoney > 0) then
            playerData.balance = playerData.balance - countOfMoney
            self.db:insert(nick, playerData)
            printD("💸 " .. nick .. " снял " .. countOfMoney .. " в " .. self.terminalName .. ". Баланс: " .. playerData.balance)
            return countOfMoney, "С баланса списано " .. countOfMoney
        end
        if (itemUtils.countOfAvailableSlots() > 0) then
            return 0, "Нет монет в магазине!"
        else
            return 0, "Освободите инвентарь!"
        end
    end

    function obj:getPlayerData(nick)
        local playerDataList = self.db:select({self:dbClause("_id", nick, "=")})
        
        if not playerDataList or not playerDataList[1] then
            local newPlayer = {_id = nick, balance = 0, items = {}}
            if not self.db:insert(nick, newPlayer) then
                printD("⚠️ Ошибка создания игрока " .. nick .. " в " .. self.terminalName)
            else
                printD("🆕 Новый игрок " .. nick .. " зарегистрирован в " .. self.terminalName)
            end
            return newPlayer
        end
        
        return playerDataList[1]
    end

    function obj:withdrawItem(nick, id, dmg, count)
        local playerData = self:getPlayerData(nick)
        for i = 1, #playerData.items do
            local item = playerData.items[i]
            if (item.id == id and item.dmg == dmg) then
                local countToWithdraw = math.min(count, item.count)
                local withdrawedCount = itemUtils.giveItem(id, dmg, countToWithdraw)
                item.count = item.count - withdrawedCount
                if (item.count == 0) then
                    table.remove(playerData.items, i)
                end
                self.db:update(nick, playerData)
                if (withdrawedCount > 0) then
                    printD("📤 " .. nick .. " забрал " .. id .. ":" .. dmg .. " (x" .. withdrawedCount .. ") из " .. self.terminalName)
                end
                return withdrawedCount, "Выдано " .. withdrawedCount .. " предметов"
            end
        end
        return 0, "Предметов нет в наличии!"
    end

    function obj:sellItem(nick, itemCfg, count)
        local playerData = self:getPlayerData(nick)
        if (playerData.balance < count * itemCfg.price) then
            return false, "Не хватает денег на счету"
        end
        local itemsCount = itemUtils.giveItem(itemCfg.id, itemCfg.dmg, count, itemCfg.nbt)
        if (itemsCount > 0) then
            playerData.balance = playerData.balance - itemsCount * itemCfg.price
            self.db:update(nick, playerData)
            local itemName = itemCfg.label or (itemCfg.id .. ":" .. itemCfg.dmg)
            printD("🛒 " .. nick .. " купил " .. itemName .. " (x" .. itemsCount .. ") по " .. itemCfg.price .. " в " .. self.terminalName .. ". Баланс: " .. playerData.balance)
            return itemsCount, "Куплено " .. itemsCount .. " предметов!"
        end
        return 0, "Ошибка выдачи предмета"
    end

    function obj:buyItem(nick, itemCfg, count)
        local itemsCount = itemUtils.takeItem(itemCfg.id, itemCfg.dmg, count)
        if itemsCount > 0 then
            local playerData = self:getPlayerData(nick)
            local oldBalance = playerData.balance
            playerData.balance = oldBalance + (itemsCount * itemCfg.price)
            if not self.db:update(nick, playerData) then
                printD("⚠️ Ошибка сохранения баланса для " .. nick .. " в " .. self.terminalName)
                return 0, "Ошибка сервера"
            end
            local itemName = itemCfg.label or (itemCfg.id .. ":" .. itemCfg.dmg)
            printD("🏪 " .. nick .. " продал " .. itemName .. " (x" .. itemsCount .. ") по " .. itemCfg.price .. " в " .. self.terminalName .. ". Баланс: " .. playerData.balance)
            return itemsCount, "Продано "..itemsCount.." предметов"
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
            if (item.count == 0) then
                table.insert(toRemove, i)
            end
            if (withdrawedCount > 0) then
                printD("📦 " .. nick .. " забрал " .. item.id .. ":" .. item.dmg .. " (x" .. withdrawedCount .. ") из " .. self.terminalName)
            end
        end
        for i = #toRemove, 1, -1 do
            table.remove(playerData.items, toRemove[i])
        end
        self.db:update(nick, playerData)
        if (sum == 0) then
            if (itemUtils.countOfAvailableSlots() > 0) then
                return sum, "Предметов нет в наличии!"
            else
                return sum, "Освободите инвентарь!"
            end
        end
        return sum, "Выдано " .. sum .. " предметов"
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
            printD("♻️ " .. nick .. " обменял " .. itemCfg.fromId .. ":" .. itemCfg.fromDmg .. " (x" .. item.count .. ") на " .. itemCfg.toId .. ":" .. itemCfg.toDmg .. " в " .. self.terminalName)
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
            return 0, "Нет руд в инвентаре!"
        else
            return sum, "Обменяно " .. sum .. " руд на слитки.", "Заберите из корзины"
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
            printD("♻️ " .. nick .. " обменял " .. itemConfig.fromId .. ":" .. itemConfig.fromDmg .. " (x" .. countOfItems .. ") на " .. itemConfig.toId .. ":" .. itemConfig.toDmg .. " в " .. self.terminalName)
            return countOfItems, "Обменяно " .. countOfItems .. " руд на слитки.", "Заберите из корзины"
        end
        return 0, "Нет руд в инвентаре!"
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
            printD("🔄 " .. nick .. " обменял " .. itemConfig.fromId .. ":" .. itemConfig.fromDmg .. " (x" .. countOfItems .. ") на " .. itemConfig.toId .. ":" .. itemConfig.toDmg .. " в " .. self.terminalName)
        end
        if(save) then
            self.db:update(nick, playerData)
            if (countOfExchanges > 0) then
                return countOfItems, "Обменяно " .. countOfItems .. " предметов.", "Заберите из корзины"
            end
        end
        return 0, "Нет предметов в инвентаре!"
    end

    obj:init()
    setmetatable(obj, self)
    self.__index = self
    return obj
end

return ShopService