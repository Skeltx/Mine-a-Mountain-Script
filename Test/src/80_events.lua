-- ============================================================
-- MaM :: 80_events.lua
-- EVENTS — вкладка Events (Halloween 2026: candy/ghost/pumpkin)
-- Все общие имена приходят из getgenv().MaMEnv (заполняет 00_main).
-- ============================================================

local E = getgenv().MaMEnv

local Services = E.Services
local LocalPlayer = E.LocalPlayer
local Mouse = E.Mouse
local Config = E.Config
local State = E.State
local Storage = E.Storage
local Connections = E.Connections
local GuiRoot = E.GuiRoot
local Remotes = E.Remotes
local Library = E.Library
local Window = E.Window
local Tabs = E.Tabs
local SettingsTab = E.SettingsTab
local reportError = E.reportError
local formatShort = E.formatShort
local formatWeight = E.formatWeight
local formatLuck = E.formatLuck
local parseValue = E.parseValue
local crystalValue = E.crystalValue
local crystalWeight = E.crystalWeight
local crystalName = E.crystalName
local crystalColor = E.crystalColor
local crystalLuck = E.crystalLuck
local backpackCapacity = E.backpackCapacity
local backpackWeight = E.backpackWeight
local backpackFree = E.backpackFree
local eachContainer = E.eachContainer
local requestStream = E.requestStream
local teleportTo = E.teleportTo

-- ====================================================================
-- ВКЛАДКА EVENTS
-- ====================================================================
local EventsTab = Window:AddTab("Events", "calendar")
local EventsBox = EventsTab:AddLeftGroupbox("Halloween 2026", "calendar")
EventsBox:AddLabel("Event Halloween 2026", true)
EventsBox:AddDivider()

-- Стоп-функции всех ивент-функций (вызываются цепочкой при выгрузке скрипта)
local _eventsStops = {}

local camera = Services.Workspace.CurrentCamera
local VirtualUser = Services.VirtualUser

-- ====================================================================
-- 1. AUTO COLLECT CANDY
-- ====================================================================
local isCandyRunning = false
local origCol = {}

-- candy-совпадение ищем по ЛЮБОМУ предку (раньше — только имя и родитель).
-- По скану CandyScan: настоящие конфеты — незаякоренные MeshPart в Workspace/DroppedCandy,
-- а заякоренные "candy"-объекты (VFX_Candy_*, Deco_CandyBowl) — это эффекты и декорации,
-- их собираемому касанию сервер не отдаёт — отсеиваем по Anchored.
local function isCandy(obj)
    if not obj or not obj.Parent then return false end
    if not (obj:IsA("BasePart") or obj:IsA("Model")) then return false end
    if obj:IsA("BasePart") then
        if obj.Anchored then return false end
    else
        local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
        if part and part.Anchored then return false end
    end

    local hit = string.lower(obj.Name):find("candy") ~= nil
    if not hit then
        local p = obj.Parent
        while p and p ~= Services.Workspace do
            if string.lower(p.Name):find("candy") then
                hit = true
                break
            end
            p = p.Parent
        end
    end
    if not hit then return false end

    -- исключения: грядки/базы/установленное — проверяем по всей цепочке предков
    local p2 = obj
    while p2 and p2 ~= Services.Workspace do
        local ln = string.lower(p2.Name)
        if ln:find("plot") or ln:find("base") or ln:find("placed") then return false end
        p2 = p2.Parent
    end
    return true
end

local function candyPos(obj)
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then
        local ok, pv = pcall(obj.GetPivot, obj)
        if ok and pv then return pv.Position end
    end
    return nil
end

local function toggleNoclip(char, state)
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if state then
                if origCol[part] == nil then origCol[part] = part.CanCollide end
                part.CanCollide = false
                part.AssemblyLinearVelocity = Vector3.zero
            elseif origCol[part] ~= nil then
                part.CanCollide = origCol[part]
            end
        end
    end
    if not state then table.clear(origCol) end
end

local candyCollected = 0

EventsBox:AddToggle("AutoCandy", {
    Text = "Auto Collect Candy",
    Default = false,
    Callback = function(v)
        isCandyRunning = v
        if v then
            candyCollected = 0
        else
            toggleNoclip(LocalPlayer.Character, false)
            if candyCollected > 0 then
                Library:Notify(string.format("Candy: collected %d for session", candyCollected), 4)
            end
        end
    end
})

table.insert(_eventsStops, function()
    isCandyRunning = false
    toggleNoclip(LocalPlayer.Character, false)
end)

task.spawn(function()
    while task.wait(0.2) do
        if not isCandyRunning then continue end

        local foundAny = false

        for _, v in ipairs(Services.Workspace:GetDescendants()) do
            if not isCandyRunning then break end

            -- устойчивость к респавну: персонаж перечитывается на каждом шаге
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not (char and hrp) then break end

            if isCandy(v) then
                -- одна конфета = один заход: деталь внутри модели-конфеты ждёт сама модель
                if v:IsA("BasePart") and v.Parent and v.Parent:IsA("Model") and isCandy(v.Parent) then
                    continue
                end
                -- до 3 попыток на конфету: телепорт прямо в точку, чуть выше, со сдвигом.
                -- Если после захода конфета ещё на месте (сервер не засчитал касание) — пробуем снова.
                for _, offset in ipairs({ Vector3.zero, Vector3.new(0, 1.5, 0), Vector3.new(1.2, 0.6, 0) }) do
                    if not v.Parent or not isCandyRunning then break end
                    local pos = candyPos(v)
                    if not pos then break end
                    toggleNoclip(char, true)
                    hrp.CFrame = CFrame.new(pos + offset)
                    task.wait(0.22)
                    char = LocalPlayer.Character
                    hrp = char and char:FindFirstChild("HumanoidRootPart")
                    if not (char and hrp) then break end
                end
                foundAny = true
                candyCollected += 1
            end
        end

        if not foundAny and LocalPlayer.Character then
            toggleNoclip(LocalPlayer.Character, false)
        end
    end
end)


-- ====================================================================
-- 2/3. AUTO FARM CAVEGHOST / SMASHABLE PUMPKIN (общая фабрика ниже)
-- ====================================================================
-- (локальные переменные старых реализаций больше не нужны)

local RemotesFolder = Services.ReplicatedStorage:FindFirstChild("Remotes") or Services.ReplicatedStorage:WaitForChild("Remotes", 5)
local DigRequest = RemotesFolder and RemotesFolder:FindFirstChild("DigRequest")

local PICK_NAMES = {
    ["The Terminus"] = true, ["Voidreign"] = true, ["Celestial Apex"] = true,
    ["Eclipse Fang"] = true, ["Nebular Throne"] = true, ["Singularity"] = true,
    ["Astral Rend"] = true, ["Obsidian Edge"] = true, ["Tempest Pick"] = true,
    ["Frostbite Pick"] = true, ["Emerald Carver"] = true, ["Volcano Basalt"] = true,
    ["Titanium Spike"] = true, ["Reinforced Steel"] = true, ["Copper Pick"] = true,
    ["Hardened Iron"] = true, ["Chipped Stone"] = true, ["Weathered Wood"] = true,
    ["Rusty Scrapper"] = true, ["Admin Pickaxe"] = true, ["Shark Pickaxe"] = true,
    ["Diamond Pickaxe"] = true
}

local function isPickaxe(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if tool:GetAttribute("IsPickaxe") == true then return true end
    if tool:GetAttribute("DigPower") ~= nil and tool:GetAttribute("Tier") == nil then return true end
    if PICK_NAMES[tool.Name] then return true end
    local lower = tool.Name:lower()
    if lower:find("pick") or lower:find("terminus") then return true end
    return false
end

local function equipPickaxe()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return end
    
    local held = char:FindFirstChildOfClass("Tool")
    if held and isPickaxe(held) then return end
    
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if isPickaxe(t) then
                hum:EquipTool(t)
                task.wait(0.05)
                return
            end
        end
    end
end

-- ====================================================================
-- ОБЩАЯ ФАБРИКА ФАРМА ИВЕНТ-СУЩНОСТЕЙ (CaveGhost / SmashablePumpkin)
-- Адаптивные удары по реальному урону, анти-залипание (таймаут на цель),
-- авто-продажа при полной сумке, устойчивость к респавну, счётчики.
-- opts = {
--     key          = имя опции (для SaveManager),
--     text         = текст тумблера,
--     label        = подпись для уведомлений,
--     matches      = function(obj) -> bool,    -- проверка "это наша цель?",
--     getPos       = function(obj) -> Vector3, -- позиция цели,
--     standDist    = число,   -- расстояние, с которого бьём (studs),
--     standOffset  = Vector3, -- смещение точки стояния,
--     lockAim      = bool,    -- true: держать позу/камеру каждый кадр,
--     hitTimeout   = число,   -- макс. сек на цель (когда HP известно),
--     bridgeTries  = число,   -- число волн, если HP неизвестно,
--     missCooldown = число,   -- сек в игнор-листе после промаха,
--     scanInterval = число,   -- сек между поисками новой цели,
--     hitWait      = число,   -- сек пауза между волнами удара,
-- }
-- ====================================================================
-- Текущее HP сущности (атрибуты HP/Health, Humanoid или дети), nil если неизвестно
local function entityHPValue(obj)
    if not obj or not obj.Parent then return nil end

    local v = tonumber(obj:GetAttribute("HP")) or tonumber(obj:GetAttribute("Health"))
    if v ~= nil then return v end

    if obj:IsA("Model") then
        local hum = obj:FindFirstChildOfClass("Humanoid")
        if hum then return hum.Health end
    end

    for _, child in ipairs(obj:GetChildren()) do
        v = tonumber(child:GetAttribute("HP")) or tonumber(child:GetAttribute("Health"))
        if v ~= nil then return v end
    end

    return nil
end

local lastEventSellClock = 0
-- Авто-продажа при заполнении сумки выше AutoSellThreshold (для всех ивент-функций)
local function autoSellIfFilled()
    local capacity = backpackCapacity()
    if not capacity or capacity == math.huge then return end

    local weight = backpackWeight()
    if weight <= 0 then return end
    if weight / capacity < (Config.AutoSellThreshold or 0.5) then return end

    local now = os.clock()
    if now - lastEventSellClock < 10 then return end
    lastEventSellClock = now

    task.spawn(function()
        local ok, sold = pcall(doSell)
        if ok and sold then
            Library:Notify("Сумка полная - продаю всё", 3)
        end
    end)
end

-- ====================================================================
local function makeEntityFarmer(opts)
    local running = false
    local kills = 0
    local currentTarget = nil
    local recentlyHit = {}
    local lastScan = 0

    local function matches(obj)
        local ok, res = pcall(opts.matches, obj)
        return ok and res == true
    end

    local function entityPos(obj)
        local ok, res = pcall(opts.getPos, obj)
        return ok and res or nil
    end

    local farm = {}

    farm.stop = function()
        running = false
        currentTarget = nil
        table.clear(recentlyHit)
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.WalkSpeed = 16
            hum.JumpPower = 50
            hum.AutoRotate = true
        end
        if kills > 0 then
            Library:Notify(string.format("%s: убито за сессию %d", opts.label or "Farm", kills), 4)
        end
        kills = 0
    end
    table.insert(_eventsStops, farm.stop)

    EventsBox:AddToggle(opts.key, {
        Text = opts.text,
        Default = false,
        Callback = function(v)
            if v then
                running = true
                kills = 0
            else
                farm.stop()
            end
        end,
    })

    -- фоновая экипировка кирки
    task.spawn(function()
        while task.wait(0.5) do
            if not running then continue end

            local char = LocalPlayer.Character
            local held = char and char:FindFirstChildOfClass("Tool")
            if held and isPickaxe(held) then continue end
            pcall(equipPickaxe)
        end
    end)

    -- основной цикл
    task.spawn(function()
        while task.wait(0.05) do
            if not running then continue end

            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not (char and hrp and hum) then continue end

            -- авто-продажа при полной сумке
            pcall(autoSellIfFilled)

            -- чистим игнор-лист
            for obj, expire in pairs(recentlyHit) do
                if os.clock() > expire or not obj.Parent then
                    recentlyHit[obj] = nil
                end
            end

            -- ищем ближайшую цель (не чаще scanInterval)
            if not (currentTarget and currentTarget.Parent) then
                currentTarget = nil
                local now = os.clock()
                if now - lastScan >= (opts.scanInterval or 0.5) then
                    lastScan = now
                    local hrpPos = hrp.Position
                    local best, bestDist = nil, math.huge
                    for _, v in ipairs(Services.Workspace:GetDescendants()) do
                        if matches(v) then
                            local p = entityPos(v)
                            if p then
                                local d = (p - hrpPos).Magnitude
                                if d < bestDist then
                                    bestDist = d
                                    best = v
                                end
                            end
                        end
                    end
                    currentTarget = best
                end
            end

            local target = currentTarget
            if not (target and target.Parent) then continue end

            local pos = entityPos(target)
            if not pos then
                currentTarget = nil
                continue
            end

            -- заморозка
            local bv = Instance.new("BodyVelocity")
            bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bv.Velocity = Vector3.zero
            bv.Parent = hrp

            hum.WalkSpeed = 0
            hum.JumpPower = 0
            hum.AutoRotate = false

            local dir = (hrp.Position - pos).Unit
            if dir.Magnitude == 0 then dir = Vector3.new(0, 0, 1) end

            local standPos = pos + (dir * (opts.standDist or 2)) + (opts.standOffset or Vector3.new(0, -1.5, 0))
            local aimPos = opts.aimOffset and (pos + opts.aimOffset) or pos

            local lockConn
            if opts.lockAim then
                lockConn = Services.RunService.RenderStepped:Connect(function()
                    if hrp and hrp.Parent then
                        hrp.CFrame = CFrame.lookAt(standPos, aimPos)
                    end
                    if camera then
                        camera.CFrame = CFrame.lookAt(camera.CFrame.Position, aimPos)
                    end
                end)
            else
                hrp.CFrame = CFrame.lookAt(standPos, aimPos)
                if camera then
                    camera.CFrame = CFrame.lookAt(camera.CFrame.Position, aimPos)
                end
            end

            task.wait(0.1)

            -- удары: адаптивно, ориентируемся на реальный урон
            pcall(equipPickaxe)
            local tool = char:FindFirstChildOfClass("Tool")

            local startHP = entityHPValue(target)
            local hp = startHP
            local seenDamage = false
            local deadline = startHP ~= nil and (os.clock() + (opts.hitTimeout or 8)) or nil
            local tries = 0

            while running and target.Parent do
                tries += 1

                if deadline then
                    if os.clock() > deadline then break end
                elseif tries > (opts.bridgeTries or 3) then
                    break
                end

                if tool and tool.Parent then
                    pcall(function() tool:Activate() end)
                    pcall(function()
                        VirtualUser:CaptureController()
                        VirtualUser:ClickButton1(Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2))
                    end)
                    if DigRequest then
                        pcall(function() DigRequest:FireServer(tool.Name, aimPos) end)
                    end
                end

                local prompt = target:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt then
                    pcall(function()
                        prompt.MaxActivationDistance = 99999
                        prompt.RequiresLineOfSight = false
                        prompt.HoldDuration = 0
                        if fireproximityprompt then fireproximityprompt(prompt) end
                    end)
                end

                local cd = target:FindFirstChildWhichIsA("ClickDetector", true)
                if cd and fireclickdetector then
                    pcall(function() fireclickdetector(cd) end)
                end

                task.wait(opts.hitWait or 0.15)

                -- проверяем реальный урон
                local newHP = entityHPValue(target)
                if newHP ~= nil then
                    if not deadline then
                        deadline = os.clock() + (opts.hitTimeout or 8)
                    end
                    if hp ~= nil and newHP < hp then
                        seenDamage = true
                    end
                    hp = newHP
                    if newHP <= 0 then
                        seenDamage = true
                        break
                    end
                end
            end

            -- итог по цели
            if not target.Parent or (hp ~= nil and hp <= 0) then
                kills += 1
                if kills % 10 == 0 then
                    Library:Notify(string.format("%s: убито %d", opts.label or "Farm", kills), 3)
                end
            elseif not seenDamage then
                -- урон не прошёл — метод не работает для этой цели, игнор-лист
                recentlyHit[target] = os.clock() + (opts.missCooldown or 2)
            end
            currentTarget = nil

            -- разморозка
            if lockConn then lockConn:Disconnect() end
            pcall(function() bv:Destroy() end)
            if hum and hum.Parent then
                hum.WalkSpeed = 16
                hum.JumpPower = 50
                hum.AutoRotate = true
            end
        end
    end)

    return farm
end

makeEntityFarmer({
    key = "AutoGhost",
    text = "Auto Farm Ghost",
    label = "Ghost Farm",
    matches = function(obj)
        if not obj or not obj.Parent then return false end
        if obj.Name ~= "CaveGhost" then return false end
        if not obj:IsA("BasePart") and not obj:IsA("Model") then return false end
        if obj:IsA("BasePart") and obj.Parent and obj.Parent.Name == "CaveGhost" then return false end
        return true
    end,
    getPos = function(obj)
        if not obj or not obj.Parent then return nil end
        if obj:IsA("BasePart") then return obj.Position end
        if obj:IsA("Model") then
            local pp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            return pp and pp.Position or nil
        end
        return nil
    end,
    standDist = 2,
    standOffset = Vector3.new(0, -1.5, 0),
    lockAim = false, -- одноразовая наводка, как в оригинале
    hitTimeout = 8,
    missCooldown = 2,
})

-- (основной цикл фарма внутри makeEntityFarmer)

-- ====================================================================
-- 3. AUTO FARM SMASHABLE PUMPKIN
-- ====================================================================
makeEntityFarmer({
    key = "AutoPumpkin",
    text = "Auto Farm Pumpkin",
    label = "Pumpkin Farm",
    matches = function(obj)
        if not obj or not obj.Parent then return false end
        if obj.Name ~= "SmashablePumpkin" then return false end
        if not obj:IsA("BasePart") and not obj:IsA("Model") then return false end
        if obj:IsA("BasePart") and obj.Parent and obj.Parent.Name == "SmashablePumpkin" then return false end

        local fullName = string.lower(obj:GetFullName())
        if fullName:find("plot") or fullName:find("base") or fullName:find("placed") then return false end
        return true
    end,
    getPos = function(obj)
        if not obj or not obj.Parent then return nil end
        if obj:IsA("BasePart") then return obj.Position end
        if obj:IsA("Model") then
            local pp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            return pp and pp.Position or nil
        end
        return nil
    end,
    standDist = 5,
    standOffset = Vector3.new(0, 2, 0),
    lockAim = true,
    hitTimeout = 8,
    missCooldown = 2,
})

-- Остановка всех ивент-функций при выгрузке/перезапуске скрипта
do
    local _prevUnload = getgenv().UniverseUnload
    local function _combined()
        for _, fn in ipairs(_eventsStops) do
            pcall(fn)
        end
        if _prevUnload and _prevUnload ~= _combined then
            pcall(_prevUnload)
        end
    end
    getgenv().UniverseUnload = _combined
    Library:OnUnload(_combined)
end


-- === Экспорт модуля ===
E._eventsStops = _eventsStops
