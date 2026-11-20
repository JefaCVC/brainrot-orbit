--!strict
-- ThiefService
-- Owns ZORK the Snatcher, the alien thief who raids the station about every
-- 70 seconds. ZORK sneaks in through the airlock, walks to a random UNLOCKED
-- module that holds brainrots, grabs one, and runs back to the airlock with
-- it. Any player can drive him off by zapping him 3 times with the Zapper
-- (F) — the third zap makes him drop the brainrot and flee, and pays
-- the zapper a credit bonus. A locked module is never targeted, so the lock
-- button is the real defence and the zapper is the rescue.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Player = any
type Model = any
type Vector3 = any
type RemoteEvent = any

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local requireModule = require :: any
local BrainrotData = requireModule(ReplicatedStorage:WaitForChild("BrainrotData"))
local BrainrotFactory = requireModule(ServerScriptService:WaitForChild("BrainrotFactory"))
local PlayerState = requireModule(ServerScriptService:WaitForChild("PlayerState"))
local Remotes = requireModule(ReplicatedStorage:WaitForChild("Remotes"))
local WildSpawner = requireModule(ServerScriptService:WaitForChild("WildSpawner"))
local WorldBuilder = requireModule(ServerScriptService:WaitForChild("WorldBuilder"))

local ThiefService = {}

local ZORK_WALK_SPEED = 7
local ZORK_ARRIVE_DISTANCE = 3

local zorkModel: Model? = nil
local zorkState = "idle" -- "idle" | "toModule" | "grabbing" | "toAirlock" | "fleeing"
local zorkTarget: Vector3? = nil
local zorkVictim: Player? = nil
local zorkStolen: any? = nil -- the BrainrotInstance ZORK is carrying
local zorkBonks = 0
local rng = Random.new()
local started = false

local function broadcastBanner(kind: string, text: string, seconds: number)
	local remote = Remotes.get("EventBanner") :: RemoteEvent?
	if remote then
		remote:FireAllClients({ kind = kind, text = text, seconds = seconds })
	end
end

local function toastPlayer(player: Player, text: string)
	local remote = Remotes.get("Toast") :: RemoteEvent?
	if remote then
		remote:FireClient(player, text)
	end
end

function ThiefService.isZorkActive(): boolean
	return zorkModel ~= nil and zorkModel.Parent ~= nil
end

function ThiefService.getZorkPosition(): Vector3?
	if not ThiefService.isZorkActive() then
		return nil
	end
	return (zorkModel :: Model):GetPivot().Position
end

-- Picks a raid target: a random unlocked module holding at least one
-- brainrot. Locked modules and empty modules are never targeted.
local function pickRaidTarget(): any?
	local candidates: { any } = {}
	for _, runtime in PlayerState.getAll() do
		if runtime.moduleIndex > 0 and not PlayerState.isModuleLocked(runtime) and PlayerState.getDockedCount(runtime) > 0 then
			table.insert(candidates, runtime)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[rng:NextInteger(1, #candidates)]
end

local function despawnZork()
	if zorkModel then
		zorkModel:Destroy()
		zorkModel = nil
	end
	zorkState = "idle"
	zorkTarget = nil
	zorkVictim = nil
	zorkStolen = nil
	zorkBonks = 0
end

local function spawnZork(targetRuntime: any)
	local model = BrainrotFactory.buildZorkModel()
	model:PivotTo(CFrame.new(WorldBuilder.AIRLOCK_POSITION))
	model.Parent = Workspace
	zorkModel = model
	zorkState = "toModule"
	zorkVictim = targetRuntime.player
	zorkBonks = 0
	local module = WorldBuilder.MODULES[targetRuntime.moduleIndex]
	zorkTarget = module.center
	broadcastBanner("zork", `ZORK the Snatcher is raiding {targetRuntime.player.Name}'s module! Zap him 3x [F]!`, 0)
	toastPlayer(targetRuntime.player, "ZORK is coming for your module! Lock it or zap him!")
end

-- ZORK grabs a random docked brainrot from the victim's module and carries
-- it off in his loot sack.
local function grabBrainrot()
	local victim = zorkVictim
	local model = zorkModel
	if not victim or not model then
		despawnZork()
		return
	end
	local runtime = PlayerState.get(victim)
	if not runtime or PlayerState.getDockedCount(runtime) == 0 then
		-- Nothing left to steal (the victim docked nothing or left): flee.
		zorkState = "fleeing"
		zorkTarget = WorldBuilder.AIRLOCK_POSITION
		return
	end
	local podIndices: { number } = {}
	for podIndex in runtime.docked do
		table.insert(podIndices, podIndex)
	end
	local podIndex = podIndices[rng:NextInteger(1, #podIndices)]
	local stolen = runtime.docked[podIndex]
	runtime.docked[podIndex] = nil
	PlayerState.syncDockedToProfile(runtime)
	zorkStolen = stolen
	if stolen.model then
		local brainrotModel = stolen.model :: Model
		brainrotModel:SetAttribute("Animate", "None")
		brainrotModel:PivotTo(model:GetPivot() * CFrame.new(0, 1.5, -1.5))
		brainrotModel.Parent = model
	end
	toastPlayer(victim, `ZORK grabbed your {stolen.species}! Zap him 3x to save it!`)
	zorkState = "toAirlock"
	zorkTarget = WorldBuilder.AIRLOCK_POSITION
end

-- Walks ZORK toward his current target. Returns true when he arrives.
local function walkZorkTowardTarget(dt: number): boolean
	local model = zorkModel
	local target = zorkTarget
	if not model or not target then
		return true
	end
	local pivot = model:GetPivot()
	local current = pivot.Position
	local toTarget = Vector3.new(target.X - current.X, 0, target.Z - current.Z)
	local distance = toTarget.Magnitude
	if distance < ZORK_ARRIVE_DISTANCE then
		return true
	end
	local step = math.min(ZORK_WALK_SPEED * dt, distance)
	local direction = toTarget / distance
	local nextPos = current + direction * step
	-- A little bounce while he runs, so he reads as alive, not sliding.
	local bounce = math.abs(math.sin(os.clock() * 8)) * 0.4
	nextPos = Vector3.new(nextPos.X, bounce, nextPos.Z)
	local facing = Vector3.new(target.X, nextPos.Y, target.Z)
	model:PivotTo(CFrame.lookAt(nextPos, facing))
	return false
end

local function onHeartbeat(dt: number)
	if not ThiefService.isZorkActive() then
		return
	end
	if zorkState == "toModule" then
		if walkZorkTowardTarget(dt) then
			zorkState = "grabbing"
			grabBrainrot()
		end
	elseif zorkState == "toAirlock" then
		if walkZorkTowardTarget(dt) then
			-- ZORK escaped with the brainrot. It is gone for good.
			local victim = zorkVictim
			local stolen = zorkStolen
			if victim and stolen then
				toastPlayer(victim, `ZORK escaped with your {stolen.species} through the airlock!`)
			end
			if stolen and stolen.model then
				(stolen.model :: Model):Destroy()
			end
			despawnZork()
		end
	elseif zorkState == "fleeing" then
		if walkZorkTowardTarget(dt) then
			despawnZork()
		end
	end
end

-- One zap from the Zapper. The third zap drives ZORK off: he drops
-- the stolen brainrot (it becomes wild where he stands) and flees, and the
-- zapper earns a credit bonus. Returns true when the zap landed.
function ThiefService.bonkZork(bonker: Player): boolean
	if not ThiefService.isZorkActive() then
		return false
	end
	zorkBonks += 1
	local model = zorkModel :: Model
	-- Knock ZORK back a little with every zap.
	local bonkerRuntime = PlayerState.get(bonker)
	local character = bonker.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local away = model:GetPivot().Position - root.Position
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude > 0.1 then
			away = away / away.Magnitude
			model:PivotTo(model:GetPivot() + away * 4)
		end
	end
	local fx = Remotes.get("FxEvent") :: RemoteEvent?
	if fx then
		fx:FireAllClients({ kind = "bonk", position = model:GetPivot().Position, count = zorkBonks })
	end
	if zorkBonks >= BrainrotData.CONFIG.zorkBonksToDriveOff then
		local stolen = zorkStolen
		if stolen then
			-- The brainrot drops where ZORK stands and goes wild again.
			WildSpawner.spawnWildAt(model:GetPivot().Position, stolen.species, stolen.mutation)
			if stolen.model then
				(stolen.model :: Model):Destroy()
			end
			zorkStolen = nil
		end
		if bonkerRuntime then
			PlayerState.addCredits(bonkerRuntime, BrainrotData.CONFIG.zorkBonkBonusCredits, false)
			bonkerRuntime.profile.data.questZapped = (bonkerRuntime.profile.data.questZapped or 0) + 1
		end
		broadcastBanner("zork-driven-off", `ZAPPED! {bonker.Name} drove ZORK off (+${BrainrotData.CONFIG.zorkBonkBonusCredits})!`, 0)
		zorkState = "fleeing"
		zorkTarget = WorldBuilder.AIRLOCK_POSITION
	end
	return true
end

-- Tour/debug: start a raid right now, whatever the timer says.
function ThiefService.forceRaid()
	if ThiefService.isZorkActive() then
		return
	end
	local target = pickRaidTarget()
	if target then
		spawnZork(target)
	end
end

local function raidLoop()
	while true do
		task.wait(BrainrotData.CONFIG.zorkPeriodSeconds)
		if not ThiefService.isZorkActive() then
			local target = pickRaidTarget()
			if target then
				spawnZork(target)
			end
		end
	end
end

function ThiefService.start()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(onHeartbeat)
	task.spawn(raidLoop)
end

return ThiefService
