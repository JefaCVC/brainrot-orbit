--!strict
-- Main
-- Server bootstrap for BRAINROT ORBIT. Startup order matters: the remotes
-- are created first (the client waits for them), then the world is built
-- (before any character loads, so nobody spawns into a void), then the
-- services start. Player characters load only after this script runs, via
-- GameService, because Players.CharacterAutoLoads is false in the project.

local Players = game:GetService("Players")
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

-- 1. The whitelisted remotes, under ReplicatedStorage/OrbitRemotes.
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

-- 6. Spawn view: every character (first spawn and respawns) starts on the
-- observation deck facing the planet through the north windows, with the
-- title pedestals and the wild brainrots in front of them. The root part
-- sits 3 studs above the deck so the character stands on the floor instead
-- of sinking into it.
local SPAWN_CFRAME = CFrame.lookAt(Vector3.new(0, 3, 34), Vector3.new(350, 10, -450))

local function positionAtSpawn(character: any)
	local root = character:WaitForChild("HumanoidRootPart")
	if root then
		character:PivotTo(SPAWN_CFRAME)
	end
end

local function onPlayerAddedForSpawn(player: any)
	player.CharacterAdded:Connect(positionAtSpawn)
	if player.Character then
		task.spawn(positionAtSpawn, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAddedForSpawn)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAddedForSpawn, player)
end

print("[BRAINROT ORBIT] Server ready — catch them, dock them, get rich before the storm hits.")
