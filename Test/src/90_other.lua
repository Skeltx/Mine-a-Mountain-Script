-- ============================================================
-- MaM :: 90_other.lua
-- OTHER — Other (Collect Rune, FPS Boost) + перенос Boulders ESP/Farm (Analog) в Boulders
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
local _eventsStops = E._eventsStops

-- ====================================================================
-- Collect Rune перенесён из вкладки Other во вкладку Farming (правый блок)
-- ==================================================================== 
local OtherBox = Tabs.farming:AddRightGroupbox("Collect Rune", "box")
OtherBox:AddDivider()

-- ↓↓↓ Collect Rune ↓↓↓
local isRuneRunning = false
local origColRune = {}

local function isRune(obj)
    if not obj or not obj.Parent or not obj:IsA("ProximityPrompt") then return false end
    local part = obj.Parent
    if not part or not part:IsA("BasePart") then return false end
    local n, p = string.lower(part.Name), string.lower(part.Parent.Name)
    local f = string.lower(obj:GetFullName())
    local a = string.lower(obj.ActionText or "")
    if f:find("plot") or f:find("base") or f:find("placed") or p:find("plot") then return false end
    return n:find("rune") or p:find("rune") or a == "collect"
end

local function toggleRuneNoclip(char, state)
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if state then
                if origColRune[part] == nil then origColRune[part] = part.CanCollide end
                part.CanCollide = false
                part.AssemblyLinearVelocity = Vector3.zero
            elseif origColRune[part] ~= nil then
                part.CanCollide = origColRune[part]
            end
        end
    end
    if not state then table.clear(origColRune) end
end

local runeCollected = 0

OtherBox:AddToggle("AutoRune", {
    Text = "Collect Rune",
    Default = false,
    Callback = function(v)
        isRuneRunning = v
        if v then
            runeCollected = 0
        else
            toggleRuneNoclip(LocalPlayer.Character, false)
            if runeCollected > 0 then
                Library:Notify(string.format("Rune: collected %d for session", runeCollected), 4)
            end
        end
    end
})

table.insert(_eventsStops, function()
    isRuneRunning = false
    toggleRuneNoclip(LocalPlayer.Character, false)
end)

task.spawn(function()
    while task.wait(0.2) do
        if not isRuneRunning then continue end

        for _, v in ipairs(Services.Workspace:GetDescendants()) do
            if not isRuneRunning then break end

            -- устойчивость к респавну: персонаж перечитывается на каждом шаге
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not (char and hrp) then break end

            if isRune(v) then
                local part = v.Parent
                if part then
                    toggleRuneNoclip(char, true)
                    hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
                    v.MaxActivationDistance = 99999
                    v.HoldDuration = 0
                    for i = 1, 3 do
                        if not isRuneRunning then break end
                        pcall(function() fireproximityprompt(v) end)
                        task.wait(0.02)
                    end
                    runeCollected += 1
                    task.wait(0.05)
                    toggleRuneNoclip(char, false)
                end
            end
        end
    end
end)

-- ====================================================================
-- BOULDERS ESP (Other) — все валуны, фильтр по типам
-- (перенесено из вкладки Other в Boulders как отдельный аналог ESP)
-- ====================================================================
local BouldersOtherBox = Tabs.esp:AddLeftGroupbox("Boulder ESP (Analog)", "mountain")

local bouldersOtherRunning = false
local bouldersOtherCache = {}
local bouldersOtherConns = {}
local bouldersOtherColorCache = {}
local bouldersOtherKnownNames = {}
local bouldersOtherFilter = nil  -- nil или пустая таблица = показывать всё

local bouldersOtherKnownColors = {
    Mossite    = {Color3.new(200/255, 205/255, 215/255), "rgb(200,205,215)"},
    Voltite    = {Color3.new(90/255,  220/255, 110/255), "rgb(90,220,110)"},
    Gildrite   = {Color3.new(80/255,  160/255, 255/255), "rgb(80,160,255)"},
    Rimeveil   = {Color3.new(190/255, 110/255, 255/255), "rgb(190,110,255)"},
    Nocturnite = {Color3.new(255/255, 200/255, 70/255),  "rgb(255,200,70)"},
}

local function bouldersOtherIsEnabled(name)
    if bouldersOtherFilter == nil or next(bouldersOtherFilter) == nil then
        return true
    end
    return bouldersOtherFilter[name] == true
end

local function bouldersOtherResolveColor(name)
    local known = bouldersOtherKnownColors[name]
    if known then return known[1], known[2] end
    local cached = bouldersOtherColorCache[name]
    if cached then return cached[1], cached[2] end
    local hash = 0
    for i = 1, #name do
        hash = (hash * 31 + string.byte(name, i)) % 360
    end
    local color = Color3.fromHSV(hash / 360, 0.8, 1.0)
    local r = math.floor(color.R * 255 + 0.5)
    local g = math.floor(color.G * 255 + 0.5)
    local b = math.floor(color.B * 255 + 0.5)
    local hex = string.format("rgb(%d,%d,%d)", r, g, b)
    bouldersOtherColorCache[name] = {color, hex}
    return color, hex
end

local function boulderHealthHex(p)
    if p >= 1 then return "rgb(0,255,0)" end
    if p <= 0 then return "rgb(255,0,0)" end
    local r, g, b
    if p >= 0.5 then
        local t = (p - 0.5) * 2
        r = math.floor(255 * (1 - t)); g = 255; b = 0
    else
        local t = p * 2
        r = 255; g = math.floor(255 * t); b = 0
    end
    return string.format("rgb(%d,%d,%d)", r, g, b)
end

local function boulderTextSize(d)
    local c = math.max(10, math.min(400, d))
    return math.floor((26 - (c - 10) * (10 / 390)) * 10) / 10
end

local function boulderPadSize(d)
    local c = math.max(10, math.min(400, d))
    return math.floor((8 - (c - 10) * (7 / 390)) * 10) / 10
end

local function boulderMakeLabel(parent, name, text, order)
    local label = Instance.new("TextLabel")
    label.Parent = parent
    label.Name = name
    label.Text = text
    label.LayoutOrder = order or 0
    label.Size = UDim2.new(1, 0, 0, 22)
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.TextSize = 22
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    label.BorderColor3 = Color3.fromRGB(0, 0, 0)
    pcall(function() label.FontFace = Font.new("rbxasset://fonts/families/ComicNeueAngular.json") end)
    label.TextWrapped = true
    label.RichText = true
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextStrokeTransparency = 0.5
    return label
end

local function boulderCreateUI(boulder)
    if not boulder or typeof(boulder) ~= "Instance" then return end
    if not bouldersOtherRunning then return end
    if bouldersOtherCache[boulder] then return end
    local ok, isModel = pcall(function() return boulder:IsA("Model") end)
    if not ok or not isModel or not boulder.Parent then return end
    if not bouldersOtherIsEnabled(boulder.Name) then return end

    local fill, hex = bouldersOtherResolveColor(boulder.Name)

    local transparencies = {}
    for _, part in ipairs(boulder:GetChildren()) do
        if part:IsA("BasePart") then
            transparencies[part] = part.Transparency
            part.Transparency = 0
        end
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "UniverseBoulderOtherHL"
    highlight.FillColor = fill
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0.2
    highlight.Parent = boulder

    local gui = Instance.new("BillboardGui")
    gui.Name = "UniverseBoulderOther"
    gui.Adornee = boulder
    gui.AlwaysOnTop = true
    gui.LightInfluence = 1
    gui.Active = true
    gui.Size = UDim2.new(0, 300, 0, 100)
    gui.ClipsDescendants = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.StudsOffset = Vector3.new(0, 10, 0)
    gui.Parent = boulder

    local layout = Instance.new("UIListLayout")
    layout.Parent = gui
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 2)

    local rarity = boulder:GetAttribute("Rarity") or "Common"
    local hp = tonumber(boulder:GetAttribute("HP")) or 100
    local maxHP = tonumber(boulder:GetAttribute("MaxHP")) or 100

    local nameLabel = boulderMakeLabel(gui, "BoulderName",
        '<font color="' .. hex .. '">' .. boulder.Name .. '</font> (' .. rarity .. ')', 0)
    local hpLabel = boulderMakeLabel(gui, "HP",
        '<font color="' .. boulderHealthHex(hp / math.max(1, maxHP)) .. '">' .. hp .. '</font>/' .. maxHP .. ' HP', 1)
    local distLabel = boulderMakeLabel(gui, "Distance", "Distance: 0 Studs", 2)

    bouldersOtherCache[boulder] = {
        HP = hpLabel, Name = nameLabel, Dist = distLabel,
        Layout = layout, Highlight = highlight, GUI = gui,
        Transparencies = transparencies,
        LastHP = hp, LastMaxHP = maxHP,
        LastSize = 22, LastPad = 2,
        LastName = boulder.Name, LastRarity = rarity,
    }
end

local function boulderDestroyUI(boulder)
    local data = bouldersOtherCache[boulder]
    if not data then return end
    if data.GUI then pcall(function() data.GUI:Destroy() end) end
    if data.Highlight then pcall(function() data.Highlight:Destroy() end) end
    if data.Transparencies then
        for part, t in pairs(data.Transparencies) do
            if part and part.Parent then
                pcall(function() part.Transparency = t end)
            end
        end
    end
    bouldersOtherCache[boulder] = nil
end

local function bouldersOtherRefreshDropdown()
    local list = {}
    for name in pairs(bouldersOtherKnownNames) do
        list[#list + 1] = name
    end
    table.sort(list)
    local dd = Library.Options.BoulderEspOtherFilter
    if dd and dd.SetValues then
        pcall(function() dd:SetValues(list) end)
    end
end

local function bouldersOtherApplyFilter()
    if not bouldersOtherRunning then return end
    local md = Services.Workspace:FindFirstChild("MountainDecorations")
    if not md then return end
    local folder = md:FindFirstChild("Boulders")
    if not folder then return end
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") then
            local enabled = bouldersOtherIsEnabled(model.Name)
            if enabled and not bouldersOtherCache[model] then
                boulderCreateUI(model)
            elseif not enabled and bouldersOtherCache[model] then
                boulderDestroyUI(model)
            end
        end
    end
end

local function bouldersOtherSetFilter(value)
    if value == nil or value == false then
        bouldersOtherFilter = nil
    elseif type(value) == "table" then
        local set = {}
        for key, flag in pairs(value) do
            if type(key) == "string" and flag == true then
                set[key] = true
            elseif type(flag) == "string" then
                set[flag] = true
            end
        end
        bouldersOtherFilter = next(set) and set or nil
    elseif type(value) == "string" then
        bouldersOtherFilter = {[value] = true}
    else
        bouldersOtherFilter = nil
    end
    bouldersOtherApplyFilter()
end

local function boulderScanFolder(force)
    if not bouldersOtherRunning and not force then return end
    local md = Services.Workspace:FindFirstChild("MountainDecorations")
    if not md then return end
    local folder = md:FindFirstChild("Boulders")
    if not folder then return end

    local newName = false
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") then
            if not bouldersOtherKnownNames[model.Name] then
                bouldersOtherKnownNames[model.Name] = true
                newName = true
            end
            if not bouldersOtherCache[model] and bouldersOtherIsEnabled(model.Name) then
                boulderCreateUI(model)
            end
        end
    end

    if newName then
        bouldersOtherRefreshDropdown()
    end
end

local function boulderUpdateAll()
    if not bouldersOtherRunning then return end
    local player = Services.Players.LocalPlayer
    local character = player and player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local stale = {}
    for boulder in pairs(bouldersOtherCache) do
        if not boulder or not boulder.Parent then
            stale[#stale + 1] = boulder
        end
    end
    for _, boulder in ipairs(stale) do
        boulderDestroyUI(boulder)
    end

    for boulder, data in pairs(bouldersOtherCache) do
        local hp = tonumber(boulder:GetAttribute("HP")) or 100
        local maxHP = tonumber(boulder:GetAttribute("MaxHP")) or 100
        if hp ~= data.LastHP or maxHP ~= data.LastMaxHP then
            data.HP.Text = '<font color="' .. boulderHealthHex(hp / math.max(1, maxHP)) .. '">' .. hp .. '</font>/' .. maxHP .. ' HP'
            data.LastHP = hp
            data.LastMaxHP = maxHP
        end

        local part = boulder.PrimaryPart or boulder:FindFirstChildWhichIsA("BasePart")
        if part then
            local dist = math.floor((root.Position - part.Position).Magnitude)
            local distText = "Distance: " .. dist .. " Studs"
            if data.Dist.Text ~= distText then
                data.Dist.Text = distText
            end

            local newSize = boulderTextSize(dist)
            if math.abs(newSize - data.LastSize) > 0.1 then
                data.HP.TextSize = newSize
                data.Name.TextSize = newSize
                data.Dist.TextSize = newSize
                local h = newSize + 2
                data.HP.Size = UDim2.new(1, 0, 0, h)
                data.Name.Size = UDim2.new(1, 0, 0, h)
                data.Dist.Size = UDim2.new(1, 0, 0, h)
                data.LastSize = newSize
            end

            local newPad = boulderPadSize(dist)
            if math.abs(newPad - data.LastPad) > 0.1 then
                data.Layout.Padding = UDim.new(0, newPad)
                data.LastPad = newPad
            end
        end

        local rarity = boulder:GetAttribute("Rarity") or "Common"
        if data.LastName ~= boulder.Name or data.LastRarity ~= rarity then
            local _, hex = bouldersOtherResolveColor(boulder.Name)
            data.Name.Text = '<font color="' .. hex .. '">' .. boulder.Name .. '</font> (' .. rarity .. ')'
            data.LastName = boulder.Name
            data.LastRarity = rarity
        end
    end
end

local function bouldersOtherStart()
    if bouldersOtherRunning then return end
    bouldersOtherRunning = true

    boulderScanFolder()

    -- Если валуны ещё не прогрузились (стриминг карты) — дособираем их сразу после включения
    task.spawn(function()
        for _ = 1, 12 do
            local md = Services.Workspace:FindFirstChild("MountainDecorations")
            local folder = md and md:FindFirstChild("Boulders")
            local count = folder and #folder:GetChildren() or 0
            if count > 0 then return end
            task.wait(0.25)
            boulderScanFolder()
        end
    end)

    table.insert(bouldersOtherConns, Services.RunService.Heartbeat:Connect(boulderUpdateAll))
    table.insert(bouldersOtherConns, Services.RunService.Stepped:Connect(function()
        boulderScanFolder()
    end))

    table.insert(bouldersOtherConns, Services.Workspace.ChildAdded:Connect(function(child)
        if child.Name == "MountainDecorations" then
            task.wait(0.5)
            boulderScanFolder()
        end
    end))

    local md = Services.Workspace:FindFirstChild("MountainDecorations")
    if md then
        table.insert(bouldersOtherConns, md.ChildAdded:Connect(function(child)
            if child.Name == "Boulders" then
                task.wait(0.2)
                boulderScanFolder()
            end
        end))
    end
end

local function bouldersOtherStop()
    bouldersOtherRunning = false
    for _, conn in ipairs(bouldersOtherConns) do
        if conn then pcall(function() conn:Disconnect() end) end
    end
    bouldersOtherConns = {}

    local all = {}
    for boulder in pairs(bouldersOtherCache) do
        all[#all + 1] = boulder
    end
    for _, boulder in ipairs(all) do
        boulderDestroyUI(boulder)
    end
    bouldersOtherCache = {}
end

-- ========== UI ==========
BouldersOtherBox:AddToggle("BoulderEspOtherToggle", {
    Text = "Boulder ESP",
    Default = false,
    Callback = function(value)
        if value then bouldersOtherStart() else bouldersOtherStop() end
    end,
})

BouldersOtherBox:AddDivider()

-- Пресеты типов убраны: типы появляются в списке автоматически по мере скана карты
-- (фоновый скан при включённом ESP, а также кнопки Select All / Clear Filter).

BouldersOtherBox:AddDropdown("BoulderEspOtherFilter", {
    Text = "Show only these",
    Values = {},
    Multi = true,
    AllowNull = true,
    Callback = bouldersOtherSetFilter,
})

BouldersOtherBox:AddButton("Select All", function()
    -- Подгружаем все типы валунов, реально присутствующие на сервере, прямо сейчас
    boulderScanFolder(true)

    local all = {}
    local list = {}
    for name in pairs(bouldersOtherKnownNames) do
        all[name] = true
        list[#list + 1] = name
    end
    table.sort(list)

    bouldersOtherFilter = all
    local dd = Library.Options.BoulderEspOtherFilter
    if dd then
        pcall(function() dd:SetValues(list) end)
        pcall(function() dd:SetValue(all) end)
    end
    bouldersOtherApplyFilter()
end)

BouldersOtherBox:AddButton("Clear Filter", function()
    boulderScanFolder(true)
    bouldersOtherFilter = nil
    local dd = Library.Options.BoulderEspOtherFilter
    if dd then
        pcall(function() dd:SetValue({}) end)
        pcall(function() dd:SetValue(nil) end)
    end
    bouldersOtherApplyFilter()
end)

-- ========== Cleanup ==========
_G.__BoulderEspOtherStop = bouldersOtherStop

do
    local _prev = getgenv().UniverseUnload
    local function _combined()
        if _G.__BoulderEspOtherStop then
            pcall(_G.__BoulderEspOtherStop)
            _G.__BoulderEspOtherStop = nil
        end
        if _prev and _prev ~= _combined then
            pcall(_prev)
        end
    end
    getgenv().UniverseUnload = _combined
    Library:OnUnload(_combined)
end

-- ====================================================================
-- НОВЫЕ ФУНКЦИИ (Other): FPS Boost, оповещения о редких кристаллах,
-- Auto Farm Boulders (Other)
-- helper: заворачивает стоп-функцию в цепочку выгрузки скрипта
-- ====================================================================
local function otherWrapUnload(stopFn)
    local prev = getgenv().UniverseUnload
    local function combined()
        pcall(stopFn)
        if prev and prev ~= combined then
            pcall(prev)
        end
    end
    getgenv().UniverseUnload = combined
    Library:OnUnload(combined)
    return combined
end

-- ====================================================================
-- FPS BOOST
-- ====================================================================
do
    local FpsBox = SettingsTab:AddRightGroupbox("FPS Boost", "gauge")

    local fpsBoostOn = false
    local savedLighting = nil
    local savedEffects = {}
    local effectConn = nil

    local function isEffect(obj)
        return obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
            or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles")
    end

    local function disableNewEffects(inst)
        if not fpsBoostOn then return end
        local list
        if inst:IsA("BasePart") or inst:IsA("Model") then
            list = inst:GetDescendants()
        else
            list = { inst }
        end
        for _, d in ipairs(list) do
            if isEffect(d) then
                savedEffects[d] = true
                pcall(function() d.Enabled = false end)
            end
        end
    end

    local function setFpsBoost(state)
        if state == fpsBoostOn then return end
        fpsBoostOn = state

        local lighting = Services.Lighting
        if state then
            if setfpscap then
                pcall(setfpscap, Library.Options.FpsBoostCap or 240)
            end
            savedLighting = {
                shadows = lighting.GlobalShadows,
                fog = lighting.FogEnd,
            }
            pcall(function() lighting.GlobalShadows = false end)
            pcall(function() lighting.FogEnd = 1e6 end)

            table.clear(savedEffects)
            for _, d in ipairs(Services.Workspace:GetDescendants()) do
                if isEffect(d) then
                    savedEffects[d] = true
                    pcall(function() d.Enabled = false end)
                end
            end

            effectConn = Services.Workspace.DescendantAdded:Connect(disableNewEffects)
            Library:Notify("FPS Boost ON", 3)
        else
            if effectConn then
                effectConn:Disconnect()
                effectConn = nil
            end
            if savedLighting then
                pcall(function() lighting.GlobalShadows = savedLighting.shadows end)
                pcall(function() lighting.FogEnd = savedLighting.fog end)
                savedLighting = nil
            end
            for obj in pairs(savedEffects) do
                if obj and obj.Parent then
                    pcall(function() obj.Enabled = true end)
                end
            end
            table.clear(savedEffects)
            if setfpscap then pcall(setfpscap, 60) end
            Library:Notify("FPS Boost OFF", 3)
        end
    end

    FpsBox:AddDivider()
    FpsBox:AddLabel("FPS Boost (тени/туман/частицы)", true)
    FpsBox:AddSlider("FpsBoostCap", {
        Text = "FPS Cap",
        Default = 240,
        Min = 60,
        Max = 360,
        Rounding = 0,
        Compact = false,
        Callback = function(value)
            if fpsBoostOn and setfpscap then
                pcall(setfpscap, value)
            end
        end,
    })

    FpsBox:AddToggle("FpsBoost", {
        Text = "Enabled",
        Default = false,
        Callback = setFpsBoost,
    })

    otherWrapUnload(function()
        if fpsBoostOn then
            setFpsBoost(false)
        end
    end)
end

