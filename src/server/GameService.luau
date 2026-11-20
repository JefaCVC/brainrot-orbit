--!strict
-- GameService
-- The core loop of BRAINROT ORBIT, server-authoritative. Every remote the
-- client can fire lands here, and every handler validates the same way:
-- rate limit first, then type, then range (measured from the SERVER's copy
-- of the character, never a client-reported position), then ownership and
-- state. The client sends intent only; the server decides what happens.
--
-- This module also runs the income tick (pods pay credits every second),
-- pushes HUD state to every player, refreshes shield domes, patrols the
-- cleaning robot and the delivery drone, blinks the console lights, and
-- owns the player lifecycle (load, module claim, save).

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Player = any
type RemoteEvent = any
type Vector3 = any
type Model = any

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local requireModule = require :: any
local BrainrotData = requireModule(ReplicatedStorage:WaitForChild("BrainrotData"))
local BrainrotFactory = requireModule(ServerScriptService:WaitForChild("BrainrotFactory"))
local PlayerDataStore = requireModule(ServerScriptService:WaitForChild("PlayerDataStore"))
local PlayerState = requireModule(ServerScriptService:WaitForChild("PlayerState"))
local Remotes = requireModule(ReplicatedStorage:WaitForChild("Remotes"))
local StormService = requireModule(ServerScriptService:WaitForChild("StormService"))
local ThiefService = requireModule(ServerScriptService:WaitForChild("ThiefService"))
local WildSpawner = requireModule(ServerScriptService:WaitForChild("WildSpawner"))
local WorldBuilder = requireModule(ServerScriptService:WaitForChild("WorldBuilder"))

local GameService = {}

local rng = Random.new()
local robotWaypointIndex = 1
local droneWaypointIndex = 1

-- Offsets for carried brainrots inside the cargo bubble (up to 3).
local CARGO_OFFSETS = { Vector3.new(0, 0, 0), Vector3.new(-2.1, 0.4, 0), Vector3.new(2.1, 0.4, 0) }

local function toast(player: Player, text: string)
	local remote = Remotes.get("Toast") :: RemoteEvent?
	if remote then
		remote:FireClient(player, text)
	end
end

local function fireFx(player: Player?, payload: { [string]: any })
	local remote = Remotes.get("FxEvent") :: RemoteEvent?
	if not remote then
		return
	end
	if player then
		remote:FireClient(player, payload)
	else
		remote:FireAllClients(payload)
	end
end

local function getRootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	return root.Position
end

local function isFiniteNumber(value: unknown): boolean
	if typeof(value) ~= "number" then
		return false
	end
	local n = value :: number
	return n == n and math.abs(n) ~= math.huge
end

-- Shows a module's shield dome while it is locked or a storm is active.
function GameService.refreshDomes()
	local stormActive = StormService.isStormActive()
	for _, runtime in PlayerState.getAll() do
		if runtime.moduleIndex > 0 then
			WorldBuilder.setDomeVisible(runtime.moduleIndex, PlayerState.isModuleLocked(runtime) or stormActive)
		end
	end
end

-- True when the player is standing inside any shield dome while a storm
-- is active: the Safe Dome pays x2 income during the storm (round 7).
local function isStormSheltered(runtime: any): boolean
	if not StormService.isStormActive() then
		return false
	end
	local rootPosition = getRootPosition(runtime.player)
	if not rootPosition then
		return false
	end
	return WorldBuilder.isInsideAnyDome(rootPosition)
end

-- Builds the full HUD state table for one player and pushes it to them.
function GameService.pushState(runtime: any)
	local player = runtime.player
	local remote = Remotes.get("StateUpdate") :: RemoteEvent?
	if not remote then
		return
	end
	local data = runtime.profile.data
	local goldenHour = StormService.isGoldenHour()
	local sheltered = isStormSheltered(runtime)
	local roster: { any } = {}
	for podIndex = 1, BrainrotData.CONFIG.maxPods do
		local brainrot = runtime.docked[podIndex]
		if brainrot then
			local species = BrainrotData.getSpecies(brainrot.species)
			local entry: { [string]: any } = {
				pod = podIndex,
				name = brainrot.species,
				rarity = species and species.rarity or "Common",
				mutation = brainrot.mutation,
				rate = brainrot.rate,
			}
			table.insert(roster, entry)
		end
	end
	local cargo: { any } = {}
	for _, brainrot in runtime.cargo do
		local species = BrainrotData.getSpecies(brainrot.species)
		local entry: { [string]: any } = {
			name = brainrot.species,
			rarity = species and species.rarity or "Common",
			mutation = brainrot.mutation,
			rate = brainrot.rate,
		}
		table.insert(cargo, entry)
	end
	local missionState = PlayerState.getMissionState(runtime)
	local questStates = PlayerState.getQuestStates(runtime)
	local questsDoneCount = 0
	for _, questState in questStates do
		if questState.done then
			questsDoneCount += 1
		end
	end
	local state = {
		credits = data.credits,
		rate = PlayerState.getIncomeRate(runtime, goldenHour, sheltered),
		baseRate = PlayerState.getBaseRate(runtime),
		multiplier = PlayerState.getMultiplier(runtime, goldenHour, sheltered),
		rebirths = data.rebirths,
		rebirthCost = PlayerState.getRebirthCost(runtime),
		moduleIndex = runtime.moduleIndex,
		podsUsed = PlayerState.getDockedCount(runtime),
		podsMax = PlayerState.getMaxPods(runtime),
		roster = roster,
		cargo = cargo,
		cargoCapacity = PlayerState.getCarryCapacity(runtime),
		upgrades = data.upgrades,
		mission = {
			index = missionState.index,
			total = #BrainrotData.MISSIONS,
			text = missionState.mission.text,
			progress = missionState.progress,
			goal = missionState.mission.goal,
			reward = missionState.mission.reward,
			complete = missionState.complete,
		},
		missionsCompleted = data.missionsCompleted,
		quests = questStates,
		questsDoneCount = questsDoneCount,
		questsTotal = #BrainrotData.QUESTS,
		discovered = data.discovered,
		lockSecondsLeft = PlayerState.getLockSecondsLeft(runtime),
		lockCooldownLeft = math.max(0, runtime.lockCooldownUntil - os.clock()),
		storm = StormService.getStormState(),
		stormSheltered = sheltered,
		goldenHourLeft = StormService.getGoldenHourSecondsLeft(),
		zorkActive = ThiefService.isZorkActive(),
	}
	remote:FireClient(player, state)
end

function GameService.pushAllStates()
	for _, runtime in PlayerState.getAll() do
		if runtime.ready then
			GameService.pushState(runtime)
		end
	end
end

-- Pays a completed mission's reward and tells the player.
local function completeMissionIfReady(runtime: any, stat: string, amount: number)
	local mission = PlayerState.recordMissionStat(runtime, stat, amount)
	if mission then
		PlayerState.addCredits(runtime, mission.reward, false)
		toast(runtime.player, `MISSION COMPLETE! +{mission.reward} credits`)
		GameService.pushState(runtime)
	end
end

-- Pays every quest that just completed and announces each one (the HUD
-- feed picks these lines up too). Called after any action that can move a
-- quest stat, and on the income tick for the earn quests.
local function completeQuestsIfReady(runtime: any)
	local completed = PlayerState.completeQuests(runtime)
	for _, quest in completed do
		toast(runtime.player, `QUEST DONE: {quest.text} +${quest.reward}`)
	end
	if #completed > 0 then
		GameService.pushState(runtime)
	end
end

-- Adds a brainrot instance to a player's cargo bubble (visual + state).
local function addToCargo(runtime: any, brainrot: any)
	local bubble = PlayerState.ensureBubble(runtime)
	table.insert(runtime.cargo, brainrot)
	local index = #runtime.cargo
	if brainrot.model then
		local model = brainrot.model :: Model
		model:SetAttribute("Animate", "None")
		model.Parent = bubble
		local offset = CARGO_OFFSETS[math.min(index, #CARGO_OFFSETS)]
		model:PivotTo(bubble:GetPivot() * CFrame.new(offset))
	end
end

-- CATCH: tractor-beam the nearest wild brainrot inside beam range into the
-- cargo bubble. The server picks the target from its own state; the client
-- only says "I pressed E".
local function onCatchBrainrot(player: Player)
	local runtime = PlayerState.get(player)
	if not runtime then
		return
	end
	local now = os.clock()
	if now - runtime.lastCatchAt < BrainrotData.CONFIG.catchCooldownSeconds then
		toast(player, "Tractor beam recharging…")
		return
	end
	runtime.lastCatchAt = now
	if #runtime.cargo >= PlayerState.getCarryCapacity(runtime) then
		toast(player, "Cargo bubble full! Dock your brainrots first.")
		return
	end
	local rootPosition = getRootPosition(player)
	if not rootPosition then
		return
	end
	local wild = WildSpawner.getNearestWild(rootPosition, PlayerState.getBeamRange(runtime))
	if not wild then
		toast(player, "No wild brainrot in tractor-beam range.")
		return
	end
	local removed = WildSpawner.removeWild(wild.id)
	if not removed then
		return -- someone else caught it first
	end
	local brainrot = {
		id = removed.id,
		species = removed.species,
		mutation = removed.mutation,
		rate = removed.rate,
		model = removed.model,
	}
	addToCargo(runtime, brainrot)
	PlayerState.addDiscovered(runtime, removed.species)
	local species = BrainrotData.getSpecies(removed.species)
	local burstColor = species and BrainrotData.RARITY_COLORS[species.rarity] or Color3.fromRGB(120, 220, 255)
	fireFx(player, { kind = "beam", from = rootPosition, to = removed.model:GetPivot().Position })
	fireFx(player, { kind = "burst", position = removed.model:GetPivot().Position, color = burstColor })
	toast(player, `Caught {removed.species}! Carry it home to your pods.`)
	completeMissionIfReady(runtime, "caught", 1)
	completeQuestsIfReady(runtime)
	GameService.pushState(runtime)
end

-- DOCK: place the first carried brainrot in the nearest empty pod of the
-- player's own module. The player must be standing next to the pod.
local function onDockBrainrot(player: Player)
	local runtime = PlayerState.get(player)
	if not runtime or runtime.moduleIndex == 0 then
		return
	end
	if #runtime.cargo == 0 then
		toast(player, "Cargo empty, catch a brainrot first!")
		return
	end
	local rootPosition = getRootPosition(player)
	if not rootPosition then
		return
	end
	local module = WorldBuilder.MODULES[runtime.moduleIndex]
	local maxPods = PlayerState.getMaxPods(runtime)
	local bestPod: number? = nil
	local bestDistance = BrainrotData.CONFIG.dockRangeStuds
	for podIndex = 1, maxPods do
		if runtime.docked[podIndex] == nil then
			local podPos = module.podPositions[podIndex] :: Vector3
			local distance = (Vector3.new(podPos.X, 0, podPos.Z) - Vector3.new(rootPosition.X, 0, rootPosition.Z)).Magnitude
			if distance <= bestDistance then
				bestPod = podIndex
				bestDistance = distance
			end
		end
	end
	if not bestPod then
		toast(player, "Stand next to an empty pod in your module!")
		return
	end
	local brainrot = runtime.cargo[1]
	table.remove(runtime.cargo, 1)
	local podPos = module.podPositions[bestPod] :: Vector3
	if brainrot.model then
		local model = brainrot.model :: Model
		model:SetAttribute("Animate", "Bob")
		model.Parent = Workspace
		model:PivotTo(CFrame.new(podPos + Vector3.new(0, 0.7 + BrainrotFactory.getRestHeight(brainrot.species), 0)))
	end
	runtime.docked[bestPod] = brainrot
	PlayerState.syncDockedToProfile(runtime)
	if #runtime.cargo == 0 then
		PlayerState.destroyBubble(runtime)
	end
	fireFx(player, { kind = "dock", position = podPos + Vector3.new(0, 3, 0), rate = brainrot.rate, name = brainrot.species })
	toast(player, `Docked {brainrot.species}, earning ${brainrot.rate}/s!`)
	completeMissionIfReady(runtime, "docked", 1)
	completeQuestsIfReady(runtime)
	GameService.pushState(runtime)
end

-- LOCK: raise the module's energy shield. While locked, nobody can steal
-- from the module and ZORK will not target it.
local function onLockModule(player: Player)
	local runtime = PlayerState.get(player)
	if not runtime then
		return
	end
	if runtime.moduleIndex == 0 then
		toast(player, "You don't have a module yet!")
		return
	end
	local now = os.clock()
	if now < runtime.lockCooldownUntil then
		toast(player, `Shield recharging, {math.ceil(runtime.lockCooldownUntil - now)}s left.`)
		return
	end
	if PlayerState.isModuleLocked(runtime) then
		toast(player, "Your module is already locked!")
		return
	end
	local lockSeconds = PlayerState.getLockSeconds(runtime)
	runtime.lockUntil = now + lockSeconds
	runtime.lockCooldownUntil = now + lockSeconds + BrainrotData.CONFIG.lockCooldownSeconds
	GameService.refreshDomes()
	toast(player, `Module locked for {lockSeconds}s! Nobody can steal from you.`)
	completeMissionIfReady(runtime, "locked", 1)
	completeQuestsIfReady(runtime)
	GameService.pushState(runtime)
end

-- STEAL: take the nearest docked brainrot from a rival's UNLOCKED module
-- into the cargo bubble. The victim is told immediately.
local function onStealBrainrot(player: Player)
	local runtime = PlayerState.get(player)
	if not runtime then
		return
	end
	local now = os.clock()
	if now - runtime.lastStealAt < BrainrotData.CONFIG.stealCooldownSeconds then
		return
	end
	runtime.lastStealAt = now
	if #runtime.cargo >= PlayerState.getCarryCapacity(runtime) then
		toast(player, "Cargo bubble full! Dock your brainrots first.")
		return
	end
	local rootPosition = getRootPosition(player)
	if not rootPosition then
		return
	end
	local bestVictim: any? = nil
	local bestPod: number? = nil
	local bestDistance = BrainrotData.CONFIG.stealRangeStuds
	for _, other in PlayerState.getAll() do
		if other.player ~= player and other.moduleIndex > 0 and not PlayerState.isModuleLocked(other) then
			for podIndex, brainrot in other.docked do
				if brainrot.model then
					local pivot = (brainrot.model :: Model):GetPivot().Position
					local distance = (Vector3.new(pivot.X, 0, pivot.Z) - Vector3.new(rootPosition.X, 0, rootPosition.Z)).Magnitude
					if distance <= bestDistance then
						bestVictim = other
						bestPod = podIndex
						bestDistance = distance
					end
				end
			end
		end
	end
	if not bestVictim or not bestPod then
		toast(player, "No stealable brainrot nearby (locked modules are safe).")
		return
	end
	local stolen = bestVictim.docked[bestPod]
	local stealPosition = (stolen.model :: Model):GetPivot().Position
	bestVictim.docked[bestPod] = nil
	PlayerState.syncDockedToProfile(bestVictim)
	addToCargo(runtime, stolen)
	PlayerState.addDiscovered(runtime, stolen.species)
	runtime.profile.data.questStolen = (runtime.profile.data.questStolen or 0) + 1
	PlayerDataStore.markDirty(player)
	fireFx(player, { kind = "steal", position = stealPosition })
	toast(player, `You stole {stolen.species} from {bestVictim.player.Name}! Run home!`)
	toast(bestVictim.player, `{player.Name} stole your {stolen.species}!`)
	completeQuestsIfReady(runtime)
	GameService.pushState(runtime)
	GameService.pushState(bestVictim)
end

-- REBIRTH: open a new station ring. Costs credits (doubling each time) and
-- resets credits to 0 and releases the docked roster back into the wild —
-- but every ring pays +50% credits forever and adds a habitat pod.
local function onRebirth(player: Player)
	local runtime = PlayerState.get(player)
	if not runtime then
		return
	end
	local cost = PlayerState.getRebirthCost(runtime)
	local data = runtime.profile.data
	if data.credits < cost then
		toast(player, `Rebirth costs ${cost} credits, you have ${math.floor(data.credits)}.`)
		return
	end
	for _, brainrot in runtime.docked do
		local module = WorldBuilder.MODULES[runtime.moduleIndex]
		local center = module and module.center or Vector3.new(0, 0, 0)
		local dropAt = center + Vector3.new(rng:NextNumber() * 20 - 10, 0, rng:NextNumber() * 20 - 10)
		WildSpawner.spawnWildAt(dropAt, brainrot.species, brainrot.mutation)
		if brainrot.model then
			(brainrot.model :: Model):Destroy()
		end
	end
	runtime.docked = {}
	data.credits = 0
	data.rebirths += 1
	PlayerState.syncDockedToProfile(runtime)
	PlayerDataStore.markDirty(player)
	local rootPosition = getRootPosition(player)
	fireFx(player, { kind = "confetti", position = rootPosition or Vector3.new(0, 3, 0) })
	toast(player, `REBIRTH! New station ring: +50% credits forever, +1 pod! (Ring {data.rebirths})`)
	completeQuestsIfReady(runtime)
	GameService.pushState(runtime)
end

-- BUY UPGRADE: one level of one named track. The track name and the level
-- are validated against the shared data; the price comes from the server.
local function onBuyUpgrade(player: Player, track: unknown)
	local runtime = PlayerState.get(player)
	if not runtime then
		return
	end
	if typeof(track) ~= "string" then
		return
	end
	local trackData = BrainrotData.UPGRADES[track]
	if not trackData then
		return
	end
	local level = PlayerState.getUpgradeLevel(runtime, track)
	if level >= #trackData.levels - 1 then
		toast(player, `{trackData.displayName} is already max level!`)
		return
	end
	local nextLevel = trackData.levels[level + 2]
	if not PlayerState.spendCredits(runtime, nextLevel.cost) then
		toast(player, `Not enough credits for {trackData.displayName} {nextLevel.name} (${nextLevel.cost}).`)
		return
	end
	runtime.profile.data.upgrades[track] = level + 1
	PlayerDataStore.markDirty(player)
	toast(player, `{trackData.displayName} upgraded to {nextLevel.name}!`)
	completeQuestsIfReady(runtime)
	GameService.pushState(runtime)
end

-- BONK: swing the Plasma Bat at ZORK. The server checks the range from its
-- own copy of the character; the bonk count lives in ThiefService.
local function onBonkZork(player: Player)
	local runtime = PlayerState.get(player)
	if not runtime then
		return
	end
	local now = os.clock()
	if now - runtime.lastBonkAt < BrainrotData.CONFIG.bonkCooldownSeconds then
		return
	end
	runtime.lastBonkAt = now
	if not ThiefService.isZorkActive() then
		toast(player, "ZORK isn't here right now.")
		return
	end
	local rootPosition = getRootPosition(player)
	local zorkPosition = ThiefService.getZorkPosition()
	if not rootPosition or not zorkPosition then
		return
	end
	local distance = (Vector3.new(zorkPosition.X, 0, zorkPosition.Z) - Vector3.new(rootPosition.X, 0, rootPosition.Z)).Magnitude
	if not isFiniteNumber(distance) then
		return
	end
	if distance > BrainrotData.CONFIG.bonkRangeStuds then
		toast(player, "ZORK is too far away, get closer!")
		return
	end
	if ThiefService.bonkZork(player) then
		completeQuestsIfReady(runtime)
		GameService.pushState(runtime)
	end
end

-- DROP CARGO: everything in the bubble becomes wild where the player
-- stands. Called by the player (Q) and by the solar storm.
function GameService.dropCargo(player: Player)
	local runtime = PlayerState.get(player)
	if not runtime or #runtime.cargo == 0 then
		return
	end
	local rootPosition = getRootPosition(player)
	local module = WorldBuilder.MODULES[runtime.moduleIndex]
	local fallback = module and module.center or Vector3.new(0, 0, 0)
	local dropAt = rootPosition or fallback
	for _, brainrot in runtime.cargo do
		local spot = dropAt + Vector3.new(rng:NextNumber() * 8 - 4, 0, rng:NextNumber() * 8 - 4)
		WildSpawner.spawnWildAt(spot, brainrot.species, brainrot.mutation)
		if brainrot.model then
			(brainrot.model :: Model):Destroy()
		end
	end
	runtime.cargo = {}
	PlayerState.destroyBubble(runtime)
	toast(player, "Your cargo dropped!")
	GameService.pushState(runtime)
end

local function onDropCargo(player: Player)
	GameService.dropCargo(player)
end

local function onPlayerReady(player: Player)
	local runtime = PlayerState.get(player)
	if not runtime then
		return
	end
	runtime.ready = true
	GameService.pushState(runtime)
end

-- Income tick: every second, every player's pods pay out. Missions that
-- track earned credits complete here, as do the earn quests. Sheltered
-- players earn double during a storm (Safe Dome bonus).
local function incomeLoop()
	while true do
		task.wait(1)
		local goldenHour = StormService.isGoldenHour()
		for _, runtime in PlayerState.getAll() do
			local sheltered = isStormSheltered(runtime)
			local rate = PlayerState.getIncomeRate(runtime, goldenHour, sheltered)
			if rate > 0 then
				PlayerState.addCredits(runtime, rate, true)
				completeMissionIfReady(runtime, "earned", 0)
				completeQuestsIfReady(runtime)
			end
			if runtime.ready then
				GameService.pushState(runtime)
			end
		end
		GameService.refreshDomes()
	end
end

-- MOP-BOT patrol: the cleaning robot drifts between waypoints around the hub.
local function robotLoop()
	local robot = WorldBuilder.CLEANING_ROBOT
	if not robot then
		return
	end
	local waypoints = WorldBuilder.ROBOT_WAYPOINTS
	while true do
		local target = waypoints[robotWaypointIndex]
		robotWaypointIndex = robotWaypointIndex % #waypoints + 1
		local pivot = robot:GetPivot()
		local current = pivot.Position
		local distance = (Vector3.new(target.X, 0, target.Z) - Vector3.new(current.X, 0, current.Z)).Magnitude
		local duration = math.max(distance / 3, 0.5)
		local start = os.clock()
		while os.clock() - start < duration do
			local alpha = (os.clock() - start) / duration
			local lerped = current:Lerp(target, alpha)
			robot:PivotTo(CFrame.new(Vector3.new(lerped.X, 0, lerped.Z)))
			task.wait(0.1)
		end
		task.wait(2)
	end
end

-- DELIVERY DRONE patrol: the drone hovers at 8 studs between the hub, the
-- garden and the airlock, bobbing gently as it flies.
local function droneLoop()
	local drone = WorldBuilder.DELIVERY_DRONE
	if not drone then
		return
	end
	local waypoints = WorldBuilder.DRONE_WAYPOINTS
	while true do
		local target = waypoints[droneWaypointIndex]
		droneWaypointIndex = droneWaypointIndex % #waypoints + 1
		local pivot = drone:GetPivot()
		local current = pivot.Position
		local distance = (Vector3.new(target.X, 0, target.Z) - Vector3.new(current.X, 0, current.Z)).Magnitude
		local duration = math.max(distance / 5, 0.5)
		local start = os.clock()
		while os.clock() - start < duration do
			local alpha = (os.clock() - start) / duration
			local lerped = current:Lerp(target, alpha)
			local bob = math.sin(os.clock() * 2.5) * 0.4
			local pos = Vector3.new(lerped.X, target.Y + bob, lerped.Z)
			local facing = Vector3.new(target.X, pos.Y, target.Z)
			if (facing - pos).Magnitude > 0.5 then
				drone:PivotTo(CFrame.lookAt(pos, facing))
			else
				drone:PivotTo(CFrame.new(pos))
			end
			task.wait(0.1)
		end
		task.wait(2)
	end
end

-- Console blink loop: the hub consoles' light strips alternate bright and
-- dim, so the deck reads as powered and busy.
local function blinkLoop()
	local lights = WorldBuilder.CONSOLE_LIGHTS
	if #lights == 0 then
		return
	end
	local tick = 0
	while true do
		task.wait(0.8)
		tick += 1
		for i, light in lights do
			if light.Parent then
				light.Transparency = if (i + tick) % 2 == 0 then 0 else 0.75
			end
		end
	end
end

local function onHeartbeat(_dt: number)
	for _, runtime in PlayerState.getAll() do
		PlayerState.updateBubblePosition(runtime)
	end
end

local function onPlayerAdded(player: Player)
	-- Profile loading yields (DataStore), so it runs in its own thread; the
	-- character only loads once the world and the profile are ready.
	task.spawn(function()
		local profile = PlayerDataStore.loadProfile(player)
		if player.Parent ~= Players then
			PlayerDataStore.endSession(player)
			return
		end
		PlayerState.create(player, profile)
		player:LoadCharacter()
	end)
end

local function onPlayerRemoving(player: Player)
	local runtime = PlayerState.get(player)
	if runtime and #runtime.cargo > 0 then
		GameService.dropCargo(player)
	end
	PlayerState.remove(player)
	PlayerDataStore.endSession(player)
end

-- Finds a runtime by player name, or the first player when name is "first".
-- Used by the finalist-review tour.
function GameService.getRuntimeForPlayerName(name: string): any?
	if name == "first" or name == "" then
		for _, runtime in PlayerState.getAll() do
			return runtime
		end
		return nil
	end
	local player = Players:FindFirstChild(name)
	if not player then
		return nil
	end
	return PlayerState.get(player)
end

-- Sends a tour command to one player's client (show title, open panels...).
function GameService.sendTourCommand(player: Player, command: string)
	local remote = Remotes.get("TourCommand") :: RemoteEvent?
	if remote then
		remote:FireClient(player, command)
	end
end

-- Teleports a player's character to a world position (tour helper).
function GameService.teleportPlayerTo(player: Player, position: Vector3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	end
end

-- Fills a player's module with a showcase roster for the tour's module
-- screenshot: assorted rarities, a Gold, a Diamond and a Cosmic.
function GameService.grantDemoModule(runtime: any)
	local showcase = {
		{ "Bloop Blorp", "None" },
		{ "Plasma Pingu", "Gold" },
		{ "Nebula Noodle", "None" },
		{ "Cosmo Corgi", "Diamond" },
		{ "Solar Squirrel", "None" },
		{ "Galaxy Gator", "None" },
		{ "Pulsar Panda", "None" },
		{ "Big Bang Burrito", "Cosmic" },
	} :: { { string } }
	local module = WorldBuilder.MODULES[runtime.moduleIndex]
	if not module then
		return
	end
	for _, brainrot in runtime.docked do
		if brainrot.model then
			(brainrot.model :: Model):Destroy()
		end
	end
	runtime.docked = {}
	local maxPods = PlayerState.getMaxPods(runtime)
	for podIndex = 1, math.min(#showcase, maxPods) do
		local entry = showcase[podIndex]
		local model = BrainrotFactory.buildBrainrotModel(entry[1], entry[2], PlayerState.newBrainrotId())
		model:SetAttribute("Animate", "Bob")
		local podPos = module.podPositions[podIndex] :: Vector3
		model:PivotTo(CFrame.new(podPos + Vector3.new(0, 0.7 + BrainrotFactory.getRestHeight(entry[1]), 0)))
		model.Parent = Workspace
		runtime.docked[podIndex] = {
			id = model:GetAttribute("BrainrotId"),
			species = entry[1],
			mutation = entry[2],
			rate = BrainrotData.getRate(entry[1], entry[2]),
			model = model,
		}
		PlayerState.addDiscovered(runtime, entry[1])
	end
	runtime.profile.data.credits = 50000
	runtime.profile.data.missionsCompleted = 2
	runtime.profile.data.missionCaught = 6
	runtime.profile.data.missionDocked = 3
	runtime.profile.data.missionEarned = 1500
	runtime.profile.data.missionLocked = 1
	runtime.profile.data.upgrades = { Beam = 1, Cargo = 1, Shield = 0, Expansion = 0 }
	PlayerState.syncDockedToProfile(runtime)
	GameService.pushState(runtime)
end

-- Spawns a guaranteed Common wild brainrot in front of the player (tour).
function GameService.spawnWildInFront(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local forward = root.CFrame.LookVector
	local spot = root.Position + Vector3.new(forward.X, 0, forward.Z) * 10
	WildSpawner.spawnWildAt(spot, "Bloop Blorp", "None")
end

function GameService.start()
	-- Storm callbacks: the storm drops cargo and refreshes domes through us.
	StormService.dropCargoCallback = function(player: Player)
		GameService.dropCargo(player)
	end
	StormService.phaseChangedCallback = function(_phase: string)
		GameService.refreshDomes()
	end

	local catchRemote = Remotes.get("CatchBrainrot") :: RemoteEvent?
	local dockRemote = Remotes.get("DockBrainrot") :: RemoteEvent?
	local lockRemote = Remotes.get("LockModule") :: RemoteEvent?
	local stealRemote = Remotes.get("StealBrainrot") :: RemoteEvent?
	local rebirthRemote = Remotes.get("Rebirth") :: RemoteEvent?
	local upgradeRemote = Remotes.get("BuyUpgrade") :: RemoteEvent?
	local bonkRemote = Remotes.get("BonkZork") :: RemoteEvent?
	local dropRemote = Remotes.get("DropCargo") :: RemoteEvent?
	local readyRemote = Remotes.get("PlayerReady") :: RemoteEvent?
	if catchRemote then
		catchRemote.OnServerEvent:Connect(onCatchBrainrot)
	end
	if dockRemote then
		dockRemote.OnServerEvent:Connect(onDockBrainrot)
	end
	if lockRemote then
		lockRemote.OnServerEvent:Connect(onLockModule)
	end
	if stealRemote then
		stealRemote.OnServerEvent:Connect(onStealBrainrot)
	end
	if rebirthRemote then
		rebirthRemote.OnServerEvent:Connect(onRebirth)
	end
	if upgradeRemote then
		upgradeRemote.OnServerEvent:Connect(onBuyUpgrade)
	end
	if bonkRemote then
		bonkRemote.OnServerEvent:Connect(onBonkZork)
	end
	if dropRemote then
		dropRemote.OnServerEvent:Connect(onDropCargo)
	end
	if readyRemote then
		readyRemote.OnServerEvent:Connect(onPlayerReady)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	RunService.Heartbeat:Connect(onHeartbeat)
	task.spawn(incomeLoop)
	task.spawn(robotLoop)
	task.spawn(droneLoop)
	task.spawn(blinkLoop)
end

return GameService
