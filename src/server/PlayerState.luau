--!strict
-- PlayerState
-- The single owner of per-player runtime state in BRAINROT ORBIT. One record
-- per player, created on join and destroyed on leave: the loaded profile
-- (credits, upgrades, missions, saved roster), the assigned module, the
-- cargo bubble, the docked brainrots and every cooldown. GameService reads
-- and mutates state only through this module, so there is exactly one place
-- where a player's credits or roster can change.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Player = any
type Model = any
type BasePart = any
type Vector3 = any

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local requireModule = require :: any
local BrainrotData = requireModule(ReplicatedStorage:WaitForChild("BrainrotData"))
local BrainrotFactory = requireModule(ServerScriptService:WaitForChild("BrainrotFactory"))
local PlayerDataStore = requireModule(ServerScriptService:WaitForChild("PlayerDataStore"))
local WorldBuilder = requireModule(ServerScriptService:WaitForChild("WorldBuilder"))

local PlayerState = {}

export type BrainrotInstance = {
	id: string,
	species: string,
	mutation: string,
	rate: number,
	model: Model?,
}

export type PlayerRuntime = {
	player: Player,
	profile: any,
	moduleIndex: number,
	cargo: { BrainrotInstance },
	docked: { [number]: BrainrotInstance },
	lockUntil: number,
	lockCooldownUntil: number,
	lastCatchAt: number,
	lastStealAt: number,
	lastBonkAt: number,
	bubble: Model?,
	ready: boolean,
}

local runtimes: { [Player]: PlayerRuntime } = {}
local idCounter = 0

function PlayerState.newBrainrotId(): string
	idCounter += 1
	return `b{idCounter}-{math.floor(os.clock() * 1000)}`
end

function PlayerState.get(player: Player): PlayerRuntime?
	return runtimes[player]
end

function PlayerState.getAll(): { PlayerRuntime }
	local list: { PlayerRuntime } = {}
	for _, runtime in runtimes do
		table.insert(list, runtime)
	end
	return list
end

-- Finds the lowest-numbered module nobody owns yet. Returns 0 when all 8 are taken.
local function claimFreeModule(player: Player): number
	for i = 1, #WorldBuilder.MODULES do
		local module = WorldBuilder.MODULES[i]
		if module.owner == nil then
			module.owner = player
			WorldBuilder.setModuleOwner(i, player.Name)
			return i
		end
	end
	return 0
end

local function releaseModule(moduleIndex: number)
	local module = WorldBuilder.MODULES[moduleIndex]
	if not module then
		return
	end
	module.owner = nil
	WorldBuilder.setModuleOwner(moduleIndex, nil)
	WorldBuilder.setDomeVisible(moduleIndex, false)
end

-- Creates the runtime record for a player: claims a module and rebuilds the
-- docked roster from the saved profile so progress survives a rejoin.
function PlayerState.create(player: Player, profile: any): PlayerRuntime
	local moduleIndex = claimFreeModule(player)
	local runtime: PlayerRuntime = {
		player = player,
		profile = profile,
		moduleIndex = moduleIndex,
		cargo = {},
		docked = {},
		lockUntil = 0,
		lockCooldownUntil = 0,
		lastCatchAt = 0,
		lastStealAt = 0,
		lastBonkAt = 0,
		bubble = nil,
		ready = false,
	}
	runtimes[player] = runtime

	-- Restore the saved docked roster onto the module's pods.
	if moduleIndex > 0 then
		local module = WorldBuilder.MODULES[moduleIndex]
		local saved = profile.data.docked :: { any }
		for podIndex, entry in saved do
			if podIndex <= #module.podPositions and BrainrotData.getSpecies(entry.species) then
				local rate = BrainrotData.getRate(entry.species, entry.mutation)
				local model = BrainrotFactory.buildBrainrotModel(entry.species, entry.mutation, PlayerState.newBrainrotId())
				model:SetAttribute("Animate", "Bob")
				local podPos = module.podPositions[podIndex] :: Vector3
				model:PivotTo(CFrame.new(podPos + Vector3.new(0, 0.7 + BrainrotFactory.getRestHeight(entry.species), 0)))
				model.Parent = Workspace
				runtime.docked[podIndex] = {
					id = model:GetAttribute("BrainrotId"),
					species = entry.species,
					mutation = entry.mutation,
					rate = rate,
					model = model,
				}
			end
		end
	end
	return runtime
end

-- Tears a player's runtime down: destroys the cargo bubble and docked models,
-- releases the module. The profile itself is saved by PlayerDataStore.
function PlayerState.remove(player: Player)
	local runtime = runtimes[player]
	if not runtime then
		return
	end
	runtimes[player] = nil
	if runtime.bubble then
		runtime.bubble:Destroy()
		runtime.bubble = nil
	end
	for _, brainrot in runtime.docked do
		if brainrot.model then
			brainrot.model:Destroy()
		end
	end
	runtime.docked = {}
	for _, brainrot in runtime.cargo do
		if brainrot.model then
			brainrot.model:Destroy()
		end
	end
	runtime.cargo = {}
	if runtime.moduleIndex > 0 then
		releaseModule(runtime.moduleIndex)
	end
end

-- Sum of the docked brainrots' rates, before multipliers.
function PlayerState.getBaseRate(runtime: PlayerRuntime): number
	local total = 0
	for _, brainrot in runtime.docked do
		total += brainrot.rate
	end
	return total
end

-- Income multiplier: +50% per rebirth ring, doubled during Golden Hour,
-- and doubled again while sheltered inside a shield dome during a solar
-- storm (round 7 Safe Dome bonus: hiding pays).
function PlayerState.getMultiplier(runtime: PlayerRuntime, goldenHourActive: boolean, stormSheltered: boolean?): number
	local multiplier = 1 + runtime.profile.data.rebirths * BrainrotData.CONFIG.rebirthMultiplierPerRing
	if goldenHourActive then
		multiplier *= BrainrotData.CONFIG.goldenHourMultiplier
	end
	if stormSheltered then
		multiplier *= 2
	end
	return multiplier
end

function PlayerState.getIncomeRate(runtime: PlayerRuntime, goldenHourActive: boolean, stormSheltered: boolean?): number
	return PlayerState.getBaseRate(runtime) * PlayerState.getMultiplier(runtime, goldenHourActive, stormSheltered)
end

function PlayerState.getUpgradeLevel(runtime: PlayerRuntime, track: string): number
	local level = runtime.profile.data.upgrades[track]
	if typeof(level) == "number" then
		return level
	end
	return 0
end

function PlayerState.getBeamRange(runtime: PlayerRuntime): number
	local track = BrainrotData.UPGRADES.Beam
	local level = math.clamp(PlayerState.getUpgradeLevel(runtime, "Beam"), 0, #track.levels - 1)
	return track.levels[level + 1].beamRange or 24
end

function PlayerState.getCarryCapacity(runtime: PlayerRuntime): number
	local track = BrainrotData.UPGRADES.Cargo
	local level = math.clamp(PlayerState.getUpgradeLevel(runtime, "Cargo"), 0, #track.levels - 1)
	return track.levels[level + 1].carryCapacity or 1
end

function PlayerState.getLockSeconds(runtime: PlayerRuntime): number
	local track = BrainrotData.UPGRADES.Shield
	local level = math.clamp(PlayerState.getUpgradeLevel(runtime, "Shield"), 0, #track.levels - 1)
	return track.levels[level + 1].lockSeconds or 30
end

function PlayerState.getMaxPods(runtime: PlayerRuntime): number
	local track = BrainrotData.UPGRADES.Expansion
	local level = math.clamp(PlayerState.getUpgradeLevel(runtime, "Expansion"), 0, #track.levels - 1)
	local extra = track.levels[level + 1].extraPods or 0
	return math.min(BrainrotData.CONFIG.basePods + runtime.profile.data.rebirths + extra, BrainrotData.CONFIG.maxPods)
end

function PlayerState.getDockedCount(runtime: PlayerRuntime): number
	local count = 0
	for _ in runtime.docked do
		count += 1
	end
	return count
end

-- First empty pod index within the player's current pod cap, or nil.
function PlayerState.getFreePodIndex(runtime: PlayerRuntime): number?
	local maxPods = PlayerState.getMaxPods(runtime)
	for i = 1, maxPods do
		if runtime.docked[i] == nil then
			return i
		end
	end
	return nil
end

function PlayerState.isModuleLocked(runtime: PlayerRuntime): boolean
	return os.clock() < runtime.lockUntil
end

function PlayerState.getLockSecondsLeft(runtime: PlayerRuntime): number
	return math.max(0, runtime.lockUntil - os.clock())
end

-- Adds credits. Income (pod ticks) also feeds the lifetime totals and the
-- "earn" mission; bonuses (mission rewards, bonk bonus) do not.
function PlayerState.addCredits(runtime: PlayerRuntime, amount: number, isIncome: boolean)
	if amount ~= amount or math.abs(amount) == math.huge then
		return
	end
	runtime.profile.data.credits += amount
	if isIncome and amount > 0 then
		runtime.profile.data.totalEarned += amount
		runtime.profile.data.missionEarned += amount
	end
	PlayerDataStore.markDirty(runtime.player)
end

function PlayerState.spendCredits(runtime: PlayerRuntime, amount: number): boolean
	if runtime.profile.data.credits < amount then
		return false
	end
	runtime.profile.data.credits -= amount
	PlayerDataStore.markDirty(runtime.player)
	return true
end

function PlayerState.addDiscovered(runtime: PlayerRuntime, species: string)
	if runtime.profile.data.discovered[species] ~= true then
		runtime.profile.data.discovered[species] = true
		PlayerDataStore.markDirty(runtime.player)
	end
end

-- Writes the live docked roster back into the saved profile.
function PlayerState.syncDockedToProfile(runtime: PlayerRuntime)
	local saved: { any } = {}
	for podIndex = 1, BrainrotData.CONFIG.maxPods do
		local brainrot = runtime.docked[podIndex]
		if brainrot then
			saved[podIndex] = { species = brainrot.species, mutation = brainrot.mutation }
		end
	end
	runtime.profile.data.docked = saved
	PlayerDataStore.markDirty(runtime.player)
end

-- The player's current mission: index (1-based), definition, live progress.
function PlayerState.getMissionState(runtime: PlayerRuntime): { index: number, mission: any, progress: number, complete: boolean }
	local completed = runtime.profile.data.missionsCompleted
	local missions = BrainrotData.MISSIONS
	if completed >= #missions then
		return { index = #missions, mission = missions[#missions], progress = missions[#missions].goal, complete = true }
	end
	local mission = missions[completed + 1]
	local progress = 0
	if mission.stat == "caught" then
		progress = runtime.profile.data.missionCaught
	elseif mission.stat == "docked" then
		progress = runtime.profile.data.missionDocked
	elseif mission.stat == "earned" then
		progress = runtime.profile.data.missionEarned
	elseif mission.stat == "locked" then
		progress = runtime.profile.data.missionLocked
	end
	return { index = completed + 1, mission = mission, progress = math.min(progress, mission.goal), complete = false }
end

-- Records mission progress (a catch, a dock, a lock, or earned credits).
-- Returns the mission that JUST completed, if any, so the caller can pay
-- its reward.
function PlayerState.recordMissionStat(runtime: PlayerRuntime, stat: string, amount: number): any?
	local data = runtime.profile.data
	if stat == "caught" then
		data.missionCaught += amount
	elseif stat == "docked" then
		data.missionDocked += amount
	elseif stat == "locked" then
		data.missionLocked += amount
	end
	PlayerDataStore.markDirty(runtime.player)
	local state = PlayerState.getMissionState(runtime)
	if state.complete then
		return nil
	end
	if state.progress >= state.mission.goal then
		data.missionsCompleted += 1
		PlayerDataStore.markDirty(runtime.player)
		return state.mission
	end
	return nil
end

-- Creates the cargo bubble above the player's head (once) and returns it.
function PlayerState.ensureBubble(runtime: PlayerRuntime): Model
	if runtime.bubble and runtime.bubble.Parent then
		return runtime.bubble
	end
	local bubble = Instance.new("Model")
	bubble.Name = `{runtime.player.Name}CargoBubble`
	local sphere = Instance.new("Part")
	sphere.Name = "Bubble"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(7, 7, 7)
	sphere.Color = Color3.fromRGB(140, 210, 255)
	sphere.Material = Enum.Material.ForceField
	sphere.Transparency = 0.45
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.Parent = bubble
	bubble.PrimaryPart = sphere
	bubble.Parent = Workspace
	-- Pin the pivot to the sphere so adding carried brainrots never shifts it.
	bubble.WorldPivot = CFrame.new(0, 10, 0)
	runtime.bubble = bubble
	return bubble
end

function PlayerState.destroyBubble(runtime: PlayerRuntime)
	if runtime.bubble then
		runtime.bubble:Destroy()
		runtime.bubble = nil
	end
end

-- Keeps the cargo bubble floating above the player's head. Called every
-- Heartbeat by GameService; a no-op when the player carries nothing.
function PlayerState.updateBubblePosition(runtime: PlayerRuntime)
	local bubble = runtime.bubble
	if not bubble or not bubble.Parent then
		return
	end
	if #runtime.cargo == 0 then
		PlayerState.destroyBubble(runtime)
		return
	end
	local character = runtime.player.Character
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local anchor = head or root
	if not anchor then
		return
	end
	bubble:PivotTo(CFrame.new(anchor.Position + Vector3.new(0, 4.5, 0)))
end

-- Rebirth cost: 5,000 credits, doubling with every ring.
function PlayerState.getRebirthCost(runtime: PlayerRuntime): number
	return BrainrotData.CONFIG.rebirthBaseCost * (2 ^ runtime.profile.data.rebirths)
end

-- The live value of one quest's stat, read from the saved profile (or
-- derived from it: discovered counts the Star Chart, upgrades sums the
-- four tracks).
local function getQuestStatValue(runtime: PlayerRuntime, stat: string): number
	local data = runtime.profile.data
	if stat == "caught" then
		return data.missionCaught
	elseif stat == "docked" then
		return data.missionDocked
	elseif stat == "earned" then
		return data.missionEarned
	elseif stat == "locked" then
		return data.missionLocked
	elseif stat == "discovered" then
		local count = 0
		for _ in data.discovered do
			count += 1
		end
		return count
	elseif stat == "upgrades" then
		local total = 0
		for _, level in data.upgrades do
			total += level
		end
		return total
	elseif stat == "rebirths" then
		return data.rebirths
	elseif stat == "stolen" then
		return data.questStolen or 0
	elseif stat == "zapped" then
		return data.questZapped or 0
	end
	return 0
end

-- Every quest with its live progress and done flag, in table order. This
-- is what the client renders in the Quests panel.
function PlayerState.getQuestStates(runtime: PlayerRuntime): { any }
	local states: { any } = {}
	for _, quest in BrainrotData.QUESTS do
		table.insert(states, {
			id = quest.id,
			text = quest.text,
			progress = math.min(getQuestStatValue(runtime, quest.stat), quest.goal),
			goal = quest.goal,
			reward = quest.reward,
			done = runtime.profile.data.questsDone[quest.id] == true,
		})
	end
	return states
end

-- Pays every quest that JUST completed (goal reached, reward not yet
-- paid). Returns the completed quests so the caller can announce them.
-- Idempotent: a quest already in questsDone is never paid twice.
function PlayerState.completeQuests(runtime: PlayerRuntime): { any }
	local completed: { any } = {}
	for _, quest in BrainrotData.QUESTS do
		if runtime.profile.data.questsDone[quest.id] ~= true and getQuestStatValue(runtime, quest.stat) >= quest.goal then
			runtime.profile.data.questsDone[quest.id] = true
			PlayerState.addCredits(runtime, quest.reward, false)
			table.insert(completed, quest)
		end
	end
	if #completed > 0 then
		PlayerDataStore.markDirty(runtime.player)
	end
	return completed
end

return PlayerState
