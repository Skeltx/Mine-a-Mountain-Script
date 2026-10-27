-- ============================================================
-- MaM :: 60_movement.lua
-- MOVEMENT — Speed/Noclip/InfJump/Fly + вкладка Movement
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
local EventsTab = E.EventsTab
local OtherTab = E.OtherTab
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

local function enforceSpeed(humanoid)
    if not humanoid or humanoid.WalkSpeed == PACE.boost then
        return
    end
    pcall(function()
        humanoid.WalkSpeed = PACE.boost
    end)
end

local function watchSpeed(humanoid)
    if State.speedHooked == humanoid then
        return
    end

    if Connections.speedConn then
        Connections.speedConn:Disconnect()
        Connections.speedConn = nil
    end

    State.speedHooked = humanoid
    if not humanoid then
        return
    end

    local ok, connection = pcall(function()
        return humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if State.speedActive then
                enforceSpeed(humanoid)
            end
        end)
    end)

    if ok then
        Connections.speedConn = connection
    end
end

local function setSpeedBoost(value)
    State.speedActive = value

    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if value then
        watchSpeed(humanoid)
        enforceSpeed(humanoid)
        return
    end

    watchSpeed(nil)

    if humanoid then
        pcall(function()
            humanoid.WalkSpeed = PACE.normal
        end)
    end
end

local Move = {}

do
    local function install()
        local FLY_KEYS = {
            { key = Enum.KeyCode.W, axis = "look", sign = 1 },
            { key = Enum.KeyCode.S, axis = "look", sign = -1 },
            { key = Enum.KeyCode.D, axis = "right", sign = 1 },
            { key = Enum.KeyCode.A, axis = "right", sign = -1 },
            { key = Enum.KeyCode.Space, axis = "up", sign = 1 },
            { key = Enum.KeyCode.LeftControl, axis = "up", sign = -1 },
        }

        local flyActive = false
        local noclipActive = false
        local jumpActive = false
        local flySpeed = Config.FlySpeed

        local velocity
        local gyro
        local flyConn
        local noclipConn
        local jumpConn
        local collisions = {}

        local function humanoidOf()
            local character = LocalPlayer.Character
            return character and character:FindFirstChildOfClass("Humanoid")
        end

        local function dropMovers()
            if velocity then
                pcall(function()
                    velocity:Destroy()
                end)
                velocity = nil
            end
            if gyro then
                pcall(function()
                    gyro:Destroy()
                end)
                gyro = nil
            end
        end

        local function attach(root)
            dropMovers()
            local ok = pcall(function()
                local body = Instance.new("BodyVelocity")
                body.Name = "UniverseFlyVelocity"
                body.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                body.P = 9e4
                body.Velocity = Vector3.zero
                body.Parent = root
                velocity = body

                local spin = Instance.new("BodyGyro")
                spin.Name = "UniverseFlyGyro"
                spin.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
                spin.P = 9e4
                spin.D = 500
                spin.CFrame = root.CFrame
                spin.Parent = root
                gyro = spin
            end)

            if not ok then
                dropMovers()
            end

            return ok
        end

        local function flyStep()
            if State.tpState then
                return
            end

            local root = getRoot()
            if not root then
                return
            end

            if not velocity or velocity.Parent ~= root then
                if not attach(root) then
                    return
                end
            end

            local camera = Services.Workspace.CurrentCamera
            if not camera then
                return
            end

            local humanoid = humanoidOf()
            if humanoid and not humanoid.PlatformStand then
                humanoid.PlatformStand = true
            end

            local frame = camera.CFrame
            local direction = Vector3.zero

            if not Services.UserInputService:GetFocusedTextBox() then
                for _, entry in ipairs(FLY_KEYS) do
                    if Services.UserInputService:IsKeyDown(entry.key) then
                        if entry.axis == "look" then
                            direction += frame.LookVector * entry.sign
                        elseif entry.axis == "right" then
                            direction += frame.RightVector * entry.sign
                        else
                            direction += Vector3.yAxis * entry.sign
                        end
                    end
                end
            end

            if direction.Magnitude > 0.1 then
                velocity.Velocity = direction.Unit * flySpeed
            else
                velocity.Velocity = Vector3.zero
            end

            local flat = Vector3.new(frame.LookVector.X, 0, frame.LookVector.Z)
            if flat.Magnitude > 0.05 then
                gyro.CFrame = CFrame.new(root.Position, root.Position + flat)
            end
        end

        local function noclipStep()
            local character = LocalPlayer.Character
            if not character then
                return
            end

            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    if collisions[part] == nil then
                        collisions[part] = true
                    end
                    part.CanCollide = false
                end
            end
        end

        function Move.setFly(value)
            flyActive = value

            if value then
                local root = getRoot()
                if root then
                    attach(root)
                end

                if not flyConn then
                    flyConn = Services.RunService.Heartbeat:Connect(function()
                        if not flyActive then
                            return
                        end
                        local ok, err = pcall(flyStep)
                        if not ok then
                            reportError("fly", err)
                        end
                    end)
                end
                return
            end

            if flyConn then
                flyConn:Disconnect()
                flyConn = nil
            end

            dropMovers()

            local humanoid = humanoidOf()
            if humanoid then
                pcall(function()
                    humanoid.PlatformStand = false
                    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end)
            end
        end

        function Move.setFlySpeed(value)
            flySpeed = math.clamp(value, 10, 500)
        end

        function Move.setNoclip(value)
            noclipActive = value

            if value then
                if not noclipConn then
                    noclipConn = Services.RunService.Heartbeat:Connect(function()
                        if not noclipActive then
                            return
                        end
                        local ok, err = pcall(noclipStep)
                        if not ok then
                            reportError("noclip", err)
                        end
                    end)
                end
                return
            end

            if noclipConn then
                noclipConn:Disconnect()
                noclipConn = nil
            end

            for part, state in pairs(collisions) do
                if part.Parent then
                    pcall(function()
                        part.CanCollide = state
                    end)
                end
            end

            table.clear(collisions)
        end

        function Move.setInfJump(value)
            jumpActive = value

            if value then
                if not jumpConn then
                    jumpConn = Services.UserInputService.JumpRequest:Connect(function()
                        if not jumpActive then
                            return
                        end
                        local humanoid = humanoidOf()
                        if humanoid then
                            pcall(function()
                                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                            end)
                        end
                    end)
                end
                return
            end

            if jumpConn then
                jumpConn:Disconnect()
                jumpConn = nil
            end
        end

        function Move.shutdown()
            Move.setFly(false)
            Move.setNoclip(false)
            Move.setInfJump(false)
            Move.glideStop()
        end
    end

    install()
end

do
    local function install()
        local GLIDE_SPEED = 350
        local AIM_RATE = 9
        local SNAP_GAP = 0.35
        local RESPONSE = 200
        local STREAM_GAP = 0.5
        local HOLD_FORCE = 1e7
        local HOLD_TORQUE = 1e7

        local attachment
        local mover
        local aligner
        local cursor
        local facing
        local goalFrame
        local aimSpot
        local streamClock = 0
        local glideConn
        local running = false

        local function humanoidOf()
            local character = LocalPlayer.Character
            return character and character:FindFirstChildOfClass("Humanoid")
        end

        local function detach()
            if mover then
                pcall(function()
                    mover:Destroy()
                end)
                mover = nil
            end
            if aligner then
                pcall(function()
                    aligner:Destroy()
                end)
                aligner = nil
            end
            if attachment then
                pcall(function()
                    attachment:Destroy()
                end)
                attachment = nil
            end
        end

        local function attach(root)
            detach()
            local ok = pcall(function()
                local point = Instance.new("Attachment")
                point.Name = "UniverseGlidePoint"
                point.Parent = root

                local position = Instance.new("AlignPosition")
                position.Name = "UniverseGlidePosition"
                position.Mode = Enum.PositionAlignmentMode.OneAttachment
                position.Attachment0 = point
                position.RigidityEnabled = false
                position.ApplyAtCenterOfMass = true
                position.ReactionForceEnabled = false
                position.MaxForce = HOLD_FORCE
                position.MaxVelocity = math.huge
                position.Responsiveness = RESPONSE
                position.Position = root.Position
                position.Parent = root

                local orientation = Instance.new("AlignOrientation")
                orientation.Name = "UniverseGlideOrientation"
                orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
                orientation.Attachment0 = point
                orientation.RigidityEnabled = false
                orientation.ReactionTorqueEnabled = false
                orientation.MaxTorque = HOLD_TORQUE
                orientation.MaxAngularVelocity = math.huge
                orientation.Responsiveness = RESPONSE
                orientation.CFrame = root.CFrame.Rotation
                orientation.Parent = root

                attachment = point
                mover = position
                aligner = orientation
            end)

            if not ok then
                detach()
            end

            return ok
        end

        local function step(deltaTime)
            if not goalFrame then
                return
            end

            local root = getRoot()
            if not root then
                return
            end

            if not mover or mover.Parent ~= root or not aligner or aligner.Parent ~= root then
                if not attach(root) then
                    return
                end
                cursor = root.Position
                facing = root.CFrame.Rotation
            end

            local humanoid = humanoidOf()
            if humanoid and not humanoid.PlatformStand then
                pcall(function()
                    humanoid.PlatformStand = true
                end)
            end

            cursor = cursor or root.Position
            facing = facing or root.CFrame.Rotation

            local delta = goalFrame.Position - cursor
            local span = GLIDE_SPEED * deltaTime

            if delta.Magnitude <= math.max(span, SNAP_GAP) then
                cursor = goalFrame.Position
            else
                cursor += delta.Unit * span
            end

            streamClock += deltaTime
            if streamClock >= STREAM_GAP then
                streamClock = 0
                requestStream(goalFrame.Position)
            end

            local look = goalFrame.Rotation
            if aimSpot then
                local gap = aimSpot - cursor
                if gap.Magnitude > 0.1 then
                    look = CFrame.lookAt(cursor, aimSpot).Rotation
                end
            end

            facing = facing:Lerp(look, 1 - math.exp(-AIM_RATE * deltaTime))
            mover.Position = cursor
            aligner.CFrame = facing
        end

        function Move.glide(goal, aim)
            if typeof(goal) ~= "CFrame" then
                return false
            end

            goalFrame = goal
            aimSpot = typeof(aim) == "Vector3" and aim or nil

            if not running then
                running = true
                local root = getRoot()
                if root then
                    cursor = root.Position
                    facing = root.CFrame.Rotation
                    attach(root)
                end
            end

            if not glideConn then
                glideConn = Services.RunService.Heartbeat:Connect(function(deltaTime)
                    if not running then
                        return
                    end
                    local ok, err = pcall(step, deltaTime)
                    if not ok then
                        reportError("glide", err)
                    end
                end)
            end

            return true
        end

        function Move.glideStop()
            running = false
            goalFrame = nil
            aimSpot = nil
            cursor = nil
            facing = nil
            streamClock = 0

            if glideConn then
                glideConn:Disconnect()
                glideConn = nil
            end

            detach()

            local root = getRoot()
            if root then
                pcall(function()
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end)
            end

            local humanoid = humanoidOf()
            if humanoid then
                pcall(function()
                    humanoid.PlatformStand = false
                    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end)
            end
        end
    end

    install()
end


do
    local function install()
        local MoveBox = Tabs.movement:AddLeftGroupbox("Movement", "zap")

        MoveBox:AddToggle("SpeedBoost", {
            Text = "Speed Boost",
            Default = false,
            Callback = setSpeedBoost,
        })

        MoveBox:AddToggle("Noclip", {
            Text = "Noclip",
            Default = false,
            Callback = Move.setNoclip,
        })

        MoveBox:AddToggle("InfJump", {
            Text = "Inf Jump",
            Default = false,
            Callback = Move.setInfJump,
        })

        MoveBox:AddDivider()

        MoveBox:AddToggle("Fly", {
            Text = "Fly",
            Default = false,
            Callback = Move.setFly,
        })

        MoveBox:AddSlider("FlySpeed", {
            Text = "Fly Speed",
            Default = Config.FlySpeed,
            Min = 20,
            Max = 300,
            Rounding = 0,
            Compact = false,
            Callback = Move.setFlySpeed,
        })
    end

    install()
end



-- === Экспорт модуля ===
E.Move = Move
E.setSpeedBoost = setSpeedBoost

-- === Регистрация тик-функций для центрального планировщика ===
E.MovementTick = function()
    local body = LocalPlayer.Character
    local mover = body and body:FindFirstChildOfClass("Humanoid")
    if mover then
        watchSpeed(mover)
        enforceSpeed(mover)
    end
end
