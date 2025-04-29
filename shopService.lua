local component = require('component')
local itemUtils = require('ItemUtils')
local event = require('event')
local Database = dofile('/home/Database.lua')
local serialization = require("serialization")
local mysql = require("luasql.mysql")

ShopService = {}

-- Конфигурация MySQL
local MYSQL_CONFIG = {
    host = "r-2-veteran.online",
    user = "u2902019_shopmc",
    password = "zZ!53579",
    database = "u2902019_shopmc",
    port = 3306
}

-- Класс для работы с MySQL
local MySQLLogger = {}
MySQLLogger.__index = MySQLLogger

function MySQLLogger:new(config)
    local obj = {
        config = config or MYSQL_CONFIG,
        env = nil,
        conn = nil,
        transactionBuffer = {},
        lastSync = os.time()
    }
    setmetatable(obj, self)
    obj:initConnection()
    return obj
end

function MySQLLogger:initConnection()
    self.env = mysql.mysql()
    self.conn = self.env:connect(self.config.database, self.config.user, 
                               self.config.password, self.config.host, self.config.port)
    if not self.conn then
        print("[MySQL] Failed to connect to database")
        return false
    end
    return true
end

function MySQLLogger:ensureConnection()
    if not self.conn or not self.conn:ping() then
        return self:initConnection()
    end
    return true
end

function MySQLLogger:logTransaction(player_id, transaction_type, item_id, item_name, quantity, amount, details)
    table.insert(self.transactionBuffer, {
        player_id = player_id,
        transaction_type = transaction_type,
        item_id = item_id,
        item_name = item_name,
        quantity = quantity,
        amount = amount,
        details = details,
        timestamp = os.date("%Y-%m-%d %H:%M:%S")
    })
end

function MySQLLogger:syncTransactions()
    if #self.transactionBuffer == 0 then return true end
    
    if not self:ensureConnection() then
        print("[MySQL] Connection failed, retrying next time")
        return false
    end

    local success, err = pcall(function()
        -- Начинаем транзакцию
        self.conn:execute("START TRANSACTION")
        
        -- Создаем временную таблицу для балансов
        self.conn:execute([[
            CREATE TEMPORARY TABLE temp_balances (
                player_id VARCHAR(36) PRIMARY KEY,
                balance_change DECIMAL(15,2) NOT NULL DEFAULT 0
            )
        ]])
        
        -- Вставляем данные транзакций
        for _, t in ipairs(self.transactionBuffer) do
            local query = string.format([[
                INSERT INTO transaction_history 
                (player_id, transaction_type, item_id, item_name, quantity, amount, details, transaction_time) 
                VALUES ('%s', '%s', %s, %s, %d, %.2f, '%s', '%s')
            ]], 
            self.conn:escape(t.player_id), 
            self.conn:escape(t.transaction_type),
            t.item_id and string.format("'%s'", self.conn:escape(t.item_id)) or 'NULL',
            t.item_name and string.format("'%s'", self.conn:escape(t.item_name)) or 'NULL',
            t.quantity or 0,
            t.amount or 0,
            self.conn:escape(t.details or ""),
            t.timestamp)
            
            self.conn:execute(query)
            
            -- Записываем изменения баланса во временную таблицу
            if t.transaction_type == 'deposit' then
                self.conn:execute(string.format([[
                    INSERT INTO temp_balances (player_id, balance_change) 
                    VALUES ('%s', %.2f)
                    ON DUPLICATE KEY UPDATE balance_change = balance_change + %.2f
                ]], self.conn:escape(t.player_id), t.amount, t.amount))
            elseif t.transaction_type == 'withdraw' then
                self.conn:execute(string.format([[
                    INSERT INTO temp_balances (player_id, balance_change) 
                    VALUES ('%s', %.2f)
                    ON DUPLICATE KEY UPDATE balance_change = balance_change - %.2f
                ]], self.conn:escape(t.player_id), t.amount, t.amount))
            end
        end
        
        -- Обновляем балансы игроков
        self.conn:execute([[
            INSERT INTO player_balances (player_id, nickname, balance)
            SELECT player_id, player_id, balance_change FROM temp_balances
            ON DUPLICATE KEY UPDATE balance = balance + VALUES(balance)
        ]])
        
        -- Фиксируем транзакцию
        self.conn:execute("COMMIT")
        
        -- Очищаем буфер
        self.transactionBuffer = {}
        self.lastSync = os.time()
    end)
    
    if not success then
        self.conn:execute("ROLLBACK")
        print("[MySQL] Sync error:", err)
        return false
    end
    
    return true
end

function MySQLLogger:close()
    if self.conn then
        self.conn:close()
    end
    if self.env then
        self.env:close()
    end
end

-- Создаем экземпляр логгера
local mysqlLogger = MySQLLogger:new()

-- Запускаем периодическую синхронизацию (раз в минуту)
event.timer(60, function()
    mysqlLogger:syncTransactions()
end, math.huge)

-- Функция для логирования транзакций
local function logTransaction(player_id, transaction_type, item_id, item_name, quantity, amount, details)
    mysqlLogger:logTransaction(player_id, transaction_type, item_id, item_name, quantity, amount, details)
    
    -- Также сохраняем в файл на случай проблем с MySQL
    local logEntry = string.format("[%s] %s %s: %s x%d (%.2f) - %s\n",
        os.date("%Y-%m-%d %H:%M:%S"),
        player_id,
        transaction_type,
        item_name or item_id or "money",
        quantity or 1,
        amount or 0,
        details or "")
    
    local logFile = io.open("/home/shop_transactions.log", "a")
    if logFile then
        logFile:write(logEntry)
        logFile:close()
    end
end

-- Инициализация Telegram логгеров (оставляем для совместимости)
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

        self.oreExchangeList = readObjectFromFile("/home/config/oreExchanger.cfg")
        self.exchangeList = readObjectFromFile("/home/config/exchanger.cfg")
        self.sellShopList = readObjectFromFile("/home/config/sellShop.cfg")
        self.buyShopList = readObjectFromFile("/home/config/buyShop.cfg")

        self.db = Database:new("USERS")
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
            
            -- Логируем пополнение баланса
            logTransaction(nick, "deposit", nil, "money", nil, countOfMoney, 
                          "Пополнение баланса через терминал " .. terminalName)
            
            printD(terminalName .. ": Игрок " .. nick .. " пополнил баланс на " .. countOfMoney .. " Текущий баланс " .. playerData.balance)
            return playerData.balance, "Баланс пополнен на " .. countOfMoney
        end
        return 0, "Нету монеток в инвентаре!"
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
            
            -- Логируем снятие денег
            logTransaction(nick, "withdraw", nil, "money", nil, countOfMoney,
                         "Снятие денег через терминал " .. terminalName)
            
            printD(terminalName .. ": Игрок " .. nick .. " снял с баланса " .. countOfMoney .. ". Текущий баланс " .. playerData.balance)
            return countOfMoney, "C баланса списанно " .. countOfMoney
        end
        if (itemUtils.countOfAvailableSlots() > 0) then
            return 0, "Нету монеток в магазине!"
        else
            return 0, "Освободите инвентарь!"
        end
    end

    function obj:getPlayerData(nick)
        print("[DEBUG] Загрузка данных для", nick)
        local playerDataList = self.db:select({self:dbClause("_id", nick, "=")})
        
        if not playerDataList or not playerDataList[1] then
            print("[DEBUG] Создание нового игрока", nick)
            local newPlayer = {_id = nick, balance = 0, items = {}}
            if not self.db:insert(nick, newPlayer) then
                print("[ERROR] Не удалось создать запись для нового игрока")
            end
            return newPlayer
        end
        
        print("[DEBUG] Найден баланс:", playerDataList[1].balance)
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
                    printD(terminalName .. ": Игрок " .. nick .. " забрал " .. id .. ":" .. dmg .. " в количестве " .. withdrawedCount)
                end
                return withdrawedCount, "Выданно " .. withdrawedCount .. " вещей"
            end
        end
        return 0, "Вещей нету в наличии!"
    end

    function obj:sellItem(nick, itemCfg, count)
        local playerData = self:getPlayerData(nick)
        if (playerData.balance < count * itemCfg.price) then
            return false, "Не хватает денег на счету"
        end
        local itemsCount = itemUtils.giveItem(itemCfg.id, itemCfg.dmg, count, itemCfg.nbt)
        if (itemsCount > 0) then
            local totalPrice = itemsCount * itemCfg.price
            playerData.balance = playerData.balance - totalPrice
            self.db:update(nick, playerData)
            
            -- Логируем покупку предмета
            logTransaction(nick, "purchase", itemCfg.id, itemCfg.label or itemCfg.id, 
                          itemsCount, totalPrice,
                          "Покупка через терминал " .. terminalName)
            
            printD(terminalName .. ": Игрок " .. nick .. " купил " .. itemCfg.id .. ":" .. itemCfg.dmg .. " в количестве " .. itemsCount .. " по цене " .. itemCfg.price .. " за шт. Текущий баланс " .. playerData.balance)
        end
        return itemsCount, "Куплено " .. itemsCount .. " предметов!"
    end

    function obj:buyItem(nick, itemCfg, count)
        print("[DEBUG] Попытка продажи:", nick, itemCfg.id, count)
        local itemsCount = itemUtils.takeItem(itemCfg.id, itemCfg.dmg, count)
        print("[DEBUG] Предметов принято:", itemsCount)
        if itemsCount > 0 then
            local playerData = self:getPlayerData(nick)
            local oldBalance = playerData.balance
            local totalPrice = itemsCount * itemCfg.price
            playerData.balance = oldBalance + totalPrice
            if not self.db:update(nick, playerData) then
                print("[ERROR] Не удалось сохранить баланс!")
                return 0, "Ошибка сервера"
            end
            
            -- Логируем продажу предмета
            logTransaction(nick, "sale", itemCfg.id, itemCfg.label or itemCfg.id,
                         itemsCount, totalPrice,
                         "Продажа через терминал " .. terminalName)
            
            print("[DEBUG] Баланс изменён:", oldBalance, "->", playerData.balance)
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
                printD(terminalName .. ": Игрок " .. nick .. " забрал " .. item.id .. ":" .. item.dmg .. " в количестве " .. withdrawedCount)
                
                -- Логируем изъятие предмета
                logTransaction(nick, "withdraw", item.id, item.label or item.id,
                             withdrawedCount, 0,
                             "Изъятие предметов через терминал " .. terminalName)
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
            
            -- Логируем обмен руды
            logTransaction(nick, "exchange", itemCfg.fromId, itemCfg.fromLabel or itemCfg.fromId,
                         item.count, 0,
                         "Обмен руды на " .. (itemCfg.toLabel or itemCfg.toId) .. 
                         " по курсу " .. itemCfg.fromCount .. ":" .. itemCfg.toCount)
            
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
            
            -- Логируем обмен руды
            logTransaction(nick, "exchange", itemConfig.fromId, itemConfig.fromLabel or itemConfig.fromId,
                         countOfItems, 0,
                         "Обмен руды на " .. (itemConfig.toLabel or itemConfig.toId) .. 
                         " по курсу " .. itemConfig.fromCount .. ":" .. itemConfig.toCount)
            
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
            
            -- Логируем обмен предметов
            logTransaction(nick, "exchange", itemConfig.fromId, itemConfig.fromLabel or itemConfig.fromId,
                         countOfItems, 0,
                         "Обмен на " .. (itemConfig.toLabel or itemConfig.toId) .. 
                         " по курсу " .. itemConfig.fromCount .. ":" .. itemConfig.toCount)
            
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