local internetLib = require("internet")

local TelegramLog = {}
TelegramLog.__index = TelegramLog

function TelegramLog:new(settings, internet)
    -- Валидация параметров settings
    if not settings or type(settings) ~= "table" then
        error("settings должны быть таблицей")
    end

    if not settings.telegramToken or type(settings.telegramToken) ~= "string" then
        error("telegramToken должен быть строкой")
    end

    if not settings.chatId or type(settings.chatId) ~= "number" or settings.chatId % 1 ~= 0 then
        error("chatId должен быть целым числом (int)")
    end

    if settings.message_thread_id and (type(settings.message_thread_id) ~= "number" or settings.message_thread_id % 1 ~= 0) then
        error("message_thread_id должен быть целым числом (int), если указан")
    end

    local obj = {
        internet = internet or internetLib,
        telegramToken = settings.telegramToken,
        chatId = tostring(settings.chatId),  -- Преобразуем в строку для API
        message_thread_id = settings.message_thread_id and tostring(settings.message_thread_id),  -- Преобразуем в строку для API
        roomLogs = {},
    }
    setmetatable(obj, self)
    return obj
end

function TelegramLog:addLog(time, message)
    local timeFormatted = os.date("%Y-%m-%d %H:%M:%S", time / 1000)
    table.insert(self.roomLogs, {
        time = timeFormatted,
        message = message
    })
end

function TelegramLog:sendLogs()
    if #self.roomLogs > 0 then
        local content = self:_getContentForSend()
        if content then
            local url = "https://api.telegram.org/bot" .. self.telegramToken .. "/sendMessage"
            local headers = { ["Content-Type"] = "application/json" }
            self.internet.request(url, content, headers, "POST")
            self.roomLogs = {} -- Очистить логи после отправки
        end
    end
end

function TelegramLog:_getContentForSend()
    local message = ""
    for _, log in ipairs(self.roomLogs) do
        message = message .. log.time .. " - " .. log.message .. "\n"
    end
    return string.format('{"chat_id": "%s", "text": "%s", "message_thread_id":"%s"}', self.chatId, message, self.message_thread_id)
end

return TelegramLog
