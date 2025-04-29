local component = require("component")
local serialization = require("serialization")

Database = {}

function Database:new(tableName)
    local db = component.proxy(component.list("database")())
    if not db then error("Database component not found") end
    
    local function ensureTable()
        if not db.get(tableName) then
            db.set(tableName, {})
        end
    end
    
    ensureTable()
    
    local methods = {}
    
    function methods:select(query)
        local data = db.get(tableName) or {}
        if not query or #query == 0 then
            return data
        end
        
        local results = {}
        for id, record in pairs(data) do
            local match = true
            for _, clause in ipairs(query) do
                if clause.operation == "=" then
                    if record[clause.column] ~= clause.value then
                        match = false
                        break
                    end
                end
            end
            if match then
                table.insert(results, record)
            end
        end
        return results
    end
    
    function methods:insert(id, data)
        local allData = db.get(tableName) or {}
        allData[id] = data
        return db.set(tableName, allData)
    end
    
    function methods:update(id, data)
        return self:insert(id, data)
    end
    
    function methods:delete(id)
        local allData = db.get(tableName) or {}
        allData[id] = nil
        return db.set(tableName, allData)
    end
    
    return methods
end

return Database