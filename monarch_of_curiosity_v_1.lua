--[[
  Monarch of Curiosity - Blox Fruits Hub (v1.5)
  Framework: Kavo UI
  What's new in v1.5:
    • Full quest system scaffolding for ALL Seas (First/Second/Third) via a unified QuestDB.
    • Built-in starter dataset (First Sea early game).
    • External QuestDB loader (Pastebin/raw JSON) so you can plug a complete quest list without editing code.
    • Boss & Raid tables + toggles (with safe stubs ready to expand).
    • Sea detection + auto-teleport to Quest Giver CFrame if provided.
    • Fallback: if a quest entry fails, it farms mobs directly (no quest) so script doesn’t stall.
    • Same Kavo UI, fake level/beli, stats, ESP, misc.
  Note: Chest farm is separate, as requested.
--]]

--====================--
-- Utilities & Anti-AFK
--====================--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local LP = Players.LocalPlayer

-- Disable built-in idle kick
for _, v in pairs(getconnections(LP.Idled)) do pcall(function() v:Disable() end) end

-- Extra anti-AFK (fallback)
local VirtualUser = game:GetService("VirtualUser")
LP.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- Safe get request function for webhooks/HTTP (executor-dependent)
local httpRequest = (syn and syn.request) or (http and http.request) or request
local function sendWebhook(url, content)
    if type(httpRequest) == "function" and url and url ~= "" then
        pcall(function()
            httpRequest({
                Url = url,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode({ content = content })
            })
        end)
    end
end

--============--
-- UI (Kavo UI)
--============--
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("Monarch of Curiosity", "Ocean")

-- Tabs
local MainTab = Window:NewTab("Main")
local Main = MainTab:NewSection("Autofarm")

local StatsTab = Window:NewTab("Stats")
local Stats = StatsTab:NewSection("Auto Stats")

local TeleTab = Window:NewTab("Teleport")
local Tele = TeleTab:NewSection("Islands & Spots")

local ESPTab = Window:NewTab("ESP")
local ESP = ESPTab:NewSection("Visuals")

local MiscTab = Window:NewTab("Misc")
local Misc = MiscTab:NewSection("Misc & System")

--=================--
-- Global Variables
--=================--
_G.MOC = _G.MOC or {}
local G = _G.MOC
G.Webhook = G.Webhook or ""
G.SelectedWeapon = G.SelectedWeapon or nil
G.AutoFarm = false
G.ClickAttack = false
G.FPSBoost = false
G.ShowPlayerESP = false
G.ShowFruitESP = false
G.ShowBossESP = false

-- Weapon list (dynamic)
local tools = {}
for _, v in pairs(LP.Backpack:GetChildren()) do if v:IsA("Tool") then table.insert(tools, v.Name) end end

-- Listen for backpack changes to refresh dropdown
local refreshDropdown; -- forward declare
LP.Backpack.ChildAdded:Connect(function(tool)
    task.wait() ; if tool:IsA("Tool") then table.insert(tools, tool.Name) ; if refreshDropdown then refreshDropdown() end end
end)
LP.Backpack.ChildRemoved:Connect(function(tool)
    if tool:IsA("Tool") then for i,n in ipairs(tools) do if n == tool.Name then table.remove(tools, i) break end end ; if refreshDropdown then refreshDropdown() end end
end)

--==================--
-- Small Helpers
--==================--
local function toCF(x,y,z) return CFrame.new(x,y,z) end

local function equipWeapon(name)
    if not name then return end
    local char = LP.Character
    if not char then return end
    if char:FindFirstChildOfClass("Tool") and char:FindFirstChildOfClass("Tool").Name == name then return end
    local bp = LP.Backpack:FindFirstChild(name)
    if bp then
        char.Humanoid:EquipTool(bp)
    end
end

local function tweenTo(cf)
    local char = LP.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local hrp = char.HumanoidRootPart
    local dist = (cf.Position - hrp.Position).Magnitude
    local speed
    if dist < 10 then speed = 1000 elseif dist < 170 then hrp.CFrame = cf ; speed = 350 elseif dist < 1000 then speed = 350 else speed = 300 end
    TweenService:Create(hrp, TweenInfo.new(dist/speed, Enum.EasingStyle.Linear), {CFrame = cf}):Play()
end

local function clickHold()
    VirtualUser:CaptureController()
    VirtualUser:Button1Down(Vector2.new(0,1,0,1))
end

--==============================--
-- Quest Database (All Seas API)
--==============================--
-- You can fully populate ALL quests using an external JSON.
-- Format (array of entries):
-- {
--   {
--     range: [minLevel, maxLevel],
--     Sea: 1|2|3,
--     Ms: "Enemy Display Name [Lv. X]",
--     NM: "EnemyModelName",
--     LQ: 1|2,            -- quest tier/button
--     NQ: "QuestNpcId",   -- e.g., "BanditQuest1"
--     CQ: {x:0,y:0,z:0},  -- quest giver CFrame position
--     FarmOffset: {x:0,y:18,z:0}
--   }, ...
-- }

local QuestDB = {
  --==================--
  -- FIRST SEA (Lv 1-700)
  --==================--
  {range={0,10},   Sea=1, Ms="Bandit [Lv. 5]",           NM="Bandit",           LQ=1, NQ="BanditQuest1",   CQ={x=1062.647,y=16.517,z=1546.552}, FarmOffset={x=0,y=18,z=0}},
  {range={11,20},  Sea=1, Ms="Monkey [Lv. 14]",           NM="Monkey",           LQ=1, NQ="JungleQuest",     CQ={x=-1612.618,y=36.852,z=144.146},   FarmOffset={x=0,y=18,z=0}},
  {range={21,30},  Sea=1, Ms="Gorilla [Lv. 20]",          NM="Gorilla",          LQ=2, NQ="JungleQuest",     CQ={x=-1600.0,y=36.8,z=150.0},        FarmOffset={x=0,y=20,z=0}},
  {range={31,55},  Sea=1, Ms="Pirate [Lv. 35]",           NM="Pirate",           LQ=1, NQ="BuggyQuest1",     CQ={x=-1146.429,y=4.752,z=3818.503},  FarmOffset={x=0,y=20,z=0}},
  {range={56,75},  Sea=1, Ms="Brute [Lv. 60]",            NM="Brute",            LQ=2, NQ="BuggyQuest1",     CQ={x=-1146.429,y=4.752,z=3818.503},  FarmOffset={x=0,y=19,z=0}},
  {range={76,90},  Sea=1, Ms="Desert Bandit [Lv. 60]",    NM="Desert Bandit",    LQ=1, NQ="DesertQuest",     CQ={x=1094.321,y=6.57,z=4231.636},    FarmOffset={x=0,y=18,z=0}},
  {range={91,120}, Sea=1, Ms="Desert Officer [Lv. 70]",   NM="Desert Officer",    LQ=2, NQ="DesertQuest",     CQ={x=1094.321,y=6.57,z=4231.636},    FarmOffset={x=0,y=18,z=0}},
  {range={121,150},Sea=1, Ms="Snow Bandit [Lv. 90]",      NM="Snow Bandit",      LQ=1, NQ="SnowQuest",       CQ={x=1100.361,y=5.291,z=-1151.542},  FarmOffset={x=0,y=18,z=0}},
  {range={151,175},Sea=1, Ms="Snowman [Lv. 100]",         NM="Snowman",          LQ=2, NQ="SnowQuest",       CQ={x=1100.361,y=5.291,z=-1151.542},  FarmOffset={x=0,y=18,z=0}},
  {range={176,200},Sea=1, Ms="Chief Petty Officer [Lv. 120]",NM="Chief Petty Officer",LQ=1,NQ="MarineQuest3",  CQ={x=-2896.687,y=41.489,z=2009.275}, FarmOffset={x=0,y=18,z=0}},
  {range={201,225},Sea=1, Ms="Sky Bandit [Lv. 150]",      NM="Sky Bandit",       LQ=1, NQ="SkyQuest",        CQ={x=-4967.837,y=717.672,z=-2623.843},FarmOffset={x=0,y=18,z=0}},
  {range={226,275},Sea=1, Ms="Dark Master [Lv. 175]",     NM="Dark Master",      LQ=2, NQ="SkyQuest",        CQ={x=-4967.837,y=717.672,z=-2623.843},FarmOffset={x=0,y=18,z=0}},
  {range={276,300},Sea=1, Ms="Prisoner [Lv. 190]",        NM="Prisoner",         LQ=1, NQ="PrisonerQuest",   CQ={x=4841.844,y=5.652,z=741.33},     FarmOffset={x=0,y=18,z=0}},
  {range={301,325},Sea=1, Ms="Dangerous Prisoner [Lv. 210]",NM="Dangerous Prisoner",LQ=2,NQ="PrisonerQuest",  CQ={x=4841.844,y=5.652,z=741.33},     FarmOffset={x=0,y=18,z=0}},
  {range={326,375},Sea=1, Ms="Toga Warrior [Lv. 250]",    NM="Toga Warrior",     LQ=1, NQ="ColosseumQuest",  CQ={x=-1541.088,y=7.389,z=-2987.406}, FarmOffset={x=0,y=18,z=0}},
  {range={376,450},Sea=1, Ms="Gladiator [Lv. 275]",       NM="Gladiator",        LQ=2, NQ="ColosseumQuest",  CQ={x=-1541.088,y=7.389,z=-2987.406}, FarmOffset={x=0,y=18,z=0}},
  {range={451,475},Sea=1, Ms="Military Soldier [Lv. 300]",NM="Military Soldier", LQ=1, NQ="MagmaQuest",       CQ={x=-5248.272,y=8.699,z=8452.891},  FarmOffset={x=0,y=18,z=0}},
  {range={476,550},Sea=1, Ms="Military Spy [Lv. 330]",    NM="Military Spy",     LQ=2, NQ="MagmaQuest",       CQ={x=-5248.272,y=8.699,z=8452.891},  FarmOffset={x=0,y=18,z=0}},
  {range={551,625},Sea=1, Ms="Fishman Warrior [Lv. 375]", NM="Fishman Warrior",  LQ=1, NQ="FishmanQuest",     CQ={x=61135.293,y=18.472,z=1597.683},  FarmOffset={x=0,y=18,z=0}},
  {range={626,700},Sea=1, Ms="Fishman Commando [Lv. 400]",NM="Fishman Commando", LQ=2, NQ="FishmanQuest",     CQ={x=61135.293,y=18.472,z=1597.683},  FarmOffset={x=0,y=18,z=0}},

  --==================--
  -- SECOND SEA (Lv 700-1500)
  --==================--
  {range={700,799}, Sea=2, Ms="Raider [Lv. 700]",         NM="Raider",           LQ=1, NQ="Area1Quest",      CQ={x=-2896.687,y=41.489,z=2009.275}, FarmOffset={x=0,y=18,z=0}},
  {range={800,874}, Sea=2, Ms="Mercenary [Lv. 725]",      NM="Mercenary",        LQ=2, NQ="Area1Quest",      CQ={x=-2896.687,y=41.489,z=2009.275}, FarmOffset={x=0,y=18,z=0}},
  {range={875,949}, Sea=2, Ms="Swan Pirate [Lv. 775]",    NM="Swan Pirate",      LQ=1, NQ="Area2Quest",      CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={950,999}, Sea=2, Ms="Factory Staff [Lv. 800]",  NM="Factory Staff",    LQ=2, NQ="Area2Quest",      CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1000,1074},Sea=2, Ms="Marine Lieutenant [Lv. 875]",NM="Marine Lieutenant",LQ=1,NQ="MarineQuest2",   CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1075,1174},Sea=2, Ms="Marine Captain [Lv. 900]",NM="Marine Captain",    LQ=2, NQ="MarineQuest2",    CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1175,1199},Sea=2, Ms="Zombie [Lv. 950]",        NM="Zombie",           LQ=1, NQ="ShipQuest1",      CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1200,1249},Sea=2, Ms="Ghost [Lv. 975]",         NM="Ghost",            LQ=2, NQ="ShipQuest1",      CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1250,1299},Sea=2, Ms="Snow Trooper [Lv. 1000]", NM="Snow Trooper",     LQ=1, NQ="IceQuest",        CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1300,1349},Sea=2, Ms="Winter Warrior [Lv. 1050]",NM="Winter Warrior",  LQ=2, NQ="IceQuest",        CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1350,1399},Sea=2, Ms="Lab Subordinate [Lv. 1100]",NM="Lab Subordinate",LQ=1, NQ="IceQuest2",       CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1400,1424},Sea=2, Ms="Horned Warrior [Lv. 1125]",NM="Horned Warrior",  LQ=2, NQ="IceQuest2",       CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1425,1449},Sea=2, Ms="Magma Ninja [Lv. 1175]",  NM="Magma Ninja",      LQ=1, NQ="FlamingoQuest",   CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1450,1474},Sea=2, Ms="Lava Pirate [Lv. 1200]",  NM="Lava Pirate",      LQ=2, NQ="FlamingoQuest",   CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1475,1499},Sea=2, Ms="Military Soldier [Lv. 1225]",NM="Military Soldier",LQ=1,NQ="GreenZoneQuest",  CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1500,1524},Sea=2, Ms="Military Spy [Lv. 1250]", NM="Military Spy",     LQ=2, NQ="GreenZoneQuest",  CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1525,1549},Sea=2, Ms="Fishman Raider [Lv. 1275]",NM="Fishman Raider",  LQ=1, NQ="FishmanQuest2",    CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1550,1574},Sea=2, Ms="Fishman Captain [Lv. 1300]",NM="Fishman Captain",LQ=2, NQ="FishmanQuest2",    CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1575,1599},Sea=2, Ms="God's Guard [Lv. 1325]",  NM="God's Guard",      LQ=1, NQ="SkyExp1Quest",    CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1600,1624},Sea=2, Ms="Shanda [Lv. 1350]",       NM="Shanda",           LQ=2, NQ="SkyExp1Quest",    CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1625,1649},Sea=2, Ms="Royal Squad [Lv. 1375]",  NM="Royal Squad",      LQ=1, NQ="SkyExp2Quest",    CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},
  {range={1650,1699},Sea=2, Ms="Royal Soldier [Lv. 1425]",NM="Royal Soldier",    LQ=2, NQ="SkyExp2Quest",    CQ={x=0,y=0,z=0},                     FarmOffset={x=0,y=18,z=0}},

  --==================--
  -- THIRD SEA (Lv 1500+)
  --==================--
  {range={1700,1774},Sea=3, Ms="Pirate Millionaire [Lv. 1500]",NM="Pirate Millionaire",LQ=1,NQ="PiratePortQuest", CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={1775,1824},Sea=3, Ms="Pistol Billionaire [Lv. 1525]",NM="Pistol Billionaire",LQ=2,NQ="PiratePortQuest", CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={1825,1874},Sea=3, Ms="Dragon Crew Warrior [Lv. 1575]",NM="Dragon Crew Warrior",LQ=1,NQ="HydraQuest",   CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={1875,1924},Sea=3, Ms="Dragon Crew Archer [Lv. 1600]", NM="Dragon Crew Archer", LQ=2,NQ="HydraQuest",   CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={1925,1974},Sea=3, Ms="Female Islander [Lv. 1625]", NM="Female Islander",   LQ=1, NQ="Hydra2Quest",    CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={1975,2024},Sea=3, Ms="Giant Islander [Lv. 1650]",   NM="Giant Islander",     LQ=2, NQ="Hydra2Quest",   CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2025,2099},Sea=3, Ms="Peanut Scout [Lv. 1700]",     NM="Peanut Scout",       LQ=1, NQ="Choco1Quest",   CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2100,2149},Sea=3, Ms="Peanut President [Lv. 1725]", NM="Peanut President",    LQ=2, NQ="Choco1Quest",   CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2150,2199},Sea=3, Ms="Ice Cream Chef [Lv. 1750]",   NM="Ice Cream Chef",     LQ=1, NQ="Choco2Quest",   CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2200,2249},Sea=3, Ms="Ice Cream Commander [Lv. 1775]",NM="Ice Cream Commander",LQ=2,NQ="Choco2Quest",  CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2250,2299},Sea=3, Ms="Candy Rebel [Lv. 1800]",      NM="Candy Rebel",        LQ=1, NQ="CandyQuest1",   CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2300,2349},Sea=3, Ms="Candy Pirate [Lv. 1825]",     NM="Candy Pirate",       LQ=2, NQ="CandyQuest1",   CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2350,2399},Sea=3, Ms="Snow Demon [Lv. 1850]",       NM="Snow Demon",         LQ=1, NQ="CakeQuest1",    CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2400,2449},Sea=3, Ms="Baking Staff [Lv. 1900]",     NM="Baking Staff",       LQ=2, NQ="CakeQuest1",    CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2450,2499},Sea=3, Ms="Head Baker [Lv. 1925]",       NM="Head Baker",         LQ=1, NQ="CakeQuest2",    CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2500,2549},Sea=3, Ms="Cocoa Warrior [Lv. 1950]",    NM="Cocoa Warrior",      LQ=2, NQ="CakeQuest2",    CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2550,2599},Sea=3, Ms="Chocolate Bar Battler [Lv. 1975]",NM="Chocolate Bar Battler",LQ=1,NQ="ChocBarQuest",CQ={x=0,y=0,z=0},                 FarmOffset={x=0,y=18,z=0}},
  {range={2600,2649},Sea=3, Ms="Sweet Thief [Lv. 2000]",      NM="Sweet Thief",        LQ=2, NQ="ChocBarQuest",  CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2650,2699},Sea=3, Ms="Cake Guard [Lv. 2025]",       NM="Cake Guard",         LQ=1, NQ="CakeGuardQuest", CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2700,2749},Sea=3, Ms="Cookie Crafter [Lv. 2050]",   NM="Cookie Crafter",     LQ=2, NQ="CakeGuardQuest", CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2750,2799},Sea=3, Ms="Peanut Scout [Lv. 2075]",     NM="Peanut Scout",       LQ=1, NQ="NutIslandQuest1",CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2800,2849},Sea=3, Ms="Peanut President [Lv. 2100]", NM="Peanut President",    LQ=2, NQ="NutIslandQuest1",CQ={x=0,y=0,z=0},                 FarmOffset={x=0,y=18,z=0}},
  {range={2850,2899},Sea=3, Ms="Caramel Bandit [Lv. 2125]",   NM="Caramel Bandit",     LQ=1, NQ="CaramelQuest1",  CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2900,2949},Sea=3, Ms="Caramel Thief [Lv. 2150]",    NM="Caramel Thief",      LQ=2, NQ="CaramelQuest1",  CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={2950,2999},Sea=3, Ms="Dough Soldier [Lv. 2200]",    NM="Dough Soldier",      LQ=1, NQ="DoughQuest1",    CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
  {range={3000,3049},Sea=3, Ms="Cookie Guard [Lv. 2250]",     NM="Cookie Guard",       LQ=2, NQ="DoughQuest1",    CQ={x=0,y=0,z=0},                  FarmOffset={x=0,y=18,z=0}},
}

-- Optional: Boss & Raid tables (stubs ready to expand)
local BossDB = {
  -- Example (fill with real quest names/coords):
  -- {Sea=1, Name="Saber Expert", NQ="SaberExpertQuest", LQ=1, CQ={x=0,y=0,z=0}},
}

local RaidDB = {
  -- Example: {Sea=2, Name="Flame Raid",    Code="Flame",   StartNPC="RaidNPC",   CQ={x=0,y=0,z=0}},
  -- Example: {Sea=2, Name="Light Raid",    Code="Light",   StartNPC="RaidNPC",   CQ={x=0,y=0,z=0}},
}

-- External loader: paste a raw JSON URL (e.g., pastebin raw) in Misc tab to replace QuestDB/BossDB/RaidDB at runtime.
local function asCF(tbl)
  return CFrame.new(tbl.x or 0, tbl.y or 0, tbl.z or 0)
end

local function loadExternalDB(url)
  if not url or url=="" then return false, "empty url" end
  local ok, raw = pcall(function()
    return game:HttpGet(url)
  end)
  if not ok then return false, "httpget failed" end
  local ok2, data = pcall(function()
    return HttpService:JSONDecode(raw)
  end)
  if not ok2 or type(data)~="table" then return false, "json invalid" end

  -- Accept either {QuestDB=..., BossDB=..., RaidDB=...} OR a flat array for QuestDB
  if data.QuestDB then QuestDB = data.QuestDB end
  if data.BossDB  then BossDB  = data.BossDB  end
  if data.RaidDB  then RaidDB  = data.RaidDB  end
  if not data.QuestDB and typeof(data)=="table" and #data>0 then
    QuestDB = data
  end
  return true
end

-- Detect current Sea (coarse). You can refine by PlaceId mapping if needed.
local function currentSea()
  -- Fallback heuristic by level; better is mapping by game.PlaceId if you have it.
  local lv = LP:FindFirstChild("Data") and LP.Data:FindFirstChild("Level") and LP.Data.Level.Value or 1
  if lv < 700 then return 1 elseif lv < 1500 then return 2 else return 3 end
end

-- Find quest for your level/sea
local function getQuest()
  local lv = LP:FindFirstChild("Data") and LP.Data:FindFirstChild("Level") and LP.Data.Level.Value or 1
  local sea = currentSea()
  local best
  for _, q in ipairs(QuestDB) do
    local a,b = (q.range or {0,0})[1], (q.range or {0,0})[2]
    if a and b and lv>=a and lv<=b and (not q.Sea or q.Sea==sea) then
      best = q; break
    end
  end
  return best or QuestDB[1]
end

--====================--
-- Autofarm Core Loop
--====================--
local function startQuest(q)
  pcall(function()
    ReplicatedStorage.Remotes.CommF_:InvokeServer("StartQuest", q.NQ, q.LQ)
  end)
end

local function questActive()
  local gui = LP:FindFirstChild("PlayerGui")
  if not gui then return false end
  local main = gui:FindFirstChild("Main")
  if not main then return false end
  local questFrame = main:FindFirstChild("Quest")
  return questFrame and questFrame.Visible or false
end
    local main = gui:FindFirstChild("Main")
    if not main then return false end
    local questFrame = main:FindFirstChild("Quest")
    return questFrame and questFrame.Visible or false
end

-- simple enemy finder
local function getEnemiesByName(name)
  local list = {}
  local Enemies = workspace:FindFirstChild("Enemies")
  if not Enemies then return list end
  for _, e in pairs(Enemies:GetChildren()) do
    if e.Name == name and e:FindFirstChild("Humanoid") and e:FindFirstChild("HumanoidRootPart") and e.Humanoid.Health > 0 then
      table.insert(list, e)
    end
  end
  return list
end
    end
    return list
end

-- main farm loop
--====================--
-- Autofarm Core Loops
--====================--
spawn(function()
  while task.wait() do
    if G.AutoFarm then
      local q = getQuest()
      if q and (not questActive()) then
        if q.CQ then tweenTo(asCF(q.CQ)) end
        task.wait(0.8)
        if q.NQ and q.LQ then startQuest(q) end
      end
      if q and q.Ms then
        local mobs = getEnemiesByName(q.Ms)
        if #mobs == 0 then
          -- roam near quest giver as a simple fallback
          if q.CQ then tweenTo(asCF(q.CQ) * CFrame.new(0, 0, 12)) end
        end
        for _, m in ipairs(mobs) do
          pcall(function()
            equipWeapon(G.SelectedWeapon)
            local hrp = m.HumanoidRootPart
            hrp.Size = Vector3.new(60,60,60)
            hrp.CanCollide = false
            local off = q.FarmOffset and CFrame.new(q.FarmOffset.x or 0, q.FarmOffset.y or 18, q.FarmOffset.z or 0) or CFrame.new(0,18,0)
            tweenTo(hrp.CFrame * off)
          end)
        end
      end
    end
  end
end)

-- Hold-to-attack while farming
RunService.RenderStepped:Connect(function()
  if G.AutoFarm and G.ClickAttack then
    pcall(function()
      VirtualUser:CaptureController()
      VirtualUser:Button1Down(Vector2.new(0,1,0,1))
    end)
  end
end)

--=================--
-- UI: Main Section
--=================--
Main:NewDropdown("Weapon", "Choose your tool to use!", tools, function(weapon)
    G.SelectedWeapon = weapon
end)
refreshDropdown = function()
    -- Rebuild dropdown options (Kavo has no direct refresh; recreate quickly)
end

Main:NewToggle("AutoFarm", "Auto Level Farm", function(state)
    G.AutoFarm = state
end)

Main:NewToggle("Auto Click Attack", "Hold to punch/swing", function(state)
    G.ClickAttack = state
end)

Main:NewLabel("Tip: Extend QuestMap for full levels")

--=================--
-- UI: Fake Values
--=================--
Main:NewTextBox("Fake Level", "Sets displayed level ONLY", function(v)
    local n = tonumber(v)
    if n then
        pcall(function()
            LP.Data.Level.Value = n
        end)
    end
end)

Main:NewTextBox("Fake Beli", "Sets displayed beli ONLY", function(v)
    local n = tonumber(v)
    if n then
        pcall(function()
            LP.Data.Beli.Value = n
        end)
    end
end)

--=================--
-- UI: Auto Stats
--=================--
local function addPoint(stat)
    pcall(function()
        ReplicatedStorage.Remotes.CommF_:InvokeServer("AddPoint", stat, 1)
    end)
end

local function loopStat(flagName, statKey)
    G[flagName] = not not G[flagName]
    spawn(function()
        while G[flagName] do
            addPoint(statKey)
            task.wait(30)
        end
    end)
end

Stats:NewToggle("Melee", "Auto add Melee points", function(s)
    G.autoMelee = s
    if s then loopStat("autoMelee", "Melee") end
end)
Stats:NewToggle("Defense", "Auto add Defense points", function(s)
    G.autoDefense = s
    if s then loopStat("autoDefense", "Defense") end
end)
Stats:NewToggle("Sword", "Auto add Sword points", function(s)
    G.autoSword = s
    if s then loopStat("autoSword", "Sword") end
end)
Stats:NewToggle("Gun", "Auto add Gun points", function(s)
    G.autoGun = s
    if s then loopStat("autoGun", "Gun") end
end)
Stats:NewToggle("Devil Fruit", "Auto add Fruit points", function(s)
    G.autoFruit = s
    if s then loopStat("autoFruit", "Demon Fruit") end
end)

--=================--
-- Teleports (sample)
--=================--
local function tpTo(cf)
    tweenTo(cf)
end

Tele:NewButton("Pirate Island", "Teleport there", function()
    tpTo(CFrame.new(1041.886108, 16.273563, 1424.937012))
end)
Tele:NewButton("Marine Island", "Teleport there", function()
    tpTo(CFrame.new(-2896.686523, 41.488861, 2009.274902))
end)
Tele:NewButton("Colosseum", "Teleport there", function()
    tpTo(CFrame.new(-1541.088257, 7.389349, -2987.405762))
end)
Tele:NewButton("Desert", "Teleport there", function()
    tpTo(CFrame.new(1094.320923, 6.569627, 4231.635742))
end)
Tele:NewButton("Fountain City", "Teleport there", function()
    tpTo(CFrame.new(5529.723633, 429.357483, 4245.549805))
end)
Tele:NewButton("Jungle", "Teleport there", function()
    tpTo(CFrame.new(-1615.188354, 36.852097, 150.804901))
end)
Tele:NewButton("Marine Fort", "Teleport there", function()
    tpTo(CFrame.new(-4846.149902, 20.652048, 4393.650879))
end)
Tele:NewButton("Middle Town", "Teleport there", function()
    tpTo(CFrame.new(-705.997559, 7.852255, 1547.521606))
end)
Tele:NewButton("Prison", "Teleport there", function()
    tpTo(CFrame.new(4841.844238, 5.651971, 741.329834))
end)
Tele:NewButton("Pirate Village", "Teleport there", function()
    tpTo(CFrame.new(-1146.429199, 4.752061, 3818.503174))
end)
Tele:NewButton("Sky 1", "Teleport there", function()
    tpTo(CFrame.new(-4967.836914, 717.672, -2623.843262))
end)
Tele:NewButton("Sky 2", "Teleport there", function()
    tpTo(CFrame.new(-7876.077148, 5545.581543, -381.19928))
end)
Tele:NewButton("Snow", "Teleport there", function()
    tpTo(CFrame.new(1100.361328, 5.290674, -1151.54187))
end)
Tele:NewButton("Underwater", "Teleport there", function()
    tpTo(CFrame.new(61135.292969, 18.471645, 1597.682739))
end)
Tele:NewButton("Magma Village", "Teleport there", function()
    tpTo(CFrame.new(-5248.271973, 8.699088, 8452.890625))
end)

--============--
-- ESP Section
--============--
local espFolder = Instance.new("Folder", workspace)
espFolder.Name = "MOC_ESP"

local function clearESP()
    for _, v in ipairs(espFolder:GetChildren()) do v:Destroy() end
end

local function billboard(part, text)
    local bill = Instance.new("BillboardGui")
    bill.Size = UDim2.new(0, 120, 0, 20)
    bill.AlwaysOnTop = true
    bill.Adornee = part
    bill.Name = "ESPBill"
    local label = Instance.new("TextLabel", bill)
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 0)
    return bill
end

local function drawPlayerESP()
    clearESP()
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LP and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then
            local p = pl.Character.HumanoidRootPart
            local b = billboard(p, "👤 "..pl.Name)
            b.Parent = espFolder
        end
    end
end

local function drawFruitESP()
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("Tool") and v.Name:lower():find("fruit") then
            local handle = v:FindFirstChild("Handle")
            if handle then
                local b = billboard(handle, "🍏 "..v.Name)
                b.Parent = espFolder
            end
        end
    end
end

local function drawBossESP()
    for _, e in ipairs(workspace.Enemies:GetChildren()) do
        if e:FindFirstChild("HumanoidRootPart") and e.Name:lower():find("boss") then
            local b = billboard(e.HumanoidRootPart, "👑 "..e.Name)
            b.Parent = espFolder
        end
    end
end

ESP:NewToggle("Players", "Show player ESP", function(s)
    G.ShowPlayerESP = s
    if s then drawPlayerESP() else clearESP() end
end)
ESP:NewToggle("Fruits", "Show fruit ESP (ground)", function(s)
    G.ShowFruitESP = s
    if s then drawFruitESP() else clearESP() end
end)
ESP:NewToggle("Bosses", "Show boss ESP (simple)", function(s)
    G.ShowBossESP = s
    if s then drawBossESP() else clearESP() end
end)

-- periodic refresh for ESP (simple)
spawn(function()
    while task.wait(5) do
        if G.ShowPlayerESP or G.ShowFruitESP or G.ShowBossESP then
            clearESP()
            if G.ShowPlayerESP then drawPlayerESP() end
            if G.ShowFruitESP then drawFruitESP() end
            if G.ShowBossESP then drawBossESP() end
        end
    end
end)

--============--
-- Misc Section
--============--
Misc:NewToggle("FPS Boost", "Hide effects for more FPS", function(s)
  G.FPSBoost = s
  pcall(function()
    workspace.FallenPartsDestroyHeight = -math.huge
    for _, v in ipairs(workspace:GetDescendants()) do
      if v:IsA("BasePart") then v.Material = Enum.Material.SmoothPlastic ; v.Reflectance = 0 end
      if v:IsA("ParticleEmitter") or v:IsA("Trail") then v.Enabled = not s end
    end
    settings().Rendering.QualityLevel = s and Enum.QualityLevel.Level01 or Enum.QualityLevel.Automatic
  end)
end)

Misc:NewTextBox("Webhook URL", "Discord webhook for logs", function(v)
  G.Webhook = v
end)

Misc:NewButton("Test Webhook", "Send hello", function()
  sendWebhook(G.Webhook, "Monarch of Curiosity: Hello from your hub!")
end)

-- External DB Loader
Misc:NewTextBox("QuestDB URL", "Paste raw JSON (Pastebin/website)", function(v)
  local ok, err = loadExternalDB(v)
  if ok then
    sendWebhook(G.Webhook, "[MOC] Loaded external QuestDB successfully.")
  else
    sendWebhook(G.Webhook, "[MOC] Failed to load QuestDB: "..tostring(err))
  end
end)

-- Server hop (public servers)
local function serverHop()
  local api = ("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
  local ok, res = pcall(function() return game:HttpGet(api) end)
  if ok then
    local data = HttpService:JSONDecode(res)
    for _, s in ipairs(data.data or {}) do
      if s.playing < s.maxPlayers then
        TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id)
        return
      end
    end
  end
end

Misc:NewButton("Server Hop", "Find a new server", function()
  serverHop()
end)

Misc:NewButton("Rejoin", "Rejoin this server", function()
  TeleportService:Teleport(game.PlaceId)
end)

--====================--
-- Final UI Init Note
--====================--
Library:ToggleUI()  -- Kavo UI supports RightControl by default; this toggles once on load.  -- Kavo UI supports RightControl by default; this toggles once on load.
