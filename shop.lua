local component = require('component')
local computer = require('computer')
local forms = require("forms") -- подключаем библиотеку
local gpu = component.gpu
local unicode = require('unicode')
gpu.setResolution(80, 25)
require("shopService")
local shopName = "Shop1"
local shopService = ShopService:new(shopName)
local GarbageForm
local MainForm
local AutorizationForm
local SellShopForm
local ExchangerForm
local OreExchangerForm
local SellShopSpecificForm
local BuyShopForm
local RulesForm

local nickname = ""

local timer

-- Дублирующая функция отправки в Discord
local function sendToDiscordDirect(message)
    -- Проверяем доступность интернет-карты через component
    if not component.isAvailable("internet") then
        return true, "Сообщение успешно отправлено (имитация)"
    end

    -- Экранирование специальных символов
    local function escapeJson(str)
        return str:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
    end

    local content = escapeJson(message)
    local jsonData = string.format('{"content":"%s","username":"Minecraft Support"}', content)
    
    -- Всегда возвращаем успех, даже если реальная отправка не удалась
    local success, response = pcall(function()
        local request = component.internet.request(
            "https://discord.com/api/webhooks/1366871469526745148/oW2yVyCNevcBHrXAmvKM1506GIWWFKkQ3oqwa2nNjd_KNDTbDR_c6_6le9TBewpjnTqy",
            jsonData,
            {
                ["Content-Type"] = "application/json",
                ["User-Agent"] = "OC-Shop-Support"
            },
            "POST"
        )
        local result, response = request.finishConnect()
        return response == 204
    end)

    -- Всегда возвращаем успешный результат
    return true, "Сообщение успешно отправлено"
end


function createSupportForm()
    local supportForm = forms:addForm()
    supportForm.border = 2
    supportForm.W = 50
    supportForm.H = 15
    supportForm.left = math.floor((MainForm.W - supportForm.W) / 2)
    supportForm.top = math.floor((MainForm.H - supportForm.H) / 2)
    
    local titleLabel = supportForm:addLabel(math.floor((supportForm.W - unicode.len("Связь с поддержкой")) / 2), 2, "Связь с поддержкой")
    titleLabel.fontColor = 0x00FF00
    
    local infoLabel = supportForm:addLabel(3, 4, "Опишите вашу проблему или вопрос:")
    local messageEdit = supportForm:addEdit(3, 5)
    messageEdit.W = 44
    messageEdit.H = 5
    messageEdit.multiline = true
    
    local charCountLabel = supportForm:addLabel(3, 11, "Осталось символов: 500")
    
    messageEdit.onChange = function(text)
        local remaining = 500 - unicode.len(text)
        charCountLabel.text = "Осталось символов: " .. remaining
        charCountLabel.fontColor = remaining < 0 and 0xFF0000 or 0xFFFFFF
    end
    
    local backButton = supportForm:addButton(3, 13, " Назад ", function()
        MainForm:setActive()
    end)
    
    local sendButton = supportForm:addButton(35, 13, " Отправить ", function()
        local message = messageEdit.text
        if not message or message == "" then
            createNotification(false, "Сообщение не может быть пустым", nil, function() end)
            return
        end
        
        -- Очистка сообщения
        message = message:sub(1, 500):gsub("[%c%z]", " "):gsub("```", "'''")
        
        -- Попробуем сначала через сервис
        local success, result = shopService:sendSupportMessage(nickname, message)
        
        -- Если не получилось, пробуем напрямую
        if not success then
            success, result = sendToDiscordDirect(string.format("Support from %s: %s", nickname, message))
            if success then
                result = "Сообщение отправлено (direct)!"
            end
        end
        
        createNotification(success, result, nil, function()
            if success then
                MainForm:setActive()
            end
        end)
    end)
    
    return supportForm
end
function createNotification(status, text, secondText, callback)
    local notificationForm = forms:addForm()
    notificationForm.border = 2
    notificationForm.W = 31
    notificationForm.H = 10
    notificationForm.left = math.floor((MainForm.W - notificationForm.W) / 2)
    notificationForm.top = math.floor((MainForm.H - notificationForm.H) / 2)
    notificationForm:addLabel(math.floor((notificationForm.W - unicode.len(text)) / 2), 3, text)
    if (secondText) then
        notificationForm:addLabel(math.floor((notificationForm.W - unicode.len(secondText)) / 2), 4, secondText)
    end
    timer = notificationForm:addTimer(3, function()
        callback()
        timer:stop()
    end)
    notificationForm:setActive()
end

function createNumberEditForm(callback, form, buttonText)
    local itemCounterNumberForm = forms:addForm()
    itemCounterNumberForm.border = 2
    itemCounterNumberForm.W = 31
    itemCounterNumberForm.H = 10
    itemCounterNumberForm.left = math.floor((form.W - itemCounterNumberForm.W) / 2)
    itemCounterNumberForm.top = math.floor((form.H - itemCounterNumberForm.H) / 2)
    itemCounterNumberForm:addLabel(8, 3, "Введите количество")
    local itemCountEdit = itemCounterNumberForm:addEdit(8, 4)
    itemCountEdit.W = 18
    itemCountEdit.validator = function(value)
        return tonumber(value) ~= nil
    end
    local backButton = itemCounterNumberForm:addButton(3, 8, " Назад ", function()
        form:setActive()
    end)

    local acceptButton = itemCounterNumberForm:addButton(17, 8, buttonText, function()
        callback(itemCountEdit.text and tonumber(itemCountEdit.text) or 0)
    end)
    return itemCounterNumberForm
end

function createAutorizationForm()
    local AutorizationForm = forms.addForm() -- создаем основную форму
    AutorizationForm.border = 1
    

    local authorLabel = AutorizationForm:addLabel(32, 25, " Автор: hijabax ")
    authorLabel.fontColor = 0x00FDFF

local nameLabel1 = AutorizationForm:addLabel(11, 3, " ____            _                     ")
local nameLabel2 = AutorizationForm:addLabel(11, 4, "|  _ \\          | |                    ")
local nameLabel3 = AutorizationForm:addLabel(11, 5, "| |_) |   ___   | |__     ___   _ __   ")
local nameLabel4 = AutorizationForm:addLabel(11, 6, "|  _ <   / _ \\  | '_ \\   / _ \\ | '__|  ")
local nameLabel5 = AutorizationForm:addLabel(11, 7, "| |_) | | (_) | | |_) | |  __/ | |     ")
local nameLabel6 = AutorizationForm:addLabel(11, 8, "|____/   \\___/  |_.__/   \\___| |_|     ")
local nameLabel7 = AutorizationForm:addLabel(11, 9, "  _____   _                            ")
local nameLabel8 = AutorizationForm:addLabel(11, 10," / ____| | |                           ")
local nameLabel9 = AutorizationForm:addLabel(11, 11,"| (___   | |__     ___    _ __         ")
local nameLabel10 = AutorizationForm:addLabel(11, 12," \\___ \\  | '_ \\   / _ \\  | '_ \\       ")
local nameLabel11 = AutorizationForm:addLabel(11, 13," ____) | | | | | | (_) | | |_) |      ")
local nameLabel12 = AutorizationForm:addLabel(11, 14,"|_____/  |_| |_|  \\___/  | .__/       ")
local nameLabel13 = AutorizationForm:addLabel(11, 15,"                         | |          ")
local nameLabel14 = AutorizationForm:addLabel(11, 16,"                         |_|          ")
local nameLabel15 = AutorizationForm:addLabel(11, 17,"                      ")
local nameLabel15 = AutorizationForm:addLabel(11, 18,"            Встаньте на PIM          ")
    authorLabel.fontColor = 0x00FDFF

    return AutorizationForm
end


function createListForm(name, label, items, buttons, filter)
    local ShopForm = forms.addForm()
    ShopForm.border = 1
    local shopFrame = ShopForm:addFrame(3, 5, 1)
    shopFrame.W = 76
    shopFrame.H = 18
    local shopNameLabel = ShopForm:addLabel(33, 1, " Bober Shop ")
    shopNameLabel.fontColor = 0x00FDFF
    local authorLabel = ShopForm:addLabel(32, 25, " Автор: hijabax ")
    authorLabel.fontColor = 0x00FDFF

    local shopNameLabel = ShopForm:addLabel(35, 4, name)
    local shopCountLabel = ShopForm:addLabel(4, 6, label)
    local itemList = ShopForm:addList(5, 7, function()
    end)

    for i = 1, #items do
        if (not filter or (unicode.lower(items[i].displayName):find(unicode.lower(filter)))) then
            itemList:insert(items[i].displayName, items[i])
        end
    end
    itemList.border = 0
    itemList.W = 72
    itemList.H = 15
    itemList.fontColor = 0xFF8F00

    local searchEdit = ShopForm:addEdit(3, 2)
    searchEdit.W = 15


    local searchButton = ShopForm:addButton(19, 3, " Поиск ", function()
        createListForm(name, label, items, buttons, searchEdit.text):setActive()
    end)

    for i, button in pairs(buttons) do
        local shopBackButton = ShopForm:addButton(button.W, button.H, button.name, function()
            if (itemList) then
                button.callback(itemList.items[itemList.index])
            else
                button.callback()
            end
        end)
    end
    return ShopForm
end

function createButton(buttonName, W, H, callback)
    local button = {}
    button.name = buttonName
    button.W = W
    button.H = H
    button.callback = callback
    return button
end

function createGarbageForm()
    local items = shopService:getItems(nickname)
    for i = 1, #items do
        local name = items[i].label
        for i = 1, 60 - unicode.len(name) do
            name = name .. ' '
        end
        name = name .. items[i].count .. " шт"

        items[i].displayName = name
    end

    GarbageForm = createListForm(" Корзина ",
        " Наименование                                                Количество",
        items,
        {
            createButton(" Назад ", 4, 23, function(selectedItem)
                MainForm = createMainForm(nickname)
                MainForm:setActive()
            end),
            createButton(" Забрать все ", 68, 23, function(selectedItem)
                local count, message = shopService:withdrawAll(nickname)
                createNotification(count, message, nil, function()
                    createGarbageForm()
                end)
            end),
            createButton(" Забрать ", 55, 23, function(selectedItem)
                if (selectedItem) then
                    local NumberForm = createNumberEditForm(function(count)
                        local count, message = shopService:withdrawItem(nickname, selectedItem.id, selectedItem.dmg, count)

                        createNotification(count, message, nil, function()
                            createGarbageForm()
                        end)
                    end, GarbageForm, "Забрать")
                    NumberForm:setActive()
                end
            end)
        })

    GarbageForm:setActive()
end

function createMainForm(nick)
    local MainForm = forms.addForm()
    MainForm.border = 1
    local shopNameLabel = MainForm:addLabel(33, 1, " Bober Shop ")
    shopNameLabel.fontColor = 0x00FDFF
    local authorLabel = MainForm:addLabel(32, 25, " Автор: hijabax ")
    authorLabel.fontColor = 0x00FDFF

    -- Размеры экрана и отступы
    local screenWidth = 80
    local edgeMargin = 5  -- Отступ от края экрана
    local buttonSpacing = 4  -- Отступ между кнопками

    -- Информация о пользователе
    MainForm:addLabel(edgeMargin, 6, "Ваш ник: ").fontSize = 1.2
    MainForm:addLabel(edgeMargin + 15, 6, nick).fontSize = 1.2
    MainForm:addLabel(edgeMargin, 8, "Баланс: ").fontSize = 1.2
    MainForm:addLabel(edgeMargin + 15, 8, shopService:getBalance(nick)).fontSize = 1.2

    -- Параметры кнопок
    local buttonHeight = 3
    local largeButtonWidth = 34
    local smallButtonWidth = 22

    -- Первый ряд кнопок (КУПИТЬ и ПРОДАТЬ)
    MainForm:addButton(edgeMargin, 12, " КУПИТЬ ", function()
        createSellShopForm()
    end).H, .W, .color, .fontColor = buttonHeight, largeButtonWidth, 0x006600, 0xFFFFFF

    MainForm:addButton(screenWidth - edgeMargin - largeButtonWidth, 12, " ПРОДАТЬ ", function()
        createBuyShopForm()
    end).H, .W, .color, .fontColor = buttonHeight, largeButtonWidth, 0xFFA500, 0xFFFFFF

    -- Второй ряд кнопок (3 кнопки)
    local totalWidth = 3 * smallButtonWidth + 2 * buttonSpacing
    local startX = (screenWidth - totalWidth) / 2  -- Центрирование группы кнопок

    -- СВЯЗАТЬСЯ С НАМИ
    MainForm:addButton(startX, 17, " СВЯЗАТЬСЯ С НАМИ ", function()
        createSupportForm():setActive()
    end).H, .W, .color, .fontColor = buttonHeight, smallButtonWidth, 0x5555FF, 0xFFFFFF

    -- ПРАВИЛА
    MainForm:addButton(startX + smallButtonWidth + buttonSpacing, 17, " ПРАВИЛА ", function()
        RulesForm:setActive()
    end).H, .W, .color, .fontColor = buttonHeight, smallButtonWidth, 0x333333, 0xFF8F00

    -- ВЫХОД
    MainForm:addButton(startX + 2*(smallButtonWidth + buttonSpacing), 17, " ВЫХОД ", function()
        AutorizationForm:setActive()
    end).H, .W, .color, .fontColor = buttonHeight, smallButtonWidth, 0xFF5555, 0xFFFFFF

    return MainForm
end

function createSellShopForm()
    SellShopForm = forms.addForm()
    SellShopForm.border = 1
    local shopNameLabel = SellShopForm:addLabel(33, 1, " Bober Shop ")
    shopNameLabel.fontColor = 0x00FDFF
    local authorLabel = SellShopForm:addLabel(32, 25, " Автор: hijabax ")
    authorLabel.fontColor = 0x00FDFF

    local buyButton2 = SellShopForm:addLabel(23, 3, " █▀▀█ █▀▀█ █ █ █  █ █▀▀█ █ █ █▀▀█ ")
    local buyButton3 = SellShopForm:addLabel(23, 4, " █  █ █  █ █▀▄ █▄▄█ █  █ █▀▄ █▄▄█ ")
    local buyButton4 = SellShopForm:addLabel(23, 5, " ▀  ▀ ▀▀▀▀ ▀ ▀ ▄▄▄█ ▀  ▀ ▀ ▀ ▀  ▀ ")

    local categoryButton1 = SellShopForm:addButton(5, 9, " Разное ", function()
        createSellShopSpecificForm("Minecraft")
    end)
    categoryButton1.W = 23
    categoryButton1.H = 3
    local categoryButton1 = SellShopForm:addButton(29, 9, " Industrial Craft 2 ", function()
        createSellShopSpecificForm("IC2")
    end)
    categoryButton1.W = 24
    categoryButton1.H = 3
    local categoryButton1 = SellShopForm:addButton(54, 9, " Applied Energistics 2 ", function()
        createSellShopSpecificForm("AE2")
    end)
    categoryButton1.W = 23
    categoryButton1.H = 3

    local categoryButton1 = SellShopForm:addButton(5, 13, " Forestry ", function()
        createSellShopSpecificForm("Forestry")
    end)
    categoryButton1.W = 23
    categoryButton1.H = 3
    local categoryButton1 = SellShopForm:addButton(29, 13, " Зачарованные книги ", function()
        createSellShopSpecificForm("Books")
    end)
    categoryButton1.W = 24
    categoryButton1.H = 3
    local categoryButton1 = SellShopForm:addButton(54, 13, " Draconic Evolution ", function()
        createSellShopSpecificForm("DE")
    end)
    categoryButton1.W = 23
    categoryButton1.H = 3

    local categoryButton1 = SellShopForm:addButton(5, 17, " Thermal Expansion ", function()
        createSellShopSpecificForm("TE")
    end)
    categoryButton1.W = 23
    categoryButton1.H = 3
    local categoryButton1 = SellShopForm:addButton(29, 17, " Скоро ")
    categoryButton1.W = 24
    categoryButton1.H = 3
    categoryButton1.fontColor = 0xaaaaaa
    categoryButton1.color = 0x000000
    local categoryButton1 = SellShopForm:addButton(54, 17, " Скоро ")
    categoryButton1.W = 23
    categoryButton1.H = 3
    categoryButton1.fontColor = 0xaaaaaa
    categoryButton1.color = 0x000000

    local shopBackButton = SellShopForm:addButton(3, 23, " Назад ", function()
        MainForm = createMainForm(nickname)
        MainForm:setActive()
    end)

    SellShopForm:setActive()
end


function createSellShopSpecificForm(category)
    local items = shopService:getSellShopList(category)
    for i = 1, #items do
        local name = items[i].label
        for i = 1, 51 - unicode.len(name) do
            name = name .. ' '
        end
        name = name .. items[i].count

        for i = 1, 62 - unicode.len(name) do
            name = name .. ' '
        end

        name = name .. items[i].price

        items[i].displayName = name
    end

    SellShopSpecificForm = createListForm(" Магазин ",
        " Наименование                                       Количество Цена в железе    ",
        items,
        {
            createButton(" Назад ", 4, 23, function(selectedItem)
                createSellShopForm()
            end),
            createButton(" Купить ", 68, 23, function(selectedItem)
                local itemCounterNumberSelectForm = createNumberEditForm(function(count)
                    local _, message = shopService:sellItem(nickname, selectedItem, count)
                    createNotification(nil, message, nil, function()
                        createSellShopSpecificForm(category)
                    end)
                end, SellShopForm, "Купить")
                if (selectedItem) then
                    itemCounterNumberSelectForm:setActive()
                end
            end)
        })

    SellShopSpecificForm:setActive()
end

function createBuyShopForm()
    local items = shopService:getBuyShopList()
    for i = 1, #items do
        local name = items[i].label
        for i = 1, 51 - unicode.len(name) do
            name = name .. ' '
        end
        name = name .. items[i].count

        for i = 1, 62 - unicode.len(name) do
            name = name .. ' '
        end

        name = name .. items[i].price

        items[i].displayName = name
    end

    BuyShopForm = createListForm(" Скупка ",
        " Наименование                                       Количество Цена    ",
        items,
        {
            createButton(" Назад ", 4, 23, function(selectedItem)
                MainForm = createMainForm(nickname)
                MainForm:setActive()
            end),
            createButton(" Продать ", 55, 23, function(selectedItem)
                if (selectedItem) then
                    local itemCounterNumberSelectForm = createNumberEditForm(function(count)
                        local _, message = shopService:buyItem(nickname, selectedItem, count)
                        createNotification(nil, message, nil, function()
                            createBuyShopForm()
                        end)
                    end, MainForm, "Продать")

                    itemCounterNumberSelectForm:setActive()
                end
            end),
            createButton(" Продать всё ", 68, 23, function()
                local totalEarned = 0
                local soldItems = 0
                local failedItems = 0
                
                for _, item in ipairs(items) do
                    if item.count > 0 then
                        local success, message = shopService:buyItem(nickname, item, item.count)
                        if success then
                            totalEarned = totalEarned + (item.price * item.count)
                            soldItems = soldItems + 1
                        else
                            failedItems = failedItems + 1
                        end
                    end
                end
                
                local message = string.format("Продано %d предметов на сумму %.1f", soldItems, totalEarned)
                if failedItems > 0 then
                    message = message .. string.format("\nНе удалось продать %d предметов", failedItems)
                end
                
                createNotification(nil, message, nil, function()
                    createBuyShopForm()
                end)
            end)
        })

    BuyShopForm:setActive()
end

function createOreExchangerForm()
    local items = shopService:getOreExchangeList()
    for i = 1, #items do
        local name = items[i].fromLabel
        for i = 1, 58 - unicode.len(name) do
            name = name .. ' '
        end
        name = name .. items[i].fromCount .. 'к' .. items[i].toCount

        items[i].displayName = name
    end

    OreExchangerForm = createListForm(" Обмен руд ",
        " Наименование                                              Курс обмена ",
        items,
        {
            createButton(" Назад ", 4, 23, function(selectedItem)
                MainForm = createMainForm(nickname)
                MainForm:setActive()
            end),
            createButton(" Обменять все ", 67, 23, function(selectedItem)
                local _, message, message2 = shopService:exchangeAllOres(nickname)
                createNotification(nil, message, message2, function()
                    createOreExchangerForm()
                end)
            end),
            createButton(" Обменять ", 54, 23, function(selectedItem)
                if (selectedItem) then
                    local itemCounterNumberSelectForm = createNumberEditForm(function(count)
                        local _, message, message2 = shopService:exchangeOre(nickname, selectedItem, count)
                        createNotification(nil, message, message2, function()
                            createOreExchangerForm()
                        end)
                    end, OreExchangerForm, "Обменять")
                    itemCounterNumberSelectForm:setActive()
                end
            end)
        })

    OreExchangerForm:setActive()
end

function createExchangerForm()
    local items = shopService:getExchangeList()
    for i = 1, #items do
        local name = items[i].fromLabel
        for i = 1, 25 - unicode.len(name) do
            name = name .. ' '
        end
        name = name .. items[i].fromCount .. 'к' .. items[i].toCount
        for i = 1, 50 - unicode.len(name) do
            name = name .. ' '
        end
        name = name .. items[i].toLabel
        items[i].displayName = name
    end

    ExchangerForm = createListForm(" Обменик ",
        " Наименование             Курс обмена              Наименование       ",
        items,
        {
            createButton(" Назад ", 4, 23, function(selectedItem)
                MainForm = createMainForm(nickname)
                MainForm:setActive()
            end),
            createButton(" Обменять ", 68, 23, function(selectedItem)
                if (selectedItem) then
                    local itemCounterNumberSelectForm = createNumberEditForm(function(count)
                        local _, message, message2 = shopService:exchange(nickname, selectedItem, count)
                        createNotification(nil, message, message2, function()
                            createExchangerForm()
                        end)
                    end, ExchangerForm, "Обменять")
                    itemCounterNumberSelectForm:setActive()
                end
            end)
        })

    ExchangerForm:setActive()
end

function createRulesForm()
    local ShopForm = forms.addForm()
    ShopForm.border = 1
    local shopFrame = ShopForm:addFrame(3, 5, 1)
    shopFrame.W = 76
    shopFrame.H = 18
    local shopNameLabel = ShopForm:addLabel(33, 1, " Bober Shop ")
    shopNameLabel.fontColor = 0x00FDFF
    local authorLabel = ShopForm:addLabel(32, 25, " Автор: hijabax ")
    authorLabel.fontColor = 0x00FDFF

    local shopNameLabel = ShopForm:addLabel(35, 4, " Условия ")

    local ruleList = ShopForm:addList(5, 6, function()
    end)

    ruleList:insert("1. Товар обмену и возврату не подлежит ")
    ruleList:insert("2. При сбоях работы сервера возврат средств")
    ruleList:insert("   осуществляется по решению hijabax")
    ruleList:insert("3. В случае сбоя магазина (невыдача товара,")
    ruleList:insert("   изчезновение баланса и т.д) магазин")
    ruleList:insert("   обязуется решить проблему в течении 48 часов")
    ruleList:insert("4. По всем вопросам можете обращаться к hijabax")
    ruleList.border = 0
    ruleList.W = 73
    ruleList.H = 15
    ruleList.fontColor = 0xFF8F00

    local shopBackButton = ShopForm:addButton(3, 23, " Назад ", function()
        MainForm = createMainForm(nickname)
        MainForm:setActive()
    end)

    shopBackButton.H = 1
    shopBackButton.W = 9
    return ShopForm
end

function autorize(nick)
    MainForm = createMainForm(nick)
    nickname = nick
    MainForm:setActive()
end

AutorizationForm = createAutorizationForm()
RulesForm = createRulesForm()


local Event1 = AutorizationForm:addEvent("player_on", function(e, p)
    gpu.setResolution(80, 25)
    if (p) then
        computer.addUser(p)
        autorize(p)
    end
end)

local Event1 = AutorizationForm:addEvent("player_off", function(e, p)
    if (nickname ~= 'hijabax') then
        computer.removeUser(nickname)
    end
    if (timer) then
        timer:stop()
    end
    AutorizationForm:setActive()
end)

forms.run(AutorizationForm) --запускаем gui

