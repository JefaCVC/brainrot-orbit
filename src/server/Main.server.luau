--!strict
-- Main
-- Server bootstrap for BRAINROT ORBIT. Startup order matters: the remotes
-- are created first (the client waits for them), then the world is built
-- (before any character loads, so nobody spawns into a void), then the
-- services start. Player characters load only after this script runs, via
-- GameService, because Players.CharacterAutoLoads is false in the project.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- require is aliased so the Luau analyzer treats module loads as untyped calls;
-- at runtime this is the plain Roblox require of a ModuleScript instance.
local requireModule = require :: any
local GameService = requireModule(ServerScriptService:WaitForChild("GameService"))
local PlayerDataStore = requireModule(ServerScriptService:WaitForChild("PlayerDataStore"))
local Remotes = requireModule(ReplicatedStorage:WaitForChild("Remotes"))
local StormService = requireModule(ServerScriptService:WaitForChild("StormService"))
local ThiefService = requireModule(ServerScriptService:WaitForChild("ThiefService"))
local WildSpawner = requireModule(ServerScriptService:WaitForChild("WildSpawner"))
local WorldBuilder = requireModule(ServerScriptService:WaitForChild("WorldBuilder"))

-- 1. The whitelisted remotes, under ReplicatedStorage/Remotes.
Remotes.createAll()

-- 2. The station itself: decks, modules, garden, airlock, pedestals, crew.
WorldBuilder.buildWorld()

-- 3. Persistence: autosave every 60s, save on leave, flush on shutdown.
PlayerDataStore.bindToClose()
PlayerDataStore.startAutosave()

-- 4. The living world: wild brainrots, storms and events, ZORK's raids.
WildSpawner.start()
StormService.start()
ThiefService.start()

-- 5. The core loop: remote handlers, income tick, player lifecycle.
GameService.start()

print("[BRAINROT ORBIT] Server ready — catch them, dock them, get rich before the storm hits.")
