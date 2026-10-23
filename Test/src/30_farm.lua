-- ============================================================
-- MaM :: 30_farm.lua
-- FARM — промпты/авто-сбор кристаллов, бэкпак, Auto Farm Crystal
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
local ESP = E.ESP
local PLAYER = E.PLAYER
local PACE = E.PACE
local TP = E.TP
local PICK = E.PICK
local COLORS = E.COLORS
local TIER_NAMES = E.TIER_NAMES
local LUCK = E.LUCK
local MUTATION_LUCK = E.MUTATION_LUCK
local WATCHED_ATTRIBUTES = E.WATCHED_ATTRIBUTES
local SUFFIXES = E.SUFFIXES
local PARSE_MULTIPLIERS = E.PARSE_MULTIPLIERS
local CONTAINER_NAMES = E.CONTAINER_NAMES
local Library = E.Library
local SaveManager = E.SaveManager
local ThemeManager = E.ThemeManager
local Window = E.Window
local Tabs = E.Tabs
local SettingsTab = E.SettingsTab
local EspHolder = E.EspHolder
local reportError = E.reportError
local formatShort = E.formatShort
local formatWeight = E.formatWeight
local formatDistance = E.formatDistance
local formatLuck = E.formatLuck
local parseValue = E.parseValue
local bindCharacter = E.bindCharacter
local getRoot = E.getRoot
local getAttr = E.getAttr
local crystalValue = E.crystalValue
local crystalWeight = E.crystalWeight
local crystalTier = E.crystalTier
local crystalRarity = E.crystalRarity
local crystalName = E.crystalName
local crystalColor = E.crystalColor
local mutationLuck = E.mutationLuck
local combinedLuckMult = E.combinedLuckMult
local computeLuck = E.computeLuck
local luckLabel = E.luckLabel
local luckLabelText = E.luckLabelText
local crystalLuck = E.crystalLuck
local meetsFilter = E.meetsFilter
local ownsGamepass = E.ownsGamepass
local realStat = E.realStat
local hasActiveRune = E.hasActiveRune
local looksLikeCrystal = E.looksLikeCrystal
local backpackCapacity = E.backpackCapacity
local backpackWeight = E.backpackWeight
local backpackFree = E.backpackFree
local isCrystal = E.isCrystal
local rebuildContainers = E.rebuildContainers
local eachContainer = E.eachContainer
local requestStream = E.requestStream
local applyPivot = E.applyPivot
local findClearGoal = E.findClearGoal
local finishTeleport = E.finishTeleport
local teleportTo = E.teleportTo
local schedule = E.schedule

local function crystalPrompt(inst)
    local cached = Storage.promptCache[inst]
    if cached and cached.Parent then
        return cached
    end

    local ok, prompt = pcall(inst.FindFirstChildOfClass, inst, "ProximityPrompt")
    if not (ok and prompt) then
        ok, prompt = pcall(inst.FindFirstChildWhichIsA, inst, "ProximityPrompt", true)
    end

    if ok and prompt then
        Storage.promptCache[inst] = prompt
        return prompt
    end

    Storage.promptCache[inst] = nil
    return nil
end

local function surfaceDistance(part, origin)
    local ok, distance = pcall(function()
        local point = part.CFrame:PointToObjectSpace(origin)
        local half = part.Size * 0.5
        local clamped = Vector3.new(
            math.clamp(point.X, -half.X, half.X),
            math.clamp(point.Y, -half.Y, half.Y),
            math.clamp(point.Z, -half.Z, half.Z)
        )
        return (point - clamped).Magnitude
    end)

    if ok and distance then
        return distance
    end

    return (part.Position - origin).Magnitude
end

local function firePrompt(prompt)
    if not Storage.promptRestores[prompt] then
        Storage.promptRestores[prompt] = {
            hold = prompt.HoldDuration,
            sight = prompt.RequiresLineOfSight,
            enabled = prompt.Enabled,
            range = prompt.MaxActivationDistance,
        }
    end

    pcall(function()
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        prompt.Enabled = true
        prompt.MaxActivationDistance = 1000
    end)

    local fired = false

    if typeof(fireproximityprompt) == "function" then
        fired = pcall(fireproximityprompt, prompt, 1)
        if not fired then
            fired = pcall(fireproximityprompt, prompt)
        end
    end

    if not fired then
        fired = pcall(function()
            prompt:InputHoldBegin()
            prompt:InputHoldEnd()
        end)
    end

    schedule(PICK.restore, function()
        local saved = Storage.promptRestores[prompt]
        if not saved then
            return
        end

        Storage.promptRestores[prompt] = nil

        if prompt.Parent then
            prompt.HoldDuration = saved.hold
            prompt.RequiresLineOfSight = saved.sight
            prompt.Enabled = saved.enabled
            prompt.MaxActivationDistance = saved.range
        end
    end)

    return fired
end

local pickupParams = OverlapParams.new()
pickupParams.FilterType = Enum.RaycastFilterType.Exclude

pcall(function()
    pickupParams.MaxParts = 300
    pickupParams.RespectCanCollide = false
end)

local pickupFound = {}
local pickupSeen = {}

local function pickupCandidates(free, origin, filterFunc)
    local found = pickupFound
    local seen = pickupSeen
    table.clear(found)
    table.clear(seen)
    local now = os.clock()

    local function consider(child)
        if not child or seen[child] then
            return
        end
        seen[child] = true

        if not child.Parent or not isCrystal(child) or getAttr(child, "Collected") == true then
            return
        end

        local claim = Storage.claimed[child]
        if claim and now - claim < PICK.retry then
            return
        end

        if filterFunc and not filterFunc(child) then
            return
        end


        local value = crystalValue(child)
        if not meetsFilter(child, value) then
            return
        end

        local weight = crystalWeight(child)
        if weight > free then
            return
        end

        local distance = surfaceDistance(child, origin)
        if distance > PICK.range then
            return
        end

        found[#found + 1] = {
            inst = child,
            prompt = crystalPrompt(child),
            value = value,
            weight = weight,
            distance = distance,
        }
    end

    pickupParams.FilterDescendantsInstances = { LocalPlayer.Character or LocalPlayer }

    local ok, hits = pcall(function()
        return Services.Workspace:GetPartBoundsInRadius(origin, PICK.range + PICK.pad, pickupParams)
    end)

    if ok and hits then
        for _, part in ipairs(hits) do
            consider(part)
        end
    end

    eachContainer(function(container)
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("BasePart") then
                consider(child)
            elseif child:IsA("Model") then
                for _, inner in ipairs(child:GetChildren()) do
                    consider(inner)
                end
            end
        end
    end)

    for inst in pairs(Storage.registry) do
        consider(inst)
    end

    table.sort(found, function(a, b)
        if a.value == b.value then
            return a.distance < b.distance
        end
        return a.value > b.value
    end)

    return found
end

local function grabCrystal(inst, prompt)
    local sent = false

    if Remotes.HoldComplete then
        sent = pcall(function()
            if Remotes.HoldComplete:IsA("RemoteEvent") then
                Remotes.HoldComplete:FireServer(inst)
            end
        end)
    end

    if not prompt then
        prompt = crystalPrompt(inst)
    end

    if prompt and prompt.Parent and firePrompt(prompt) then
        sent = true
    end

    if not sent and typeof(fireclickdetector) == "function" then
        local ok, detector = pcall(inst.FindFirstChildWhichIsA, inst, "ClickDetector", true)
        if ok and detector then
            sent = pcall(fireclickdetector, detector, 0)
        end
    end

    return sent
end

local function instantPromptPatch(prompt)
    if Storage.instantPatched[prompt] or Storage.promptRestores[prompt] then
        return
    end

    Storage.instantPatched[prompt] = {
        hold = prompt.HoldDuration,
        sight = prompt.RequiresLineOfSight,
        enabled = prompt.Enabled,
    }

    pcall(function()
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        prompt.Enabled = true
    end)
end

local function restoreInstantPrompts()
    for prompt, saved in pairs(Storage.instantPatched) do
        if prompt.Parent then
            pcall(function()
                prompt.HoldDuration = saved.hold
                prompt.RequiresLineOfSight = saved.sight
                prompt.Enabled = saved.enabled
            end)
        end
    end
    table.clear(Storage.instantPatched)
end

local function nearbyCrystalParts(origin, radius)
    pickupParams.FilterDescendantsInstances = { LocalPlayer.Character or LocalPlayer }
    local ok, hits = pcall(function()
        return Services.Workspace:GetPartBoundsInRadius(origin, radius, pickupParams)
    end)

    if ok and hits then
        return hits
    end
    return nil
end

local function refreshInstantPrompts()
    local root = getRoot()
    if not root then
        return
    end

    for prompt in pairs(Storage.instantPatched) do
        if not prompt.Parent then
            Storage.instantPatched[prompt] = nil
        end
    end

    local hits = nearbyCrystalParts(root.Position, PICK.instantRadius)
    if not hits then
        return
    end

    for _, part in ipairs(hits) do
        if isCrystal(part) and getAttr(part, "Collected") ~= true then
            local prompt = crystalPrompt(part)
            if prompt then
                instantPromptPatch(prompt)
            end
        end
    end
end

local function setInstantPrompt(value)
    State.instantPromptActive = value
    State.instantAccumulator = math.huge

    if not value then
        restoreInstantPrompts()
    end
end

local function instantGrab()
    if not State.instantPromptActive then
        return
    end

    local root = getRoot()
    if not root then
        return
    end

    local hits = nearbyCrystalParts(root.Position, PICK.range + PICK.pad)
    if not hits then
        return
    end

    local best, bestPrompt, bestDistance

    for _, part in ipairs(hits) do
        if part.Parent and isCrystal(part) and getAttr(part, "Collected") ~= true then
            local distance = surfaceDistance(part, root.Position)
            if distance <= PICK.range and (not best or distance < bestDistance) then
                best = part
                bestPrompt = crystalPrompt(part)
                bestDistance = distance
            end
        end
    end

    if not best then
        return
    end

    if bestPrompt then
        instantPromptPatch(bestPrompt)
    end

    if grabCrystal(best, bestPrompt) then
        Storage.claimed[best] = os.clock()
    end
end

local function pickupStep(filterFunc)
    local now = os.clock()
    if now - State.lastPickup < PICK.cooldown then
        return
    end

    local root = getRoot()
    if not root then
        return
    end

    local free = backpackFree()
    if free <= 0 then
        if now - State.lastBagWarn >= 8 then
            State.lastBagWarn = now
            Library:Notify("Backpack full", 2)
        end
        return
    end

    for inst, stamp in pairs(Storage.claimed) do
        if now - stamp >= PICK.forget or not inst.Parent then
            Storage.claimed[inst] = nil
        end
    end

    local candidatesList = pickupCandidates(free, root.Position, filterFunc)
    if #candidatesList == 0 then
        requestStream(root.Position)
        return
    end

    local budget = free
    local grabs = 0

    for _, entry in ipairs(candidatesList) do
        if grabs >= PICK.burst then
            break
        end

        if entry.weight <= budget then
            Storage.claimed[entry.inst] = now
            if grabCrystal(entry.inst, entry.prompt) then
                budget -= entry.weight
                grabs += 1
            end
        end
    end

    if grabs > 0 then
        State.lastPickup = now
    end
end

local BackpackLabel

local function updateBackpackLabel()
    if not BackpackLabel then
        return
    end

    local capacity = backpackCapacity()
    local used = backpackWeight()

    if capacity == math.huge then
        BackpackLabel:SetText(string.format("Bag %.1f / \u{221E} kg", used))
        return
    end

    local free = math.max(0, capacity - used)
    BackpackLabel:SetText(string.format("Bag %.1f / %.1f kg\nFree %.1f kg", used, capacity, free))
end

do
    local function install()
        local PickupBox = Tabs.farming:AddLeftGroupbox("Pickup", "pickaxe")

        PickupBox:AddToggle("AutoPickup", {
            Text = "Auto Pickup",
            Default = false,
            Callback = function(value)
                State.autoPickupActive = value
            end,
        })

        PickupBox:AddToggle("InstantPrompt", {
            Text = "Instant Prompt",
            Default = false,
            Callback = setInstantPrompt,
        })

        PickupBox:AddToggle("AutoRunePickup", {
            Text = "Auto Rune Pickup",
            Default = false,
            Callback = Mountain.setAutoGrab,
        })

        PickupBox:AddDivider()
        BackpackLabel = PickupBox:AddLabel("Bag 0.0 / 0.0 kg", true)
    end

    install()
end


local Money = {}

do
    local function install()
        local SCAN_SPOTS = {
            CFrame.new(-12.7105675, 459.090942, 818.847412, 0.993408799, -0.00500036497, -0.11451605, 0.000644713698, 0.999275982, -0.0380407833, 0.114623353, 0.0377162211, 0.992692769),
            CFrame.new(13.0506754, 318.450409, -488.078888, -0.99998939, 0.000884758658, -0.00452193478, -0.000498382491, 0.954864502, 0.297041386, 0.00458064489, 0.297040492, -0.954853892),
            CFrame.new(74.3923645, 610.789368, 210.838226, -0.94896102, -0.27110818, 0.161162555, 2.26557495e-06, 0.51098305, 0.859590769, -0.315393418, 0.815718472, -0.484902382),
        }

        local SCAN_HOLD = 1.4
        local PEAK_GAP = 8
        local PEAK_STEP = 48
        local PEAK_RINGS = 12
        local COLUMN_STEP = 8
        local RING_MAX = 6
        local RAY_TOP = 120
        local RAY_DROP = 60
        local ZONE_PAD = 12
        local SURFACE_GAP = 0.15
        local COLUMN_DRY = 25
        local DIG_BURST = 7
        local DIG_SINK = 1.2
        local DIG_LIFT = 6
        local EQUIP_STEP = 0.5
        local SELL_MARK = Config.AutoSellThreshold
        local SELL_WAIT = 7
        local DIG_REACH = 12
        local DIG_REFRESH = 5
        local COLLECT_RANGE = 32000
        local COLLECT_LIFT = 5
        local COLLECT_GAP = 0.15
        local GRAB_GAP = 0.05
        local MAX_LOOT_TIME = 4.0

        local OFFSETS = { Vector2.new(0, 0) }
        local PEAK_OFFSETS = { Vector2.new(0, 0) }

        for ring = 1, RING_MAX do
            local slices = ring * 6
            for slice = 0, slices - 1 do
                local angle = slice / slices * math.pi * 2
                local reach = ring * COLUMN_STEP
                OFFSETS[#OFFSETS + 1] = Vector2.new(math.cos(angle) * reach, math.sin(angle) * reach)
            end
        end

        for ring = 1, PEAK_RINGS do
            local slices = ring * 3
            for slice = 0, slices - 1 do
                local angle = slice / slices * math.pi * 2
                local reach = ring * PEAK_STEP
                PEAK_OFFSETS[#PEAK_OFFSETS + 1] = Vector2.new(math.cos(angle) * reach, math.sin(angle) * reach)
            end
        end

        local surfaceParams = RaycastParams.new()
        surfaceParams.FilterType = Enum.RaycastFilterType.Include
        surfaceParams.FilterDescendantsInstances = { Services.Workspace.Terrain }
        surfaceParams.IgnoreWater = true

        local digParams = RaycastParams.new()
        digParams.FilterType = Enum.RaycastFilterType.Include
        digParams.IgnoreWater = true

        local digClock = 0

        local function digFilter(now)
            if digClock > 0 and now - digClock < DIG_REFRESH then
                return
            end
            digClock = now

            local list = { Services.Workspace.Terrain }
            local decorations = Services.Workspace:FindFirstChild("MountainDecorations")
            local boulders = decorations and decorations:FindFirstChild("Boulders")
            if boulders then
                list[#list + 1] = boulders
            end

            local test = Services.Workspace:FindFirstChild("BoulderTest")
            if test then
                list[#list + 1] = test
            end

            digParams.FilterDescendantsInstances = list
        end

        local function pickReach(tool)
            local override = tool and tonumber(getAttr(tool, "OverrideMaxReach"))
            return (override or DIG_REACH) + 3
        end

        local function aimPoint(origin, spot, reach, now)
            digFilter(now)
            local goals = {
                spot,
                spot - Vector3.new(0, 2, 0),
                origin - Vector3.new(0, reach, 0),
            }

            for _, goal in ipairs(goals) do
                local delta = goal - origin
                local distance = delta.Magnitude
                if distance > 0.05 then
                    local span = math.min(distance + 4, reach)
                    local hit = Services.Workspace:Raycast(origin, delta.Unit * span, digParams)
                    if hit then
                        return hit.Position
                    end
                end
            end

            local delta = spot - origin
            if delta.Magnitude <= reach then
                return spot
            end
            return origin + delta.Unit * reach
        end

        local active = false
        local autoSell = false
        local focusLuck = false
        local minLuckPoints = 4
        local autoPlantLuck = false
        local plantClock = 0
        local heldPick
        local loot
        local lootClock = 0
        local grabClock = 0
        local lootHp
        local lootMax
        local lootStartTime = 0
        local lootLastHpChange = 0
        local lootHpMark
        local blacklistedLoot = {}
        local blacklistedColumns = {}
        local target
        local columnY
        local columnDry = 0
        local columnSwings = 0
        local surfaceClock = 0
        local peakClock = 0
        local scanIndex = 0
        local scanUntil = 0
        local loaded = false
        local swingClock = 0
        local equipClock = 0
        local sellPhase = "idle"
        local sellReturnCFrame
        local sellPhaseClock = 0
        local plantPhase = "idle"
        local plantPhaseClock = 0
        local plantReturnCFrame
        local plantTools = {}
        local plantIndex = 1
        local plantPlotPos
        local plantGroundPos
        local lootBlocked = false
        local statusText = "Idle"

        local function toggleValue(name)
            local store = Library and Library.Toggles
            local entry = store and store[name]
            if entry and type(entry.Value) == "boolean" then
                return entry.Value
            end
            return false
        end

        local function getSellCFrame()
            local things = Services.Workspace:FindFirstChild("Things")
            local prox = things and things:FindFirstChild("SellProx")
            if prox and prox:IsA("BasePart") then
                return CFrame.new(prox.Position + Vector3.new(0, 3, 0), prox.Position)
            end
            local model = things and things:FindFirstChild("SellModel")
            local part = model and model:FindFirstChild("SellPart")
            if part and part:IsA("BasePart") then
                return CFrame.new(part.Position + Vector3.new(0, 3, 0), part.Position)
            end
            return CFrame.new(-45.85, 32, 1066.58)
        end

        local function zoneBase()
            local base = Services.Workspace:GetAttribute("MountainBaseY")
            if typeof(base) == "number" then
                return base
            end
            return Config.MountainCenter.Y - 500
        end

        local function zonePeak()
            local peak = Services.Workspace:GetAttribute("MountainPeakY")
            if typeof(peak) == "number" then
                return peak
            end
            return Config.MountainCenter.Y + 600
        end

        local function zoneCenter()
            local spot = mountainSpot()
            if spot then
                return Vector2.new(spot.X, spot.Z)
            end
            return Vector2.new(Config.MountainCenter.X, Config.MountainCenter.Z)
        end

        local function insideZone(x, z)
            local center = zoneCenter()
            if not center then
                return false
            end
            return (Vector2.new(x, z) - center).Magnitude <= mountainSpan() + ZONE_PAD
        end

        local function surfaceAt(x, z)
            if not insideZone(x, z) then
                return nil
            end

            local base = zoneBase()
            local top = zonePeak() + RAY_TOP
            local hit = Services.Workspace:Raycast(
                Vector3.new(x, top, z),
                Vector3.new(0, -(top - base + RAY_DROP), 0),
                surfaceParams
            )

            if not hit or hit.Position.Y <= base + 1 then
                return nil
            end
            return hit.Position
        end

        local function farmOrigin(root)
            if insideZone(root.Position.X, root.Position.Z) then
                return root.Position
            end
            return mountainSpot() or root.Position
        end

        local function gridKey(x, z)
            return string.format("%d_%d", math.floor(x / 4), math.floor(z / 4))
        end

        local function highestColumn(origin, offsets)
            local now = os.clock()
            local best

            for _, offset in ipairs(offsets) do
                local posX = origin.X + offset.X
                local posZ = origin.Z + offset.Y
                local key = gridKey(posX, posZ)

                local expire = blacklistedColumns[key]
                if not expire or now > expire then
                    blacklistedColumns[key] = nil
                    local spot = surfaceAt(posX, posZ)
                    if spot and (not best or spot.Y > best.Y) then
                        best = spot
                    end
                end
            end

            return best
        end

        local function pickTarget(origin, now)
            local center = mountainSpot()
            if center and now - peakClock >= PEAK_GAP then
                peakClock = now
                local high = highestColumn(center, PEAK_OFFSETS)
                if high then
                    return high
                end
            end

            local spot = highestColumn(origin, OFFSETS)
            if spot then
                return spot
            end

            if center then
                peakClock = now
                return highestColumn(center, PEAK_OFFSETS)
            end

            return nil
        end

        local function holdAt(goal, aim)
            return Move.glide(goal, aim)
        end

        local function swing(spot)
            local event = Remotes.DigRequest
            if not event or not heldPick then
                return false
            end

            local name = heldPick.Name
            local root = getRoot()
            local aim = spot

            if root then
                aim = aimPoint(root.Position, spot, pickReach(heldPick), os.clock()) or spot
            end

            return pcall(function()
                for step = 0, DIG_BURST - 1 do
                    fireRemote(event, name, aim - Vector3.new(0, step * DIG_SINK, 0))
                end
            end)
        end

        local function bagRatio()
            local capacity = backpackCapacity()
            if capacity == math.huge or capacity <= 0 then
                return 0
            end
            return backpackWeight() / capacity
        end

        local function getPlayerPlot()
            local lpName = LocalPlayer.Name
            local slots = Services.Workspace:FindFirstChild("Things") and Services.Workspace.Things:FindFirstChild("Plots") and Services.Workspace.Things.Plots:FindFirstChild("Slots")
            if slots then
                local plot = slots:FindFirstChild(lpName)
                if plot then
                    return plot
                end
            end
            return nil
        end

        local function getPlotPlantPosition()
            local plot = getPlayerPlot()
            if not plot then
                return nil
            end
            local spawn = plot:FindFirstChild("Spawn")
            local region = plot:FindFirstChild("Region")
            if region and region:IsA("BasePart") and spawn and spawn:IsA("BasePart") then
                local corner = region.CFrame * CFrame.new(-region.Size.X/2 + 15, 0, -region.Size.Z/2 + 15)
                return Vector3.new(corner.Position.X, spawn.Position.Y - 1.5, corner.Position.Z)
            end
            if spawn and spawn:IsA("BasePart") then
                return spawn.Position - Vector3.new(30, 1.5, 30)
            end
            local ok, pivot = pcall(plot.GetPivot, plot)
            if ok and pivot then
                return pivot.Position
            end
            return nil
        end

        local function getLuckToolsInBackpack()
            local list = {}

            local function scan(container)
                if not container then return end
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("Tool") then
                        local isCryst = getAttr(child, "Tier") ~= nil or child:GetAttribute("MeshTemplate") ~= nil
                        if isCryst then
                            local luckPts = math.floor(crystalLuck(child) * 100 + 0.5)
                            if luckPts >= minLuckPoints then
                                list[#list + 1] = child
                            end
                        end
                    end
                end
            end

            scan(LocalPlayer:FindFirstChildOfClass("Backpack"))
            scan(LocalPlayer.Character)
            return list
        end

        -- Replaced with plantPhase state machine in step()

        local function findLoot(free, origin)
            local now = os.clock()
            local best, bestScore, bestDistance
            local blocked = false
            local seen = {}

            for inst, expire in pairs(blacklistedLoot) do
                if now > expire or not inst.Parent then
                    blacklistedLoot[inst] = nil
                end
            end

            local function consider(inst)
                if not inst or seen[inst] or blacklistedLoot[inst] then
                    return
                end
                seen[inst] = true

                if not inst.Parent or not isCrystal(inst) or getAttr(inst, "Collected") == true then
                    return
                end

                local score = 0
                if focusLuck then
                    local luckPts = math.floor(crystalLuck(inst) * 100 + 0.5)
                    if luckPts < minLuckPoints then
                        return
                    end
                    score = luckPts
                else
                    local value = crystalValue(inst)
                    if not meetsFilter(inst, value) then
                        return
                    end
                    score = value
                end

                local distance = (inst.Position - origin).Magnitude
                if distance > COLLECT_RANGE then
                    return
                end

                if crystalWeight(inst) > free then
                    blocked = true
                    return
                end

                local better = false
                if not best then
                    better = true
                elseif score > bestScore then
                    better = true
                elseif score == bestScore and distance < bestDistance then
                    better = true
                end

                if better then
                    best = inst
                    bestScore = score
                    bestDistance = distance
                end
            end

            eachContainer(function(container)
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("BasePart") then
                        consider(child)
                    elseif child:IsA("Model") then
                        for _, inner in ipairs(child:GetChildren()) do
                            if inner:IsA("BasePart") then
                                consider(inner)
                            end
                        end
                    end
                end
            end)

            for inst in pairs(Storage.registry) do
                consider(inst)
            end

            return best, blocked
        end

        local function stop()
            active = false
            target = nil
            columnY = nil
            loaded = false
            Move.glideStop()
            scanIndex = 0
            loot = nil
            lootHp = nil
            lootMax = nil
            lootBlocked = false
            lootStartTime = 0
            lootLastHpChange = 0
            lootHpMark = nil
            table.clear(blacklistedLoot)
            table.clear(blacklistedColumns)
            table.clear(blacklistedColumns)
            sellPhase = "idle"
            sellReturnCFrame = nil
            sellPhaseClock = 0
            plantPhase = "idle"
            plantPhaseClock = 0
            plantReturnCFrame = nil
            heldPick = nil
            statusText = "Idle"

            Move.setFly(toggleValue("Fly"))
            Move.setNoclip(toggleValue("Noclip"))
            Mountain.setAutoGrab(toggleValue("AutoRunePickup"))
        end

        local function crystalHealth(inst)
            if not inst then return nil end
            local hp = getAttr(inst, "MinedHP") or getAttr(inst, "Health") or getAttr(inst, "Hp") or getAttr(inst, "CurrentHealth")
            return tonumber(hp)
        end

        local function step(deltaTime)
            local root = getRoot()
            if not root then
                statusText = "Waiting for character"
                return
            end

            local now = os.clock()

            if plantPhase ~= "idle" then
                if plantPhase == "travel" then
                    statusText = "Traveling to plot..."
                    holdAt(plantPlotPos)
                    if (root.Position - plantPlotPos.Position).Magnitude < 10 or (now - plantPhaseClock > 12) then
                        plantPhase = "do_plant"
                        plantPhaseClock = now
                    end
                    return
                end

                if plantPhase == "do_plant" then
                    statusText = "Planting luck crystals..."
                    holdAt(plantPlotPos)
                    if now - plantPhaseClock >= 0.15 then
                        plantPhaseClock = now
                        if plantIndex <= #plantTools then
                            local tool = plantTools[plantIndex]
                            local col = (plantIndex - 1) % 6
                            local row = math.floor((plantIndex - 1) / 6)
                            local plantSpot = plantGroundPos + Vector3.new(col * 4 - 10, 0, row * 4 - 10)
                            pcall(function()
                                Remotes.PlotPlaceRequest:FireServer(tool.Name, plantSpot, 0, tool)
                            end)
                            plantIndex += 1
                        else
                            plantPhase = "return"
                            plantPhaseClock = now
                        end
                    end
                    return
                end

                if plantPhase == "return" then
                    statusText = "Returning to mountain..."
                    local destination = plantReturnCFrame or mountainSpot()
                    holdAt(destination)
                    if (root.Position - destination.Position).Magnitude < 12 or (now - plantPhaseClock > 12) then
                        plantPhase = "idle"
                        plantReturnCFrame = nil
                        target = nil
                        columnY = nil
                        surfaceClock = 0
                    end
                    return
                end
            end

            if autoPlantLuck and plantPhase == "idle" and now - plantClock >= 2.0 then
                plantClock = now
                local tools = getLuckToolsInBackpack()
                if #tools >= 5 then
                    local pos = getPlotPlantPosition()
                    if pos then
                        plantGroundPos = pos
                        plantPlotPos = CFrame.new(pos + Vector3.new(0, 8, 0), pos)
                        plantReturnCFrame = root.CFrame
                        plantTools = tools
                        plantIndex = 1
                        plantPhase = "travel"
                        plantPhaseClock = now
                        statusText = "Heading to plot..."
                        return
                    end
                end
            end

            if not loaded then
                if scanIndex == 0 then
                    scanIndex = 1
                    scanUntil = now + SCAN_HOLD
                end

                if scanIndex <= #SCAN_SPOTS then
                    holdAt(SCAN_SPOTS[scanIndex])
                    statusText = string.format("Loading terrain %d/%d", scanIndex, #SCAN_SPOTS)

                    if now >= scanUntil then
                        scanIndex += 1
                        scanUntil = now + SCAN_HOLD
                    end

                    return
                end

                loaded = true
                peakClock = 0
            end

            if sellPhase ~= "idle" then
                local sellCFrame = getSellCFrame()

                if sellPhase == "travel" then
                    statusText = "Traveling to sell station..."
                    holdAt(sellCFrame)

                    if (root.Position - sellCFrame.Position).Magnitude < 10 or (now - sellPhaseClock > 12) then
                        sellPhase = "do_sell"
                        sellPhaseClock = now
                    end
                    return
                end

                if sellPhase == "do_sell" then
                    statusText = "Selling crystals..."
                    holdAt(sellCFrame)

                    if now - sellPhaseClock >= 0.3 and now - sellPhaseClock < 0.6 then
                        unfavoriteAll()
                        fireRemote(Remotes.SellRequest, "all")

                        local things = Services.Workspace:FindFirstChild("Things")
                        local prox = things and things:FindFirstChild("SellProx")
                        local prompt = prox and prox:FindFirstChildOfClass("ProximityPrompt")
                        if prompt then
                            firePrompt(prompt)
                        end
                    end

                    if (now - sellPhaseClock >= 1.5) or (backpackWeight() <= 0) then
                        lootBlocked = false
                        sellPhase = "return"
                        sellPhaseClock = now
                    end
                    return
                end

                if sellPhase == "return" then
                    statusText = "Returning to mountain..."
                    local destination = sellReturnCFrame or mountainSpot()
                    holdAt(destination)

                    if (root.Position - destination.Position).Magnitude < 12 or (now - sellPhaseClock > 12) then
                        sellPhase = "idle"
                        sellReturnCFrame = nil
                        target = nil
                        columnY = nil
                        surfaceClock = 0
                    end
                    return
                end
            end

            if autoSell and sellPhase == "idle" and (bagRatio() >= SELL_MARK or lootBlocked) then
                sellReturnCFrame = root.CFrame
                sellPhase = "travel"
                sellPhaseClock = now
                statusText = "Heading to sell station..."
                return
            end

            if focusLuck then
                pickupStep(function(inst)
                    local luckPts = math.floor(crystalLuck(inst) * 100 + 0.5)
                    return luckPts >= minLuckPoints
                end)
            else
                pickupStep()
            end

            if heldPick == nil or heldPick.Parent ~= LocalPlayer.Character then
                equipClock = 0
                heldPick = Farm.equipPick()
            else
                equipClock += deltaTime
                if equipClock >= EQUIP_STEP then
                    equipClock = 0
                    heldPick = Farm.equipPick() or heldPick
                end
            end

            if not heldPick then
                statusText = "Equipping pickaxe..."
                return
            end

            swingClock += deltaTime
            local swingNeed = math.max(0.02, Farm.swingGap(heldPick) * 0.4)
            local canSwing = swingClock >= swingNeed
            local free = backpackFree()

            if loot then
                local parented = loot.Parent ~= nil
                local collected = (getAttr(loot, "Collected") == true)
                local currentHp = crystalHealth(loot)

                if currentHp and currentHp > 0 then
                    if lootHpMark == nil or currentHp < (lootHpMark - 0.001) then
                        lootHpMark = currentHp
                        lootLastHpChange = now
                    end
                end

                local hpStuck = (now - lootLastHpChange > 12.0) and (now - lootStartTime > 12.0)
                local maxTimeout = (now - lootStartTime > 40.0)
                local cantFit = (crystalWeight(loot) > free)

                if not parented or collected or hpStuck or maxTimeout or cantFit then
                    if (hpStuck or maxTimeout) and loot and parented then
                        blacklistedLoot[loot] = now + 20
                    end
                    loot = nil
                    lootHp = nil
                    lootMax = nil
                    lootHpMark = nil
                end
            end

            if loot then
                local hp = crystalHealth(loot)
                if hp and (lootMax == nil or hp > lootMax) then
                    lootMax = hp
                end
                lootHp = hp
            end

            if not loot and now - lootClock >= COLLECT_GAP then
                lootClock = now
                loot, lootBlocked = findLoot(free, root.Position)
                if loot then
                    lootStartTime = now
                    lootLastHpChange = now
                    lootHp = crystalHealth(loot)
                    lootMax = lootHp
                    lootHpMark = lootHp
                end
            end

            if loot and loot.Parent then
                local spot = loot.Position
                holdAt(CFrame.new(spot + Vector3.new(0, COLLECT_LIFT, 0), spot), spot)
                requestStream(spot)

                if canSwing then
                    swingClock -= swingNeed
                    swing(spot)
                end

                if now - grabClock >= GRAB_GAP then
                    grabClock = now
                    grabCrystal(loot, crystalPrompt(loot))
                end

                if lootHp and lootHp > 0 then
                    local ratio = 0
                    if lootMax and lootMax > 0 then
                        ratio = math.clamp(1 - lootHp / lootMax, 0, 1)
                    end
                    statusText = string.format("Mining %s (%s) %d%%", crystalName(loot), formatShort(crystalValue(loot), "$"), math.floor(ratio * 100))
                else
                    statusText = string.format("Collecting %s (%s)...", crystalName(loot), formatShort(crystalValue(loot), "$"))
                end

                return
            end

            local origin = farmOrigin(root)

            if target and now - surfaceClock >= SURFACE_GAP then
                surfaceClock = now
                local spot = surfaceAt(target.X, target.Z)

                if not spot then
                    target = nil
                    columnY = nil
                    columnDry = 0
                    columnSwings = 0
                else
                    if not columnY or spot.Y < columnY - 0.05 then
                        columnDry = 0
                    else
                        columnDry += columnSwings
                    end

                    columnSwings = 0
                    columnY = spot.Y
                    target = spot

                    if columnDry >= COLUMN_DRY then
                        blacklistedColumns[gridKey(target.X, target.Z)] = now + 20
                        target = nil
                        columnY = nil
                        columnDry = 0
                    end
                end
            end

            if not target then
                local spot = pickTarget(origin, now)
                if not spot then
                    spot = surfaceAt(origin.X, origin.Z)
                end

                if not spot then
                    requestStream(origin)
                    if canSwing then
                        swingClock -= swingNeed
                        swing(root.Position - Vector3.new(0, DIG_REACH * 0.5, 0))
                    end
                    statusText = "Loading terrain"
                    return
                end

                target = spot
                columnY = spot.Y
                columnDry = 0
                columnSwings = 0
                surfaceClock = now
            end

            holdAt(CFrame.new(target + Vector3.new(0, DIG_LIFT, 0), target), target)

            if canSwing then
                swingClock -= swingNeed
                columnSwings += 1
                swing(target)
            end

            statusText = string.format("Mining surface at %dm", math.floor(target.Y))
        end

        local function setActive(value)
            if not value then
                stop()
                return
            end

            active = true
            target = nil
            columnY = nil
            columnDry = 0
            columnSwings = 0
            surfaceClock = 0
            peakClock = 0
            scanIndex = 0
            scanUntil = 0
            loaded = false
            loot = nil
            lootClock = 0
            lootHp = nil
            lootMax = nil
            lootBlocked = false
            lootStartTime = 0
            table.clear(blacklistedLoot)
            table.clear(blacklistedColumns)
            swingClock = 0
            equipClock = 0
            sellSpot = nil
            sellUntil = 0
            heldPick = nil
            statusText = "Starting"

            Move.setFly(false)
            Move.setNoclip(true)
            Mountain.setAutoGrab(true)
        end

        local MoneyBox = Tabs.farming:AddRightGroupbox("Auto Farm Crystal", "gem")
        MoneyBox:AddLabel("Loads the mountain and digs crystals by cash value or luck points", true)
        MoneyBox:AddDivider()

        MoneyBox:AddToggle("AutoFarmMoney", {
            Text = "Auto Farm",
            Default = false,
            Callback = setActive,
        })

        MoneyBox:AddToggle("FocusLuckCrystals", {
            Text = "Focus Luck Crystals",
            Default = false,
            Callback = function(value)
                focusLuck = value
                loot = nil
            end,
        })

        MoneyBox:AddSlider("MinLuckFilterPoints", {
            Text = "Min Luck Points",
            Default = 10,
            Min = 1,
            Max = 1000,
            Rounding = 0,
            Compact = false,
            Callback = function(val)
                minLuckPoints = val
                Config.MinLuckBoost = val
                loot = nil
            end,
        })

        MoneyBox:AddDivider()

        MoneyBox:AddToggle("AutoPlantLuckCrystals", {
            Text = "Auto Plant Luck Crystals On Plot",
            Default = false,
            Callback = function(value)
                autoPlantLuck = value
            end,
        })

        MoneyBox:AddToggle("MoneyAutoSell", {
            Text = "Auto Sell At 50%",
            Default = false,
            Callback = function(value)
                autoSell = value
            end,
        })

        MoneyBox:AddDivider()

        local StatusLabel = MoneyBox:AddLabel("Idle", true)
        local labelClock = 0

        Connections.moneyConn = Services.RunService.Heartbeat:Connect(function(deltaTime)
            if active then
                local ok, err = pcall(step, deltaTime)
                if not ok then
                    reportError("moneyFarm", err)
                end
            end

            labelClock += deltaTime
            if labelClock >= 0.25 then
                labelClock = 0
                StatusLabel:SetText(statusText)
            end
        end)

        Money.stop = stop
    end

    install()
end


-- === Экспорт модуля ===
E.Money = Money
E.restoreInstantPrompts = restoreInstantPrompts

-- === Регистрация тик-функций для центрального планировщика ===
E.PickupTick = pickupStep
E.InstantTick = refreshInstantPrompts
E.InstantGrab = instantGrab
E.SlowTick = updateBackpackLabel
