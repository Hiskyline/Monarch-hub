--// Monarch of Curiosity Hub
--// Single-file UI Hub using Rayfield
--// Features: Auto-Join Marines, Auto Level Farm, Chest Farm (with Server Hop), Fruit Finder (Webhook+Auto Store), Settings Save/Load
--// Credits: Monarch of Curiosity

--[[
  HOW TO USE (Paste & Play):
  - Put this entire file on a gist or GitHub raw, then execute:
        loadstring(game:HttpGet("https://your-host/MonarchHub.lua"))()
  - OR paste this whole file directly in your executor.
]]]

-- === Preflight ===
repeat task.wait() until game:IsLoaded() and game:GetService("Players").LocalPlayer
local Players, ReplicatedStorage, TweenService, HttpService, TeleportService, RunService =
    game:GetService("Players"),
    game:GetService("ReplicatedStorage"),
    game:GetService("TweenService"),
    game:GetService("HttpService"),
    game:GetService("TeleportService"),
    game:GetService("RunService")

local plr = Players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")

-- Anti-Idle
for _,v in pairs(getconnections(plr.Idled)) do
    pcall(function() v:Disable() end)
end

-- === Persistent Storage ===
local SETTINGS_FILE = "monarch_settings.json"
local PROGRESS_FILE = "monarch_progress.json"

local Settings = {
    UI_Theme = "Default",
    Webhook = "",
    AutoJoinMarines = true,

    AutoFarm = false,
    FastAttack = false,
    PreferredWeapon = "",

    ChestFinder = false,
    ChestInstantRatio = 0.5,    -- 50% instant TP, 50% tween
    ChestDelayMin = 2,
    ChestDelayMax = 4,
    ChestWaitBeforeHop = 5,
    ServerHopCooldown = 5,      -- seconds between hops when decided

    FruitFinder = false,
    AutoStoreFruit = true,
}

local Progress = {
    TotalChests = 0,
    VisitedServers = {},
    LastServerPlaceId = 0
}

local function SaveJSON(path, tbl)
    local ok, data = pcall(function() return HttpService:JSONEncode(tbl) end)
    if ok then
        writefile(path, data)
    end
end
local function LoadJSON(path, fallback)
    if isfile(path) then
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(readfile(path))
        end)
        if ok and type(decoded)=="table" then return decoded end
    end
    return fallback
end

Settings = LoadJSON(SETTINGS_FILE, Settings)
Progress = LoadJSON(PROGRESS_FILE, Progress)

local function SaveSettings() SaveJSON(SETTINGS_FILE, Settings) end
local function SaveProgress() SaveJSON(PROGRESS_FILE, Progress) end

-- ensure visited set fresh if we changed place
if Progress.LastServerPlaceId ~= game.PlaceId then
    Progress.VisitedServers = {}
    Progress.LastServerPlaceId = game.PlaceId
    SaveProgress()
end

-- === Utilities ===
local function Notify(msg)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {Title="Monarch of Curiosity", Text=tostring(msg), Duration=4})
    end)
end

local function Distance(a, b) return (a - b).Magnitude end

local function SoftTeleport(cf)
    -- gradual movement to reduce kicks
    local distance = Distance(hrp.Position, cf.Position)
    local speed = 300
    local t = math.clamp(distance / speed, 0.2, 3.0)
    local ti = TweenInfo.new(t, Enum.EasingStyle.Linear)
    local tween = TweenService:Create(hrp, ti, {CFrame = cf})
    tween:Play()
    tween.Completed:Wait()
end

local function InstantTeleport(cf)
    hrp.CFrame = cf
end

local function TouchPart(part)
    if not part then return end
    pcall(function()
        firetouchinterest(hrp, part, 0)
        task.wait(0.15)
        firetouchinterest(hrp, part, 1)
    end)
end

-- === Auto Join Marines (on boot) ===
local function JoinMarines()
    if plr.Team ~= game.Teams.Marines and plr.Team ~= game.Teams.Pirates then
        pcall(function()
            ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommF_"):InvokeServer("SetTeam", "Marines")
        end)
    end
end
if Settings.AutoJoinMarines then
    JoinMarines()
end
plr.CharacterAdded:Connect(function(nc)
    char = nc
    hrp = char:WaitForChild("HumanoidRootPart")
    if Settings.AutoJoinMarines then task.delay(0.5, JoinMarines) end
end)

-- === Rayfield UI ===
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "👑 Monarch of Curiosity",
    LoadingTitle = "Monarch of Curiosity",
    LoadingSubtitle = "by Monarch of Curiosity",
    ConfigurationSaving = {
        Enabled = false
    },
    Discord = { Enabled = false },
    KeySystem = false
})

-- Tabs
local Home = Window:CreateTab("Home", 4483362458)
local Farm = Window:CreateTab("Auto Farm", 4483362458)
local Chest = Window:CreateTab("Chest Finder", 4483362458)
local Fruit = Window:CreateTab("Fruit Finder", 4483362458)
local SettingsTab = Window:CreateTab("Settings", 4483362458)
local Credits = Window:CreateTab("Credits", 4483362458)

-- Home
Home:CreateLabel("Welcome to Monarch of Curiosity 👑")
Home:CreateParagraph({Title="Tip", Content="Toggle features per tab. Settings are saved locally in monarch_settings.json"})

-- === Auto Farm (Level) ===

-- Quest Table (compact coverage; extend as needed)
local QuestDB = {
    -- First Sea
    {min=0,   max=10,  mob="Bandit [Lv. 5]", quest="BanditQuest1", qId=1, qPos=CFrame.new(1060,17,1547), farmHeight=18},
    {min=10,  max=30,  mob="Monkey [Lv. 14]", quest="JungleQuest", qId=1, qPos=CFrame.new(-1600,37,152), farmHeight=18},
    {min=30,  max=60,  mob="Gorilla [Lv. 20]", quest="JungleQuest", qId=2, qPos=CFrame.new(-1600,37,152), farmHeight=18},
    {min=60,  max=90,  mob="Desert Bandit [Lv. 60]", quest="DesertQuest", qId=1, qPos=CFrame.new(1094,7,4232), farmHeight=18},
    {min=90,  max=120, mob="Desert Officer [Lv. 70]", quest="DesertQuest", qId=2, qPos=CFrame.new(1094,7,4232), farmHeight=18},
    -- (add more as needed)
    -- Second Sea sample
    {min=700, max=850, mob="Marine Captain [Lv. 900]", quest="MarineQuest3", qId=1, qPos=CFrame.new(-2841,475,2110), farmHeight=30},
    -- Third Sea sample
    {min=1500, max=1600, mob="Pirate Millionaire [Lv. 1525]", quest="PiratePortQuest", qId=2, qPos=CFrame.new(-342,74,5538), farmHeight=30},
}

local function GetQuestForLevel(lv)
    for _,q in ipairs(QuestDB) do
        if lv >= q.min and lv <= q.max then return q end
    end
    -- fallback: nil
end

local CurrentWeapon = Settings.PreferredWeapon
local function SetWeapon(name) CurrentWeapon = name or "" Settings.PreferredWeapon = CurrentWeapon SaveSettings() end

local function EquipWeapon()
    if CurrentWeapon == "" then return end
    local tool = plr.Backpack:FindFirstChild(CurrentWeapon) or (plr.Character and plr.Character:FindFirstChild(CurrentWeapon))
    if tool and tool:IsA("Tool") then
        tool.Parent = plr.Character
    end
end

local AutoFarmToggle = Farm:CreateToggle({
    Name = "Auto Farm (Levels)",
    CurrentValue = Settings.AutoFarm,
    Flag = "AutoFarmToggle",
    Callback = function(val)
        Settings.AutoFarm = val
        SaveSettings()
    end
})
local FastAttackToggle = Farm:CreateToggle({
    Name = "Fast Attack",
    CurrentValue = Settings.FastAttack,
    Callback = function(val)
        Settings.FastAttack = val
        SaveSettings()
    end
})

local WeaponDropdown = Farm:CreateDropdown({
    Name = "Preferred Weapon",
    Options = {},
    CurrentOption = Settings.PreferredWeapon ~= "" and {Settings.PreferredWeapon} or {},
    Callback = function(opt)
        if type(opt)=="table" then opt = opt[1] end
        SetWeapon(opt)
    end
})

local function RefreshWeapons()
    local opts = {}
    for _,v in ipairs(plr.Backpack:GetChildren()) do
        if v:IsA("Tool") then table.insert(opts, v.Name) end
    end
    for _,v in ipairs(plr.Character:GetChildren()) do
        if v:IsA("Tool") then
            local exists=false
            for _,n in ipairs(opts) do if n==v.Name then exists=true break end end
            if not exists then table.insert(opts, v.Name) end
        end
    end
    WeaponDropdown:Refresh(opts, true)
end
task.spawn(function()
    while task.wait(2) do
        RefreshWeapons()
    end
end)

-- farming loop
task.spawn(function()
    local vu = game:GetService("VirtualUser")
    while task.wait(0.15) do
        if Settings.FastAttack then
            pcall(function()
                vu:CaptureController()
                vu:Button1Down(Vector2.new(0,1,0,1))
            end)
        end
    end
end)

task.spawn(function()
    while task.wait(0.2) do
        if not Settings.AutoFarm then continue end
        local lv = plr:FindFirstChild("Data") and plr.Data:FindFirstChild("Level") and plr.Data.Level.Value or 1
        local q = GetQuestForLevel(lv)
        if not q then
            Home:CreateParagraph({Title="Notice", Content="No quest table match for your level yet. The hub will idle."})
            task.wait(2)
            continue
        end

        -- Start quest if not active
        local gui = plr.PlayerGui:FindFirstChild("Main")
        local hasQuest = gui and gui:FindFirstChild("Quest") and gui.Quest.Visible
        if not hasQuest then
            SoftTeleport(q.qPos)
            task.wait(0.3)
            pcall(function() ReplicatedStorage.Remotes.CommF_:InvokeServer("StartQuest", q.quest, q.qId) end)
            task.wait(0.4)
        end

        EquipWeapon()

        -- Find target enemy
        local target = nil
        for _,e in ipairs(workspace:WaitForChild("Enemies"):GetChildren()) do
            if e.Name == q.mob and e:FindFirstChild("Humanoid") and e.Humanoid.Health > 0 and e:FindFirstChild("HumanoidRootPart") then
                target = e
                break
            end
        end
        if not target then
            task.wait(0.25)
        else
            -- grip & nuke
            local root = target.HumanoidRootPart
            root.Size = Vector3.new(60,60,60)
            root.CanCollide = false
            local holdCF = root.CFrame * CFrame.new(0, q.farmHeight, 0)
            SoftTeleport(holdCF)
        end
    end
end)

-- === Chest Finder ===
local ChestStats = Chest:CreateParagraph({Title="Chests", Content="Total: "..tostring(Progress.TotalChests)})
local ChestStatus = Chest:CreateParagraph({Title="Status", Content="Idle"})

local ChestToggle = Chest:CreateToggle({
    Name = "Enable Chest Finder",
    CurrentValue = Settings.ChestFinder,
    Callback = function(v)
        Settings.ChestFinder = v
        SaveSettings()
    end
})

local RatioSlider = Chest:CreateSlider({
    Name = "Instant Teleport Ratio (%)",
    Range = {0,100},
    Increment = 5,
    CurrentValue = math.floor(Settings.ChestInstantRatio*100),
    Callback = function(val)
        Settings.ChestInstantRatio = val/100
        SaveSettings()
    end
})
Chest:CreateSlider({
    Name = "Delay per Chest (Min)",
    Range = {0,6},
    Increment = 1,
    CurrentValue = Settings.ChestDelayMin,
    Callback = function(v) Settings.ChestDelayMin=v SaveSettings() end
})
Chest:CreateSlider({
    Name = "Delay per Chest (Max)",
    Range = {1,8},
    Increment = 1,
    CurrentValue = Settings.ChestDelayMax,
    Callback = function(v) Settings.ChestDelayMax=v SaveSettings() end
})

local function UpdateChestUIStatus(txt) ChestStatus:Set({Title="Status", Content=txt}) end
local function UpdateChestCount() ChestStats:Set({Title="Chests", Content="Total: "..tostring(Progress.TotalChests)}) end

local function IsChestInstance(inst)
    if not inst then return false end
    if inst:IsA("Model") then
        -- Common chest models live in ChestModels with PrimaryPart
        if inst.Parent and inst.Parent.Name == "ChestModels" then return inst.PrimaryPart ~= nil end
        if inst.Name:lower():find("chest") ~= nil then
            return inst:FindFirstChildWhichIsA("BasePart") ~= nil
        end
    elseif inst:IsA("BasePart") then
        return inst.Name:lower():find("chest") ~= nil
    end
    return false
end

local function EnumerateChests()
    local found = {}
    local chestModels = workspace:FindFirstChild("ChestModels")
    if chestModels then
        for _,m in ipairs(chestModels:GetChildren()) do
            if m:IsA("Model") and m.PrimaryPart then table.insert(found, m.PrimaryPart) end
        end
    end
    for _,d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") and d.Name:lower():find("chest") then
            table.insert(found, d)
        end
    end
    -- unique
    local uniq, seen = {}, {}
    for _,p in ipairs(found) do
        if p and p.Parent and p:IsDescendantOf(workspace) then
            local k = tostring(p:GetDebugId())
            if not seen[k] then seen[k]=true table.insert(uniq, p) end
        end
    end
    -- sort by distance
    table.sort(uniq, function(a,b)
        return Distance(hrp.Position, a.Position) < Distance(hrp.Position, b.Position)
    end)
    return uniq
end

local function ServerHop()
    UpdateChestUIStatus("Server hop: fetching servers...")
    local cursor = nil
    for page=1,5 do
        local url = "https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"..(cursor and ("&cursor="..cursor) or "")
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if ok then
            local decoded = HttpService:JSONDecode(res)
            cursor = decoded.nextPageCursor
            for _,s in ipairs(decoded.data) do
                if s.id ~= game.JobId and s.playing < s.maxPlayers then
                    if not table.find(Progress.VisitedServers, s.id) then
                        table.insert(Progress.VisitedServers, s.id)
                        SaveProgress()
                        task.wait(Settings.ServerHopCooldown)
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id)
                        return
                    end
                end
            end
        end
        if not cursor then break end
    end
    -- fallback: teleport to any different server
    TeleportService:Teleport(game.PlaceId)
end

task.spawn(function()
    while task.wait(0.5) do
        if not Settings.ChestFinder then continue end
        local list = EnumerateChests()
        if #list == 0 then
            UpdateChestUIStatus("No chests -> waiting "..Settings.ChestWaitBeforeHop.."s, then hop")
            task.wait(Settings.ChestWaitBeforeHop)
            if Settings.ChestFinder then ServerHop() end
        else
            for _,part in ipairs(list) do
                if not Settings.ChestFinder then break end
                local useInstant = (math.random() < Settings.ChestInstantRatio)
                UpdateChestUIStatus((useInstant and "Instant" or "Tween").." to chest...")
                if useInstant then
                    InstantTeleport(CFrame.new(part.Position + Vector3.new(0,3,0)))
                else
                    SoftTeleport(CFrame.new(part.Position + Vector3.new(0,3,0)))
                end
                TouchPart(part)
                -- validate pickup by brief wait near
                task.wait(0.25)
                if not part:IsDescendantOf(workspace) then
                    Progress.TotalChests += 1
                    SaveProgress()
                    UpdateChestCount()
                end
                task.wait(math.random(Settings.ChestDelayMin, Settings.ChestDelayMax))
            end
        end
    end
end)

-- === Fruit Finder ===
local FruitStatus = Fruit:CreateParagraph({Title="Status", Content="Idle"})
local FruitToggle = Fruit:CreateToggle({
    Name = "Enable Fruit Finder",
    CurrentValue = Settings.FruitFinder,
    Callback = function(v) Settings.FruitFinder=v SaveSettings() end
})
local StoreToggle = Fruit:CreateToggle({
    Name = "Auto Store Fruits",
    CurrentValue = Settings.AutoStoreFruit,
    Callback = function(v) Settings.AutoStoreFruit=v SaveSettings() end
})
local WebhookBox = Fruit:CreateInput({
    Name = "Discord Webhook (optional)",
    PlaceholderText = Settings.Webhook ~= "" and Settings.Webhook or "https://discord.com/api/webhooks/...",
    RemoveTextAfterFocusLost = false,
    Callback = function(txt) Settings.Webhook = txt SaveSettings() end
})

local function SendWebhook(title, desc)
    if not Settings.Webhook or Settings.Webhook == "" then return end
    local payload = {
        content = "**Monarch of Curiosity**",
        embeds = {{
            title = title,
            description = desc,
            color = 65280,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }}
    }
    local ok,err = pcall(function()
        HttpService:PostAsync(Settings.Webhook, HttpService:JSONEncode(payload), Enum.HttpContentType.ApplicationJson)
    end)
end

local function FindBasePart(model)
    for _, v in ipairs(model:GetDescendants()) do
        if v:IsA("BasePart") then return v end
    end
end

local function CollectFruit(item)
    if not item then return false end
    if item:IsA("Tool") then
        local handle = item:FindFirstChild("Handle")
        if handle then
            InstantTeleport(CFrame.new(handle.Position + Vector3.new(0,2,0)))
            task.wait(0.1)
            handle.CFrame = hrp.CFrame
            task.wait(0.2)
            if not item:IsDescendantOf(workspace) then
                return true
            end
        end
    elseif item:IsA("Model") then
        local base = FindBasePart(item)
        if base then
            SoftTeleport(CFrame.new(base.Position + Vector3.new(0,3,0)))
            task.wait(0.2)
            if not item:IsDescendantOf(workspace) then
                return true
            end
        end
    end
    return false
end

local function StoreBackpackFruits()
    if not Settings.AutoStoreFruit then return end
    for _,fr in ipairs(plr.Backpack:GetChildren()) do
        if fr:IsA("Tool") and fr.Name:lower():find("fruit") then
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", fr:GetAttribute("OriginalName"), fr)
            end)
        end
    end
end

task.spawn(function()
    while task.wait(1) do
        if not Settings.FruitFinder then continue end
        local found, collected = false, false
        FruitStatus:Set({Title="Status", Content="Scanning..."})
        pcall(function()
            for _,v in ipairs(workspace:GetChildren()) do
                if v:IsA("Tool") and v.Name:lower():find("fruit") then
                    found = true
                    FruitStatus:Set({Title="Status", Content="Found tool fruit: "..v.Name})
                    if CollectFruit(v) then
                        collected = true
                        SendWebhook("Fruit Collected", "Collected tool: **"..v.Name.."**")
                        break
                    end
                end
            end
        end)
        if not collected then
            pcall(function()
                for _,v in ipairs(workspace:GetChildren()) do
                    if v:IsA("Model") and (v.Name:lower()=="fruit") then
                        found = true
                        FruitStatus:Set({Title="Status", Content="Found model fruit"})
                        if CollectFruit(v) then
                            collected = true
                            SendWebhook("Fruit Collected", "Collected a fruit model")
                            break
                        end
                    end
                end
            end)
        end
        if collected then
            StoreBackpackFruits()
        else
            FruitStatus:Set({Title="Status", Content= found and "Trying to collect..." or "No fruits found"})
        end
    end
end)

-- === Settings Tab ===
SettingsTab:CreateToggle({
    Name = "Auto-Join Marines on start",
    CurrentValue = Settings.AutoJoinMarines,
    Callback = function(v) Settings.AutoJoinMarines = v SaveSettings() end
})
SettingsTab:CreateButton({
    Name = "Save Settings",
    Callback = function()
        SaveSettings()
        Notify("Settings saved.")
    end
})
SettingsTab:CreateButton({
    Name = "Save Progress (Chests/Servers)",
    Callback = function()
        SaveProgress()
        Notify("Progress saved.")
    end
})

-- === Credits ===
Credits:CreateParagraph({Title="Monarch of Curiosity", Content="Hub & UI by Monarch of Curiosity 👑\nThanks for using the hub!"})

Notify("Monarch of Curiosity loaded.")
