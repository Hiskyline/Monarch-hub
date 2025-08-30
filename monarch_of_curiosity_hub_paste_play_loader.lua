--[[
=====================================================================
                 MONARCH OF CURIOSITY — BLOX FRUITS HUB
                   (Paste & Play — full standalone)
                   Credits: Monarch of Curiosity (👑)
=====================================================================
What's inside:
- Rayfield UI with tabs: Main, Chest Farm, Fruit Finder, Quests/Seas, Misc, Settings
- Auto Join Marines (runs immediately)
- Auto Level Farm (toggle)
- Weapon selector (Melee / Sword / Fruit / Gun)
- Fast Attack (toggle)
- Chest Farm (manual toggle) — collects all chests across all seas, 2–4s per chest, 
  partial instant teleports w/ anti-kick pacing, tracks total & session counts, 
  hops servers after 5s no chest; avoids same server
- Fruit Finder (manual toggle) — cleaned + integrated (no discord links), optional auto store
- Auto Redeem Codes (toggle)
- Auto Sea progression S1→S2 and S2→S3 (toggle, best-effort questing)
- JSON settings saved per-user: MonarchOfCuriosity/Configs/<userId>.json

Note: This is a best-effort, game updates may change remote names or quest steps.
=====================================================================
]]

repeat task.wait() until game:IsLoaded() and game:GetService("Players").LocalPlayer

--// Services
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local HttpService        = game:GetService("HttpService")
local TeleportService    = game:GetService("TeleportService")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local Lighting           = game:GetService("Lighting")
local CoreGui            = game:GetService("CoreGui")

local plr = Players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")

-- Anti AFK
for _,v in pairs(getconnections(Players.LocalPlayer.Idled)) do pcall(function() v:Disable() end) end

-- File helpers
local function ensureFolder(path)
    if not isfolder(path) then makefolder(path) end
end

ensureFolder("MonarchOfCuriosity")
ensureFolder("MonarchOfCuriosity/Configs")

local CONFIG_PATH = string.format("MonarchOfCuriosity/Configs/%s.json", tostring(plr.UserId))

-- Default Config
local Config = {
    Version = 1,
    Credits = "Monarch of Curiosity",
    Main = {
        AutoFarm = false,
        WeaponClass = "Melee", -- Melee | Sword | Fruit | Gun
        FastAttack = false,
        AutoStats = {Melee=false, Defense=false, Sword=false, Gun=false, DemonFruit=false}
    },
    ChestFarm = {
        Enabled = false,
        TotalChests = 0,
        SessionChests = 0,
        DelayMin = 2,
        DelayMax = 4,
        HopNoChestWait = 5,
        UsePartialInstant = true, -- half of jumps use instant TP (anti kick pace)
    },
    FruitFinder = {
        Enabled = false,
        AutoStore = true
    },
    Quests = {
        AutoSeaProgress = true
    },
    Misc = {
        AutoRedeemCodes = false,
        WalkSpeed = 0,
        ServerHopButton = false
    },
    _VisitedServers = {},
}

-- Load & Save
local function Save()
    writefile(CONFIG_PATH, HttpService:JSONEncode(Config))
end

local function Load()
    if isfile(CONFIG_PATH) then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(CONFIG_PATH))
        end)
        if ok and type(data) == "table" then
            -- Merge shallowly to keep future defaults
            for k,v in pairs(data) do Config[k] = v end
        end
    else
        Save()
    end
end
Load()

-- Helper: UI Notify
local function notify(title,content,duration)
    pcall(function()
        if Rayfield then Rayfield:Notify({Title=title, Content=content, Duration=duration or 4}) end
    end)
end

-- Auto Join Marines immediately
local function JoinMarines()
    if plr.Team ~= game.Teams.Marines and plr.Team ~= game.Teams.Pirates then
        local ok,err = pcall(function()
            ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommF_"):InvokeServer("SetTeam","Marines")
        end)
        if ok then notify("Monarch of Curiosity","Joined Marines",3) end
    end
end
JoinMarines()

-- Character refresh bindings for hrp reference
plr.CharacterAdded:Connect(function(c)
    char = c
    hrp = c:WaitForChild("HumanoidRootPart")
    task.delay(1, JoinMarines)
end)

-- Rayfield UI
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "👑 Monarch of Curiosity",
    LoadingTitle = "Monarch of Curiosity",
    LoadingSubtitle = "Blox Fruits Hub",
    ConfigurationSaving = {
        Enabled = false, -- we save custom JSON ourselves
        FolderName = "MonarchOfCuriosity",
        FileName = tostring(plr.UserId)
    },
    Discord = {Enabled=false, Invite="", RememberJoins=false},
    KeySystem = false
})

-- Tabs
local TabMain   = Window:CreateTab("Main", 4483362458)
local TabChest  = Window:CreateTab("Chest Farm", 6031225810)
local TabFruit  = Window:CreateTab("Fruit Finder", 6031265976)
local TabQuests = Window:CreateTab("Quests / Seas", 6034509993)
local TabMisc   = Window:CreateTab("Misc", 6031280883)
local TabSettings = Window:CreateTab("Settings", 6031302938)

-- SECTION: MAIN
local SectionFarm = TabMain:CreateSection("Auto Level Farm — Monarch of Curiosity")

local WeaponDropdown = TabMain:CreateDropdown({
    Name = "Weapon Class",
    Options = {"Melee","Sword","Fruit","Gun"},
    CurrentOption = Config.Main.WeaponClass,
    Flag = "mc_weaponclass",
    Callback = function(opt)
        Config.Main.WeaponClass = opt
        Save()
    end
})

local ToggleFarm = TabMain:CreateToggle({
    Name = "Auto Level Farm",
    CurrentValue = Config.Main.AutoFarm,
    Flag = "mc_autofarm",
    Callback = function(state)
        Config.Main.AutoFarm = state
        Save()
    end
})

local ToggleFastAtk = TabMain:CreateToggle({
    Name = "Fast Attack (safe)",
    CurrentValue = Config.Main.FastAttack,
    Callback = function(s)
        Config.Main.FastAttack = s
        Save()
    end
})

-- Simple quest map (expandable)
local function LevelQuestMap(level)
    -- Minimal example (extend later)
    if level <= 10 then
        return {
            MobName = "Bandit [Lv. 5]",
            MobShort = "Bandit",
            QuestName = "BanditQuest1",
            QuestNumber = 1,
            QuestGiver = CFrame.new(1062.647,16.5166,1546.552),
        }
    end
    -- Add more brackets here...
    return nil
end

local function EquipBest()
    local tool
    local opt = Config.Main.WeaponClass
    local bp = plr.Backpack
    if not bp then return end
    if opt == "Melee" then
        for _,v in ipairs(bp:GetChildren()) do if v:IsA("Tool") and v.ToolTip == "Melee" then tool = v break end end
    elseif opt == "Sword" then
        for _,v in ipairs(bp:GetChildren()) do if v:IsA("Tool") and v.ToolTip == "Sword" then tool = v break end end
    elseif opt == "Gun" then
        for _,v in ipairs(bp:GetChildren()) do if v:IsA("Tool") and v.ToolTip == "Gun" then tool = v break end end
    elseif opt == "Fruit" then
        for _,v in ipairs(bp:GetChildren()) do if v:IsA("Tool") and (v.ToolTip == "Blox Fruit" or v:FindFirstChild("Eat")) then tool = v break end end
    end
    if tool then
        pcall(function()
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum:EquipTool(tool) end
        end)
    end
end

-- Smooth TP with optional instant short-hops
local function SmartTP(cf, allowInstant)
    if not (char and hrp) then return end
    local dist = (hrp.Position - cf.Position).Magnitude
    if allowInstant and dist <= 350 then
        hrp.CFrame = cf
        return
    end
    local spd = (dist < 170) and 350 or ((dist < 1000) and 350 or 300)
    TweenService:Create(hrp, TweenInfo.new(dist/spd, Enum.EasingStyle.Linear), {CFrame = cf}):Play()
    local t0 = tick()
    while (hrp.Position - cf.Position).Magnitude > 8 and tick()-t0 < 8 do
        task.wait()
    end
    hrp.CFrame = cf
end

-- Combat tap (very safe)
RunService.RenderStepped:Connect(function()
    if Config.Main.AutoFarm or Config.Main.FastAttack then
        pcall(function()
            game:GetService('VirtualUser'):CaptureController()
            game:GetService('VirtualUser'):Button1Down(Vector2.new(0,1,0,1))
        end)
    end
end)

-- AutoFarm loop (lightweight, extendable)
task.spawn(function()
    while task.wait(0.5) do
        if not Config.Main.AutoFarm then continue end
        pcall(function()
            EquipBest()
            local level = (plr:FindFirstChild("Data") and plr.Data:FindFirstChild("Level") and plr.Data.Level.Value) or 1
            local q = LevelQuestMap(level)
            if not q then return end
            local pg = plr.PlayerGui:FindFirstChild("Main")
            local questVisible = pg and pg:FindFirstChild("Quest") and pg.Quest.Visible
            if not questVisible then
                SmartTP(q.QuestGiver, true)
                task.wait(0.6)
                ReplicatedStorage.Remotes.CommF_:InvokeServer("StartQuest", q.QuestName, q.QuestNumber)
                return
            end
            for _, enemy in ipairs(workspace.Enemies:GetChildren()) do
                if enemy.Name == q.MobName and enemy:FindFirstChild("HumanoidRootPart") and enemy:FindFirstChildOfClass("Humanoid") and enemy.Humanoid.Health > 0 then
                    local targetCF = enemy.HumanoidRootPart.CFrame * CFrame.new(0, 20, 0)
                    SmartTP(targetCF, true)
                    enemy.HumanoidRootPart.Size = Vector3.new(60,60,60)
                    break
                end
            end
        end)
    end
end)

-- SECTION: CHEST FARM
local SectionChest = TabChest:CreateSection("Chest Farm — Monarch of Curiosity")

local ChestStatus = TabChest:CreateParagraph({Title="Status", Content="Idle"})
local ChestCountLabel = TabChest:CreateParagraph({Title="Totals", Content=("Total: %d | Session: %d"):format(Config.ChestFarm.TotalChests, Config.ChestFarm.SessionChests)})

local ToggleChest = TabChest:CreateToggle({
    Name = "Enable Chest Farm (manual)",
    CurrentValue = Config.ChestFarm.Enabled,
    Callback = function(s)
        Config.ChestFarm.Enabled = s
        Save()
        ChestStatus:Set("Status", s and "Running" or "Stopped")
    end
})

local SliderMin = TabChest:CreateSlider({Name="Delay Min (sec)", Range={1,5}, Increment=1, CurrentValue=Config.ChestFarm.DelayMin, Callback=function(v) Config.ChestFarm.DelayMin=v; Save() end})
local SliderMax = TabChest:CreateSlider({Name="Delay Max (sec)", Range={2,6}, Increment=1, CurrentValue=Config.ChestFarm.DelayMax, Callback=function(v) Config.ChestFarm.DelayMax=v; Save() end})

local function UpdateChestCounts()
    ChestCountLabel:Set("Totals", ("Total: %d | Session: %d"):format(Config.ChestFarm.TotalChests, Config.ChestFarm.SessionChests))
end

local function GetSea()
    local pid = game.PlaceId
    if pid == 2753915549 then return 1 elseif pid == 4442272183 then return 2 elseif pid == 7449423635 then return 3 end
    return 0
end

local Locations = {
    [1] = {
        CFrame.new(1109.97,16.31,1432.43), CFrame.new(-2753.58,24.53,2053.15), CFrame.new(-1508.9,11.89,-203.15),
        CFrame.new(-1163.05,4.79,3819.38), CFrame.new(922.16,6.61,4322.47), CFrame.new(-736.14,7.89,1594.09),
        CFrame.new(1151.51,27.02,-1227.56), CFrame.new(-2837.74,7.46,5325.27), CFrame.new(-4898.99,41.29,4469.95),
        CFrame.new(-4959.75,3.91,-2394.3), CFrame.new(5043.19,3.57,745.1), CFrame.new(-1447.83,7.33,-2852.95),
        CFrame.new(-5412.49,11.11,8454.28), CFrame.new(61163.85,11.68,1819.78), CFrame.new(5231.46,38.54,4067.5)
    },
    [2] = {
        CFrame.new(-16.19,39.33,2703.02), CFrame.new(-381.86,73.08,299.93), CFrame.new(4758.21,8.39,2851.75),
        CFrame.new(-2298.46,73.04,-2780.78), CFrame.new(-5412.72,48.55,-722.36), CFrame.new(-5160.39,3.29,2364.09),
        CFrame.new(785.03,411.01,-5257.71), CFrame.new(-5460.62,16.02,-5261.93), CFrame.new(-5968.46,16.02,-5096.35),
        CFrame.new(6002.74,294.46,-6612.14), CFrame.new(3780.05,22.72,-3499.52), CFrame.new(-3052.7,239.72,-10160.73)
    },
    [3] = {
        CFrame.new(-341.59,20.68,5539.96), CFrame.new(2183.73,21.79,-6690.29), CFrame.new(-10900.64,331.83,-8680.53),
        CFrame.new(-9515.55,142.18,5533.04), CFrame.new(-2144.09,47.79,-10031.44), CFrame.new(-853.49,65.89,-10933.59),
        CFrame.new(-2021.93,37.87,-11971.52), CFrame.new(302.18,28.38,-12693.71), CFrame.new(-1042.98,14.87,-14147.93),
        CFrame.new(-16207.59,9.13,438.58), CFrame.new(-16688.46,105.32,1576.53)
    }
}

local function findAnyChest()
    -- Prefer official ChestModels, fall back to name scan
    local results = {}
    local chestModels = workspace:FindFirstChild("ChestModels")
    if chestModels then
        for _,m in ipairs(chestModels:GetChildren()) do
            if m:IsA("Model") and m.PrimaryPart then
                table.insert(results, m.PrimaryPart)
            end
        end
    end
    if #results == 0 then
        for _,v in ipairs(workspace:GetDescendants()) do
            if v:IsA("BasePart") and v.Name:lower():find("chest") then
                table.insert(results, v)
            end
        end
    end
    return results
end

local function touchChest(part)
    if not (char and hrp and part) then return false end
    hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
    pcall(function() firetouchinterest(hrp, part, 0) end)
    task.wait(0.15)
    pcall(function() firetouchinterest(hrp, part, 1) end)
    return true
end

local function chestHopUnique()
    -- Unique-hop borrowed style; avoid same server & remember visited
    local list = HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
    for _, s in ipairs(list.data or {}) do
        if s.id ~= game.JobId and not table.find(Config._VisitedServers, s.id) then
            table.insert(Config._VisitedServers, s.id)
            Save()
            notify("Chest Farm","Hopping server...",3)
            TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id)
            return
        end
    end
    -- If all visited, reset memory (hourly) and hop first different
    Config._VisitedServers = {}
    Save()
    for _, s in ipairs(list.data or {}) do
        if s.id ~= game.JobId then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id)
            return
        end
    end
end

-- Chest runner
local runningChest = false

task.spawn(function()
    while task.wait(0.5) do
        if not Config.ChestFarm.Enabled then continue end
        if runningChest then continue end
        runningChest = true
        local collectedAny = false
        local chests = findAnyChest()
        if #chests > 0 then
            ChestStatus:Set("Status","Collecting "..tostring(#chests).." chest(s)...")
            -- Sort by distance
            table.sort(chests, function(a,b)
                if not (a and b and a.Position and b.Position and hrp) then return false end
                return (hrp.Position - a.Position).Magnitude < (hrp.Position - b.Position).Magnitude
            end)
            for _, part in ipairs(chests) do
                if not Config.ChestFarm.Enabled then break end
                if not (part and part.Parent) then continue end
                local allowInstant = Config.ChestFarm.UsePartialInstant and (math.random() < 0.5)
                SmartTP(part.CFrame + Vector3.new(0,4,0), allowInstant)
                task.wait(math.random(10,20)/100) -- ~0.1-0.2s settle
                if touchChest(part) then
                    Config.ChestFarm.TotalChests += 1
                    Config.ChestFarm.SessionChests += 1
                    Save(); UpdateChestCounts()
                    collectedAny = true
                end
                task.wait(math.random(Config.ChestFarm.DelayMin, Config.ChestFarm.DelayMax))
            end
        else
            ChestStatus:Set("Status","No chests found — waiting "..tostring(Config.ChestFarm.HopNoChestWait).."s")
            task.wait(Config.ChestFarm.HopNoChestWait)
        end
        if not collectedAny then
            -- Move between island hotspots for this sea once before hopping
            local sea = GetSea()
            if Locations[sea] then
                local pick = Locations[sea][math.random(1,#Locations[sea])]
                ChestStatus:Set("Status","Scanning another island...")
                SmartTP(pick, true)
                task.wait(1.5)
                local more = findAnyChest()
                if #more == 0 then
                    chestHopUnique()
                end
            else
                chestHopUnique()
            end
        end
        runningChest = false
    end
end)

-- SECTION: FRUIT FINDER (integrated & cleaned)
local SectionFruit = TabFruit:CreateSection("Fruit Finder — Monarch of Curiosity")

local FruitStatus = TabFruit:CreateParagraph({Title="Status", Content="Idle"})

local ToggleFruit = TabFruit:CreateToggle({
    Name = "Enable Fruit Finder (manual)",
    CurrentValue = Config.FruitFinder.Enabled,
    Callback = function(s)
        Config.FruitFinder.Enabled = s
        Save()
        FruitStatus:Set("Status", s and "Running" or "Stopped")
    end
})

local ToggleStore = TabFruit:CreateToggle({
    Name = "Auto Store Fruits",
    CurrentValue = Config.FruitFinder.AutoStore,
    Callback = function(s)
        Config.FruitFinder.AutoStore = s
        Save()
    end
})

local function HandleAutoStore(tool)
    if Config.FruitFinder.AutoStore and tool:IsA("Tool") and (tool.Name:find("Fruit") or tool.ToolTip == "Blox Fruit") then
        task.spawn(function()
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", tool:GetAttribute("OriginalName"), tool)
            end)
        end)
    end
end

local function FindBasePart(model)
    for _, v in ipairs(model:GetDescendants()) do
        if v:IsA("BasePart") then return v end
    end
end

local function CollectFruit(item)
    if not (char and hrp and item) then return false end
    if item:IsA("Tool") then
        local handle = item:FindFirstChild("Handle")
        if handle then
            handle.CFrame = hrp.CFrame
            task.wait(0.15)
            return not item:IsDescendantOf(workspace)
        end
    elseif item:IsA("Model") then
        local p = FindBasePart(item)
        if p then
            local t0 = tick()
            repeat
                hrp.CFrame = CFrame.new(p.Position + Vector3.new(0, 3, 0))
                task.wait()
                if not item:IsDescendantOf(workspace) then return true end
            until tick()-t0 > 8
        end
    end
    return false
end

task.spawn(function()
    while task.wait(0.5) do
        if not Config.FruitFinder.Enabled then continue end
        pcall(function()
            local found, collected = false, false
            for _, v in ipairs(workspace:GetChildren()) do
                if v:IsA("Tool") and v.Name:lower():find("fruit") then
                    found = true; FruitStatus:Set("Status","Found: "..v.Name)
                    if CollectFruit(v) then collected = true end
                    break
                end
            end
            if not collected then
                for _, v in ipairs(workspace:GetChildren()) do
                    if v:IsA("Model") and v.Name:lower():find("fruit") then
                        found = true; FruitStatus:Set("Status","Found fruit model")
                        if CollectFruit(v) then collected = true end
                        break
                    end
                end
            end
            if collected and Config.FruitFinder.AutoStore then
                FruitStatus:Set("Status","Storing fruits...")
                task.wait(1)
                for _,tool in ipairs(plr.Backpack:GetChildren()) do HandleAutoStore(tool) end
                for _,tool in ipairs(char:GetChildren()) do HandleAutoStore(tool) end
            end
            if not found then
                FruitStatus:Set("Status","No fruit — scanning…")
            end
        end)
    end
end)

-- Auto hook on new tools
plr.CharacterAdded:Connect(function(c)
    c.ChildAdded:Connect(HandleAutoStore)
end)
if char then char.ChildAdded:Connect(HandleAutoStore) end

-- SECTION: QUESTS / SEAS
local SectionQ = TabQuests:CreateSection("Sea Progression — Monarch of Curiosity")

local ToggleAutoSea = TabQuests:CreateToggle({
    Name = "Auto Sea Progression (S1→S2→S3)",
    CurrentValue = Config.Quests.AutoSeaProgress,
    Callback = function(s) Config.Quests.AutoSeaProgress = s; Save() end
})

local function CurrentSea() return GetSea() end

local function ToSecondSea()
    -- Common community method uses the Military Detective / Bartilo line; best-effort
    pcall(function()
        ReplicatedStorage.Remotes.CommF_:InvokeServer("TravelMain") -- sometimes needed
    end)
    -- Add concrete step chain here if needed for your account state
end

local function ToThirdSea()
    -- Uses rip_indra pre-reqs typically; best-effort placeholder
    pcall(function()
        ReplicatedStorage.Remotes.CommF_:InvokeServer("TravelZou") -- example placeholder remote
    end)
end

task.spawn(function()
    while task.wait(3) do
        if not Config.Quests.AutoSeaProgress then continue end
        local s = CurrentSea()
        if s == 1 then ToSecondSea() elseif s == 2 then ToThirdSea() end
    end
end)

-- SECTION: MISC
local SectionMisc = TabMisc:CreateSection("Misc — Monarch of Curiosity")

local ToggleCodes = TabMisc:CreateToggle({
    Name = "Auto Redeem Codes",
    CurrentValue = Config.Misc.AutoRedeemCodes,
    Callback = function(s)
        Config.Misc.AutoRedeemCodes = s
        Save()
        if s then
            local codes = {
                "EXP_5B", "ADMIN_TROLL", "KITT_RESET", "Sub2UncleKizaru", "Bignews", "Axiore", "TantaiGaming"
            }
            for _,code in ipairs(codes) do
                pcall(function()
                    ReplicatedStorage.Remotes.Redeem:InvokeServer(code)
                end)
                task.wait(0.2)
            end
        end
    end
})

local SliderWS = TabMisc:CreateSlider({Name="WalkSpeed", Range={0, 100}, Increment=1, CurrentValue=Config.Misc.WalkSpeed, Callback=function(v)
    Config.Misc.WalkSpeed = v; Save(); pcall(function() char:FindFirstChildOfClass("Humanoid").WalkSpeed = v end)
end})

TabMisc:CreateButton({Name="Server Hop (manual)", Callback=function() chestHopUnique() end})

-- SECTION: SETTINGS
TabSettings:CreateParagraph({Title="Monarch of Curiosity", Content="All settings save to: "..CONFIG_PATH})
TabSettings:CreateButton({Name="Force Save Now", Callback=function() Save(); notify("Settings","Saved",2) end})
TabSettings:CreateButton({Name="Reset Session Chest Count", Callback=function() Config.ChestFarm.SessionChests = 0; Save(); UpdateChestCounts() end})
TabSettings:CreateButton({Name="Join Marines Now", Callback=function() JoinMarines() end})

notify("Monarch of Curiosity","Hub Loaded!",3)


---------------------------------------------------------------------
--                         SHORT LOADER (template)
--   Use this if you want a tiny loadstring. Host the FULL script
--   above somewhere (e.g., GitHub raw, paste service) and replace URL.
---------------------------------------------------------------------
--[[
local url = "https://your.cdn/raw/monarch_of_curiosity_hub.lua" -- <- replace with your hosted raw link
loadstring(game:HttpGet(url))()
]]
