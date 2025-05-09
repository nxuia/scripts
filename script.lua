--<< CONFIGURATION >>--

local Config = {
    Key = "8e2feffb-be9a-4c74-84f1-14ecfbc1520b",

    Helper = "",

    Disable3DRendering = false,
    RejoinOnKick = true,
    RedeemCodes = true,
    FPS_Cap = 60,

    WebSocketURL = "ws://127.0.0.1:8080"
}

--<< GAME LOAD >>--

if not game:IsLoaded() then
    game.Loaded:Wait()
end

--<< CONFIG CHECK >>--

local Config = Config

if not Config then
    warn("Configuration table is missing.")
    return
end

local RequiredConfigs = {
    Key = "string"
}

for requiredValue, requiredType in pairs(RequiredConfigs) do
    local configValue = Config[requiredValue]

    if not configValue or type(configValue) ~= requiredType then
        warn("Missing required config value: " .. requiredValue)
        return
    end
end

Config = {
    Key = Config.Key,

    Helper = Config.Helper,

    Disable3DRendering = Config.Disable3DRendering and true or false,
    RejoinOnKick = Config.RejoinOnKick and true or false,
    RedeemCodes = Config.RedeemCodes and true or false,
    FPS_Cap = Config.FPS_Cap or 30,

    WebSocketURL = Config.WebSocketURL or "wss://bgsi-2.onrender.com",
}

--<< PERFORM CLEANUP FUNCTION >>--

if getgenv().DisableScript then
    pcall(getgenv().DisableScript)
end

--<< SERVICES >>--

local Services = {
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    ContentProvider = game:GetService("ContentProvider"),
    TeleportService = game:GetService("TeleportService"),
    TweenService = game:GetService("TweenService"),
    VirtualUser = game:GetService("VirtualUser"),
    HttpService = game:GetService("HttpService"),
    StarterGui = game:GetService("StarterGui"),
    RunService = game:GetService("RunService"),
    Workspace = game:GetService("Workspace"),
    CoreGui = game:GetService("CoreGui"),
    Players = game:GetService("Players")
}

--<< VARIABLES >>--

local LocalPlayer = Services.Players.LocalPlayer
local Camera = Services.Workspace.CurrentCamera

if game.PlaceId ~= 85896571713843 then
    LocalPlayer:Kick("This script does not support the current game.")

    return
end

local LoadIntro = require(Services.ReplicatedStorage.Client.Gui.Animations.Intro)

LoadIntro.IsPlaying = false
LoadIntro.Play = function()
    return false
end

local Leaderstats = LocalPlayer:WaitForChild("leaderstats", 20)

if not Leaderstats then
    Services.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId)
    
    return
end

local StatsUtil = require(Services.ReplicatedStorage.Shared.Utils.Stats.StatsUtil)
local WorldUtil = require(Services.ReplicatedStorage.Shared.Utils.WorldUtil)

local LocalData = require(Services.ReplicatedStorage.Client.Framework.Services.LocalData)
local RemoteModule = require(Services.ReplicatedStorage.Shared.Framework.Network.Remote)
local MasteryData = require(Services.ReplicatedStorage.Shared.Data.Mastery)
local FlavorsData = require(Services.ReplicatedStorage.Shared.Data.Flavors)
local PrizesData = require(Services.ReplicatedStorage.Shared.Data.Prizes)
local CodesData = require(Services.ReplicatedStorage.Shared.Data.Codes)
local EggsData = require(Services.ReplicatedStorage.Shared.Data.Eggs)
local PetsData = require(Services.ReplicatedStorage.Shared.Data.Pets)
local GumData = require(Services.ReplicatedStorage.Shared.Data.Gum)

local WebSocketConnection = nil
local WebSocketFunctions = {}
local WebSocketActions = {}

local CommandFunctions = {}
local ComponentFunctions = {}
local Functions = {}

local Connections = {}
local Commands = {}
local UIComponents = {}

local Variables = {}; do
    Variables.Unloaded = false
    Variables.InAction = false

    Variables.ClientStatus = "Idle"
    Variables.IsConnected = false
    Variables.ReconnectAttempts = 0
    Variables.MaxReconnectAttempts = 999
    Variables.ReconnectDelay = 5

    Variables.CoinsFolder = nil
    Variables.EggsFolder = nil

    Variables.IsUpgrading = false
    Variables.IsClaiming = false
    Variables.IsHatching = false
    Variables.IsFarming = false
    Variables.IsSelling = false

    Variables.FarmingStrategy = "Maximize"

    Variables.TradeHistoryDuration = "1 Hour"
    Variables.AutoAcceptTrade = true
    Variables.Helper = Config.Helper

    Variables.CurrentPriority = 0

    Variables.NotFoundEggs = {}
    Variables.Tweens = {}
end

--<< COMMAND FUNCTIONS >>--

CommandFunctions = {}; do
    function CommandFunctions.GetCommand(name)
        local Lowered = tostring(name):lower()

        for _, command in pairs(Commands) do
            if command.Name:lower() == Lowered then
                return command
            end

            for _, alias in pairs(command.Aliases) do
                if alias:lower() == Lowered then
                    return command
                end
            end
        end
    end

    function CommandFunctions.AddCommand(values)
        local RequiredValues = {
            Name = "string",
            Callback = "function"
        }

        for valueName, valueType in pairs(RequiredValues) do
            local value = values[valueName]

            if not value or type(value) ~= valueType then
                return false, "Missing required value: " .. valueName
            end
        end

        if CommandFunctions.GetCommand(values.Name) then
            return false, "Command already exists: " .. values.Name
        end

        Commands[values.Name] = {
            Name = values.Name,
            Aliases = values.Aliases or {},
            Callback = values.Callback,
            Parameters = values.Parameters or {}
        }

        return true
    end

    function CommandFunctions.RemoveCommand(name)
        Commands[Command.Name] = nil
    end

    function CommandFunctions.ExecuteCommand(command, arguments)
        return pcall(command.Callback, arguments)
    end

    function CommandFunctions.FilterCommandMessage(message)
        local Arguments = message:split(" ")
        local CommandName = #Arguments > 0 and Arguments[1]
        local Command = CommandName and CommandFunctions.GetCommand(CommandName)

        table.remove(Arguments, 1)

        return Command, Arguments
    end

    function CommandFunctions.ConvertPlayerArgument(str, speaker, exclude, checks)
        local String = str and tostring(str)
        if not String then return end

        if String == "." or String:lower() == "me" then
            return LocalPlayer
        else
            return Functions.GetPlayer(String, {speaker, LocalPlayer})
        end
    end

    function CommandFunctions.HandleMessage(message)
        if not message then return end
        
        local Command, Arguments = CommandFunctions.FilterCommandMessage(message)

        if not Command then
            return false, "Invalid command."
        end

        if Command.Parameters then
            if #Arguments < #Command.Parameters then
                return false, "Missing required parameters: " .. table.concat(Command.Parameters, ", ")
            end
        end

        local Success, Response = CommandFunctions.ExecuteCommand(Command, Arguments)

        if not Success then
            warn(Command.Name .. " command failed to execute. Response: " .. tostring(Response))
        end
    end
end

--<< TOGGLE FUNCTIONS >>--

ComponentFunctions = {}; do
    function ComponentFunctions.GetComponent(name, tab)
        if not name or not tab then return end

        local Tab = UIComponents[tab]

        for _, Component in pairs(Tab or {}) do
            if Component.Name == name then
                return Component
            end
        end

        return nil
    end
    
    function ComponentFunctions.CreateToggle(values)
        local RequiredValues = {
            Name = "string",
            Tab = "string",
            Callback = "function"
        }

        for valueName, valueType in pairs(RequiredValues) do
            local value = values[valueName]

            if not value or type(value) ~= valueType then
                return false, "Missing required value: " .. valueName
            end
        end

        if ComponentFunctions.GetComponent(values.Name, values.Tab) then
            return false, "Toggle already exists: " .. values.Name
        end

        if not UIComponents[values.Tab] then
            UIComponents[values.Tab] = {}
        end

        table.insert(UIComponents[values.Tab], {
            Name = values.Name,
            Type = "toggle",
            Default = values.Default or false,
            Tab = values.Tab,
            Disabled = values.Disabled or false,
            IndexOrder = values.IndexOrder or 999,
            Value = values.Default or false,
            Callback = values.Callback
        })

        return true
    end

    function ComponentFunctions.CreateDropdown(values)
        local RequiredValues = {
            Name = "string",
            Tab = "string",
            Options = "table",
            Callback = "function"
        }

        for valueName, valueType in pairs(RequiredValues) do
            local value = values[valueName]

            if not value or type(value) ~= valueType then
                return false, "Missing required value: " .. valueName
            end
        end

        if ComponentFunctions.GetComponent(values.Name, values.Tab) then
            return false, "Dropdown already exists: " .. values.Name
        end

        if not UIComponents[values.Tab] then
            UIComponents[values.Tab] = {}
        end

        table.insert(UIComponents[values.Tab], {
            Name = values.Name,
            Type = "dropdown",
            Default = values.Default or values.Options[1],
            Value = values.Default or values.Options[1],
            Options = values.Options,
            Tab = values.Tab,
            Disabled = values.Disabled or false,
            IndexOrder = values.IndexOrder or 999,
            Callback = values.Callback
        })

        return true
    end

    function ComponentFunctions.CreateInput(values)
        local RequiredValues = {
            Name = "string",
            Tab = "string",
            Callback = "function"
        }

        for valueName, valueType in pairs(RequiredValues) do
            local value = values[valueName]

            if not value or type(value) ~= valueType then
                return false, "Missing required value: " .. valueName
            end
        end

        if ComponentFunctions.GetComponent(values.Name, values.Tab) then
            return false, "Input already exists: " .. values.Name
        end

        if not UIComponents[values.Tab] then
            UIComponents[values.Tab] = {}
        end

        table.insert(UIComponents[values.Tab], {
            Name = values.Name,
            Type = "input",
            Default = values.Default or "",
            Value = values.Default or "",
            Placeholder = values.Placeholder or "",
            Tab = values.Tab,
            Disabled = values.Disabled or false,
            IndexOrder = values.IndexOrder or 999,
            Callback = values.Callback
        })

        return true
    end

    function ComponentFunctions.DisableComponent(name, tab)
        local Component = ComponentFunctions.GetComponent(name, tab)
        
        if not Component then
            return false
        end
        
        Component.Disabled = true
        
        return true
    end

    function ComponentFunctions.EnableComponent(name, tab)
        local Component = ComponentFunctions.GetComponent(name, tab)
        
        if not Component then
            return false
        end
        
        Component.Disabled = false
        
        return true
    end

    function ComponentFunctions.UpdateComponentState(name, tab, value)
        local Component = ComponentFunctions.GetComponent(name, tab)

        if not Component then
            return
        end

        local Success, Response = pcall(function()
            Component.Value = value
            Component.Callback(value)
        end)

        if not Success then
           warn("Failed to update component state: " .. tostring(Response))
        end
    end
end

--<< MAIN FUNCTIONS >>--

Functions = {}; do
    function Functions.GetConnection(name)
        return Connections[name]
    end

    function Functions.DisableConnection(name)
        local Connection = Functions.GetConnection(name)

        if not Connection then
            return false
        end

        pcall(function()
            Connection:Disconnect()
        end)

        Connections[name] = nil

        return true
    end

    function Functions.AddConnection(name, connection)
        Functions.DisableConnection(name)

        Connections[name] = connection
    end

    function Functions.UpdatePriority()
        local Priority = 0

        if Variables.IsHatching then
            Priority = 1
        end

        if Variables.IsSelling then
            Priority = 1
        end

        if Variables.IsUpgrading then
            Priority = 2
        end

        if Variables.IsClaiming then
            Priority = 2
        end

        if Variables.IsFarming then
            Priority = 5
        end

        Variables.CurrentPriority = Priority

        return Priority
    end

    function Functions.CommaSeparateValue(value)
        local Formatted = value

        while true do
            Formatted, k = string.gsub(Formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
            if k == 0 then break end
        end

        return Formatted
    end

    function Functions.GetPlayer(name, exclude)
        local Lowered = tostring(name):lower()
        local Exclude = exclude or {}

        for _, Property in pairs({"Name", "DisplayName"}) do
            for _, Player in pairs(Services.Players:GetChildren()) do
                if not table.find(Exclude, Player) then
                    if string.find(Player[Property]:lower(), Lowered) then
                        return Player
                    end
                end
            end
        end
    end

    function Functions.GetBodyPart(name, player)
        local Player = player or LocalPlayer
        local Character = Player and Player.Character

        return Character and Character:FindFirstChild(name)
    end

    function Functions.GetRoot(player)
        return Functions.GetBodyPart("HumanoidRootPart", player)
    end

    function Functions.GetHumanoid(player)
        return Functions.GetBodyPart("Humanoid", player)
    end

    function Functions.IsAlive(player)
        local Humanoid = Functions.GetHumanoid(player)

        return Humanoid and Humanoid.Health > 0
    end

    function Functions.IsKicked()
        local Success, Response = pcall(function()
            return Services.CoreGui.RobloxPromptGui.promptOverlay.ErrorPrompt.Visible
        end)

        return Success and Response or false
    end

    function Functions.OnKicked(Func)
        repeat wait() until Functions.IsKicked() or Variables.Unloaded

        if Variables.Unloaded then
            return
        end

        return pcall(function()
            Func()
        end)
    end

    function Functions.EnableNoclip(player)
        local Player = player or LocalPlayer

        if not Player or not Player.Character then
            return
        end

        local Character = Player.Character

        task.spawn(function()
            while not Variables.Unloaded do
                if Character ~= Player.Character then
                    break
                end

                for _, v in pairs(Character:GetDescendants()) do
                    pcall(function() v.CanCollide = false end)
                end

                task.wait(0.05)
            end
        end)
    end

    function Functions.Indexify(tbl)
        local NewTable = {}

        for Index, _ in pairs(tbl) do
            table.insert(NewTable, Index)
        end
        
        return NewTable
    end

    function Functions.FireRemote(...)
        Services.ReplicatedStorage.Shared.Framework.Network.Remote.Event:FireServer(...)

        -- Functions.FireRemote("BlowBubble")
        -- Functions.FireRemote("SellBubble")
        -- Functions.FireRemote("UseGift", "Mystery Box", 10)
        -- Functions.FireRemote("GumShopPurchase", "Watermelon")
        -- Functions.FireRemote("GumShopPurchase", "Epic Gum")
        -- Functions.FireRemote("ClaimChest", "Giant Chest")
        -- Functions.FireRemote("ClaimFreeWheelSpin")
        -- Functions.FireRemote("ClaimWheelSpinQueue")
        -- Functions.FireRemote("FreeNotifyLegendary")
        -- Functions.FireRemote("UnlockRiftChest", "golden-chest")
        -- Functions.FireRemote("ClaimPrize", 1)
        -- Functions.FireRemote("ClaimSeason")
        -- Functions.FireRemote("UnlockRiftChest", "golden-chest", false) -- GOLDEN KEY
        -- Functions.FireRemote("ChallengePassClaimReward")
        -- Functions.FireRemote("UnlockWorld", "Minigame Paradise")

        -- Functions.FireRemote("TradeAcceptRequest", PLAYER)
        -- Functions.FireRemote("TradeAccept")
        -- Functions.FireRemote("TradeConfirm")
    end

    function Functions.InvokeRemote(...)
        Services.ReplicatedStorage.Shared.Framework.Network.Remote.Function:InvokeServer(...)

        -- Functions.InvokeRemote("WheelSpin")
    end

    function Functions.GetEggs(golden)
        local Eggs = {}

        for _, Egg in pairs(Services.ReplicatedStorage.Assets.Eggs:GetChildren()) do
            if not golden and Egg.Name:sub(1, 6) == "Golden" then
                continue
            end
            
            table.insert(Eggs, Egg)
        end

        return Eggs
    end

    function Functions.StringifyValues(tbl)
        local Values = {}

        for _, Value in pairs(tbl) do
            table.insert(Values, tostring(Value))
        end

        return Values
    end

    function Functions.SortAlphabetically(tbl)
        table.sort(tbl, function(a, b)
            return tostring(a):lower() < tostring(b):lower()
        end)

        return tbl
    end

    function Functions.IsEggUnlocked(egg)
        return egg.Hitbox.Transparency ~= 1 and egg.Hitbox.Color ~= Color3.fromRGB(0, 0, 0)
    end

    function Functions.GetMostExpensiveEgg(data, nonUnlocked, customEggs)
        local BestEgg, HighestPrice = nil, 0

        for Egg, Data in pairs(customEggs or EggsData) do
            if table.find(Variables.NotFoundEggs, Egg) then
                continue
            end

            if Data.Cost.Currency == "Coins" and not Data.ProductId then
                if data and (data.Coins < Data.Cost.Amount) then
                    continue
                end

                if (data and nonUnlocked) and data.EggsOpened[Egg] then
                    continue
                end

                if Data.Cost.Amount > HighestPrice then
                    BestEgg = Egg
                    HighestPrice = Data.Cost.Amount
                end
            end
        end

        return BestEgg, HighestPrice
    end 

    function Functions.GetBestSellZone()
        local BestSell, BestMultiplier = nil, 0

        for _, World in pairs(workspace.Worlds:GetChildren()) do
            local WorldSell = World:FindFirstChild("Sell")

            if WorldSell then
                local Multiplier = WorldSell:GetAttribute("Multiplier")

                if Multiplier and Multiplier > BestMultiplier then
                    BestMultiplier = Multiplier; BestSell = WorldSell
                end
            end

            for _, Island in pairs(World.Islands:GetChildren()) do
                local SellZone = Island.Island:FindFirstChild("Sell")

                if not SellZone then
                    continue
                end

                local Multiplier = SellZone:GetAttribute("Multiplier")

                if Multiplier and Multiplier > BestMultiplier then
                    BestMultiplier = Multiplier; BestSell = SellZone
                end
            end
        end

        return BestSell
    end

    function Functions.CancelTweens()
        for _, Tween in pairs(Variables.Tweens) do
            Tween:Cancel()
        end

        Variables.Tweens = {}
    end

    function Functions.TweenTeleport(position, disable, speed, nonDirect)
        local Root = Functions.GetRoot()

        if not Root then
            return
        end

        Functions.CancelTweens()

        if nonDirect then
            Root.CFrame = CFrame.new(
                Root.Position.X,
                20000,
                Root.Position.Z
            )
        end

        local Position = nonDirect and Vector3.new(
            position.X,
            20000,
            position.Z
        ) or position

        local Distance = (Root.Position - Position).Magnitude
        local Info = TweenInfo.new(Distance / (speed or 30), Enum.EasingStyle.Linear)

        if Distance > 400 then
            return
        end

        local BodyVelocity = Instance.new("BodyVelocity")
        BodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        BodyVelocity.Velocity = Vector3.zero
        BodyVelocity.Parent = Root

        local Tween = Services.TweenService:Create(Root, Info, {
            CFrame = CFrame.new(Position)
        })

        table.insert(Variables.Tweens, Tween)

        local Completed = false

        task.spawn(function()
            Tween.Completed:Wait()
            Completed = true
        end)

        Tween:Play()

        repeat wait() until (disable and disable()) or Completed

        pcall(function()
            Tween:Cancel()
            BodyVelocity:Destroy()

            Root.CFrame = CFrame.new(position)
        end)

        return not (disable and disable())
    end

    function Functions.TeleportToObjectOnIsland(object, island, shouldTeleport, disable)
        local Position = typeof(object) == "Instance" and object.Position or object
        local Root = Functions.GetRoot()

        local ShouldTeleport = shouldTeleport ~= false and (Root.Position - Position).Magnitude > 10

        Functions.CancelTweens()

        if ShouldTeleport then
            wait(0.5)
            
            for i = 1, 3 do wait(0.1)
                Functions.CancelTweens()
                Functions.TeleportToIsland(island)
            end

            wait(1)
        end

        Functions.TweenTeleport(Position, disable)
    end
    
    function Functions.SellAtBestZone(disable)
        local SellZone = Functions.GetBestSellZone()

        if not SellZone then
            return
        end

        Variables.IsSelling = true

        local TeleportIsland = Services.Workspace.Worlds["The Overworld"].Islands["Twilight"]
        local SellPart = Services.ReplicatedStorage.Assets.Rifts["bubble-rift"].Sell

        Functions.TeleportToIsland(TeleportIsland)
        Functions.TweenTeleport(SellPart.Root.Position + Vector3.new(0, 3, 0), disable, 40, true)

        if (disable and disable()) then
            Variables.IsSelling = false

            return
        end

        local Root = Functions.GetRoot()
        local BodyVelocity = Instance.new("BodyVelocity")
        BodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        BodyVelocity.Velocity = Vector3.zero
        BodyVelocity.Parent = Root

        local Start = tick()

        repeat wait(0.1)
            Functions.FireRemote("SellBubbles")
        until tick() - Start > 2.5 or (disable and disable())

        Functions.TeleportToIsland(TeleportIsland)

        if BodyVelocity then
            BodyVelocity:Destroy()
        end

        Variables.IsSelling = false
    end

    function Functions.HasInfinityGum()
        local Data = LocalData:Get()
        return Data
    end

    function Functions.GetBubbleData()
        local Data = LocalData:Get()
        return Data.Bubble.Amount, StatsUtil:GetBubbleStorage(Data)
    end

    function Functions.GetGumData()
        local Data = LocalData:Get()
        return Data.Gum, Data.Gum["Infinity Gum"]
    end

    function Functions.HasUnlockedEgg(egg)
        local Data = LocalData:Get()
        return Data.EggsOpened[egg] and true or false
    end

    function Functions.GetHatches()
        local Data = LocalData:Get()
        return Data.Stats.Hatches or 0
    end
    
    function Functions.HasUnlockedIsland(island)
        local Data = LocalData:Get()
        return Data.AreasUnlocked[tostring(island)] or false
    end

    function Functions.GetItems()
        local Data = LocalData:Get()
        return Data and Data.Powerups
    end

    function Functions.GetCooldown(cooldown)
        local Data = LocalData:Get()
        return Data and Data.Cooldowns[cooldown] or 0
    end

    function Functions.IsGoldRushActive()
        local Data = LocalData:Get()
        
        for _, Buff in pairs(Data.ActiveBuffs) do
            if Buff.Name == "GoldRush" then
                return true
            end
        end

        return false
    end

    function Functions.GetIsland(island)
        for _, World in pairs(Services.Workspace.Worlds:GetChildren()) do
            local Island = World:FindFirstChild(island)

            if Island then
                return Island
            end
        end
    end

    function Functions.GetCompletedPrizes()
        local ClientData = LocalData:Get()
        local Prizes = {}
        
        for _, Prize in pairs(PrizesData) do
            if not Prize.Type then
                continue
            end

            local LocalType = nil

            if Prize.Type == "Bubbles" then
                LocalType = ClientData.Stats.Bubbles
            elseif Prize.Type == "Eggs" then
                LocalType = ClientData.Stats.Hatches
            end

            if LocalType >= Prize.Requirement then
                local PrizeIndex = tonumber(Prize.Key:split("-")[2])

                table.insert(Prizes, {
                    Type = Prize.Type,
                    Index = (Prize.Type == "Eggs") and (PrizeIndex + 15) or PrizeIndex,
                    Requirement = Prize.Requirement,
                    Reward = Prize.Reward,
                    Key = Prize.Key,
                    Claimed = ClientData.ClaimedPrizes[Prize.Key] or false
                })
            end
        end

        return Prizes
    end

    function Functions.HatchEgg(egg, disable)        
        if (disable and disable()) then
            return
        end

        Variables.IsHatching = true

        local EggData = EggsData[egg]

        if not EggData then
            return
        end

        local TeleportSpot = nil
        print("a", egg, EggData.World)
        if EggData.World == "The Overworld" then
            print("b")
            TeleportSpot = "Workspace.Worlds.The Overworld.FastTravel.Spawn"
        elseif EggData.World == "Minigame Paradise" or EggData.Cost.Currency == "Tickets" then
            print("c")
            local World = Services.Workspace.Worlds:FindFirstChild("Minigame Paradise")
            print("d")
            TeleportSpot = World and (World:GetFullName() .. ".FastTravel.Spawn")
        end
        print("f")

        if not Variables.EggsFolder then
            Functions.FireRemote("Teleport", TeleportSpot)
            wait(0.5)
            Functions.SetEggsFolder()
        end

        local Egg = Variables.EggsFolder:FindFirstChild(egg)
        local Root = Functions.GetRoot()

        local Prompt = Egg and Egg:FindFirstChild("Prompt")

        if not Prompt or (Root.Position - Prompt.Position).Magnitude > 15 then
            Functions.CancelTweens()
            
            wait(0.25)

            Functions.FireRemote("Teleport", TeleportSpot)
            
            Egg = Egg or Variables.EggsFolder:WaitForChild(egg, 3)

            if not Egg then
                table.insert(Variables.NotFoundEggs, egg)

                return false
            end

            Functions.TweenTeleport(Egg.Prompt.Position, disable, 35)

            wait(1)
        end

        Functions.FireRemote("HatchEgg", egg, 100)

        wait(0.75)

        Variables.IsHatching = false
    end
    
    function Functions.SetEggsFolder()
        for _, Folder in pairs(Services.Workspace.Rendered:GetChildren()) do
            if Folder.Name ~= "Chunker" then
                continue
            end
        
            for _, Inst in pairs(Folder:GetChildren()) do
                if Inst:IsA("Model") and Inst.Name:find(" Egg") then
                    Variables.EggsFolder = Folder
                    
                    break
                end
            end
        end
    end
    
    function Functions.GetBestPotionLevel(potionType)
        local Data = LocalData:Get()
        local BestLevel = -1

        for _, Potion in pairs(Data.Potions) do
            if Potion.Name == potionType then
                if (Potion.Level or 0) > BestLevel then
                    BestLevel = Potion.Level
                end
            end
        end

        return potionType, BestLevel
    end

    function Functions.IsUsingBetterPotion(potionType, potionLevel)
        local Data = LocalData:Get()

        local PotionPath = Data.ActivePotions[potionType]

        if PotionPath then
            local Active = PotionPath.Active or {}

            if (Active.Level or 0) >= potionLevel then
                return true
            end

            for _, Potion in pairs(PotionPath.Queue or {}) do
                if (Potion.Level or 0) >= potionLevel then
                    return true
                end
            end
        end

        return false
    end

    function Functions.SetCoinsFolder()
        Variables.CoinsFolder = nil

        for _, Folder in pairs(Services.Workspace.Rendered:GetChildren()) do
            if Variables.CoinsFolder then
                break
            end

            if Folder.Name ~= "Chunker" then
                continue
            end
        
            for _, Descendant in pairs(Folder:GetDescendants()) do
                if Descendant:IsA("MeshPart") then
                    local Name = Descendant.Name:lower()

                    if Name:find("coin") or Name:find("gem") then
                        Variables.CoinsFolder = Folder

                        break
                    end
                end
            end
        end
    end
    
    function Functions.GetNextMasteryLevel(mastery)
        local Data = LocalData:Get()
        local Level = Data.MasteryLevels[mastery] or 0
        local Mastery = MasteryData.Upgrades[mastery]
        
        if not Mastery then
            return
        end
        
        local WantedUpgrade = Mastery.Levels[Level + 1]
        
        if not WantedUpgrade then
            return
        end
        
        return (Level + 1), WantedUpgrade.Cost
    end

    function Functions.GetMostExpensiveFlavor()
        local MostExpensive = nil
        local HighestPrice = 0

        for Flavor, _ in pairs(LocalData:Get().Flavors) do
            local FlavorData = FlavorsData[Flavor]

            if not FlavorData or type(FlavorData.Cost) ~= "table" then
                continue
            end

            local Price = FlavorData.Cost.Amount
            
            if Price > HighestPrice then
                MostExpensive = Flavor
                HighestPrice = Price
            end
        end

        return MostExpensive, HighestPrice
    end

    function Functions.GetMostExpensiveGum()
        local MostExpensive = nil
        local HighestPrice = 0

        for Gum, _ in pairs(LocalData:Get().Gum) do
            local GumData = GumData[Gum]

            if not GumData or type(GumData.Cost) ~= "table" then
                continue
            end

            local Price = GumData.Cost.Amount
            
            if Price > HighestPrice then
                MostExpensive = Gum
                HighestPrice = Price
            end
        end

        return MostExpensive, HighestPrice
    end

    function Functions.GetNextPurchasable(tbl, minPrice)
        local NextPurchasable = nil
        local NextPrice = {Amount = math.huge}

        for Name, Purchasable in pairs(tbl) do
            if not Purchasable.Cost or type(Purchasable.Cost) ~= "table" then
                continue
            end

            local Price = Purchasable.Cost.Amount

            if Price > minPrice and Price < NextPrice.Amount then
                NextPurchasable = Name
                NextPrice = {Amount = Price, Currency = Purchasable.Cost.Currency}
            end
        end

        return NextPurchasable, NextPrice
    end

    function Functions.GetIslandPortal(island)
        return Services.Workspace.Rendered.Generic:FindFirstChild(island)
    end
    
    function Functions.UnlockIsland(Island, Disable)
        local Height = Island:GetAttribute("Height")
        local Start = tick()

        if not Height then
            return
        end

        for _, OtherIsland in pairs(Island.Parent:GetChildren()) do
            local OtherHeight = OtherIsland:GetAttribute("Height")

            if not OtherHeight then
                continue
            end

            if OtherHeight < Height and not Functions.HasUnlockedIsland(OtherIsland) then
                Functions.UnlockIsland(OtherIsland, Disable)
            end
        end

        repeat
            if (Disable and Disable()) then
                return
            end

            firetouchinterest(Island.Island.UnlockHitbox, LocalPlayer.Character.HumanoidRootPart, 0)
            firetouchinterest(Island.Island.UnlockHitbox, LocalPlayer.Character.HumanoidRootPart, 1)

            wait(0.25)
        until Functions.HasUnlockedIsland(Island) or tick() - Start > 5

        return Functions.HasUnlockedIsland(Island)
    end

    function Functions.IsAtIsland(Island)
        local Root = Functions.GetRoot(LocalPlayer)
        local Height = Island:GetAttribute("Height")

        if not Root or Island.Parent.Name == "Worlds" then
            return true
        end

        return (Root.Position.Y >= (Height - 10))
    end

    function Functions.TeleportToIsland(Island)
        if Functions.IsAtIsland(Island) then
            return
        end

        local Suffix = nil

        if Island.Parent.Name ~= "Worlds" then
            Suffix = ".Island.Portal.Spawn"

            if not Functions.HasUnlockedIsland(Island) then
                local Success = Functions.UnlockIsland(Island)

                if not Success then
                    warn("Failed to unlock island.")
                    return
                end
            end
        else
            Suffix = ".PortalSpawn"
        end

        local Start = tick()

        repeat
            Functions.FireRemote("Teleport", Island:GetFullName() .. Suffix)
            wait(0.1)
        until Functions.IsAtIsland(Island) or tick () - Start > 5 
    end
    
    function Functions.UnlockAllIslands(world, disable)
        local World = world or Services.Workspace.Worlds:FindFirstChild(
            WorldUtil:GetPlayerWorld(LocalPlayer)
        )

        if not World then
            return
        end

        for _, Island in pairs(World.Islands:GetChildren()) do
            if (disable and disable()) then return end

            if not Functions.HasUnlockedIsland(Island.Name) then
                Functions.UnlockIsland(Island, disable)
            end
        end
    end

    function Functions.IsInTrade()
        local Success, Response = pcall(function()
            return LocalPlayer.PlayerGui.ScreenGui.Trading.Visible
        end)

        return Success and Response or false
    end

    function Functions.HasPlayerAcceptedTrade()
        local TradeFrame = LocalPlayer.PlayerGui.ScreenGui.Trading
        return TradeFrame.Frame.Inner.Them.Cover.Visible
    end

    function Functions.HasPlayerConfirmedTrade()
        local TradeFrame = LocalPlayer.PlayerGui.ScreenGui.Trading
        return TradeFrame.Frame.Inner.Offers.Status.Text:find("has confirmed") and true or false
    end

    function Functions.CalculateDuration(timestamp)
        local CurrentTime = os.time()
        local Difference = os.difftime(CurrentTime, timestamp)
        
        local IsFuture = Difference < 0
        Difference = math.abs(Difference)
        
        local Days = math.floor(Difference / 86400)
        local Remaining = Difference % 86400

        local Hours = math.floor(Remaining / 3600)
        Remaining = Remaining % 3600

        local Minutes = math.floor(Remaining / 60)
        local Seconds = Remaining % 60
        
        if IsFuture then
            Days = -Days
            Hours = -Hours
            Minutes = -Minutes
            Seconds = -Seconds
        end
        
        return {
            Days = Days,
            Hours = Hours,
            Minutes = Minutes,
            Seconds = Seconds,
        }
    end

    function Functions.GetTradeHistoryFromPlayer(player, duration)
        local ClientData = LocalData:Get()
        local CurrentTime = os.time()
        local DurationInSeconds = 0
        
        if type(duration) == "string" then
            for Value, Unit in string.gmatch(duration, "(%d+)%s*(%a+)") do
                Value = tonumber(Value)
                Unit = Unit:lower()
                
                if Unit:find("day") then
                    DurationInSeconds = DurationInSeconds + (Value * 86400)
                elseif Unit:find("hour") then
                    DurationInSeconds = DurationInSeconds + (Value * 3600)
                elseif Unit:find("minute") then
                    DurationInSeconds = DurationInSeconds + (Value * 60)
                elseif Unit:find("second") then
                    DurationInSeconds = DurationInSeconds + Value
                end
            end
        elseif type(duration) == "number" then
            DurationInSeconds = duration
        end
        
        local MinTimestamp = CurrentTime - DurationInSeconds
        local FilteredTrades = {}
        
        for _, Trade in pairs(ClientData.TradeHistory) do
            if Trade.Timestamp >= MinTimestamp then
                local IsPlayerInvolved = false
                
                if player then
                    if Trade.Party0.UserId == player or Trade.Party1.UserId == player then
                        IsPlayerInvolved = true
                    end
                else
                    IsPlayerInvolved = true
                end
                
                if IsPlayerInvolved then
                    table.insert(FilteredTrades, Trade)
                end
            end
        end
        
        return FilteredTrades
    end

    function Functions.RemoveDuplicates(tbl)
        local Result = {}
        
        for _, Value in pairs(tbl) do
            if not table.find(Result, Value) then
                table.insert(Result, Value)
            end
        end
        
        return Result
    end

    function Functions.GetPlayerTradeOffers(trades, player)
        local Offers = {}

        for _, Trade in pairs(trades) do
            local Player = nil

            if Trade.Party0.UserId == player then
                Player = Trade.Party0
            elseif Trade.Party1.UserId == player then
                Player = Trade.Party1
            end

            if Player then
                for _, Offer in pairs(Player.Items) do
                    table.insert(Offers, Offer)
                end
            end
        end

        return Offers
    end

    function Functions.TradePlayer(player, offer)
        if not Functions.IsInTrade() then
            if not player then
                return
            end

            repeat
                if not (player and player.Parent) then
                    return false
                end
    
                Functions.FireRemote("TradeRequest", player)
                
                wait(1)
            until Functions.IsInTrade()
        end

        for _, PetId in pairs(offer or {}) do
            Functions.FireRemote("TradeAddPet", PetId .. ":0")
        end

        repeat wait(0.5)
            if not Functions.IsInTrade() then
                return false
            end
        until Functions.HasPlayerAcceptedTrade()

        for i = 1, 3 do
            Functions.FireRemote("TradeAccept")
            wait(0.25)
        end
        
        repeat wait(0.5)
            if not Functions.IsInTrade() then
                return false
            end
        until Functions.HasPlayerConfirmedTrade()
        
        for i = 1, 3 do
            Functions.FireRemote("TradeConfirm")
            wait(0.25)
        end

        return true
    end
end

--<< WEBSOCKET FUNCTIONS >>--

WebSocketFunctions = {}; do
    function WebSocketFunctions.SendData(data)
        if not WebSocketConnection then return end

        return pcall(function()
            WebSocketConnection:Send(Services.HttpService:JSONEncode(data))
        end)
    end

    function WebSocketFunctions.SendStatus(status, details)
        if not WebSocketConnection or not Variables.IsConnected then
            return
        end

        Variables.ClientStatus = status

        return WebSocketFunctions.SendData({
            Action = "status_update",
            Identifier = LocalPlayer.Name,
            Status = status,
            Details = details
        })
    end

    function WebSocketFunctions.HandleDisconnect()        
        Functions.DisableConnection("WebSocket Message")
        Functions.DisableConnection("WebSocket Close")
        
        Variables.IsConnected = false

        WebSocketFunctions.ScheduleReconnect()
    end

    function WebSocketFunctions.SendInitialData()
        local ComponentsData = {}

        for tab, items in pairs(UIComponents) do
            ComponentsData[tab] = {}

            for _, data in pairs(items) do
                table.insert(ComponentsData[tab], {
                    name = data.Name,
                    type = data.Type,
                    default = data.Default,
                    options = data.Options,
                    indexOrder = data.IndexOrder
                })
            end
        end

        local ComponentsString = Services.HttpService:JSONEncode(ComponentsData)

        return WebSocketFunctions.SendData({
            Action = "client_connect",
            Identifier = LocalPlayer.Name,
            Username = LocalPlayer.Name,
            DisplayName = LocalPlayer.DisplayName,
            UserId = LocalPlayer.UserId,
            Status = Variables.ClientStatus,
            PlaceId = game.PlaceId,
            JobId = game.JobId,
            Key = Config.Key,
            Toggles = ComponentsString
        })
    end

    function WebSocketFunctions.SendCommandResult(command, success, response, color)
        return WebSocketFunctions.SendData({
            Action = "command_result",
            Identifier = LocalPlayer.Name,
            Command = command,
            Success = success,
            Response = response,
            Color = color
        })
    end

    function WebSocketFunctions.AddWebSocketAction(str, callback)
        WebSocketActions[str] = callback
    end

    function WebSocketFunctions.HandleWebSocketMessage(message)
        local Success, Response = pcall(function()
            return Services.HttpService:JSONDecode(message)
        end)

        if not Success then
            return false, "Failed to decode message: " .. tostring(message)
        end

        if not WebSocketActions[Response.Action] then
            return false, "Invalid action: " .. tostring(Response.Action)
        end

        return pcall(function()
            return WebSocketActions[Response.Action](Response)
        end)
    end

    function WebSocketFunctions.ScheduleReconnect()
        if Variables.Unloaded then return end
        
        Variables.ReconnectAttempts += 1

        if Variables.ReconnectAttempts > Variables.MaxReconnectAttempts then
            warn("[!] Max reconnection attempts reached.")
            return
        end
        
        local Delay = Variables.ReconnectDelay * math.min(Variables.ReconnectAttempts, 3)
        print("Reconnecting in " .. Delay .. " seconds (Attempt " .. Variables.ReconnectAttempts .. ")")
        
        pcall(function()
            task.delay(Delay, WebSocketFunctions.Connect)
        end)
    end
    
    function WebSocketFunctions.Disconnect()
        if WebSocketConnection then
            pcall(function() WebSocketConnection:Close() end)
            WebSocketConnection = nil
        end
        
        for _, Connection in ipairs({"WebSocket Message", "WebSocket Close", "WebSocket Heartbeat"}) do
            Functions.DisableConnection(Connection)
        end
    end

    function WebSocketFunctions.Connect()
    if WebSocketConnection then
        pcall(function() WebSocketConnection:Close() end)
    end

    pcall(function()
        WebSocketConnection = WebSocket.connect(Config.WebSocketURL)
    end)

    if not WebSocketConnection then
        warn("[!] Failed to connect to WebSocket server.")
        return WebSocketFunctions.ScheduleReconnect()
    end

    print("[+] Successfully connected to WebSocket server.")
    Variables.ReconnectAttempts = 0

    if not WebSocketFunctions.SendInitialData() then
        warn("[!] Failed to send client data.")
        return WebSocketFunctions.ScheduleReconnect()
    end

    -- Send current pets
    pcall(function()
        local Data = LocalData:Get()
        if Data and Data.Pets then
            local PetNames = {}
            for _, pet in pairs(Data.Pets) do
                table.insert(PetNames, pet.Name)
            end

            WebSocketFunctions.SendData({
                Action = "pet_list",
                Identifier = LocalPlayer.Name,
                Pets = PetNames
            })
        end
    end)

    Functions.AddConnection("WebSocket Message", WebSocketConnection.OnMessage:Connect(function(message)
        local Success, Response = WebSocketFunctions.HandleWebSocketMessage(message)

        if not Success then
            warn("[!] Failed to perform action. Error: " .. tostring(Response))
        end
    end))

    Functions.AddConnection("WebSocket Close", WebSocketConnection.OnClose:Connect(function()
        WebSocketFunctions.HandleDisconnect()
    end))

    task.spawn(function()
        local LastHeartbeat = 0
        local NextDuration = math.random(20, 30)

        while Functions.GetConnection("WebSocket Message") do
            if not WebSocketConnection then break end

            local Tick = tick()

            if Tick - LastHeartbeat > NextDuration then
                local Success = pcall(function()
                    local Data = LocalData:Get()

                    WebSocketFunctions.SendData({
                        Action = "heartbeat",
                        Identifier = LocalPlayer.Name,
                        Data = {
                            Coins = Data.Coins,
                            Gems = Data.Gems
                        }
                    })
                end)

                if not Success and not Variables.Unloaded then
                    WebSocketFunctions.Connect()
                end

                LastHeartbeat = tick()
                NextDuration = math.random(10, 25)
            end

            wait(1)
        end
    end)
end

--<< LISTENERS >>--

Functions.AddConnection("CharacterAdded Listener", LocalPlayer.CharacterAdded:Connect(function(character)
    repeat wait() until character:FindFirstChild("HumanoidRootPart")

    Functions.EnableNoclip()
end))

Functions.AddConnection("PlayerAdded Listener", Services.Players.PlayerAdded:Connect(function(player)

end))

Functions.AddConnection("PlayerRemoving Listener", Services.Players.PlayerRemoving:Connect(function(player)
    if player == LocalPlayer then
        WebSocketFunctions.Disconnect()

        return
    end
end))

Functions.AddConnection("Mystery Box Added", Services.Workspace.Rendered.Gifts.ChildAdded:Connect(function(gift)
    wait(0.5)

    Functions.FireRemote("ClaimGift", gift.Name)

    task.delay(3, function()
        gift:Destroy()
    end)
end))

Functions.AddConnection("Trade Listener", RemoteModule.Event("TradeRequest"):Connect(function(player)
    if not Variables.AutoAcceptTrade then
        return
    end

    local HelperPlayer = Functions.GetPlayer(Variables.Helper)

    if not HelperPlayer or HelperPlayer ~= player then
        warn("[!] Trade request received from a non-helper.")

        return
    end

    local IsInTrade = Functions.IsInTrade()

    if IsInTrade then
        warn("[!] You are already in a trade.")

        return
    end

    local Start = tick()

    repeat wait()
        Functions.FireRemote("TradeAcceptRequest", HelperPlayer)
    until Functions.IsInTrade() or tick() - Start > 5

    if not Functions.IsInTrade() then
        warn("[!] Failed to accept trade request.")

        return
    end

    Functions.TradePlayer(player)
end))

task.spawn(Functions.OnKicked, function()
    if not Config.RejoinOnKick then
        return
    end

    Services.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId)
end)

do
    local Success, _ = pcall(function()
        local AmountDisabled = 0

        for i, v in next, getconnections(LocalPlayer.Idled) do
            v:Disable(); AmountDisabled += 1
        end

        if AmountDisabled == 0 then error() end
    end)

    if not Success then
        Functions.AddConnection("Anti Afk", LocalPlayer.Idled:Connect(function()
            Services.VirtualUser:CaptureController(); Services.VirtualUser:ClickButton2(Vector2.new())
        end))
    end
end

--<< DEFINE CLEANUP FUNCTION >>--

getgenv().DisableScript = function()
    Variables.Unloaded = true

    for Connection, _ in pairs(Connections) do
        Functions.DisableConnection(Connection)
    end

    WebSocketFunctions.Disconnect()
end

--<< STARTUP >>--

pcall(function()
    setfpscap(Config.FPS_Cap)
end)

Functions.AddConnection("Priority Updater", Services.RunService.Heartbeat:Connect(function()
    Functions.UpdatePriority()
end))

task.spawn(function()
    local Settings = {
        ["Hide Global Secret Messages"] = true,
        ["Skip Easy Legendary"] = true,
        ["Hide Others Pets"] = true,
        ["Low Detail Mode"] = true,
        ["Hide Bubbles"] = true
    }

    for Setting, Value in pairs(Settings) do
        Functions.FireRemote("SetSetting", Setting, Value)
        wait(0.75)
    end
end)

do -- Load Into Game
    local IntroGui = LocalPlayer.PlayerGui:FindFirstChild("Intro")

    if IntroGui then
        local MainGui = LocalPlayer.PlayerGui:WaitForChild("ScreenGui")
        local Fade = IntroGui:FindFirstChild("Fade")

        if MainGui then
            MainGui.Enabled = true
        end

        if Fade then
            Fade.BackgroundTransparency = 1
        end

        for _, Child in pairs(IntroGui:GetChildren()) do
            if Child:IsA("GuiObject") and Child ~= Fade then
                Child.Visible = false
            end
        end

        if IntroGui:FindFirstChild("NumberValue") then
            -- IntroGui.NumberValue:Destroy()
        end

        -- IntroGui:Destroy()
        IntroGui.Enabled = false

        Services.StarterGui:SetCoreGuiEnabled("All", true)
    end
end

do -- Use Codes
    if Config.RedeemCodes then
        for Code, _ in pairs(CodesData) do
            Functions.InvokeRemote("RedeemCode", Code)
        end
    end
end

do -- Infinite Pickup Range
    function StatsUtil:GetPickupRange()
        return math.huge
    end
end

Functions.SetEggsFolder()
Functions.EnableNoclip()

task.delay(10, function()
    Functions.FireRemote("FreeNotifyLegendary")
end)

Functions.FireRemote("DailyRewardClaimStars")
Functions.FireRemote("EquipBestPets")

Services.RunService:Set3dRenderingEnabled(not Config.Disable3DRendering)

--<< COMMAND ADDING >>--



--<< COMPONENTS SECTION >>--

ComponentFunctions.CreateToggle({
    Name = "Auto Hatch",
    Tab = "Automations",
    Default = false,
    IndexOrder = 1,
    Callback = function(value)
        Variables.AutoHatch = value

        if value then
            local LastHatch = 0

            while Variables.AutoHatch do wait()
                if Variables.Unloaded then
                    break
                end

                if not Variables.HatchEgg then
                    wait(0.5); continue
                end

                if tick() - LastHatch < 1 or Variables.CurrentPriority >= 1 or Functions.IsHatching then
                    continue
                end

                LastHatch = tick()

                print("before")
                Functions.HatchEgg(Variables.HatchEgg, function()
                    return not Variables.AutoHatch or Variables.Unloaded or Variables.CurrentPriority > 1
                end)
                print("after")
            end
        end
    end
})

local EggOptions = Functions.SortAlphabetically(Functions.StringifyValues(Functions.GetEggs(true)))

ComponentFunctions.CreateDropdown({
    Name = "Egg to Hatch",
    Tab = "Automations",
    Options = EggOptions,
    Default = EggOptions[1],
    Callback = function(value)
        Variables.HatchEgg = value
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Blow Bubbles",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoBlowBubbles = value

        if value then
            local LastBlow = 0

            while Variables.AutoBlowBubbles do wait()
                if Variables.Unloaded then
                    break
                end

                if tick() - LastBlow < 0.3 then
                    continue
                end

                LastBlow = tick()

                Functions.FireRemote("BlowBubble")
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Sell Bubbles",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoSellBubbles = value

        if value then
            local LastSell = tick()

            while Variables.AutoSellBubbles do wait()
                if Variables.Unloaded then
                    break
                end

                Functions.UpdatePriority()

                if tick() - LastSell < 1.3 or Variables.CurrentPriority >= 1 or Functions.IsHatching then
                    continue
                end

                local Bubbles, Storage = Functions.GetBubbleData()
                local _, HasInfinityGum = Functions.GetGumData()
                
                if HasInfinityGum then
                    if tick() - LastSell < 60 then
                        continue
                    end
                elseif Bubbles < Storage then
                    continue
                end

                Functions.SellAtBestZone(function()
                    return not Variables.AutoSellBubbles or Variables.Unloaded or Variables.CurrentPriority > 1
                end)

                LastSell = tick()
            end

            Functions.UpdatePriority()

            if Variables.CurrentPriority <= 0 then
                Functions.TeleportToIsland(Services.Workspace.Worlds["The Overworld"])
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Open Mystery Box",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoOpenMysteryBox = value

        if value then
            local LastOpen = 0

            for _, gift in pairs(Services.Workspace.Rendered.Gifts:GetChildren()) do
                Functions.FireRemote("ClaimGift", gift.Name)
            end

            while Variables.AutoOpenMysteryBox do wait()
                if Variables.Unloaded then
                    break
                end

                if tick() - LastOpen < 5 then
                    continue
                end

                LastOpen = tick()

                local Items = Functions.GetItems()["Mystery Box"]

                if Items then
                    Functions.FireRemote("UseGift", "Mystery Box", Items >= 10 and 10 or Items)
                end
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Use Golden Orb",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoUseGoldenOrb = value

        if value then
            local LastUse = 0

            while Variables.AutoUseGoldenOrb do wait()
                if Variables.Unloaded then
                    break
                end

                if tick() - LastUse < 5 then
                    continue
                end

                if not Functions.IsGoldRushActive() then
                    Functions.FireRemote("UseGoldenOrb")
                end

                LastUse = tick()
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Playtime Rewards",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoPlaytimeRewards = value

        if value then
            local LastClaim = 0

            while Variables.AutoPlaytimeRewards do wait()
                if Variables.Unloaded then
                    break
                end

                if tick() - LastClaim < 5 then
                    continue
                end

                local ClientData = LocalData:Get()

                for i = 1, 9 do
                    if ClientData.PlaytimeRewards.Claimed[tostring(i)] then
                        continue
                    end

                    Functions.InvokeRemote("ClaimPlaytime", i)
                end

                LastClaim = tick()
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Claim Season Rewards",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoClaimSeasonReward = value

        if value then
            local LastClaim = 0

            while Variables.AutoClaimSeasonReward do wait()
                if Variables.Unloaded then
                    break
                end

                if tick() - LastClaim < 2 then
                    continue
                end

                Functions.FireRemote("ClaimSeason")

                LastClaim = tick()
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Claim Quest Prizes",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoClaimQuestPrizes = value

        if value then
            local LastClaim = 0

            while Variables.AutoClaimQuestPrizes do wait()
                if Variables.Unloaded then
                    break
                end

                if tick() - LastClaim < 5 then
                    continue
                end

                local Prizes = Functions.GetCompletedPrizes()

                for _, Prize in pairs(Prizes) do
                    if Prize.Claimed then
                        continue
                    end

                    Functions.FireRemote("ClaimPrize", Prize.Index)

                    wait(0.5)
                end

                LastClaim = tick()
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Collect",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoCollect = value

        if value then
            local ClientData = LocalData:Get()
            local TopIsland = nil
            local LastCheck = 0

            if ClientData.WorldsUnlocked["Minigame Paradise"] then
                TopIsland = Services.Workspace.Worlds["Minigame Paradise"].Islands["Robot Factory"]
            else
                TopIsland = Services.Workspace.Worlds["The Overworld"].Islands.Zen.Island
            end

            while Variables.AutoCollect do wait()
                if Variables.Unloaded then
                    break
                end

                if tick() - LastCheck < 1 or Variables.CurrentPriority >= 1 then
                    continue
                end

                local Root = Functions.GetRoot()

                if not Root then
                    continue
                end

                if not Functions.HasUnlockedIsland(TopIsland.Parent) then
                    Functions.UnlockAllIslands(TopIsland.Parent.Parent, function()
                        return Variables.Unloaded or not Variables.AutoCollect
                    end)
                end

                if not Functions.IsAtIsland(TopIsland) then
                    Functions.TeleportToIsland(TopIsland.Parent)
                end

                LastCheck = tick()
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Equip Best Pets",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoEquipBestPets = value

        if value then
            local LastEquip = 0

            while Variables.AutoEquipBestPets do wait()
                if Variables.Unloaded then
                    break
                end

                if tick() - LastEquip < 10 then
                    continue
                end

                Functions.FireRemote("EquipBestPets")

                LastEquip = tick()
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Upgrade Storage & Bubbles",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoUpgrade = value

        if value then
            local LastUpgrade = 0

            while Variables.AutoUpgrade do wait()
                if Variables.Unloaded then
                    break
                end

                if tick() - LastUpgrade < 3 or Variables.CurrentPriority >= 2 then
                    continue
                end

                local ClientData = LocalData:Get()

                local Flavor, FlavorPrice = Functions.GetMostExpensiveFlavor()
                local Gum, GumPrice = Functions.GetMostExpensiveGum()

                local NextFlavor, NextFlavorPrice = Functions.GetNextPurchasable(FlavorsData, FlavorPrice)
                local NextGum, NextGumPrice = Functions.GetNextPurchasable(GumData, GumPrice)

                wait(0.5)

                if NextFlavor then
                    Variables.IsUpgrading = true
                    
                    if ClientData[NextFlavorPrice.Currency] >= NextFlavorPrice.Amount then
                        Functions.FireRemote("Teleport", "Workspace.Worlds.The Overworld.Shop.Root")
                        wait(1)
                        Functions.FireRemote("GumShopPurchase", NextFlavor)
                    end
                end

                if NextGum then
                    Variables.IsUpgrading = true

                    if ClientData[NextGumPrice.Currency] >= NextGumPrice.Amount then
                        Functions.FireRemote("Teleport", "Workspace.Worlds.The Overworld.Shop.Root")
                        wait(1)
                        Functions.FireRemote("GumShopPurchase", NextGum)
                    end
                end

                Variables.IsUpgrading = false

                LastUpgrade = tick()
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Claim Chests",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoClaimChests = value

        if value then
            local LastClaim = 0

            while Variables.AutoClaimChests do wait()
                if Variables.Unloaded then
                    break
                end

                if tick() - LastClaim < 5 or Variables.CurrentPriority >= 2 then
                    continue
                end

                local TimeNow = Services.Workspace:GetServerTimeNow()

                if (Functions.GetCooldown("Giant Chest") - TimeNow) <= 0 then
                    Variables.IsClaiming = true

                    local FloatingIsland = Services.Workspace.Worlds["The Overworld"].Islands["Floating Island"]

                    Functions.TeleportToObjectOnIsland(Vector3.new(12, 428, 156), FloatingIsland, true, function()
                        return Variables.Unloaded or not Variables.AutoClaimChests or Variables.CurrentPriority > 2
                    end, 35)

                    wait(1.5)

                    Functions.FireRemote("ClaimChest", "Giant Chest")
                end

                if (Functions.GetCooldown("Void Chest") - TimeNow) <= 0 then
                    Variables.IsClaiming = true

                    local FloatingIsland = Services.Workspace.Worlds["The Overworld"].Islands["The Void"]

                    Functions.TeleportToObjectOnIsland(Vector3.new(74, 10148, 56), FloatingIsland, true, function()
                        return Variables.Unloaded or not Variables.AutoClaimChests or Variables.CurrentPriority > 2
                    end, 35)

                    wait(1.5)

                    Functions.FireRemote("ClaimChest", "Void Chest")
                end

                Variables.IsClaiming = false

                LastClaim = tick()
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Use Best Coins Potion",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoUseCoinsPotion = value

        if value then
            local LastPotionUsage = 0

            while Variables.AutoUseCoinsPotion do wait()
                if Variables.Unloaded then
                    break
                end

                if tick() - LastPotionUsage < 5 then
                    continue
                end

                local PotionType, BestPotion = Functions.GetBestPotionLevel("Coins")

                if (BestPotion and BestPotion > 0) and not Functions.IsUsingBetterPotion(PotionType, BestPotion) then
                    Functions.FireRemote("UsePotion", PotionType, BestPotion)
                end
                
                LastPotionUsage = tick()
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Upgrade Mastery",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoUpgradeMastery = value

        if value then
            local LastMasteryUpgrade = 0

            while Variables.AutoUpgradeMastery do wait()
                if Variables.Unloaded then
                    break
                end

                if tick() - LastMasteryUpgrade < 5 then
                    continue
                end

                local ClientData = LocalData:Get()

                local PetsShop, NextPetsPrice = Functions.GetNextMasteryLevel("Pets")
                local NextBuff, NextBuffPrice = Functions.GetNextMasteryLevel("Buffs")
                local NextShop, NextShopPrice = Functions.GetNextMasteryLevel("Shops")

                if PetsShop and NextPetsPrice.Amount <= ClientData[NextPetsPrice.Currency] then
                    Functions.FireRemote("UpgradeMastery", "Pets")
                end
                
                if NextBuff <= 15 and NextBuffPrice.Amount <= ClientData[NextBuffPrice.Currency] then
                    Functions.FireRemote("UpgradeMastery", "Buffs")
                end

                if NextShop and NextShopPrice.Amount <= ClientData[NextShopPrice.Currency] then
                    Functions.FireRemote("UpgradeMastery", "Shops")
                end
                
                LastMasteryUpgrade = tick()
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Dice Minigame",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoDiceMinigame = value

        if value then
            local LastDiceMinigame = 0

            while Variables.AutoDiceMinigame do wait()
                if Variables.Unloaded then
                    break
                end

                if tick() - LastDiceMinigame < 1 then
                    continue
                end

                local ClientData = LocalData:Get()

                if #ClientData.Pets == 0 then
                    continue
                end

                if not ClientData.Board["Piece"] then
                    Functions.FireRemote("ChoosePiece", ClientData.Pets[1].Id)
                end

                local Dices = {
                    [1] = "Dice",
                    [2] = "Giant Dice",
                    [3] = "Golden Dice"
                }

                local ChosenDice = nil

                for _, Dice in ipairs(Dices) do
                    local Amount = ClientData.Powerups[Dice]

                    if Amount and Amount > 0 then
                        ChosenDice = Dice
                        break
                    end
                end

                if ChosenDice then
                    Functions.InvokeRemote("RollDice", ChosenDice)
                    wait(0.5)
                    Functions.FireRemote("ClaimTile")
                end

                LastDiceMinigame = tick()
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Robot Claw",
    Tab = "Automations",
    Default = false,
    Callback = function(value)
        Variables.AutoRobotClaw = value

        if value then
            local LastRobotClaw = 0

            while Variables.AutoRobotClaw do wait()
                if Variables.Unloaded then
                    break
                end

                if tick() - LastRobotClaw < 1 then
                    continue
                end

                local TimeNow = Services.Workspace:GetServerTimeNow()

                if (Functions.GetCooldown("Robot Claw") - TimeNow) <= 0 then
                    Functions.FireRemote("StartMinigame", "Robot Claw", "Easy")
                    
                    local Found = false

                    repeat wait(0.5)
                        for _, Item in pairs(LocalPlayer.PlayerGui.ScreenGui:GetChildren()) do
                            if Item.Name:find("ClawItem") then
                                Found = true; break
                            end
                        end
                    until Found

                    wait(1)

                    for _, Item in pairs(LocalPlayer.PlayerGui.ScreenGui:GetChildren()) do
                        if Item.Name:find("ClawItem") then
                            local ItemId = Item.Name:gsub("ClawItem", "")
                            Functions.FireRemote("GrabMinigameItem", ItemId)

                            wait(6)
                        end
                    end

                    Functions.FireRemote("FinishMinigame")
                end

                LastRobotClaw = tick()
            end
        end
    end
})

ComponentFunctions.CreateToggle({
    Name = "Start Strategy",
    Tab = "Strategies",
    IndexOrder = 2,
    Default = false,
    Callback = function(value)
        Variables.StartStrategy = value

        if value then
            local Strategy = Variables.FarmingStrategy
            local MinimumHeight = 15900
            local HasHatched = false

            local LastChallengeReward = 0
            local LastStoragePurchase = 0
            local LastMasteryUpgrade = 0
            local LastSeasonReward = 0
            local LastRewardClaim = 0
            local LastPotionUsage = 0
            local LastClawMachine = 0
            local LastChestClaim = 0
            local LastMysteryBox = 0
            local LastPrizeClaim = 0
            local LastWheelSpin = 0
            local LastGoldenOrb = 0
            local LastBestEquip = 0
            local LastBlow = 0

            local TopIsland = Services.Workspace.Worlds["The Overworld"].Islands.Zen.Island
            local BottomIsland = Services.Workspace.Worlds["The Overworld"].Islands.Twilight.Island

            if Variables.FarmingStrategy == "Maximize" then
                Functions.FireRemote("EquipBestPets")
                
                Functions.UnlockAllIslands(Services.Workspace.Worlds["The Overworld"], function()
                    return not Variables.StartStrategy or Variables.Unloaded
                end)
            end

            while Variables.StartStrategy do wait()
                if Variables.Unloaded then
                    break
                end

                local Root = Functions.GetRoot()
                if not Root then
                    continue
                end

                if Variables.FarmingStrategy == "Maximize" then
                    local ClientData = LocalData:Get()

                    do -- Complete Tutorial
                        if Services.ReplicatedStorage.Client.Gui.Utils.Notification:GetAttribute("Tutorial") then
                            repeat wait(0.2)
                                local Bubbles, Storage = Functions.GetBubbleData()
                                
                                if Bubbles >= Storage then
                                    break
                                end

                                Functions.FireRemote("BlowBubble")
                            until false

                            local SellZone = Services.Workspace.Worlds["The Overworld"].Sell
                            Functions.FireRemote("Teleport", SellZone.Root:GetFullName())

                            wait(0.5)

                            Functions.FireRemote("SellBubble")

                            wait(0.5)

                            Services.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId)

                            break
                        end
                    end

                    do -- Make Sure of Zen Island
                        if not Functions.HasUnlockedIsland(TopIsland.Parent) then
                            local Start = tick()
                            
                            repeat wait()
                                if tick() - Start > 5 then
                                    break
                                end
                            until Functions.UnlockIsland(TopIsland.Parent)

                            if tick() - Start > 5 then
                                Functions.TeleportToIsland(BottomIsland.Parent)

                                wait(0.5)

                                Root.CFrame = CFrame.new(
                                    Root.Position.X,
                                    TopIsland.Parent:GetAttribute("Height") + 20,
                                    Root.Position.Z
                                )

                                wait(0.5)

                                if not Functions.HasUnlockedIsland(TopIsland.Parent) then
                                    break
                                end
                            end
                        end
                    end

                    do -- Claim Playtime Rewards
                        if tick() - LastRewardClaim > 5 then
                            for i = 1, 9 do
                                Functions.InvokeRemote("ClaimPlaytime", i)
                            end

                            LastRewardClaim = tick()
                        end
                    end

                    do -- Claim Quest Prizes
                        if tick() - LastPrizeClaim > 5 then
                            local Prizes = Functions.GetCompletedPrizes()

                            for _, Prize in pairs(Prizes) do
                                if Prize.Claimed then
                                    continue
                                end

                                Functions.FireRemote("ClaimPrize", Prize.Index)

                                wait(0.5)
                            end

                            LastPrizeClaim = tick()
                        end
                    end

                    do -- Auto Mystery Box
                        if tick() - LastMysteryBox > 5 then
                            local Items = Functions.GetItems()["Mystery Box"]

                            if Items then
                                Functions.FireRemote("UseGift", "Mystery Box", Items >= 10 and 10 or Items)
                            end

                            LastMysteryBox = tick()
                        end
                    end

                    do -- Claim Challenge Rewards
                        if tick() - LastChallengeReward > 5 then
                            Functions.FireRemote("ChallengePassClaimReward")

                            LastChallengeReward = tick()
                        end
                    end

                    do -- Claim Season Rewards
                        if tick() - LastSeasonReward > 3 then
                            Functions.FireRemote("ClaimSeason")

                            LastSeasonReward = tick()
                        end
                    end

                    do -- Wheel Spin
                        if tick() - LastWheelSpin > 10 then
                            Functions.FireRemote("ClaimFreeWheelSpin")

                            local SpinTickets = ClientData.Powerups["Spin Ticket"] or 0

                            if SpinTickets > 0 then
                                local FloatingIsland = Services.Workspace.Worlds["The Overworld"].Islands["Floating Island"]

                                Functions.TeleportToIsland(FloatingIsland)
                                wait(1)
                                Functions.FireRemote("Teleport", "Workspace.Worlds.The Overworld.Islands.Floating Island.Island.WheelSpin.Activation.Root")

                                repeat wait(1)
                                    Functions.InvokeRemote("WheelSpin")
                                    Functions.FireRemote("ClaimWheelSpinQueue")
                                until (ClientData.Powerups["Spin Ticket"] or 0) <= 0
                            end
                            
                            LastWheelSpin = tick()
                        end
                    end

                    do -- Claim Chests
                        if tick() - LastChestClaim > 10 then
                            local TimeNow = Services.Workspace:GetServerTimeNow()

                            if (Functions.GetCooldown("Giant Chest") - TimeNow) <= 0 then
                                local FloatingIsland = Services.Workspace.Worlds["The Overworld"].Islands["Floating Island"]

                                Functions.TeleportToObjectOnIsland(Vector3.new(12, 428, 156), FloatingIsland, true, function()
                                    return not Variables.StartStrategy or Variables.Unloaded or Variables.FarmingStrategy ~= Strategy
                                end, 35)

                                wait(1.5)

                                Functions.FireRemote("ClaimChest", "Giant Chest")
                            end

                            if (Functions.GetCooldown("Void Chest") - TimeNow) <= 0 then
                                local FloatingIsland = Services.Workspace.Worlds["The Overworld"].Islands["The Void"]

                                Functions.TeleportToObjectOnIsland(Vector3.new(74, 10148, 56), FloatingIsland, true, function()
                                    return not Variables.StartStrategy or Variables.Unloaded or Variables.FarmingStrategy ~= Strategy
                                end, 35)

                                wait(1.5)

                                Functions.FireRemote("ClaimChest", "Void Chest")
                            end

                            LastChestClaim = tick()
                        end
                    end

                    do -- Hatch Egg For Gem Pets
                        local AmountOfGemPets = {}

                        for _, Pet in pairs(ClientData.Pets) do
                            local PetsData = PetsData[Pet.Name]

                            if PetsData.Stats.Gems then
                                table.insert(AmountOfGemPets, Pet)
                            end
                        end

                        if #AmountOfGemPets < StatsUtil:GetMaxPetsEquipped(ClientData) and ClientData["Coins"] >= 1500000 then
                            local Egg, Price = Functions.GetMostExpensiveEgg(ClientData, true, {
                                ["Rainbow Egg"] = EggsData["Rainbow Egg"],
                                ["100M Egg"] = EggsData["100M Egg"],
                            })

                            local ShouldReturn = false

                            if Egg and Price then
                                local CanPurchaseAmount = math.floor(ClientData["Coins"] / Price)

                                for i = 1, (CanPurchaseAmount > 3 and 3 or CanPurchaseAmount) do
                                    local Response = Functions.HatchEgg(Egg, function()
                                        return not Variables.StartStrategy or Variables.Unloaded or Variables.FarmingStrategy ~= Strategy
                                    end)

                                    if Response == false then
                                        ShouldReturn = true
                                        break
                                    end
                                end

                                if ShouldReturn then
                                    continue
                                end
                            end
                        end
                    end

                    do -- Upgrades
                        local NextPets, NextPetsPrice = Functions.GetNextMasteryLevel("Pets")
                        
                        if NextPets and NextPets <= 10 then
                            if NextPetsPrice.Amount <= ClientData[NextPetsPrice.Currency] then
                                Functions.FireRemote("UpgradeMastery", "Pets")

                                continue
                            end

                            local Bubbles, Storage = Functions.GetBubbleData()
                            local _, HasInfinityGum = Functions.GetGumData()
                            
                            if not HasInfinityGum and Bubbles >= Storage then
                                Functions.SellAtBestZone(function()
                                    return not Variables.StartStrategy or Variables.Unloaded or Variables.FarmingStrategy ~= Strategy
                                end)
                            elseif tick() - LastBlow > 0.5 then
                                Functions.FireRemote("BlowBubble")
    
                                LastBlow = tick()
                            end

                            if tick() - LastStoragePurchase > 5 then
                                local Flavor, FlavorPrice = Functions.GetMostExpensiveFlavor()
                                local Gum, GumPrice = Functions.GetMostExpensiveGum()
    
                                local NextFlavor, NextFlavorPrice = Functions.GetNextPurchasable(FlavorsData, FlavorPrice)
                                local NextGum, NextGumPrice = Functions.GetNextPurchasable(GumData, GumPrice)
    
                                if NextFlavor then
                                    if ClientData[NextFlavorPrice.Currency] >= NextFlavorPrice.Amount then
                                        Functions.FireRemote("Teleport", "Workspace.Worlds.The Overworld.Shop.Root")
                                        wait(1)
                                        Functions.FireRemote("GumShopPurchase", NextFlavor)
                                    end
                                end
    
                                if NextGum then
                                    if ClientData[NextGumPrice.Currency] >= NextGumPrice.Amount then
                                        Functions.FireRemote("Teleport", "Workspace.Worlds.The Overworld.Shop.Root")
                                        wait(1)
                                        Functions.FireRemote("GumShopPurchase", NextGum)
                                    end
                                end
    
                                LastStoragePurchase = tick()
                            end

                            if tick() - LastBestEquip > 10 then
                                Functions.FireRemote("EquipBestPets")

                                LastBestEquip = tick()
                            end

                            if tick() - LastGoldenOrb > 5 then
                                if not Functions.IsGoldRushActive() then
                                    Functions.FireRemote("UseGoldenOrb")
                                end

                                LastGoldenOrb = tick()
                            end
                            
                            if Root.Position.Y < 15800 then
                                Functions.TeleportToIsland(Services.Workspace.Worlds["The Overworld"].Islands.Zen)
                            end

                            continue
                        end
                    end

                    do -- Hatch 2000 Eggs
                        if Functions.GetHatches() < 2000 then
                            if ClientData.Coins < 20000 then
                                if tick() - LastPotionUsage > 10 then
                                    local PotionType, BestPotion = Functions.GetBestPotionLevel("Coins")
        
                                    if (BestPotion and BestPotion > 0) and not Functions.IsUsingBetterPotion(PotionType, BestPotion) then
                                        Functions.FireRemote("UsePotion", PotionType, BestPotion)
                                    end
                                    
                                    LastPotionUsage = tick()
                                end

                                if Root.Position.Y < 15800 then
                                    Functions.TeleportToIsland(Services.Workspace.Worlds["The Overworld"].Islands.Zen)
                                end

                                continue
                            end

                            local PotionType1, BestSpeedPotion = Functions.GetBestPotionLevel("Speed")

                            if (BestSpeedPotion and BestSpeedPotion > 0) and not Functions.IsUsingBetterPotion(PotionType1, BestSpeedPotion) then
                                Functions.FireRemote("UsePotion", PotionType1, BestSpeedPotion)
                            end

                            -- local PotionType2, BestLuckyPotion = Functions.GetBestPotionLevel("Lucky")

                            -- if BestLuckyPotion and BestLuckyPotion > -1 and not Functions.IsUsingBetterPotion(PotionType2, -1) then
                            --     Functions.FireRemote("UsePotion", PotionType2, BestLuckyPotion)
                            -- end

                            local PotionType3, BestElixirPotion = Functions.GetBestPotionLevel("Infinity Elixir")

                            if BestElixirPotion and BestElixirPotion > -1 and not Functions.IsUsingBetterPotion(PotionType3, -1) then
                                Functions.FireRemote("UsePotion", PotionType3, BestElixirPotion)
                            end

                            for _, Pet in pairs(EggsData["Common Egg"].Pool) do
                                if ClientData.Discovered[Pet.Item.Name] then
                                    if not ClientData.AutoDelete[Pet.Item.Name] then
                                        Functions.FireRemote("ToggleAutoDelete", Pet.Item.Name)
                                    end
                                end
                            end

                            Functions.HatchEgg("Common Egg", function()
                                return not Variables.StartStrategy or Variables.Unloaded or Variables.FarmingStrategy ~= Strategy
                            end)

                            continue
                        end
                    end

                    -- workspace.Rendered.Rifts["royal-chest"]

                    do -- Activate Gold Orb
                        if tick() - LastGoldenOrb > 5 then
                            if not Functions.IsGoldRushActive() then
                                Functions.FireRemote("UseGoldenOrb")
                            end

                            LastGoldenOrb = tick()
                        end
                    end

                    do -- Farm Coins and Gems
                        if not ClientData.WorldsUnlocked["Minigame Paradise"] then
                            if Root.Position.Y < (TopIsland.Parent:GetAttribute("Height") - 30) then
                                Functions.TeleportToIsland(TopIsland.Parent)
                            end
                        
                            if not Functions.HasUnlockedIsland(TopIsland.Parent) then
                                Functions.TeleportToIsland(BottomIsland.Parent)
                                wait(0.5)
                                Root.CFrame = CFrame.new(
                                    Root.Position.X,
                                    TopIsland.Parent:GetAttribute("Height"),
                                    Root.Position.Z
                                )

                                Functions.TweenTeleport(Vector3.new(36, 15972, 42), function()
                                    return not Variables.StartStrategy or Variables.Unloaded or Variables.FarmingStrategy ~= Strategy
                                        or Functions.HasUnlockedIsland(TopIsland.Parent)
                                end, 35)
                            end

                            if tick() - LastPotionUsage > 10 then
                                local PotionType, BestPotion = Functions.GetBestPotionLevel("Coins")
    
                                if (BestPotion and BestPotion > 0) and not Functions.IsUsingBetterPotion(PotionType, BestPotion) then
                                    Functions.FireRemote("UsePotion", PotionType, BestPotion)
                                end
                                
                                LastPotionUsage = tick()
                            end

                            if tick() - LastBestEquip > 10 then
                                Functions.FireRemote("EquipBestPets")
    
                                LastBestEquip = tick()
                            end
                        end
                    end

                    do -- Upgrade Masteries
                        local Purchased = nil

                        if tick() - LastMasteryUpgrade > 5 then
                            local NextBuff, NextBuffPrice = Functions.GetNextMasteryLevel("Buffs")
                            local NextShop, NextShopPrice = Functions.GetNextMasteryLevel("Shops")

                            Purchased = false

                            if NextBuff and NextBuff <= 15 and NextBuffPrice.Amount <= ClientData[NextBuffPrice.Currency] then
                                Purchased = true

                                Functions.FireRemote("UpgradeMastery", "Buffs")
                            end

                            if NextShop and NextShopPrice.Amount <= ClientData[NextShopPrice.Currency] then
                                Purchased = true

                                Functions.FireRemote("UpgradeMastery", "Shops")
                            end

                            LastMasteryUpgrade = tick()
                        end

                        if Purchased ~= nil then
                            continue
                        end
                    end

                    do -- Purchase Second World
                        local OwnsNewWorld = ClientData.WorldsUnlocked["Minigame Paradise"]

                        if OwnsNewWorld and WorldUtil:GetPlayerWorld(LocalPlayer) ~= "Minigame Paradise" then
                            Functions.FireRemote("WorldTeleport", "Minigame Paradise")
                        elseif not OwnsNewWorld and ClientData.Coins >= 10000000000 then
                            Functions.FireRemote("UnlockWorld", "Minigame Paradise")

                            continue
                        end

                        local TopDiceIsland = Services.Workspace.Worlds["Minigame Paradise"].Islands["Robot Factory"]

                        if not Functions.HasUnlockedIsland(TopDiceIsland) then
                            Functions.UnlockAllIslands(Services.Workspace.Worlds["Minigame Paradise"], function()
                                return not Variables.StartStrategy or Variables.Unloaded or Variables.FarmingStrategy ~= Strategy
                            end)

                            continue
                        end

                        Functions.TeleportToIsland(TopDiceIsland)

                        if tick() - LastPotionUsage > 10 then
                            local PotionType, BestPotion = Functions.GetBestPotionLevel("Tickets")

                            if (BestPotion and BestPotion > 0) and not Functions.IsUsingBetterPotion(PotionType, BestPotion) then
                                Functions.FireRemote("UsePotion", PotionType, BestPotion)
                            end
                            
                            LastPotionUsage = tick()
                        end

                        if tick() - LastBestEquip > 10 then
                            Functions.FireRemote("EquipBestPets")

                            LastBestEquip = tick()
                        end

                        if tick() - LastClawMachine > 5 and ClientData.Tickets >= 250000000 then
                            wait(1.5)

                            Functions.FireRemote("StartMinigame", "Robot Claw", "Easy")
                    
                            local Found = false
                            local Start = tick()

                            repeat wait(0.5)
                                for _, Item in pairs(LocalPlayer.PlayerGui.ScreenGui:GetChildren()) do
                                    if Item.Name:find("ClawItem") then
                                        Found = true; break
                                    end
                                end
                            until Found or (tick() - Start > 5)

                            if Found then
                                wait(1)

                                for _, Item in pairs(LocalPlayer.PlayerGui.ScreenGui:GetChildren()) do
                                    if Item.Name:find("ClawItem") then
                                        local ItemId = Item.Name:gsub("ClawItem", "")
                                        Functions.FireRemote("GrabMinigameItem", ItemId)

                                        wait(6)
                                    end
                                end

                                Functions.FireRemote("FinishMinigame")
                            end

                            LastClawMachine = tick()
                        end

                        wait(0.5)
                    end
                end
            end
        end
    end
})

ComponentFunctions.CreateDropdown({
    Name = "Farming Strategy",
    Tab = "Strategies",
    Options = {"Maximize", "Potion", "Index", "Battlepass"},
    Default = "Maximize",
    Callback = function(value)
        Variables.FarmingStrategy = value
    end
})

ComponentFunctions.CreateInput({
    Name = "Helper Player",
    Tab = "Strategies",
    Default = Variables.Helper,
    Placeholder = "'@1234' or 'username'",
    Callback = function(value)
        local Username = value

        if string.sub(Username, 1, 1) == "@" then
            local UserId = string.sub(Username, 2)

            local Success, Response = pcall(function()
                Username = Services.Players:GetNameFromUserIdAsync(tonumber(UserId))
            end)

            if Success then
                Username = Response
            else
                return false, "Invalid User ID"
            end
        end

        Variables.Helper = Username

        return true, "Helper set to " .. Username
    end
})

ComponentFunctions.CreateToggle({
    Name = "Auto Accept Trade",
    Tab = "Strategies",
    Default = Variables.AutoAcceptTrade,
    Callback = function(value)
        Variables.AutoAcceptTrade = value
    end
})

ComponentFunctions.CreateToggle({
    Name = "Disable 3D Rendering",
    Tab = "Miscellaneous",
    IndexOrder = 3,
    Default = Config.Disable3DRendering,
    Callback = function(value)
        Config.Disable3DRendering = value
        Services.RunService:Set3dRenderingEnabled(not value)
    end
})

ComponentFunctions.CreateToggle({
    Name = "Rejoin On Kick",
    Tab = "Miscellaneous",
    Default = Config.RejoinOnKick,
    Callback = function(value)
        Config.RejoinOnKick = value
    end
})

ComponentFunctions.CreateInput({
    Name = "FPS Cap",
    Tab = "Miscellaneous",
    Default = Config.FPS_Cap,
    Placeholder = "30",
    Callback = function(value)
        Config.FPS_Cap = value

        local Success, Response = pcall(function()
            setfpscap(tonumber(value))
        end)

        if Success then
            return "Set max FPS to " .. tostring(value)
        else
            return false, "Something went wrong when changing max FPS. Error: " .. tostring(Response)
        end
    end
})

ComponentFunctions.CreateInput({
    Name = "Join Job ID",
    Tab = "Miscellaneous",
    Callback = function(value)
        if value == game.JobId and string.sub(value, 1, 1) ~= "." then
            return
        end

        local JobId = (value == ".") and game.JobId or value

        Services.TeleportService:TeleportToPlaceInstance(game.PlaceId, JobId)
    end
})

--<< INITIALIZE WEBSOCKET >>--

WebSocketFunctions.AddWebSocketAction("execute_code", function(Data)
    if not Data.code then return end

    local Success, Response = pcall(function()
        return loadstring(Data.code)()
    end)

    if not Success then
        print("Error executing code:", Response)
    end
end)

WebSocketFunctions.AddWebSocketAction("execute_command", function(Data)
    local Command, Arguments = CommandFunctions.FilterCommandMessage(Data.Command)

    if not Command then
        return WebSocketFunctions.SendCommandResult(
            "Command not found",
            false,
            "Attempted command: " .. tostring(Data.Command)
        )
    end

    if Command.Parameters and #Arguments < #Command.Parameters then
        return WebSocketFunctions.SendCommandResult(
            "Missing Parameters",
            false,
            "Required parameters: " .. table.concat(Command.Parameters, ", ")
        )
    end

    local Success, Response, Optional = CommandFunctions.ExecuteCommand(Command, Arguments)
    local Message = Optional or Response

    if Success and type(Response) == "boolean" then
        Success = Response
    end

    return WebSocketFunctions.SendCommandResult(
        Command.Name,
        Success,
        Message
    )
end)

WebSocketFunctions.AddWebSocketAction("update_clients", function(Data)
    if not Data or not Data.Clients then return end

    Variables.OtherClients = Data.Clients
    Variables.OtherClientPlayers = {}

    for _, v in ipairs(Variables.OtherClients) do
        if v ~= LocalPlayer.Name then
            table.insert(Variables.OtherClientPlayers, Services.Players:FindFirstChild(v))
        end
    end
end)

WebSocketFunctions.AddWebSocketAction("connection_confirmed", function(Data)
    Variables.IsConnected = true

    WebSocketFunctions.SendData({
        Action = "update_clients"
    })
end)

WebSocketFunctions.AddWebSocketAction("get_bot_status", function(Data)
    WebSocketFunctions.SendClientData()
end)

WebSocketFunctions.AddWebSocketAction("update_toggle_state", function(Data)
    if not Data or not Data.Name or not Data.Tab then
        warn("Invalid component data: " .. table.concat(Data, ", "))
        return
    end

    ComponentFunctions.UpdateComponentState(Data.Name, Data.Tab, Data.Value)
end)

WebSocketFunctions.AddWebSocketAction("heartbeat", function(Data)
    
end)

WebSocketFunctions.Connect()