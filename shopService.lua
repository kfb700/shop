local component = require('component')
local itemUtils = require('ItemUtils')
local event = require('event')
local internet = require('internet')
local serialization = require("serialization")
local fs = require('filesystem')

-- Настройки Discord
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1366871469526745148/oW2yVyCNevcBHrXAmvKM1506GIWWFKkQ3oqwa2nNjd_KNDTbDR_c6_6le9TBewpjnTqy"
local DISCORD_USERNAME = "Minecraft Shop"
local DISCORD_AVATAR = "https://www.minecraft.net/content/dam/minecraft/touchup-2020/minecraft-logo.svg"

-- Логирование
local LOG_FILE = "/home/shop_log.txt"
local function log(message)
    local logEntry = os.date("[%Y-%m-%d %H:%M:%S] ") .. message .. "\n"
    print(logEntry:sub(1, -2)) -- Вывод в консоль без переноса
    
    -- Запись в файл
    local file = io.open(LOG_FILE, "a")
    if file then
        file:write(logEntry)
        file:close()
    end
end

-- Модуль Database
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
    if not file then 
        log("Ошибка записи в БД: "..path)
        return false 
    end
    
    value._id = key
    local ok, serialized = pcall(serialization.serialize, value)
    if not ok then
        log("Ошибка сериализации данных")
        file:close()
        return false
    end
    
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
        local fh, err = io.open(path, 'r')
        if not fh then
            log("Ошибка чтения файла "..path..": "..(err or "unknown"))
            goto continue
        end
        
        local data = fh:read('*a')
        fh:close()
        
        local ok, record = pcall(serialization.unserialize, data)
        if not ok or not record then
            log("Ошибка десериализации "..path)
            goto continue
        end
        
        local match = true
        for _, cond in ipairs(conditions or {}) do
            local field, value, op = cond.column, cond.value, cond.operation or "=="
            local fieldValue = record[field]
            
            if op == "==" and fieldValue ~= value then
                match = false
            elseif op == "~=" and fieldValue == value then
                match = false
            elseif op == "<" and not (fieldValue < value) then
                match = false
            elseif op == "<=" and not (fieldValue <= value) then
                match = false
            elseif op == ">" and not (fieldValue > value) then
                match = false
            elseif op == ">=" and not (fieldValue >= value) then
                match = false
            end
            
            if not match then break end
        end
        
        if match then
            table.insert(results, record)
        end
        
        ::continue::
    end
    
    return results
end

-- Улучшенная отправка в Discord
local function sendToDiscord(message)
    -- Проверка интернет-карты
    if not component.isAvailable("internet") then
        log("Интернет-карта не доступна")
        return false
    end

    -- Подготовка данных
    local payload = {
        content = message,
        username = DISCORD_USERNAME,
        avatar_url = DISCORD_AVATAR
    }

    local ok, json = pcall(serialization.serialize, payload)
    if not ok then
        log("Ошибка сериализации Discord сообщения")
        return false
    end

    -- Отправка с повторными попытками
    for attempt = 1, 3 do
        local success, err = pcall(function()
            local request = internet.request(
                DISCORD_WEBHOOK,
                json,
                {
                    ["Content-Type"] = "application/json",
                    ["User-Agent"] = "OC-Shop/1.0"
                },
                "POST"
            )
            
            -- Ожидаем ответ 5 секунд
            for _ = 1, 5 do
                if request.finishConnect() ~= nil then
                    return true
                end
                os.sleep(1)
            end
            return false
        end)

        if success and err then
            log("Сообщение отправлено в Discord: "..message)
            return true
        else
            log(string.format("Попытка %d не удалась: %s", attempt, err or "таймаут"))
            os.sleep(2)
        end
    end
    
    log("Не удалось отправить сообщение в Discord после 3 попыток")
    return false
end

-- Функция чтения конфигов
local function readConfig(path)
    local file, err = io.open(path, "r")
    if not file then
        log("Ошибка открытия конфига "..path..": "..(err or ""))
        return nil
    end
    
    local content = file:read("*a")
    file:close()
    
    local ok, data = pcall(serialization.unserialize, content)
    if not ok then
        log("Ошибка парсинга конфига "..path)
        return nil
    end
    
    return data
end

-- Основной модуль ShopService
ShopService = {}

function ShopService:new(terminalName)
    local obj = {}
    
    function obj:init()
        self.terminalName = terminalName or "Без названия"
        
        -- Загрузка конфигов
        self.oreExchangeList = readConfig("/home/config/oreExchanger.cfg") or {}
        self.exchangeList = readConfig("/home/config/exchanger.cfg") or {}
        self.sellShopList = readConfig("/home/config/sellShop.cfg") or {}
        self.buyShopList = readConfig("/home/config/buyShop.cfg") or {}

        -- Валюта
        self.currencies = {
            {item = {name = "minecraft:gold_nugget", damage = 0}, money = 1000},
            {item = {name = "minecraft:gold_ingot", damage = 0}, money = 10000},
            {item = {name = "minecraft:diamond", damage = 0}, money = 100000},
            {item = {name = "minecraft:emerald", damage = 0}, money = 1000000}
        }
        itemUtils.setCurrency(self.currencies)
        
        -- База данных
        self.db = Database:new("USERS")
        
        sendToDiscord("🔄 Магазин "..self.terminalName.." запущен")
        log("Магазин "..self.terminalName.." инициализирован")
    end

    -- Вспомогательные функции
    function obj:dbClause(field, value, op)
        return {column = field, value = value, operation = op or "=="}
    end

    -- API магазина
    function obj:getPlayerData(nick)
        local data = self.db:select({self:dbClause("_id", nick)})[1]
        if not data then
            data = {_id = nick, balance = 0, items = {}}
            if not self.db:insert(nick, data) then
                log("Ошибка создания профиля "..nick)
            else
                sendToDiscord("🆕 Новый игрок: "..nick)
            end
        end
        return data
    end

    function obj:depositMoney(nick, amount)
        local taken = itemUtils.takeMoney(amount)
        if taken > 0 then
            local data = self:getPlayerData(nick)
            data.balance = data.balance + taken
            self.db:update(nick, data)
            sendToDiscord(string.format("💰 %s +%d (Баланс: %d)", nick, taken, data.balance))
            return data.balance
        end
        return 0
    end

    function obj:withdrawMoney(nick, amount)
        local data = self:getPlayerData(nick)
        if data.balance < amount then
            return 0
        end
        
        local given = itemUtils.giveMoney(amount)
        if given > 0 then
            data.balance = data.balance - given
            self.db:update(nick, data)
            sendToDiscord(string.format("💸 %s -%d (Баланс: %d)", nick, given, data.balance))
            return given
        end
        return 0
    end

    function obj:sellItem(nick, item, count)
        local data = self:getPlayerData(nick)
        local total = item.price * count
        
        if data.balance < total then
            return 0
        end
        
        local given = itemUtils.giveItem(item.id, item.dmg, count, item.nbt)
        if given > 0 then
            data.balance = data.balance - (item.price * given)
            self.db:update(nick, data)
            local name = item.label or item.id
            sendToDiscord(string.format("🛒 %s купил %s ×%d за %d", nick, name, given, item.price))
            return given
        end
        return 0
    end

    function obj:buyItem(nick, item, count)
        local taken = itemUtils.takeItem(item.id, item.dmg, count)
        if taken > 0 then
            local data = self:getPlayerData(nick)
            data.balance = data.balance + (item.price * taken)
            self.db:update(nick, data)
            local name = item.label or item.id
            sendToDiscord(string.format("🏪 %s продал %s ×%d за %d", nick, name, taken, item.price))
            return taken
        end
        return 0
    end

    -- Остальные методы остаются аналогичными, но используют sendToDiscord вместо printD
    
    obj:init()
    setmetatable(obj, self)
    self.__index = self
    return obj
end

-- Тестирование при загрузке
local function selfTest()
    log("=== ТЕСТИРОВАНИЕ ===")
    
    -- Тест Discord
    log("Тест Discord...")
    local testMsg = "Тест магазина "..os.date("%H:%M:%S")
    local res = sendToDiscord(testMsg)
    log("Discord test: "..(res and "OK" or "FAIL"))
    
    -- Тест БД
    log("Тест базы данных...")
    local db = Database:new("TEST_DB")
    db:insert("test", {value = 123})
    local data = db:select({{column = "value", value = 123}})
    log("DB test: "..(#data > 0 and "OK" or "FAIL"))
    fs.remove("/home/TEST_DB/test")
    
    log("=== ТЕСТ ЗАВЕРШЕН ===")
end

-- Запустить тест при загрузке (можно отключить)
selfTest()

return ShopService