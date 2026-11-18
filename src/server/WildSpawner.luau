--!strict
-- WildSpawner
-- Owns the wild alien brainrots that roam the station: keeps the population
-- at its target, rolls species by rarity weight and mutations by chance,
-- wanders each one around its zone (hub or outer deck), and handles the
-- storm's Irradiated mutations and the Meteor Shower's bonus spawns.
-- GameService takes wild brainrots out of this module when a player catches
-- one, and puts brainrots back in when cargo is dropped.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Model = any
type Vector3 = any
type Instance = any

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local requireModule = require :: any
local BrainrotData = requireModule(ReplicatedStorage:WaitForChild("BrainrotData"))
local BrainrotFactory = requireModule(ServerScriptService:WaitForChild("BrainrotFactory"))
local PlayerState = requireModule(ServerScriptService:WaitForChild("PlayerState"))
local WorldBuilder = requireModule(ServerScriptService:WaitForChild("WorldBuilder"))

local WildSpawner = {}

export type WildBrainrot = {
	id: string,
	species: string,
	mutation: string,
	rate: number,
	model: Model,
	zone: string, -- "hub" | "deck"
	target: Vector3,
	nextRetargetAt: number,
	phase: number, -- waddle phase offset, so neighbours do not sway in sync
}

local wild: { [string]: WildBrainrot } = {}
local wildFolder: Instance? = nil
local rng = Random.new()
local started = false

local GOLD_CHANCE = 0.08
local DIAMOND_CHANCE = 0.03
local COSMIC_CHANCE = 0.005

-- Weighted species roll. With boostRare (Meteor Shower), Rare+ species are
-- five times as likely, so the shower feels generous.
local function rollSpecies(boostRare: boolean): string
	local total = 0
	for _, species in BrainrotData.SPECIES do
		local weight = species.weight
		if boostRare and (species.rarity == "Rare" or species.rarity == "Epic" or species.rarity == "Legendary" or species.rarity == "Secret") then
			weight *= 5
		end
		total += weight
	end
	local roll = rng:NextNumber() * total
	for _, species in BrainrotData.SPECIES do
		local weight = species.weight
		if boostRare and (species.rarity == "Rare" or species.rarity == "Epic" or species.rarity == "Legendary" or species.rarity == "Secret") then
			weight *= 5
		end
		roll -= weight
		if roll <= 0 then
			return species.name
		end
	end
	return BrainrotData.SPECIES[1].name
end

-- Mutation roll for a fresh wild spawn. Irradiated never rolls here: it
-- only ever comes from a solar storm (see irradiateExposed).
local function rollMutation(): string
	local roll = rng:NextNumber()
	if roll < COSMIC_CHANCE then
		return "Cosmic"
	elseif roll < COSMIC_CHANCE + DIAMOND_CHANCE then
		return "Diamond"
	elseif roll < COSMIC_CHANCE + DIAMOND_CHANCE + GOLD_CHANCE then
		return "Gold"
	end
	return "None"
end

-- True when a point is at least 10 studs from every other wild brainrot,
-- so wanderers spread out across the deck instead of clumping into one
-- pile with overlapping name tags.
local function isSeparated(candidate: Vector3, selfId: string?): boolean
	for id, other in wild do
		if id ~= selfId then
			local otherPos = other.model:GetPivot().Position
			local distance = (Vector3.new(candidate.X, 0, candidate.Z) - Vector3.new(otherPos.X, 0, otherPos.Z)).Magnitude
			if distance < 10 then
				return false
			end
		end
	end
	return true
end

local function pickWanderTarget(zone: string, from: Vector3, selfId: string?): Vector3
	local fallback: Vector3? = nil
	for _ = 1, 8 do
		local angle = rng:NextNumber() * math.pi * 2
		local distance = 8 + rng:NextNumber() * 18
		local candidate = from + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local radius = Vector3.new(candidate.X, 0, candidate.Z).Magnitude
		local inZone = (zone == "hub" and radius < 66) or (zone == "deck" and radius > 78 and radius < 108)
		if inZone then
			if not fallback then
				fallback = candidate
			end
			if isSeparated(candidate, selfId) then
				return candidate
			end
		end
	end
	return fallback or from
end

-- Spawns one wild brainrot at a position. Species/mutation may be forced
-- (dropped cargo keeps its identity); otherwise they are rolled.
function WildSpawner.spawnWildAt(position: Vector3, forcedSpecies: string?, forcedMutation: string?): WildBrainrot
	local species = forcedSpecies or rollSpecies(false)
	local mutation = forcedMutation or rollMutation()
	local id = PlayerState.newBrainrotId()
	local model = BrainrotFactory.buildBrainrotModel(species, mutation, id)
	model:SetAttribute("Animate", "Rock")
	local restHeight = BrainrotFactory.getRestHeight(species)
	model:PivotTo(CFrame.new(position + Vector3.new(0, restHeight, 0)))
	model.Parent = wildFolder
	local radius = Vector3.new(position.X, 0, position.Z).Magnitude
	local zone = if radius > 72 then "deck" else "hub"
	local entry: WildBrainrot = {
		id = id,
		species = species,
		mutation = mutation,
		rate = BrainrotData.getRate(species, mutation),
		model = model,
		zone = zone,
		target = position,
		nextRetargetAt = os.clock() + 4 + rng:NextNumber() * 4,
		phase = rng:NextNumber() * math.pi * 2,
	}
	wild[id] = entry
	return entry
end

-- Meteor Shower bonus: extra wild brainrots with boosted rarity, all on the
-- exposed outer deck so players must risk the open ring to grab them.
function WildSpawner.spawnMeteorBrainrots(count: number)
	for _ = 1, count do
		local position = WorldBuilder.getRandomOuterDeckPoint()
		local species = rollSpecies(true)
		WildSpawner.spawnWildAt(position, species, nil)
	end
end

-- Solar storm: every wild brainrot exposed outside the shield domes has a
-- chance to mutate Irradiated (x4 income). The model is rebuilt in place so
-- its name tag and glow show the new mutation.
function WildSpawner.irradiateExposed()
	local chance = BrainrotData.CONFIG.stormIrradiateChance
	local mutated = 0
	for id, entry in wild do
		if entry.mutation ~= "Irradiated" and rng:NextNumber() < chance then
			local pivot = entry.model:GetPivot()
			entry.model:Destroy()
			local model = BrainrotFactory.buildBrainrotModel(entry.species, "Irradiated", id)
			model:SetAttribute("Animate", "Rock")
			model:PivotTo(pivot)
			model.Parent = wildFolder
			entry.model = model
			entry.mutation = "Irradiated"
			entry.rate = BrainrotData.getRate(entry.species, "Irradiated")
			mutated += 1
		end
	end
	if mutated > 0 then
		print(`[WildSpawner] Solar storm irradiated {mutated} wild brainrot(s)`)
	end
end

-- Nearest wild brainrot to a position within maxRange, or nil.
function WildSpawner.getNearestWild(position: Vector3, maxRange: number): WildBrainrot?
	local best: WildBrainrot? = nil
	local bestDistance = maxRange
	for _, entry in wild do
		local pivot = entry.model:GetPivot()
		local distance = (Vector3.new(pivot.Position.X, 0, pivot.Position.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
		if distance <= bestDistance then
			best = entry
			bestDistance = distance
		end
	end
	return best
end

-- Removes a wild brainrot from the wild population and hands its live model
-- to the caller (catch, ZORK grab). Returns nil when the id is not wild.
function WildSpawner.removeWild(id: string): WildBrainrot?
	local entry = wild[id]
	if not entry then
		return nil
	end
	wild[id] = nil
	return entry
end

function WildSpawner.getCount(): number
	local count = 0
	for _ in wild do
		count += 1
	end
	return count
end

function WildSpawner.getAll(): { WildBrainrot }
	local list: { WildBrainrot } = {}
	for _, entry in wild do
		table.insert(list, entry)
	end
	return list
end

-- Walks every wild brainrot toward its wander target. Runs on Heartbeat so
-- the movement is smooth; each brainrot re-targets every few seconds.
local function onHeartbeat(dt: number)
	local speed = BrainrotData.CONFIG.wildWanderSpeed
	local now = os.clock()
	for _, entry in wild do
		local pivot = entry.model:GetPivot()
		local current = pivot.Position
		local target = entry.target
		local toTarget = Vector3.new(target.X - current.X, 0, target.Z - current.Z)
		local distance = toTarget.Magnitude
		if distance < 1.5 or now >= entry.nextRetargetAt then
			entry.target = pickWanderTarget(entry.zone, current, entry.id)
			entry.nextRetargetAt = now + 5 + rng:NextNumber() * 5
			continue
		end
		local step = math.min(speed * dt, distance)
		local direction = toTarget / distance
		local nextPos = current + direction * step
		nextPos = Vector3.new(nextPos.X, BrainrotFactory.getRestHeight(entry.species), nextPos.Z)
		local facing = Vector3.new(target.X, nextPos.Y, target.Z)
		-- A gentle side-to-side waddle while walking, done server-side so
		-- the client animator never fights the movement update.
		local waddle = math.sin(os.clock() * 6 + entry.phase) * 0.06
		entry.model:PivotTo(CFrame.lookAt(nextPos, facing) * CFrame.Angles(0, 0, waddle))
	end
end

-- Keeps the wild population at its target count.
local function maintainPopulation()
	while true do
		task.wait(5)
		local missing = BrainrotData.CONFIG.wildTargetCount - WildSpawner.getCount()
		for _ = 1, math.min(missing, 3) do
			WildSpawner.spawnWildAt(WorldBuilder.getRandomWildSpawnPoint(), nil, nil)
		end
	end
end

function WildSpawner.start()
	if started then
		return
	end
	started = true
	local folder = Workspace:FindFirstChild("WildBrainrots")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "WildBrainrots"
	folder.Parent = Workspace
	wildFolder = folder
	for _ = 1, BrainrotData.CONFIG.wildTargetCount do
		WildSpawner.spawnWildAt(WorldBuilder.getRandomWildSpawnPoint(), nil, nil)
	end
	RunService.Heartbeat:Connect(onHeartbeat)
	task.spawn(maintainPopulation)
end

return WildSpawner
