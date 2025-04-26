---@module Database
-- Файловая база данных для OpenComputers с поддержкой сериализации.
-- Хранит данные в виде файлов в указанной директории.
-- @license MIT
-- @author YourName
local fs = require('filesystem')
local serialization = require('serialization')

local Database = {}
Database.__index = Database

--- Создает новый экземпляр базы данных.
---@function new
---@classmod Database
---@param directory string Путь к директории для хранения данных
---@return Database новый экземпляр
---@usage local Database = require('database')
---local db = Database:new("players_data")
function Database:new(directory)
    local obj = setmetatable({}, self)
    obj.directory = directory
    
    if not fs.exists(directory) then
        fs.makeDirectory(directory)
    end
    
    return obj
end

--- Сохраняет или полностью заменяет данные по ключу.
---@function insert
---@param key string|number Уникальный идентификатор записи
---@param value table Данные для сохранения (таблица)
---@return boolean true при успешной записи
---@usage db:insert("player123", {balance = 500, items = {}})
function Database:insert(key, value)
    local path = fs.concat(self.directory, tostring(key))
    local file = io.open(path, 'w')
    if not file then return false end
    
    value._id = key
    local serialized = serialization.serialize(value)
    file:write(serialized)
    file:close()
    return true
end

--- Обновляет данные по ключу (полная перезапись).
---@function update
---@param key string|number Уникальный идентификатор записи
---@param value table Новые данные для записи
---@return boolean true при успешном обновлении
---@see insert
---@usage db:update("player123", {balance = 600, items = {}})
function Database:update(key, value)
    return self:insert(key, value)
end

--- Ищет записи по заданным условиям.
---@function select
---@param conditions table[] Список условий в формате {column, value, operation}
---@return table[] Массив найденных записей
---@usage 
--local results = db:select({
--     {column = "balance", value = 1000, operation = ">"},
--     {column = "vip", value = true}
-- })
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
                    
                    if not self:_checkCondition(record[field], value, operation) then
                        match = false
                        break
                    end
                end
                
                if match then
                    table.insert(results, record)
                end
            end
        end
    end
    
    return results
end

--- (Приватный) Проверяет условие для фильтрации.
---@function _checkCondition
---@local
---@param a any Значение из записи
---@param b any Сравниваемое значение
---@param op string Оператор сравнения
---@return boolean Результат проверки
function Database:_checkCondition(a, b, op)
    if op == "=" or op == "==" then
        return a == b
    elseif op == "~=" or op == "!=" then
        return a ~= b
    elseif op == "<" then
        return a < b
    elseif op == "<=" then
        return a <= b
    elseif op == ">" then
        return a > b
    elseif op == ">=" then
        return a >= b
    end
    return false
end

return Database
