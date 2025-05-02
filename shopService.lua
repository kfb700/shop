local component = require('component')
local itemUtils = require('ItemUtils')
local event = require('event')
local internet = require('internet')
local serialization = require("serialization")
local fs = require('filesystem')
local os = require('os')

-- Сначала определяем модуль Database локально
local Database = {}
Database.__index = Database

function Database:new(directory)
    local obj = setmetatable({}, self)
    obj.directory = "/home/"..directory
    
    if not fs.exists(obj.directory) then
        fs.makeDirectory(obj.directory)
    end
    
    return obj
end

function Database:insert(key, value)
    local path = fs.concat(self.directory, tostring(key))
    local file = io.open(path, "w")
    if not file then return false end
    
    value._id = key
    local serialized = serialization.serialize(value)
    file:write(serialized)
    file:close()
    return true
end

function Database:update(key, value)
    return self:insert(key, value)
end

function Database:select(conditions)
    local results = {}
    
    for file in fs.list(self.directory) do
        local path = fs.concat(self.directory, file)
        local fh = io.open(path, 'r')
        if fh then
            local data = fh:read('*a')
            fh:close()
            local ok, record = pcall(serialization.unserialize, data)
            
            if ok and record then
                local match = true
                for _, condition in ipairs(conditions or {}) do
                    local field = condition.column
                    local value = condition.value
                    local operation = condition.operation or "=="
                    
                    if operation == "=" or operation == "==" then
                        if record[field] ~= value then match = false end
                    elseif operation == "~=" or operation == "!=" then
                        if record[field] == value then match = false end
                    elseif operation == "<" then
                        if not (record[field] < value) then match = false end
                    elseif operation == "<=" then
                        if not (record[field] <= value) then match = false end
                    elseif operation == ">" then
                        if not (record[field] > value) then match = false end
                    elseif operation == ">=" then
                        if not (record[field] >= value) then match = false end
                    end
                    
                    if not match then break end
                end
                
                if match then
                    table.insert(results, record)
                end
            end
        end
    end
    
    return results
end

-- Теперь определяем ShopService
ShopService = {}
ShopService.__index = ShopService

-- Конфигурация Discord Webhook
local DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/1366871469526745148/oW2yVyCNevcBHrXAmvKM1506GIWWFKkQ3oqwa2nNjd_KNDTbDR_c6_6le9TBewpjnTqy"

local function sendToDiscord(message)
    -- Всегда возвращаем успех
    local function escapeJson(str)
        return str:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
    end

    local content = escapeJson(message)
    local jsonData = string.format('{"content":"%s","username":"Minecraft Shop"}', content)
    
    -- Пытаемся отправить, но не обрабатываем ошибки
    pcall(function()
        if component.isAvailable("internet") then
            local request = component.internet.request(
                DISCORD_WEBHOOK_URL,
                jsonData,
                {
                    ["Content-Type"] = "application/json",
                    ["User-Agent"] = "OC-Shop-Webhook"
                },
                "POST"
            )
            request.finishConnect()
        end
    end)
    
    return true
end

local function printD(message)
    -- Убираем print(message) - больше не выводим в игровой интерфейс
    local success = sendToDiscord(message)
    -- Также убираем сообщение об ошибке, если хотим скрыть все уведомления
    -- if not success then
    --     print("⚠️ Не удалось отправить сообщение в Discord")
    -- end
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
    setmetatable(obj, self)
    
    obj.terminalName = terminalName or "Bober Shop"
    
    -- Инициализация данных
    obj.oreExchangeList = readObjectFromFile("/home/config/oreExchanger.cfg") or {}
    obj.exchangeList = readObjectFromFile("/home/config/exchanger.cfg") or {}
    obj.sellShopList = readObjectFromFile("/home/config/sellShop.cfg") or {}
    obj.buyShopList = readObjectFromFile("/home/config/buyShop.cfg") or {}

    obj.currencies = {
        {item = {name = "minecraft:gold_nugget", damage = 0}, money = 1000},
        {item = {name = "minecraft:gold_ingot", damage = 0}, money = 10000},
        {item = {name = "minecraft:diamond", damage = 0}, money = 100000},
        {item = {name = "minecraft:emerald", damage = 0}, money = 1000000}
    }

    itemUtils.setCurrency(obj.currencies)
    
    obj.db = Database:new("USERS")
    
    -- Сообщение только в Discord
    printD("🔄 " .. obj.terminalName .. " инициализирован")
    
    -- Методы объекта
    function obj:dbClause(fieldName, fieldValue, typeOfClause)
        return {
            column = fieldName,
            value = fieldValue,
            operation = typeOfClause or "=="
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

    function obj:sendSupportMessage(nick, message)
        if not message or message == "" then
            return false, "Сообщение не может быть пустым"
        end
        
        if #message > 500 then
            return false, "Сообщение слишком длинное (макс. 500 символов)"
        end
        
        -- Форматируем сообщение без Markdown, если есть проблемы
        local discordMessage = string.format("📩 **Новое сообщение от: %s:**\n\n```%s```", nick, message)
        
        local success, err = sendToDiscord(discordMessage)
        
        if success then
            --print("📩 " .. nick .. " отправил сообщение поддержки")
            return true, "Сообщение отправлено!"
        else
           -- return false, "Ошибка отправки: " .. tostring(err)
        end
    end

    function obj:depositMoney(nick, count)
        local countOfMoney = itemUtils.takeMoney(count)
        if countOfMoney > 0 then
            local playerData = self:getPlayerData(nick)
            playerData.balance = playerData.balance + countOfMoney
            self.db:insert(nick, playerData)
            printD("💰 " .. nick .. " пополнил баланс на " .. countOfMoney .. " в " .. obj.terminalName .. ". Баланс: " .. playerData.balance)
            return playerData.balance, "Баланс пополнен на " .. countOfMoney
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
            playerData.balance = playerData.balance - countOfMoney
            self.db:insert(nick, playerData)
            printD("💸 " .. nick .. " снял " .. countOfMoney .. " в " .. obj.terminalName .. ". Баланс: " .. playerData.balance)
            return countOfMoney, "С баланса списано " .. countOfMoney
        end
        
        return 0, itemUtils.countOfAvailableSlots() > 0 and "Нет монет в магазине!" or "Освободите инвентарь!"
    end

    function obj:getPlayerData(nick)
        local playerDataList = self.db:select({self:dbClause("_id", nick)})
        
        if not playerDataList or not playerDataList[1] then
            local newPlayer = {_id = nick, balance = 0, items = {}}
            if not self.db:insert(nick, newPlayer) then
                printD("⚠️ Ошибка создания игрока " .. nick .. " в " .. obj.terminalName)
            else
                printD("🆕 Новый игрок " .. nick .. " зарегистрирован в " .. obj.terminalName)
            end
            return newPlayer
        end
        
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
                    printD("📤 " .. nick .. " забрал " .. id .. ":" .. dmg .. " (x" .. withdrawedCount .. ") из " .. obj.terminalName)
                end
                return withdrawedCount, "Выдано " .. withdrawedCount .. " предметов"
            end
        end
        return 0, "Предметов нет в наличии!"
    end

    function obj:sellItem(nick, itemCfg, count)
        local playerData = self:getPlayerData(nick)
        local totalPrice = count * itemCfg.price
        
        if playerData.balance < totalPrice then
            return false, "Не хватает денег на счету"
        end
        
        local itemsCount = itemUtils.giveItem(itemCfg.id, itemCfg.dmg, count, itemCfg.nbt)
        if itemsCount > 0 then
            playerData.balance = playerData.balance - (itemsCount * itemCfg.price)
            self.db:update(nick, playerData)
            local itemName = itemCfg.label or (itemCfg.id .. ":" .. itemCfg.dmg)
            printD(":green_circle: ```**" .. nick .. "** купил " .. itemName .. " (x" .. itemsCount .. ") по " .. itemCfg.price .. " в " .. obj.terminalName .. ". Баланс: " .. playerData.balance .. "```")
            return itemsCount, "Куплено " .. itemsCount .. " предметов!"
        end
        return 0, "Ошибка выдачи предмета"
    end

    function obj:buyItem(nick, itemCfg, count)
        local itemsCount = itemUtils.takeItem(itemCfg.id, itemCfg.dmg, count)
        if itemsCount > 0 then
            local playerData = self:getPlayerData(nick)
            playerData.balance = playerData.balance + (itemsCount * itemCfg.price)
            
            if not self.db:update(nick, playerData) then
                printD("⚠️ Ошибка сохранения баланса для " .. nick .. " в " .. obj.terminalName)
                return 0, "Ошибка сервера"
            end
            
            local itemName = itemCfg.label or (itemCfg.id .. ":" .. itemCfg.dmg)
            printD(":green_circle: ```**" .. nick .. "** продал " .. itemName .. " (x" .. itemsCount .. ") по " .. itemCfg.price .. " в " .. obj.terminalName .. ". Баланс: " .. playerData.balance .. "```")
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
            
            if item.count == 0 then
                table.insert(toRemove, i)
            end
            
            if withdrawedCount > 0 then
                printD("📦 " .. nick .. " забрал " .. item.id .. ":" .. item.dmg .. " (x" .. withdrawedCount .. ") из " .. obj.terminalName)
            end
        end
        
        for i = #toRemove, 1, -1 do
            table.remove(playerData.items, toRemove[i])
        end
        
        self.db:update(nick, playerData)
        
        if sum == 0 then
            return sum, itemUtils.countOfAvailableSlots() > 0 and "Предметов нет в наличии!" or "Освободите инвентарь!"
        end
        return sum, "Выдано " .. sum .. " предметов"
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
            sum = sum + item.count
            local itemCfg
            for _, itemConfig in pairs(self.oreExchangeList) do
                if item.id == itemConfig.fromId and item.dmg == itemConfig.fromDmg then
                    itemCfg = itemConfig
                    break
                end
            end
            
            printD("♻️ " .. nick .. " обменял " .. itemCfg.fromId .. ":" .. itemCfg.fromDmg .. " (x" .. item.count .. ") на " .. itemCfg.toId .. ":" .. itemCfg.toDmg .. " в " .. obj.terminalName)
            
            local found = false
            for _, storedItem in ipairs(playerData.items) do
                if storedItem.id == itemCfg.toId and storedItem.dmg == itemCfg.toDmg then
                    storedItem.count = storedItem.count + (item.count * itemCfg.toCount / itemCfg.fromCount)
                    found = true
                    break
                end
            end
            
            if not found then
                table.insert(playerData.items, {
                    id = itemCfg.toId,
                    dmg = itemCfg.toDmg,
                    label = itemCfg.toLabel,
                    count = item.count * itemCfg.toCount / itemCfg.fromCount
                })
            end
        end
        
        self.db:update(nick, playerData)
        
        if sum == 0 then
            return 0, "Нет руд в инвентаре!"
        end
        return sum, "Обменяно " .. sum .. " руд на слитки.", "Заберите из корзины"
    end

    function obj:exchangeOre(nick, itemConfig, count)
        local countOfItems = itemUtils.takeItem(itemConfig.fromId, itemConfig.fromDmg, count)
        if countOfItems > 0 then
            local playerData = self:getPlayerData(nick)
            local found = false
            
            for _, item in ipairs(playerData.items) do
                if item.id == itemConfig.toId and item.dmg == itemConfig.toDmg then
                    item.count = item.count + (countOfItems * itemConfig.toCount / itemConfig.fromCount)
                    found = true
                    break
                end
            end
            
            if not found then
                table.insert(playerData.items, {
                    id = itemConfig.toId,
                    dmg = itemConfig.toDmg,
                    label = itemConfig.toLabel,
                    count = countOfItems * itemConfig.toCount / itemConfig.fromCount
                })
            end
            
            self.db:update(nick, playerData)
            printD("♻️ " .. nick .. " обменял " .. itemConfig.fromId .. ":" .. itemConfig.fromDmg .. " (x" .. countOfItems .. ") на " .. itemConfig.toId .. ":" .. itemConfig.toDmg .. " в " .. obj.terminalName)
            return countOfItems, "Обменяно " .. countOfItems .. " руд на слитки.", "Заберите из корзины"
        end
        return 0, "Нет руд в инвентаре!"
    end

    function obj:exchange(nick, itemConfig, count)
        local countOfItems = itemUtils.takeItem(itemConfig.fromId, itemConfig.fromDmg, count * itemConfig.fromCount)
        local countOfExchanges = math.floor(countOfItems / itemConfig.fromCount)
        local left = math.floor(countOfItems % itemConfig.fromCount)
        local updated = false
        local playerData = self:getPlayerData(nick)
        
        if left > 0 then
            updated = true
            local found = false
            
            for _, item in ipairs(playerData.items) do
                if item.id == itemConfig.fromId and item.dmg == itemConfig.fromDmg then
                    item.count = item.count + left
                    found = true
                    break
                end
            end
            
            if not found then
                table.insert(playerData.items, {
                    id = itemConfig.fromId,
                    dmg = itemConfig.fromDmg,
                    label = itemConfig.fromLabel,
                    count = left
                })
            end
        end
        
        if countOfExchanges > 0 then
            updated = true
            local found = false
            
            for _, item in ipairs(playerData.items) do
                if item.id == itemConfig.toId and item.dmg == itemConfig.toDmg then
                    item.count = item.count + (countOfExchanges * itemConfig.toCount)
                    found = true
                    break
                end
            end
            
            if not found then
                table.insert(playerData.items, {
                    id = itemConfig.toId,
                    dmg = itemConfig.toDmg,
                    label = itemConfig.toLabel,
                    count = countOfExchanges * itemConfig.toCount
                })
            end
            
            printD("🔄 " .. nick .. " обменял " .. itemConfig.fromId .. ":" .. itemConfig.fromDmg .. " (x" .. countOfItems .. ") на " .. itemConfig.toId .. ":" .. itemConfig.toDmg .. " в " .. obj.terminalName)
        end
        
        if updated then
            self.db:update(nick, playerData)
            if countOfExchanges > 0 then
                return countOfItems, "Обменяно " .. countOfItems .. " предметов.", "Заберите из корзины"
            end
        end
        
        return 0, "Нет предметов в инвентаре!"
    end

    return obj
end

return ShopService