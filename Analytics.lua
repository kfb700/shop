local Analytics = {}
local serialization = require("serialization")
local fs = require("filesystem")

function Analytics:new(db)
    local obj = {
        db = db,
        statsFile = "/home/shop_stats.dat"
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Analytics:recordTransaction(nick, amount, item, isDeposit)
    local stats = self:loadStats()
    local time = os.time()
    
    -- Запись транзакции
    table.insert(stats.transactions, {
        nick = nick,
        amount = amount,
        item = item,
        time = time,
        type = isDeposit and "deposit" or "withdraw"
    })
    
    self:saveStats(stats)
end

function Analytics:loadStats()
    if fs.exists(self.statsFile) then
        return serialization.unserialize(io.open(self.statsFile):read("*a"))
    else
        return {transactions = {}}
    end
end

function Analytics:saveStats(stats)
    local file = io.open(self.statsFile, "w")
    file:write(serialization.serialize(stats))
    file:close()
end

return Analytics
