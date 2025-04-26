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
    local autorizationLabel = AutorizationForm:addLabel(23, 14, "Что б авторизаватся встаньте на PIM");

    local authorLabel = AutorizationForm:addLabel(32, 25, " Автор: 3_1415926535 ")
    authorLabel.fontColor = 0x00FDFF

    local nameLabel1 = AutorizationForm:addLabel(11, 3, " _                               _    _____ _                 ")
    local nameLabel2 = AutorizationForm:addLabel(11, 4, "| |                             | |  / ____| |  ")
    local nameLabel3 = AutorizationForm:addLabel(11, 5, "| |     ___  __ _  ___ _ __   __| | | (___ | |__   ___  _ __  ")
    local nameLabel4 = AutorizationForm:addLabel(11, 6, "| |    / _ \\/ _` |/ _ \\ '_ \\ / _` |  \\___ \\| '_ \\ / _ \\| '_ \\ ")
    local nameLabel5 = AutorizationForm:addLabel(11, 7, "| |___|  __/ (_| |  __/ | | | (_| |  ____) | | | | (_) | |_) |")
    local nameLabel6 = AutorizationForm:addLabel(11, 8, "|______\\___|\\__, |\\___|_| |_|\\__,_| |_____/|_| |_|\\___/| .__/")
    local nameLabel7 = AutorizationForm:addLabel(11, 9, "             __/ |                                     | |")
    local nameLabel8 = AutorizationForm:addLabel(11, 10, "            |___/                                      |_|    ")

    authorLabel.fontColor = 0x00FDFF

    return AutorizationForm
end


function createListForm(name, label, items, buttons, filter)
    local ShopForm = forms.addForm()
    ShopForm.border = 1
    local shopFrame = ShopForm:addFrame(3, 5, 1)
    shopFrame.W = 76
    shopFrame.H = 18
    local shopNameLabel = ShopForm:addLabel(33, 1, " Legend Shop ")
    shopNameLabel.fontColor = 0x00FDFF
    local authorLabel = ShopForm:addLabel(32, 25, " Автор: 3_1415926535 ")
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
    local shopNameLabel = MainForm:addLabel(33, 1, " Legend Shop ")
    shopNameLabel.fontColor = 0x00FDFF
    local authorLabel = MainForm:addLabel(32, 25, " Автор: 3_1415926535 ")
    authorLabel.fontColor = 0x00FDFF

    local frameBalance = MainForm:addFrame(3, 3, 1)
    frameBalance.W = 76
    frameBalance.H = 7

    MainForm:addLabel(5, 4, "Ваш ник: ")
    MainForm:addLabel(7, 4, nick)

    MainForm:addLabel(5, 6, "Баланс: ")
    MainForm:addLabel(27, 6, shopService:getBalance(nick))

    local sellButton = MainForm:addButton(60, 5, " Выход ", function()
        AutorizationForm:setActive()
    end)
    sellButton.H = 3
    sellButton.W = 15

    local itemCounterNumberSelectDepositBalanceForm = createNumberEditForm(function(count)
        local _, message = shopService:depositMoney(nick, count)
        if (count % 1000 ~= 0) then
            createNotification(nil, "Выввод/ввод осуществляется ", "кратно 1000", function()
                MainForm = createMainForm(nick)
                MainForm:setActive()
            end)
            return
        end
        createNotification(nil, message, nil, function()
            MainForm = createMainForm(nick)
            MainForm:setActive()
        end)
    end, MainForm, "Пополнить")

    local itemCounterNumberSelectWithdrawBalanceForm = createNumberEditForm(function(count)
        if (count % 1000 ~= 0) then
            createNotification(nil, "Выввод/ввод осуществляется ", "кратно 1000", function()
                MainForm = createMainForm(nick)
                MainForm:setActive()
            end)
            return
        end
        local _, message = shopService:withdrawMoney(nick, count)
        createNotification(nil, message, nil, function()
            MainForm = createMainForm(nick)
            MainForm:setActive()
        end)
    end, MainForm, "Снять")

    local depositButton = MainForm:addButton(36, 4, "Пополнить баланс ", function()
        itemCounterNumberSelectDepositBalanceForm:setActive()
    end)
    depositButton.W = 20

    local withdrawButton = MainForm:addButton(36, 6, "Снять с баланса ", function()
        itemCounterNumberSelectWithdrawBalanceForm:setActive()
    end)
    withdrawButton.W = 20

    MainForm:addLabel(5, 8, "Количество предметов: ")
    MainForm:addLabel(27, 8, shopService:getItemCount(nick))

    local withdrawButton = MainForm:addButton(36, 8, "Забрать предметы", function()
        createGarbageForm()
    end)
    withdrawButton.W = 20

    local buyButton = MainForm:addButton(8, 17, " Купить ", function()
        createSellShopForm()
    end)
    buyButton.H = 3
    buyButton.W = 21

    local sellButton = MainForm:addButton(30, 17, " Продать ", function()
        createBuyShopForm()
    end)
    sellButton.H = 3
    sellButton.W = 22

    local exchangeButton = MainForm:addButton(53, 17, " Обмен руд", function()
        createOreExchangerForm()
    end)
    exchangeButton.H = 3
    exchangeButton.W = 21

    local buyButton = MainForm:addButton(8, 21, " Обменик ", function()
        createExchangerForm()
    end)
    buyButton.H = 3
    buyButton.W = 21

    local sellButton = MainForm:addButton(30, 21, " Примечание ", function()
        RulesForm:setActive()
    end)
    sellButton.H = 3
    sellButton.W = 44

    return MainForm
end


function createSellShopForm()
    SellShopForm = forms.addForm()
    SellShopForm.border = 1
    local shopNameLabel = SellShopForm:addLabel(33, 1, " Legend Shop ")
    shopNameLabel.fontColor = 0x00FDFF
    local authorLabel = SellShopForm:addLabel(32, 25, " Автор: 3_1415926535 ")
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
        " Наименование                                       Количество Цена    ",
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
            createButton(" Продать ", 68, 23, function(selectedItem)
                if (selectedItem) then
                    local itemCounterNumberSelectForm = createNumberEditForm(function(count)
                        local _, message = shopService:buyItem(nickname, selectedItem, count)
                        createNotification(nil, message, nil, function()
                            createBuyShopForm()
                        end)
                    end, MainForm, "Продать")

                    itemCounterNumberSelectForm:setActive()
                end
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
    local shopNameLabel = ShopForm:addLabel(33, 1, " PI Shop ")
    shopNameLabel.fontColor = 0x00FDFF
    local authorLabel = ShopForm:addLabel(32, 25, " Автор: 3_1415926535 ")
    authorLabel.fontColor = 0x00FDFF

    local shopNameLabel = ShopForm:addLabel(35, 4, " Примечания ")

    local ruleList = ShopForm:addList(5, 6, function()
    end)

    ruleList:insert("1. Баланс на компьютерах разный, пользуйтесь одним магазином для удобства пользования! ")
    ruleList:insert("2. При возникновении какого либо вопроса, обращайтесь к:")
    ruleList:insert("   3_1415926535")
    ruleList:insert("3. Вывод/ввод денег осуществляется кратно 1000")

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


