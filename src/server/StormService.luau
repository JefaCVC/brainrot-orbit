--!strict
-- StormService
-- Owns the sky over BRAINROT ORBIT: the solar storm cycle (a 15-second
-- warning, then 15 seconds of storm that knocks exposed players back, drops
-- their cargo and can mutate wild brainrots Irradiated), plus the two
-- rotating events — Golden Hour (2x credits for 60s) and Meteor Shower
-- (bonus brainrots on the outer deck). Every phase change is broadcast to
-- all clients as an event banner with a countdown, so the HUD always shows
-- what is coming.
--
-- GameService injects two callbacks at startup (drop a player's cargo, and
-- refresh dome visibility) so this module never requires GameService back.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Player = any
type RemoteEvent = any
type Color3 = any

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local requireModule = require :: any
local BrainrotData = requireModule(ReplicatedStorage:WaitForChild("BrainrotData"))
local FormatUtil = requireModule(ReplicatedStorage:WaitForChild("FormatUtil"))
local PlayerState = requireModule(ServerScriptService:WaitForChild("PlayerState"))
local Remotes = requireModule(ReplicatedStorage:WaitForChild("Remotes"))
local WildSpawner = requireModule(ServerScriptService:WaitForChild("WildSpawner"))
local WorldBuilder = requireModule(ServerScriptService:WaitForChild("WorldBuilder"))

local StormService = {}

-- Callbacks injected by GameService at startup.
StormService.dropCargoCallback = nil :: ((player: Player) -> ())?
StormService.phaseChangedCallback = nil :: ((phase: string) -> ())?

local stormPhase = "calm" -- "calm" | "warning" | "active"
local nextStormAt = 0
local phaseEndsAt = 0
local goldenHourUntil = 0
local skipWarning = false -- set by forceStormActive: jump straight to the storm
local originalAmbient: Color3? = nil
local originalOutdoorAmbient: Color3? = nil
local rng = Random.new()
local started = false

local function broadcastBanner(kind: string, text: string, seconds: number)
	local remote = Remotes.get("EventBanner") :: RemoteEvent?
	if remote then
		remote:FireAllClients({ kind = kind, text = text, seconds = seconds })
	end
end

-- A full-screen orange flash on every client when the storm hits.
local function broadcastStormFlash()
	local remote = Remotes.get("FxEvent") :: RemoteEvent?
	if remote then
		remote:FireAllClients({ kind = "stormFlash" })
	end
end

function StormService.getStormState(): { phase: string, secondsLeft: number, nextStormIn: number }
	local now = os.clock()
	if stormPhase == "calm" then
		return { phase = "calm", secondsLeft = 0, nextStormIn = math.max(0, nextStormAt - now) }
	end
	return { phase = stormPhase, secondsLeft = math.max(0, phaseEndsAt - now), nextStormIn = 0 }
end

function StormService.isGoldenHour(): boolean
	return os.clock() < goldenHourUntil
end

function StormService.getGoldenHourSecondsLeft(): number
	return math.max(0, goldenHourUntil - os.clock())
end

function StormService.isStormActive(): boolean
	return stormPhase == "active"
end

-- Tour/debug: jump straight to the storm warning.
function StormService.forceStorm()
	if stormPhase == "calm" then
		nextStormAt = os.clock()
	end
end

-- Tour/debug: jump straight to the ACTIVE storm (domes up, orange sky),
-- skipping the 15-second warning — the screenshot moment.
function StormService.forceStormActive()
	if stormPhase == "calm" then
		skipWarning = true
		nextStormAt = os.clock()
	end
end

function StormService.forceGoldenHour()
	goldenHourUntil = os.clock() + BrainrotData.CONFIG.goldenHourDurationSeconds
	broadcastBanner("golden-hour", "GOLDEN HOUR! 2x credits for 60s!", BrainrotData.CONFIG.goldenHourDurationSeconds)
end

local function setStormLighting(active: boolean)
	if active then
		if originalAmbient == nil then
			originalAmbient = Lighting.Ambient
			originalOutdoorAmbient = Lighting.OutdoorAmbient
		end
		Lighting.Ambient = Color3.fromRGB(255, 170, 90)
		Lighting.OutdoorAmbient = Color3.fromRGB(160, 60, 30)
	else
		if originalAmbient ~= nil then
			Lighting.Ambient = originalAmbient
			Lighting.OutdoorAmbient = originalOutdoorAmbient
		end
	end
end

local function setStormEmitters(enabled: boolean)
	for _, emitter in WorldBuilder.STORM_EMITTERS do
		emitter.Enabled = enabled
	end
end

-- The storm hits: every player outside a shield dome is flung by the blast
-- and drops their cargo bubble. Players inside a dome are safe.
local function knockBackExposedPlayers()
	local knockback = BrainrotData.CONFIG.stormKnockbackSpeed
	for _, runtime in PlayerState.getAll() do
		local player = runtime.player
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local position = root.Position
			if not WorldBuilder.isInsideAnyDome(position) then
				local angle = rng:NextNumber() * math.pi * 2
				local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
				root.AssemblyLinearVelocity = direction * knockback + Vector3.new(0, 25, 0)
				if StormService.dropCargoCallback then
					local dropCargo = StormService.dropCargoCallback :: (player: Player) -> ()
					dropCargo(player)
				end
				local toast = Remotes.get("Toast") :: RemoteEvent?
				if toast then
					toast:FireClient(player, "The solar storm threw you back and your cargo dropped!")
				end
			end
		end
	end
end

local function setPhase(phase: string, durationSeconds: number)
	stormPhase = phase
	phaseEndsAt = os.clock() + durationSeconds
	local callback = StormService.phaseChangedCallback
	if callback then
		(callback :: (phase: string) -> ())(phase)
	end
end

local function stormLoop()
	local config = BrainrotData.CONFIG
	nextStormAt = os.clock() + config.stormPeriodSeconds
	while true do
		-- Calm: wait for the next storm (checked twice a second so a forced
		-- storm from the tour starts almost immediately).
		while os.clock() < nextStormAt do
			task.wait(0.5)
		end

		-- Warning: 15 seconds to get to your dome, counted down on the HUD.
		-- (Skipped when the tour jumps straight to the active storm.)
		if not skipWarning then
			setPhase("warning", config.stormWarningSeconds)
			for remaining = config.stormWarningSeconds, 1, -1 do
				broadcastBanner("storm-warning", `SOLAR STORM IN {FormatUtil.formatCountdown(remaining)} - GET TO YOUR DOME!`, remaining)
				task.wait(1)
			end
		end
		skipWarning = false

		-- Active: the storm hits, domes rise, the sky turns orange.
		setPhase("active", config.stormDurationSeconds)
		setStormLighting(true)
		setStormEmitters(true)
		WorldBuilder.setAllDomesVisible(true)
		WildSpawner.irradiateExposed()
		knockBackExposedPlayers()
		broadcastBanner("storm-active", "SOLAR STORM! SHELTER IN THE DOME! DOME PAYS x2!", config.stormDurationSeconds)
		broadcastStormFlash()
		task.wait(config.stormDurationSeconds)

		-- Over: the sky clears; domes fall again unless a module is locked
		-- (GameService re-raises the locked ones via the phase callback).
		setPhase("calm", 0)
		setStormLighting(false)
		setStormEmitters(false)
		WorldBuilder.setAllDomesVisible(false)
		broadcastBanner("storm-over", "The storm has passed. The station is safe... for now.", 0)
		nextStormAt = os.clock() + config.stormPeriodSeconds
	end
end

local function goldenHourLoop()
	local config = BrainrotData.CONFIG
	while true do
		local gap = config.goldenHourMinGapSeconds + rng:NextNumber() * (config.goldenHourMaxGapSeconds - config.goldenHourMinGapSeconds)
		task.wait(gap)
		goldenHourUntil = os.clock() + config.goldenHourDurationSeconds
		broadcastBanner("golden-hour", "GOLDEN HOUR! 2x credits for 60s!", config.goldenHourDurationSeconds)
		task.wait(config.goldenHourDurationSeconds)
		broadcastBanner("golden-hour-over", "Golden Hour is over.", 0)
	end
end

local function meteorShowerLoop()
	local config = BrainrotData.CONFIG
	while true do
		local gap = config.meteorShowerMinGapSeconds + rng:NextNumber() * (config.meteorShowerMaxGapSeconds - config.meteorShowerMinGapSeconds)
		task.wait(gap)
		WildSpawner.spawnMeteorBrainrots(config.meteorShowerBonusCount)
		broadcastBanner("meteor", "METEOR SHOWER! Bonus brainrots landed on the outer deck!", 0)
	end
end

function StormService.start()
	if started then
		return
	end
	started = true
	task.spawn(stormLoop)
	task.spawn(goldenHourLoop)
	task.spawn(meteorShowerLoop)
end

return StormService
