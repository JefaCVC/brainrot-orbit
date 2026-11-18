--!strict
-- PlayerDataStore
-- Persistent player data for BRAINROT ORBIT, in the ProfileStore pattern:
-- one versioned DataStore key per player, a session lock so only one server
-- owns a profile at a time, schema migration on load, autosave every 60
-- seconds, a save on leave, and a BindToClose flush. Written for this game
-- (no third-party module), so every line is ours.
--
-- A DataStore outage never wipes progress: if the load fails after retries
-- (Studio without API access, a throttled store), the player gets an
-- in-memory profile that is never written back, and the game keeps working.
-- A save from a NEWER schema version is never overwritten either.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Player = any
type DataStore = any

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerDataStore = {}

export type SavedBrainrot = {
	species: string,
	mutation: string,
}

export type PlayerData = {
	version: number,
	credits: number,
	rebirths: number,
	upgrades: { [string]: number },
	discovered: { [string]: boolean },
	missionsCompleted: number,
	missionCaught: number,
	missionDocked: number,
	missionEarned: number,
	missionLocked: number,
	totalEarned: number,
	docked: { SavedBrainrot },
}

export type Profile = {
	data: PlayerData,
	persist: boolean, -- false when the profile is memory-only (load failed)
	dirty: boolean,
	lockId: string,
	dataKey: string,
	lockKey: string,
	heartbeatThread: thread?,
}

local CURRENT_VERSION = 1
local STORE_NAME = "BrainrotOrbit_PlayerData_v1"
local LOCK_TTL_SECONDS = 120
local LOAD_RETRIES = 3
local AUTOSAVE_SECONDS = 60

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}

local function getStore(): DataStore?
	if store then
		return store
	end
	local name = STORE_NAME
	if RunService:IsStudio() then
		name = STORE_NAME .. "_Studio"
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		store = result
		return store
	end
	warn(`[PlayerDataStore] DataStore {name} unavailable: {result}`)
	return nil
end

local function defaultData(): PlayerData
	return {
		version = CURRENT_VERSION,
		credits = 0,
		rebirths = 0,
		upgrades = { Beam = 0, Cargo = 0, Shield = 0, Expansion = 0 },
		discovered = {},
		missionsCompleted = 0,
		missionCaught = 0,
		missionDocked = 0,
		missionEarned = 0,
		missionLocked = 0,
		totalEarned = 0,
		docked = {},
	}
end

-- Fills any field missing from a loaded save with the template default, so
-- old saves keep working when new fields are added.
local function reconcile(stored: { [string]: any }): PlayerData
	local data = defaultData()
	for key, value in stored do
		if key == "upgrades" and typeof(value) == "table" then
			for track, level in value :: { [string]: any } do
				if typeof(level) == "number" then
					data.upgrades[track] = level
				end
			end
		elseif key == "discovered" and typeof(value) == "table" then
			for name, seen in value :: { [string]: any } do
				if seen == true then
					data.discovered[name] = true
				end
			end
		elseif key == "docked" and typeof(value) == "table" then
			local docked: { SavedBrainrot } = {}
			for _, entry in value :: { any } do
				if typeof(entry) == "table" and typeof(entry.species) == "string" and typeof(entry.mutation) == "string" then
					table.insert(docked, { species = entry.species, mutation = entry.mutation })
				end
			end
			data.docked = docked
		elseif key == "credits"
			or key == "rebirths"
			or key == "missionsCompleted"
			or key == "missionCaught"
			or key == "missionDocked"
			or key == "missionEarned"
			or key == "missionLocked"
			or key == "totalEarned" then
			if typeof(value) == "number" and value == value and math.abs(value) ~= math.huge then
				(data :: any)[key] = value
			end
		end
	end
	data.version = CURRENT_VERSION
	return data
end

-- Migrates a stored save to the current schema. Errors on a save from the
-- future (a newer server wrote it) so this server never clobbers it.
local function migrate(stored: { [string]: any }): PlayerData
	local version = stored.version
	if typeof(version) ~= "number" then
		version = 1
	end
	if version > CURRENT_VERSION then
		error(`save is version {version}; this server only knows up to {CURRENT_VERSION}`)
	end
	-- Version 1 is the first shipped schema; older saves have no version
	-- field and reconcile fills their missing fields above.
	return reconcile(stored)
end

-- Tries to claim the session lock for a player. Returns true when this
-- server owns the lock, false when another live server holds it.
local function tryAcquireLock(dataStore: DataStore, lockKey: string, lockId: string): boolean
	local ok, result = pcall(function()
		return dataStore:UpdateAsync(lockKey, function(old: any): any
			if typeof(old) == "table" and old.id ~= lockId then
				local lockedAt = old.at
				if typeof(lockedAt) == "number" and os.time() - lockedAt < LOCK_TTL_SECONDS then
					return nil -- another live server owns it; cancel the write
				end
			end
			return { id = lockId, at = os.time(), server = game.JobId }
		end)
	end)
	if not ok then
		warn(`[PlayerDataStore] lock acquire failed for {lockKey}: {result}`)
		return false
	end
	return result ~= nil
end

local function releaseLock(dataStore: DataStore, lockKey: string, lockId: string)
	pcall(function()
		dataStore:UpdateAsync(lockKey, function(old: any): any
			if typeof(old) == "table" and old.id == lockId then
				return nil -- clear only our own lock
			end
			return old
		end)
	end)
end

local function refreshLock(dataStore: DataStore, lockKey: string, lockId: string)
	pcall(function()
		dataStore:UpdateAsync(lockKey, function(old: any): any
			if typeof(old) == "table" and old.id == lockId then
				return { id = lockId, at = os.time(), server = game.JobId }
			end
			return old
		end)
	end)
end

local function memoryOnlyProfile(player: Player): Profile
	return {
		data = defaultData(),
		persist = false,
		dirty = false,
		lockId = "",
		dataKey = `player_{player.UserId}`,
		lockKey = `player_{player.UserId}_lock`,
		heartbeatThread = nil,
	}
end

-- Loads (or creates) a player's profile, claiming the session lock first.
-- Always returns a usable profile; on any persistent failure the profile is
-- memory-only and the game keeps running without saving.
function PlayerDataStore.loadProfile(player: Player): Profile
	local existing = profiles[player]
	if existing then
		return existing
	end

	local dataKey = `player_{player.UserId}`
	local lockKey = `player_{player.UserId}_lock`
	local lockId = HttpService:GenerateGUID(false)
	local dataStore = getStore()
	if not dataStore then
		warn(`[PlayerDataStore] {player.Name}: no DataStore, using a memory-only profile`)
		local profile = memoryOnlyProfile(player)
		profiles[player] = profile
		return profile
	end

	-- Claim the session lock, retrying while another server holds it.
	local locked = false
	for _ = 1, LOAD_RETRIES do
		if tryAcquireLock(dataStore, lockKey, lockId) then
			locked = true
			break
		end
		task.wait(2)
	end
	if not locked then
		warn(`[PlayerDataStore] {player.Name}: profile locked by another server, using a memory-only profile`)
		local profile = memoryOnlyProfile(player)
		profiles[player] = profile
		return profile
	end

	-- Read the save, retrying transient failures.
	local stored: any = nil
	local readOk = false
	for _ = 1, LOAD_RETRIES do
		local ok, result = pcall(function()
			return dataStore:GetAsync(dataKey)
		end)
		if ok then
			stored = result
			readOk = true
			break
		end
		task.wait(1)
	end
	if not readOk then
		warn(`[PlayerDataStore] {player.Name}: save read failed, using a memory-only profile`)
		releaseLock(dataStore, lockKey, lockId)
		local profile = memoryOnlyProfile(player)
		profiles[player] = profile
		return profile
	end

	local data: PlayerData
	if stored == nil then
		data = defaultData() -- a genuinely new player
	else
		local migrated, result = pcall(migrate, stored)
		if not migrated then
			-- A save from the future: never touch it, play memory-only.
			warn(`[PlayerDataStore] {player.Name}: {result}, using a memory-only profile`)
			releaseLock(dataStore, lockKey, lockId)
			local profile = memoryOnlyProfile(player)
			profiles[player] = profile
			return profile
		end
		data = result
	end

	local profile: Profile = {
		data = data,
		persist = true,
		dirty = false,
		lockId = lockId,
		dataKey = dataKey,
		lockKey = lockKey,
		heartbeatThread = nil,
	}
	-- Heartbeat: keep the session lock alive while the player is here.
	profile.heartbeatThread = task.spawn(function()
		while profiles[player] == profile do
			task.wait(20)
			if profiles[player] == profile then
				refreshLock(dataStore, lockKey, lockId)
			end
		end
	end)
	profiles[player] = profile
	return profile
end

function PlayerDataStore.getProfile(player: Player): Profile?
	return profiles[player]
end

function PlayerDataStore.markDirty(player: Player)
	local profile = profiles[player]
	if profile then
		profile.dirty = true
	end
end

-- Writes one profile back to the DataStore (only when it is dirty and
-- persistent). Returns true when the save landed.
function PlayerDataStore.saveProfile(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile.persist or not profile.dirty then
		return false
	end
	local dataStore = getStore()
	if not dataStore then
		return false
	end
	local data = profile.data
	-- Never persist a non-finite number: one bad value fails the whole write.
	if data.credits ~= data.credits or math.abs(data.credits) == math.huge then
		data.credits = 0
	end
	local ok, err = pcall(function()
		dataStore:SetAsync(profile.dataKey, data)
	end)
	if ok then
		profile.dirty = false
		return true
	else
		warn(`[PlayerDataStore] save failed for {player.Name}: {err}`)
		return false
	end
end

-- Final save + lock release when a player leaves (or the server closes).
function PlayerDataStore.endSession(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profiles[player] = nil
	if profile.heartbeatThread then
		task.cancel(profile.heartbeatThread)
	end
	if not profile.persist then
		return
	end
	local dataStore = getStore()
	if not dataStore then
		return
	end
	-- Save directly from the local profile (it is already out of the map).
	if profile.dirty then
		local data = profile.data
		if data.credits ~= data.credits or math.abs(data.credits) == math.huge then
			data.credits = 0
		end
		local ok, err = pcall(function()
			dataStore:SetAsync(profile.dataKey, data)
		end)
		if not ok then
			warn(`[PlayerDataStore] final save failed for {player.Name}: {err}`)
		end
	end
	releaseLock(dataStore, profile.lockKey, profile.lockId)
end

-- Autosave loop: every 60 seconds, save every dirty persistent profile.
function PlayerDataStore.startAutosave()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player, _ in profiles do
				PlayerDataStore.saveProfile(player)
			end
		end
	end)
end

-- BindToClose: on shutdown, save every profile still in the server.
function PlayerDataStore.bindToClose()
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(function()
				PlayerDataStore.endSession(player)
			end)
		end
		task.wait(4) -- give the saves time to flush (30s max in production)
	end)
end

return PlayerDataStore
