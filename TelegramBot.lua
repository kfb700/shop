local internet = require("internet")
local serialization = require("serialization")
local Analytics = require("Analytics")
local Database = require("Database")

local TelegramBot = {}
TelegramBot.__index = TelegramBot

function TelegramBot:new(token, chatId)
    local obj = {
        token = token,
        chatId = chatId,
        analytics = Analytics:new(Database:new("USERS")),
        commands = {
            ["/top"] = "getTopBalances",
            ["/stats"] = "getStats"
        }
    }
    setmetatable(obj, self)
    return obj
end

function TelegramBot:processCommand(cmd, period)
    if cmd == "/top" then
        return self:getTopBalances()
    elseif cmd == "/stats" then
        return self:getStats(period)
    end
    return "Неизвестная команда"
end

function TelegramBot:getTopBalances()
    local users = Database:new("USERS"):getAllBalances()
    local msg = "🏆 Топ балансов:\n\n"
    for i, user in ipairs(users) do
        msg = msg .. string.format("%d. %s: %.2f\n", i, user.name, user.balance)
        if i >= 10 then break end
    end
    return msg
end

function TelegramBot:getStats(period)
    -- Реализация фильтрации по периодам
    return "Статистика за "..(period or "все время")
end

function TelegramBot:run()
    while true do
        local updates = self:getUpdates()
        for _, update in ipairs(updates) do
            if update.message and update.message.text then
                local response = self:processCommand(update.message.text)
                self:sendMessage(update.message.chat.id, response)
            end
        end
        os.sleep(5)
    end
end

return TelegramBot
