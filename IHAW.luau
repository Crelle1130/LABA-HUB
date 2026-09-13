repeat task.wait() until game:IsLoaded()
if getgenv().IHAW_LOADED then return end
    getgenv().IHAW_LOADED = true

;(function()
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local HttpService = game:GetService("HttpService")
    local LocalPlayer = Players.LocalPlayer

    local UI = loadstring(readfile("LABAHUB.luau"))()
    local win = UI:CreateWindow({
        Title = "IHAW",
        Size = UDim2.fromOffset(380, 340),
        Intro = { Title = "IHAW", Subtitle = "LABA HUB", Duration = 2 },
    })

    local homeTab = win:AddTab("Home")
    local shopTab = win:AddTab("Shop")
    local OrderRegisterEvent = ReplicatedStorage:WaitForChild("OrderRegisterEvent")
    local BatchCookingFunction = ReplicatedStorage:WaitForChild("BatchCookingFunction")
    local BatchCookingEvent = ReplicatedStorage:WaitForChild("BatchCookingEvent")
    local FanEvent = ReplicatedStorage:WaitForChild("FanEvent")
    local BroomEvent = ReplicatedStorage:WaitForChild("BroomEvent")
    local FoodEconomyFunction = ReplicatedStorage:WaitForChild("FoodEconomyFunction")
    local FurnitureShopFunction = ReplicatedStorage:WaitForChild("FurnitureShopFunction")
    local RawTableEvent = ReplicatedStorage:WaitForChild("RawTableEvent")

    local condimentCount = 0
    local unlockedFoods = {}
    local foodStock = {}

    RawTableEvent.OnClientEvent:Connect(function(action, data)
        if action == "Sync" and data then
            if data.Condiments then condimentCount = data.Condiments end
            if data.Unlocked then unlockedFoods = data.Unlocked end
            if data.Stock then foodStock = data.Stock end
        end
    end)

    local function buyStock(foodKey, amount)
        local ok, result = pcall(function()
            return FoodEconomyFunction:InvokeServer("BuyStock", foodKey, amount)
        end)
        return ok, result
    end

    local FOOD_KEYS = {
        "PorkBBQ", "Hotdog", "Isaw", "GrilledCorn", "Betamax",
        "Longganisa", "Adidas", "Tenga", "Liempo", "ChickenInasal",
        "GrilledSquid", "Bangus",
    }

    local PHASE_LABELS = {
        SideOne = "Cooking...",
        SideTwo = "Almost ready...",
        Turn = "Ready to flip",
        TurnWarning = "Flip NOW",
        Ready = "Ready! Take it",
        ReadyWarning = "TAKE NOW!",
        Burnt = "Burnt",
    }

    local STATE = {
        assignEnabled = false,
        grillEnabled = false,
        cooldown = false,
        delay = 0.5,
        queueState = nil,
        range = 15,
        myPlot = nil,
        grillId = "1",
        selectedFood = "PorkBBQ",
        loadMode = "Needed",
        lastStatus = "",
        assignBusy = false,
        deliverEnabled = false,
        lock = nil,
        broomEnabled = false,
        lastBroomStatus = "Idle",
        emergency = false,
        restockEnabled = false,
        buyAmount = 10,
        lastRestockStatus = "Idle",
        sync = nil,
        alive = true,
        autoBuy = false,
        shopSelected = {},
    }

    print("[STATE] alive:", STATE.alive, "autoBuy:", STATE.autoBuy, "shopSelected:", typeof(STATE.shopSelected))

    -- Detect plot immediately on execution
    task.spawn(function()
        task.wait(2)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local nearest, nearestDist = nil, math.huge
            for _, plot in ipairs(workspace.KantoPlots:GetChildren()) do
                local equip = plot:FindFirstChild("Equipment")
                if equip then
                    local cashbox = equip:FindFirstChild("CashBoxStation")
                    if cashbox then
                        local part = cashbox:FindFirstChild("InteractionPart")
                        if part then
                            local dist = (part.Position - hrp.Position).Magnitude
                            if dist < nearestDist then nearestDist = dist; nearest = plot.Name end
                        end
                    end
                end
            end
            if nearest then STATE.myPlot = nearest end
        end
    end)

    local function acquireLock(name)
        while STATE.lock do task.wait(0.1) end
        STATE.lock = name
    end

    local function releaseLock()
        STATE.lock = nil
    end

    local function yieldIfEmergency()
        while STATE.emergency do task.wait(0.1) end
    end

    local cookingState = {
        fanCooldown = 0,
        flipCooldown = 0,
        busy = false,
    }

    -- ========== SYNC LISTENER ==========

    BatchCookingEvent.OnClientEvent:Connect(function(action, data)
        if action == "Sync" and type(data) == "table" then
            STATE.sync = data
        end
    end)

    -- ========== PLOT DETECTION ==========

    local function detectMyPlot()
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return nil end
        local nearest, nearestDist = nil, math.huge
        for _, plot in ipairs(workspace.KantoPlots:GetChildren()) do
            local equip = plot:FindFirstChild("Equipment")
            if equip then
                local cashbox = equip:FindFirstChild("CashBoxStation")
                if cashbox then
                    local part = cashbox:FindFirstChild("InteractionPart")
                    if part then
                        local dist = (part.Position - hrp.Position).Magnitude
                        if dist < nearestDist then nearestDist = dist; nearest = plot.Name end
                    end
                end
            end
        end
        if nearest then return nearest end
        local attr = LocalPlayer:GetAttribute("PlotName") or LocalPlayer:GetAttribute("Plot")
        if attr and workspace.KantoPlots:FindFirstChild(attr) then return attr end
        return nil
    end

    local function getMyPlot()
        if STATE.myPlot and workspace.KantoPlots:FindFirstChild(STATE.myPlot) then
            return STATE.myPlot
        end
        STATE.myPlot = detectMyPlot()
        return STATE.myPlot
    end

    local function getCashboxPos(plotName)
        local plot = workspace.KantoPlots:FindFirstChild(plotName)
        if not plot then return nil end
        local equip = plot:FindFirstChild("Equipment")
        equip = equip and equip:FindFirstChild("CashBoxStation")
        equip = equip and equip:FindFirstChild("InteractionPart")
        return equip and equip.Position or nil
    end

    -- ========== TP HELPERS ==========

    local function tpNear(part, offset)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp or not part then return nil end
        local orig = hrp.CFrame
        hrp.CFrame = CFrame.new(part.Position + (offset or Vector3.new(2, 0, 0)))
        return orig
    end

    local function tpBack() end

    -- ========== TOOL EQUIP ==========

    local function equipTool(name)
        local char = LocalPlayer.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        local tool = LocalPlayer.Backpack:FindFirstChild(name)
        if tool then
            hum:EquipTool(tool)
            task.wait(0.15)
        end
    end

    local function unequipTools()
        local char = LocalPlayer.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum:UnequipTools() end
    end

    -- ========== COOKING HELPERS ==========

    local function requestState()
        local uuid = HttpService:GenerateGUID(false)
        pcall(function()
            BatchCookingFunction:InvokeServer("GetState", "", nil, uuid)
        end)
    end

    local function waitForSync(timeout)
        local deadline = tick() + (timeout or 3)
        while tick() < deadline and not STATE.sync do
            task.wait(0.1)
        end
        return STATE.sync
    end

    local function activateFan()
        if os.clock() < cookingState.fanCooldown then return end
        cookingState.fanCooldown = os.clock() + 0.12
        pcall(function() FanEvent:FireServer("Fan") end)
    end

    local function fanLoop(duration)
        equipTool("Pamaypay")
        task.wait(0.15)
        local endTime = os.clock() + duration
        while os.clock() < endTime and STATE.grillEnabled do
            activateFan()
            task.wait(0.15)
        end
    end

    -- ========== GRILL OPERATIONS (using sync data) ==========

    local function getGrillAnchor(grillId)
        local sync = STATE.sync
        if not sync or not sync.grills then return nil end
        for _, g in ipairs(sync.grills) do
            if g.id == grillId then
                return g.anchor, g
            end
        end
        return nil
    end

    local function getRackAnchor()
        local sync = STATE.sync
        if sync and sync.rackAnchor then
            return sync.rackAnchor
        end
        local plotName = getMyPlot()
        if not plotName then return nil end
        local plot = workspace.KantoPlots:FindFirstChild(plotName)
        if not plot then return nil end
        local runtime = plot:FindFirstChild("Runtime")
        if not runtime then return nil end
        local bcr = runtime:FindFirstChild("BatchCookingRuntime")
        if not bcr then return nil end
        local rack = bcr:FindFirstChild("BatchServingRack")
        if not rack then return nil end
        return rack:FindFirstChild("RackInteraction")
    end

    local function tpToGrill(grillId)
        local anchor = getGrillAnchor(grillId)
        if not anchor then return nil end
        return tpNear(anchor, Vector3.new(2, 0, 0))
    end

    local function tpToRack()
        local anchor = getRackAnchor()
        if not anchor then return nil end
        return tpNear(anchor, Vector3.new(2, 0, 0))
    end

    local function loadFoodOnGrill(grillId, foodKey, quantity)
        local anchor = getGrillAnchor(grillId)
        if not anchor then return false end
        local orig = tpNear(anchor, Vector3.new(2, 0, 0))
        task.wait(0.3)
        local prompt = anchor:FindFirstChild("GrillPadPrompt") or anchor:FindFirstChild("BatchGrillPrompt")
        if prompt then
            local waitEnd = tick() + 2
            while not prompt.Enabled and tick() < waitEnd do
                task.wait(0.1)
            end
            if prompt.Enabled then
                fireproximityprompt(prompt)
                task.wait(0.5)
            end
        end
        local uuid = HttpService:GenerateGUID(false)
        pcall(function()
            BatchCookingFunction:InvokeServer("Load", grillId, {
                key = foodKey,
                quantity = quantity or STATE.loadMode,
            }, uuid)
        end)
        tpBack()
        return true
    end

    local function flipOnGrill(grillId)
        local anchor = getGrillAnchor(grillId)
        if not anchor then return false end
        local orig = tpNear(anchor, Vector3.new(2, 0, 0))
        task.wait(0.2)
        equipTool("Tongs")
        task.wait(0.15)
        local uuid = HttpService:GenerateGUID(false)
        pcall(function()
            BatchCookingFunction:InvokeServer("ToolTurn", grillId, nil, uuid)
        end)
        unequipTools()
        tpBack()
        return true
    end

    local function collectFromGrill(grillId)
        local uuid = HttpService:GenerateGUID(false)
        pcall(function()
            BatchCookingFunction:InvokeServer("Collect", grillId, nil, uuid)
        end)
        return true
    end

    local function pickupFromRack()
        local anchor = getRackAnchor()
        if not anchor then return false end
        local prompt = anchor:FindFirstChild("BatchRackPrompt")
        if not prompt then return false end
        local orig = tpNear(anchor, Vector3.new(2, 0, 0))
        task.wait(0.5)
        local waitEnd = tick() + 3
        while not prompt.Enabled and tick() < waitEnd do
            task.wait(0.1)
        end
        if prompt.Enabled then
            fireproximityprompt(prompt)
            task.wait(0.8)
        end
        tpBack()
        return true
    end

    local servedCustomers = {}

    local function serveToCustomer()
        local plotName = getMyPlot()
        if not plotName then return false end
        local plot = workspace.KantoPlots:FindFirstChild(plotName)
        if not plot then return false end
        local customers = plot:FindFirstChild("Runtime")
        customers = customers and customers:FindFirstChild("Customers")
        if not customers then return false end

        for _, cust in ipairs(customers:GetChildren()) do
            if servedCustomers[cust] then continue end
            local hrp = cust:FindFirstChild("HumanoidRootPart")
            local hum = cust:FindFirstChild("Humanoid")
            local serve = hrp and hrp:FindFirstChild("ServePrompt")
            if hrp and hum and serve then
                local state = hum:GetState()
                if state == Enum.HumanoidStateType.Seated and serve.Enabled then
                    local hrpPlayer = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if not hrpPlayer then return false end
                    hrpPlayer.CFrame = CFrame.new(hrp.Position + Vector3.new(2, 0, 0))
                    task.wait(0.5)
                    local waitEnd = tick() + 3
                    while not serve.Enabled and tick() < waitEnd do
                        task.wait(0.1)
                    end
                    if serve.Enabled then
                        fireproximityprompt(serve)
                        servedCustomers[cust] = true
                        task.wait(0.8)
                    end
                    return true
                end
            end
        end
        return false
    end

    local function hasFoodTool()
        local char = LocalPlayer.Character
        if not char then return false end
        local tray = char:FindFirstChild("BatchServingTray")
        if not tray then return false end
        for _, c in ipairs(tray:GetChildren()) do
            if c.Name:match("_Ready$") then
                return true
            end
        end
        return false
    end

    local function getTrayFoodCount()
        local char = LocalPlayer.Character
        if not char then return 0 end
        local tray = char:FindFirstChild("BatchServingTray")
        if not tray then return 0 end
        local count = 0
        for _, c in ipairs(tray:GetChildren()) do
            if c.Name:match("_Ready$") then
                count = count + 1
            end
        end
        return count
    end

    local function getTrayFoodTypes()
        local char = LocalPlayer.Character
        if not char then return {} end
        local tray = char:FindFirstChild("BatchServingTray")
        if not tray then return {} end
        local foods = {}
        for _, c in ipairs(tray:GetChildren()) do
            local foodKey = c.Name:match("^(.+)_Ready$")
            if foodKey then
                foods[foodKey] = (foods[foodKey] or 0) + 1
            end
        end
        return foods
    end

    -- ========== ASSIGN SEAT ==========

    local function countSeatedAndChairs(plotName)
        local plot = workspace.KantoPlots:FindFirstChild(plotName)
        if not plot then return 0, 0 end
        local runtime = plot:FindFirstChild("Runtime")
        local customers = runtime and runtime:FindFirstChild("Customers")
        local pads = runtime and runtime:FindFirstChild("FurniturePads")

        local seated = 0
        if customers then
            for _, cust in ipairs(customers:GetChildren()) do
                local hum = cust:FindFirstChild("Humanoid")
                if hum and hum:GetState() == Enum.HumanoidStateType.Seated then
                    seated = seated + 1
                end
            end
        end

        local chairs = 0
        if pads then
            for _, pad in ipairs(pads:GetChildren()) do
                local furniture = pad:FindFirstChild("PlacedFurniture")
                if furniture then
                    for _, chair in ipairs(furniture:GetChildren()) do
                        if chair.Name:find("DiningChair") then
                            chairs = chairs + 1
                        end
                    end
                end
            end
        end

        return seated, chairs
    end

    local function findWaitingNPC(plotName)
        local cashboxPos = getCashboxPos(plotName)
        if not cashboxPos then return nil end
        local plot = workspace.KantoPlots:FindFirstChild(plotName)
        if not plot then return nil end
        local customers = plot:FindFirstChild("Runtime")
        customers = customers and customers:FindFirstChild("Customers")
        if not customers then return nil end

        for _, cust in ipairs(customers:GetChildren()) do
            local hrp = cust:FindFirstChild("HumanoidRootPart")
            local hum = cust:FindFirstChild("Humanoid")
            if hrp and hum then
                local dist = (hrp.Position - cashboxPos).Magnitude
                local state = hum:GetState()
                if dist <= STATE.range and state ~= Enum.HumanoidStateType.Seated then
                    return cust
                end
            end
        end
        return nil
    end

    local function openCounter()
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
        local plotName = getMyPlot()
        if not plotName then return false end
        local plot = workspace.KantoPlots:FindFirstChild(plotName)
        if not plot then return false end

        local cashboxPart = plot:FindFirstChild("Equipment")
        cashboxPart = cashboxPart and cashboxPart:FindFirstChild("CashBoxStation")
        cashboxPart = cashboxPart and cashboxPart:FindFirstChild("InteractionPart")
        if not cashboxPart then return false end

        local prompt = cashboxPart:FindFirstChild("OrderRegisterPrompt")
        if not prompt then return false end

        local origPos = hrp.CFrame
        hrp.CFrame = CFrame.new(cashboxPart.Position + Vector3.new(2, 0, 0))
        task.wait(0.3)
        fireproximityprompt(prompt)
        task.wait(0.8)
        return true, origPos
    end

    local function closeCounter()
        local gui = LocalPlayer.PlayerGui:FindFirstChild("IhawOrderCounter")
        if gui then pcall(function() gui.Enabled = false end) end
    end

    local function getAvailableSeat()
        local qs = STATE.queueState
        if not qs or not qs.seats then return nil end
        for _, seat in ipairs(qs.seats) do
            if seat.state == "Available" then
                return seat
            end
        end
        return nil
    end

    local function getFrontCustomer()
        local qs = STATE.queueState
        if not qs or not qs.front then return nil end
        return qs.front
    end

    local function assignSeat(seatId)
        if STATE.cooldown then return end
        local qs = STATE.queueState
        if not qs then return end
        local front = qs.front
        if not front then return end

        STATE.cooldown = true
        OrderRegisterEvent:FireServer(
            "AssignSeat",
            front.id,
            seatId,
            tonumber(qs.revision) or 0,
            qs.ownerUserId or LocalPlayer.UserId
        )
        task.delay(STATE.delay, function()
            STATE.cooldown = false
        end)
    end

    local function tryAssign()
        if not STATE.assignEnabled then return end
        acquireLock("assign")
        STATE.assignBusy = true
        local plotName = getMyPlot()
        if not plotName then STATE.assignBusy = false releaseLock() return end
        local seated, chairs = countSeatedAndChairs(plotName)
        if seated >= chairs then STATE.assignBusy = false releaseLock() return end
        local npc = findWaitingNPC(plotName)
        if not npc then STATE.assignBusy = false releaseLock() return end

        STATE.queueState = nil
        local opened = openCounter()
        if not opened then releaseLock() return end

        local deadline = tick() + 3
        while tick() < deadline and not STATE.queueState do
            task.wait(0.1)
        end

        while STATE.assignEnabled do
            local front = getFrontCustomer()
            local seat = getAvailableSeat()
            if not front or not seat then break end
            assignSeat(seat.id)
            STATE.queueState = nil
            local qDeadline = tick() + 2
            while tick() < qDeadline and not STATE.queueState do
                task.wait(0.1)
            end
            seated, chairs = countSeatedAndChairs(plotName)
            if seated >= chairs then break end
        end

        closeCounter()
        STATE.assignBusy = false
        releaseLock()
    end

    OrderRegisterEvent.OnClientEvent:Connect(function(action, data)
        if type(data) == "table" and data.seats ~= nil then
            STATE.queueState = data
        end
    end)

    -- ========== AUTO-GRILL + DELIVER LOOP ==========

    local function getTrayFoodKeys()
        local keys = {}
        local char = LocalPlayer.Character
        if not char then return keys end
        local tray = char:FindFirstChild("BatchServingTray")
        if not tray then return keys end
        for _, c in ipairs(tray:GetChildren()) do
            local foodKey = c.Name:match("^(.+)_Ready$")
            if foodKey then
                keys[foodKey] = (keys[foodKey] or 0) + 1
            end
        end
        return keys
    end

    local function getRackFoodKeys()
        local keys = {}
        local sync = STATE.sync
        if not sync then return keys end
        for _, item in ipairs(sync.rack or {}) do
            if item.key then
                keys[item.key] = (keys[item.key] or 0) + (item.count or 1)
            end
        end
        return keys
    end

    local function autoGrillLoop()
        local lastCustomerCount = 0
        while STATE.grillEnabled do
            yieldIfEmergency()

            -- Reset served tracking when customers change
            local plotName = getMyPlot()
            if plotName then
                local plot = workspace.KantoPlots:FindFirstChild(plotName)
                if plot then
                    local custFolder = plot:FindFirstChild("Runtime") and plot.Runtime:FindFirstChild("Customers")
                    if custFolder then
                        local count = #custFolder:GetChildren()
                        if count ~= lastCustomerCount then
                            servedCustomers = {}
                            lastCustomerCount = count
                        end
                    end
                end
            end

            -- Request fresh sync
            requestState()
            task.wait(0.2)

            local sync = STATE.sync
            if not sync then
                STATE.lastStatus = "Waiting for sync..."
                task.wait(1)
                continue
            end

            local grills = sync.grills or {}
            local orders = sync.orders or {}
            local demand = sync.demand or {}
            local syncStock = sync.stock or {}

            -- ============================================================
            -- STEP 1: FLIP — highest priority, prevent burning
            -- ============================================================
            for _, g in ipairs(grills) do
                if not STATE.grillEnabled then break end
                yieldIfEmergency()
                local anchor = g.anchor
                if not anchor then continue end
                for _, batch in ipairs(g.batches or {}) do
                    if batch.phase == "Turn" or batch.phase == "TurnWarning" then
                        STATE.lastStatus = "Flip " .. (batch.key or "?") .. " (grill " .. g.id .. ")"
                        flipOnGrill(g.id)
                        task.wait(0.2)
                        break
                    end
                end
            end

            -- ============================================================
            -- STEP 2: COLLECT ready food from all grills
            -- ============================================================
            for _, g in ipairs(grills) do
                if not STATE.grillEnabled then break end
                yieldIfEmergency()
                for _, batch in ipairs(g.batches or {}) do
                    if batch.phase == "Ready" or batch.phase == "ReadyWarning" then
                        STATE.lastStatus = "Collect " .. (batch.key or "?") .. " (grill " .. g.id .. ")"
                        collectFromGrill(g.id)
                        task.wait(0.3)
                        break
                    end
                end
            end

            -- ============================================================
            -- STEP 3: DELIVER tray food to ALL customers
            -- ============================================================
            while STATE.grillEnabled do
                yieldIfEmergency()
                local trayFood = getTrayFoodKeys()
                local trayCount = 0
                for _, count in pairs(trayFood) do trayCount = trayCount + count end
                if trayCount <= 0 then break end

                -- Try to serve one customer
                STATE.lastStatus = "Deliver tray (" .. trayCount .. " left)"
                local served = serveToCustomer()
                if not served then break end
                task.wait(0.5)
            end

            -- Also pickup from rack and deliver ALL
            while STATE.grillEnabled do
                yieldIfEmergency()
                requestState()
                sync = STATE.sync or sync
                local rackFood = getRackFoodKeys()
                local rackCount = 0
                for _, count in pairs(rackFood) do rackCount = rackCount + count end
                if rackCount == 0 then break end

                STATE.lastStatus = "Pickup rack (" .. rackCount .. ")"
                pickupFromRack()
                task.wait(0.5)

                while STATE.grillEnabled and hasFoodTool() do
                    STATE.lastStatus = "Deliver rack food"
                    local served = serveToCustomer()
                    if not served then break end
                    task.wait(0.5)
                end
            end

            -- ============================================================
            -- STEP 4: LOAD grills based on orders
            -- ============================================================
            -- Recalculate after possible collects
            demand = (STATE.sync or sync).demand or {}
            grills = (STATE.sync or sync).grills or {}
            orders = (STATE.sync or sync).orders or {}
            syncStock = (STATE.sync or sync).stock or {}

            local neededFoods = {}
            for _, order in ipairs(orders) do
                if order.key and order.remaining and order.remaining > 0 then
                    neededFoods[order.key] = (neededFoods[order.key] or 0) + order.remaining
                end
            end

            local trayFood = getTrayFoodKeys()
            local rackFood = getRackFoodKeys()

            local alreadyMade = {}
            for key, d in pairs(demand) do
                alreadyMade[key] = (d.cooking or 0) + (d.ready or 0) + (d.plated or 0)
            end

            local toCook = {}
            for key, need in pairs(neededFoods) do
                local made = alreadyMade[key] or 0
                local onTray = trayFood[key] or 0
                local onRack = rackFood[key] or 0
                local total = made + onTray + onRack
                if need > total and (syncStock[key] or 0) > 0 then
                    toCook[key] = need - total
                end
            end

            -- Load each grill that has space
            for _, g in ipairs(grills) do
                if not STATE.grillEnabled then break end
                yieldIfEmergency()

                local batches = g.batches or {}
                local capacity = g.capacity or 4
                local freeSlots = capacity - #batches

                if freeSlots <= 0 then continue end

                local foodToLoad = nil
                local qtyToLoad = nil

                for key, remaining in pairs(toCook) do
                    if remaining > 0 then
                        foodToLoad = key
                        qtyToLoad = math.min(remaining, freeSlots)
                        toCook[key] = remaining - qtyToLoad
                        break
                    end
                end

                if not foodToLoad then
                    for key, d in pairs(demand) do
                        if (d.load or 0) > 0 and (syncStock[key] or 0) > 0 then
                            foodToLoad = key
                            qtyToLoad = math.min(d.load, freeSlots)
                            break
                        end
                    end
                end

                if foodToLoad then
                    STATE.lastStatus = "Load " .. foodToLoad .. " x" .. qtyToLoad .. " (grill " .. g.id .. ")"
                    loadFoodOnGrill(g.id, foodToLoad, qtyToLoad)
                    task.wait(0.5)
                end
            end

            -- ============================================================
            -- STEP 5: FAN grills that are full and cooking
            -- ============================================================
            for _, g in ipairs(grills) do
                if not STATE.grillEnabled then break end
                local batches = g.batches or {}
                if #batches > 0 then
                    local allCooking = true
                    for _, batch in ipairs(batches) do
                        if batch.phase ~= "SideOne" and batch.phase ~= "SideTwo" then
                            allCooking = false
                        end
                    end
                    if allCooking and #batches >= (g.capacity or 4) then
                        STATE.lastStatus = "Fan grill " .. g.id
                        fanLoop(1.5)
                    end
                end
            end

            task.wait(0.3)
        end
        STATE.lastStatus = "Stopped"
    end

    -- ========== AUTO-BROOM LOGIC ==========

    local function findRunawayCustomer()
        local plotName = getMyPlot()
        if not plotName then return nil end
        local plot = workspace.KantoPlots:FindFirstChild(plotName)
        if not plot then return nil end
        local customers = plot:FindFirstChild("Runtime")
        customers = customers and customers:FindFirstChild("Customers")
        if not customers then return nil end

        for _, cust in ipairs(customers:GetChildren()) do
            local hrp = cust:FindFirstChild("HumanoidRootPart")
            if hrp then
                local state = cust:GetAttribute("CustomerState")
                local owed = cust:GetAttribute("OwedPlayerUserId")
                local deadline = cust:GetAttribute("EscapeDeadline") or 0
                if state == "FleeingWithoutPaying"
                    and owed == LocalPlayer.UserId
                    and workspace:GetServerTimeNow() < deadline then
                    return cust, hrp
                end
            end
        end
        return nil
    end

    local function swingBroom()
        pcall(function() BroomEvent:FireServer("Swing") end)
    end

    local function autoBroomLoop()
        while STATE.broomEnabled do
            local cust, hrp = findRunawayCustomer()
            if not cust or not hrp then
                STATE.lastBroomStatus = "No runaways"
                task.wait(0.5)
                continue
            end

            STATE.emergency = true
            STATE.lock = nil
            acquireLock("broom")
            STATE.emergency = false

            STATE.lastBroomStatus = "Chasing " .. cust.Name .. "!"
            local hrpPlayer = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not hrpPlayer then
                releaseLock()
                task.wait(0.5)
                continue
            end

            equipTool("Basic Broom")
            task.wait(0.15)

            local deadline = tick() + 5
            while STATE.broomEnabled and tick() < deadline do
                hrpPlayer = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not hrpPlayer then break end
                hrpPlayer.CFrame = CFrame.new(hrp.Position + Vector3.new(3, 0, 0))
                task.wait(0.1)
                swingBroom()
                task.wait(0.3)
                local still = cust:GetAttribute("CustomerState")
                if still ~= "FleeingWithoutPaying" then
                    STATE.lastBroomStatus = "Caught!"
                    break
                end
            end

            unequipTools()
            releaseLock()
            task.wait(0.5)
        end
        STATE.lastBroomStatus = "Stopped"
    end

    -- ========== AUTO-RESTOCK LOGIC ==========

    local function buyCondiments()
        local ok, result = pcall(function()
            return FoodEconomyFunction:InvokeServer("BuyCondiments", "Condiments", 100)
        end)
        return ok, result
    end

    local function autoRestockLoop()
        while STATE.restockEnabled do
            local amt = STATE.buyAmount

            if condimentCount <= 5 then
                STATE.lastRestockStatus = "Low condiments (" .. condimentCount .. "), buying..."
                buyCondiments()
                task.wait(1)
            end

            local restockedAny = false
            for key, unlocked in pairs(unlockedFoods) do
                if unlocked and (foodStock[key] or 0) < 6 then
                    STATE.lastRestockStatus = "Restocking " .. key .. " (buy " .. amt .. ")..."
                    local ok = buyStock(key, amt)
                    if ok then restockedAny = true end
                    task.wait(0.5)
                end
            end

            if restockedAny then
                STATE.lastRestockStatus = "Food restocked!"
            elseif condimentCount <= 5 then
                STATE.lastRestockStatus = "Condiments restocked!"
            else
                STATE.lastRestockStatus = "All stock OK"
            end

            task.wait(3)
        end
        STATE.lastRestockStatus = "Stopped"
    end

    -- ========== UI: HOME TAB ==========

    homeTab:AddToggle({
        Name = "Auto Assign",
        Value = false,
        Callback = function(v)
            STATE.assignEnabled = v
            if v then
                STATE.myPlot = detectMyPlot()
                task.spawn(function()
                    while STATE.assignEnabled do
                        yieldIfEmergency()
                        tryAssign()
                        task.wait(2)
                    end
                end)
            end
        end,
    })

    homeTab:AddToggle({
        Name = "Auto Grill + Deliver",
        Value = false,
        Callback = function(v)
            STATE.grillEnabled = v
            if v then
                STATE.myPlot = detectMyPlot()
                task.spawn(autoGrillLoop)
            end
        end,
    })

    homeTab:AddToggle({
        Name = "Auto Broom",
        Value = false,
        Callback = function(v)
            STATE.broomEnabled = v
            if v then
                STATE.myPlot = detectMyPlot()
                task.spawn(autoBroomLoop)
            end
        end,
    })

    homeTab:AddDropdown({
        Name = "Restock Amount",
        Options = { "1", "5", "10", "100" },
        Value = "10",
        Callback = function(v)
            STATE.buyAmount = tonumber(v) or 10
        end,
    })

    homeTab:AddToggle({
        Name = "Auto Restock",
        Value = false,
        Callback = function(v)
            STATE.restockEnabled = v
            if v then
                task.spawn(autoRestockLoop)
            end
        end,
    })

    -- ========== SHOP ITEMS (sorted by Rank) ==========
    local SHOP_ITEMS = {
        -- Rank 1
        { Key = "CheapStool", Name = "Starter Stool", Category = "Chairs", Price = 100, Rank = 1 },
        { Key = "MakeshiftGrill", Name = "Makeshift Grill", Category = "Grills", Price = 600, Rank = 1 },
        { Key = "CheapTable", Name = "Starter Scrap Table", Category = "Tables", Price = 360, Rank = 1 },
        { Key = "CraftsmanCashCounter", Name = "Craftsman Cash Counter", Category = "Cashboxes", Price = 12000, Rank = 1 },
        -- Rank 2
        { Key = "SimpleWoodChair", Name = "Simple Wooden Chair", Category = "Chairs", Price = 200, Rank = 2 },
        { Key = "SteelGrill", Name = "Steel Charcoal Grill", Category = "Grills", Price = 2000, Rank = 2 },
        { Key = "SimpleWoodTable", Name = "Simple Wooden Table", Category = "Tables", Price = 750, Rank = 2 },
        { Key = "MetroCashCounter", Name = "Metro Checkout Counter", Category = "Cashboxes", Price = 150000, Rank = 2 },
        -- Rank 3
        { Key = "MonoblocChair", Name = "Monobloc Chair", Category = "Chairs", Price = 330, Rank = 3 },
        { Key = "CommercialGrill", Name = "Commercial Grill", Category = "Grills", Price = 7200, Rank = 3 },
        { Key = "PlasticPatioTable", Name = "Plastic Patio Table", Category = "Tables", Price = 1600, Rank = 3 },
        { Key = "LuxeCashCounter", Name = "Luxe Cash Counter", Category = "Cashboxes", Price = 1000000, Rank = 3 },
        -- Rank 4
        { Key = "FoldingMetalChair", Name = "Folding Metal Chair", Category = "Chairs", Price = 570, Rank = 4 },
        { Key = "PremiumGrill", Name = "Premium Stainless Grill", Category = "Grills", Price = 19500, Rank = 4 },
        { Key = "MetalCafeTable", Name = "Metal Café Table", Category = "Tables", Price = 2850, Rank = 4 },
        -- Rank 5
        { Key = "RattanChair", Name = "Rattan Chair", Category = "Chairs", Price = 4500, Rank = 5 },
        { Key = "LongFoldingTable", Name = "Long Folding Table", Category = "Tables", Price = 3750, Rank = 5 },
        -- Rank 6
        { Key = "UpholsteredChair", Name = "Upholstered Chair", Category = "Chairs", Price = 12500, Rank = 6 },
        { Key = "RattanDiningTable", Name = "Rattan Dining Table", Category = "Tables", Price = 25000, Rank = 6 },
        -- Rank 7
        { Key = "SampaguitaChair", Name = "Sampaguita Jade Chair", Category = "Chairs", Price = 0, Rank = 7, Locked = true },
        { Key = "SampaguitaTable", Name = "Sampaguita Pearl Table", Category = "Tables", Price = 0, Rank = 7, Locked = true },
        -- Rank 8
        { Key = "AmihanChair", Name = "Amihan Gold Chair", Category = "Chairs", Price = 0, Rank = 8, Locked = true },
        { Key = "AmihanTable", Name = "Amihan Midnight Table", Category = "Tables", Price = 0, Rank = 8, Locked = true },
        -- Rank 9 (Suites)
        { Key = "KawayanChair", Name = "Kawayan Chair", Category = "Chairs", Price = 22000, Rank = 9 },
        { Key = "KawayanTable", Name = "Kawayan Table", Category = "Tables", Price = 60000, Rank = 9 },
        { Key = "KawayanGrill", Name = "Kawayan Grill", Category = "Grills", Price = 65000, Rank = 9 },
        { Key = "KawayanSign", Name = "Kawayan Sign", Category = "Signs", Price = 35000, Rank = 9 },
        -- Rank 10
        { Key = "HaranaChair", Name = "Harana Chair", Category = "Chairs", Price = 55000, Rank = 10 },
        { Key = "HaranaTable", Name = "Harana Table", Category = "Tables", Price = 150000, Rank = 10 },
        { Key = "HaranaGrill", Name = "Harana Grill", Category = "Grills", Price = 180000, Rank = 10 },
        { Key = "HaranaSign", Name = "Harana Sign", Category = "Signs", Price = 100000, Rank = 10 },
        -- Rank 11
        { Key = "NocturneChair", Name = "Nocturne Chair", Category = "Chairs", Price = 150000, Rank = 11 },
        { Key = "NocturneTable", Name = "Nocturne Table", Category = "Tables", Price = 450000, Rank = 11 },
        { Key = "NocturneGrill", Name = "Nocturne Grill", Category = "Grills", Price = 500000, Rank = 11 },
        { Key = "NocturneSign", Name = "Nocturne Sign", Category = "Signs", Price = 300000, Rank = 11 },
        -- Rank 12
        { Key = "EsmeraldaChair", Name = "Esmeralda Chair", Category = "Chairs", Price = 350000, Rank = 12 },
        { Key = "EsmeraldaTable", Name = "Esmeralda Table", Category = "Tables", Price = 1000000, Rank = 12 },
        { Key = "EsmeraldaGrill", Name = "Esmeralda Grill", Category = "Grills", Price = 1000000, Rank = 12 },
        { Key = "EsmeraldaSign", Name = "Esmeralda Sign", Category = "Signs", Price = 1000000, Rank = 12 },
    }

    local function buyFurniture(itemKey)
        local ok, result = pcall(function()
            return FurnitureShopFunction:InvokeServer("Buy", itemKey, 1)
        end)
        return ok, result
    end

    -- Build display names for dropdown
    local shopNames = {}
    for _, item in ipairs(SHOP_ITEMS) do
        local priceStr = item.Price > 0 and (" $" .. item.Price) or ""
        table.insert(shopNames, item.Name .. " - " .. item.Category .. priceStr)
    end


     shopTab:AddDropdown({
        Name = "Select Items",
        Options = shopNames,
        Multi = true,
        Callback = function(v)
            STATE.shopSelected = v
        end,
    })

    shopTab:AddToggle({
        Name = "Auto Buy Selected",
        Value = false,
        Callback = function(v)
            STATE.autoBuy = v
        end,
    })

        -- ========== STOCK HELPERS (read Remaining stock per item) ==========
    local function getShopState()
        local ok, _, data = pcall(function()
            return FurnitureShopFunction:InvokeServer("GetState")
        end)
        if not ok or type(data) ~= "table" then return nil end
        return data
    end

    -- ========== AUTO BUY LOOP (stock-aware) ==========
    local boughtThisCycle = {}
    local lastSecs = nil

       -- ========== STOCK CHECK ==========
    local function getShopState()
        local ok, _, data = pcall(function()
            return FurnitureShopFunction:InvokeServer("GetState")
        end)
        if not ok or type(data) ~= "table" then return nil end
        return data
    end

        -- ========== STOCK CHECK ==========
    local function getShopState()
        local ok, _, data = pcall(function()
            return FurnitureShopFunction:InvokeServer("GetState")
        end)
        if not ok or type(data) ~= "table" then return nil end
        return data
    end

    -- ========== AUTO BUY LOOP ==========
    local boughtThisCycle = {}
    local lastSecs = nil

    task.spawn(function()
        print("[AutoBuy] loop started")
        while STATE.alive do
            if STATE.autoBuy and STATE.shopSelected and #STATE.shopSelected > 0 then
                local data = getShopState()
                if data then
                    local stock = type(data.Stock) == "table" and data.Stock or {}
                    local remaining = type(stock.Remaining) == "table" and stock.Remaining or {}
                    local available = type(data.Available) == "table" and data.Available or {}
                    local secs = tonumber(stock.SecondsUntilReset) or 999

                    if lastSecs and secs > lastSecs + 100 then
                        print("[AutoBuy] restock — clearing cache")
                        boughtThisCycle = {}
                    end
                    lastSecs = secs

                    -- Iterate over ARRAY of selected display names
                    for _, displayName in ipairs(STATE.shopSelected) do
                        if type(displayName) == "string" then
                            for _, item in ipairs(SHOP_ITEMS) do
                                local priceStr = item.Price > 0 and (" $" .. item.Price) or ""
                                local expected = item.Name .. " - " .. item.Category .. priceStr

                                if expected == displayName and not item.Locked then
                                    local qty = tonumber(remaining[item.Key]) or 0
                                    local isAvail = available[item.Key] == true

                                    if qty > 0 and isAvail and not boughtThisCycle[item.Key] then
                                        print(string.format("[AutoBuy] buying %s (stock %d)", item.Key, qty))
                                        local ok, result = buyFurniture(item.Key)
                                        print(string.format("[AutoBuy] %s → ok=%s result=%s",
                                            item.Key, tostring(ok), tostring(result)))
                                        if ok and result == true then
                                            boughtThisCycle[item.Key] = true
                                            pcall(function()
                                                win:Notify("Shop", "Bought " .. item.Name, 2)
                                            end)
                                        end
                                        task.wait(0.2)
                                    end
                                    break
                                end
                            end
                        end
                    end

                    task.wait(secs <= 5 and 0.3 or 1.0)
                else
                    task.wait(1)
                end
            else
                task.wait(1)
            end
        end
        print("[AutoBuy] loop exited")
    end)

end)()
    
       
       
