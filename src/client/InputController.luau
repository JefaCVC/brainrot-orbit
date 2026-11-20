--!strict
-- InputController
-- Keyboard (and touch-button) input for BRAINROT ORBIT, bound through
-- ContextActionService — never through UserInputService.InputBegan with a
-- gameProcessedEvent filter, which the default camera scripts swallow for
-- the keys they own. One context action per verb:
--
--   E  Interact — catch the nearest wild brainrot, dock in the nearest
--      empty pod, or steal from a rival module, whichever the player is
--      standing next to (the prompt label always says which).
--   L  Lock Module — raise the energy shield.
--   F  Zap ZORK — zap the Snatcher with the Zapper (3x drives him off).
--   Q  Drop Cargo — drop everything in the cargo bubble.
--
-- The client only decides WHICH remote to fire from proximity; the server
-- re-checks range, ownership and state for every single one.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Player = any
type Model = any
type Vector3 = any
type RemoteEvent = any

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local requireModule = require :: any
local BrainrotData = requireModule(ReplicatedStorage:WaitForChild("BrainrotData"))
local ClientState = requireModule(script.Parent:WaitForChild("ClientState"))
local FormatUtil = requireModule(ReplicatedStorage:WaitForChild("FormatUtil"))
local HudController = requireModule(script.Parent:WaitForChild("HudController"))
local Remotes = requireModule(ReplicatedStorage:WaitForChild("Remotes"))
local TitleController = requireModule(script.Parent:WaitForChild("TitleController"))

local InputController = {}

local player = Players.LocalPlayer

local currentAction = "none" -- "none" | "catch" | "dock" | "steal"
local currentTargetName = ""
local currentTargetRate = 0
local zorkInBonkRange = false
local brainrotModelCache: { Model } = {}
local cacheRefreshedAt = 0
local lastConnectionToastAt = 0

local function getRootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	return root.Position
end

local function getBeamRange(state: { [string]: any }?): number
	if not state then
		return 24
	end
	local upgrades = state.upgrades :: { [string]: any }?
	local level = 0
	if upgrades and typeof(upgrades.Beam) == "number" then
		level = upgrades.Beam
	end
	local track = BrainrotData.UPGRADES.Beam
	level = math.clamp(level, 0, #track.levels - 1)
	return track.levels[level + 1].beamRange or 24
end

-- Refreshes the cached list of brainrot models (a full descendant scan is
-- too expensive to run every prompt tick).
local function refreshBrainrotCache()
	local now = os.clock()
	if now - cacheRefreshedAt < 2 then
		return
	end
	cacheRefreshedAt = now
	local found: { Model } = {}
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Model") and descendant:GetAttribute("IsBrainrot") == true then
			table.insert(found, descendant)
		end
	end
	brainrotModelCache = found
end

local function getMyModuleCenter(state: { [string]: any }?): Vector3?
	local moduleIndex = 0
	if state and typeof(state.moduleIndex) == "number" then
		moduleIndex = state.moduleIndex
	end
	if moduleIndex == 0 then
		return nil
	end
	local station = Workspace:FindFirstChild("Station")
	local moduleFolder = station and station:FindFirstChild(`Module{moduleIndex}`)
	local floor = moduleFolder and moduleFolder:FindFirstChild(`Module{moduleIndex}Floor`)
	if floor and floor:IsA("BasePart") then
		return floor.Position
	end
	return nil
end

-- The prompt scan: figures out what [E] does from where the player stands.
-- Runs four times a second; the server re-validates everything on press.
local function scanContext()
	refreshBrainrotCache()
	local rootPosition = getRootPosition()
	local state = ClientState.getState()
	if not rootPosition or not state then
		currentAction = "none"
		HudController.setPrompt("Connecting to server… (no state yet)")
		return
	end
	local cargo = state.cargo :: { any }
	local cargoCount = #cargo
	local cargoCapacity = state.cargoCapacity or 1
	local myCenter = getMyModuleCenter(state)
	local nearestWildDistance: number? = nil

	-- 1. Dock: carrying something and standing by one of my empty pods.
	if cargoCount > 0 and myCenter then
		local moduleIndex = state.moduleIndex or 0
		local station = Workspace:FindFirstChild("Station")
		local moduleFolder = station and station:FindFirstChild(`Module{moduleIndex}`)
		if moduleFolder then
			local occupied: { [number]: boolean } = {}
			for _, entry in state.roster :: { any } do
				occupied[entry.pod] = true
			end
			local bestPod = 0
			local bestDistance = 12
			for _, child in moduleFolder:GetChildren() do
				local podNumber = string.match(child.Name, "^Pod(%d+)Platform$")
				if podNumber and child:IsA("BasePart") then
					local podIndex = tonumber(podNumber) or 0
					if podIndex >= 1 and podIndex <= (state.podsMax or 4) and not occupied[podIndex] then
						local distance = (Vector3.new(child.Position.X, 0, child.Position.Z) - Vector3.new(rootPosition.X, 0, rootPosition.Z)).Magnitude
						if distance <= bestDistance then
							bestPod = podIndex
							bestDistance = distance
						end
					end
				end
			end
			if bestPod > 0 then
				currentAction = "dock"
				currentTargetName = cargo[1].name
				HudController.setPrompt(`[E] Dock {currentTargetName} in Pod {bestPod}`)
				return
			end
		end
	end

	-- 2. Steal: a rival's docked brainrot within reach (docked = "Bob"
	-- animation, not mine, not a pedestal showpiece).
	if cargoCount < cargoCapacity then
		local best: Model? = nil
		local bestDistance = 12
		local station = Workspace:FindFirstChild("Station")
		local pedestals = station and station:FindFirstChild("TitlePedestals")
		for _, model in brainrotModelCache do
			if model:GetAttribute("Animate") == "Bob" and model.Parent ~= nil then
				if pedestals and model:IsDescendantOf(pedestals) then
					continue
				end
				local pivot = model:GetPivot().Position
				if myCenter and (Vector3.new(pivot.X, 0, pivot.Z) - Vector3.new(myCenter.X, 0, myCenter.Z)).Magnitude < 20 then
					continue -- my own docked brainrot
				end
				local distance = (Vector3.new(pivot.X, 0, pivot.Z) - Vector3.new(rootPosition.X, 0, rootPosition.Z)).Magnitude
				if distance <= bestDistance then
					best = model
					bestDistance = distance
				end
			end
		end
		if best then
			currentAction = "steal"
			currentTargetName = best:GetAttribute("SpeciesName") or "brainrot"
			local species = BrainrotData.getSpecies(currentTargetName)
			currentTargetRate = species and species.rate or 0
			HudController.setPrompt(`[E] Steal {currentTargetName} ({FormatUtil.formatRate(currentTargetRate)})`)
			return
		end
	end

	-- 3. Catch: a wild brainrot inside tractor-beam range.
	if cargoCount < cargoCapacity then
		local wildFolder = Workspace:FindFirstChild("WildBrainrots")
		if wildFolder then
			local beamRange = getBeamRange(state)
			local best: Model? = nil
			local bestDistance = beamRange
			for _, model in wildFolder:GetChildren() do
				if model:IsA("Model") and model.PrimaryPart then
					local pivot = model:GetPivot().Position
					local distance = (Vector3.new(pivot.X, 0, pivot.Z) - Vector3.new(rootPosition.X, 0, rootPosition.Z)).Magnitude
					if not nearestWildDistance or distance < nearestWildDistance then
						nearestWildDistance = distance
					end
					if distance <= bestDistance then
						best = model
						bestDistance = distance
					end
				end
			end
			if best then
				currentAction = "catch"
				currentTargetName = best:GetAttribute("SpeciesName") or "brainrot"
				local species = BrainrotData.getSpecies(currentTargetName)
				currentTargetRate = species and species.rate or 0
				local mutation = best:GetAttribute("Mutation")
				local label = currentTargetName
				if mutation and mutation ~= "None" then
					label = `{label} [{mutation}]`
				end
				HudController.setPrompt(`[E] Catch {label} ({FormatUtil.formatRate(currentTargetRate)})`)
				return
			end
		end
	end

	-- No action is available: say why, instead of going silent. The prompt
	-- always shows something once the title is dismissed.
	currentAction = "none"
	if cargoCount >= cargoCapacity then
		HudController.setPrompt("Cargo full - dock first")
	elseif nearestWildDistance then
		HudController.setPrompt(`Nearest brainrot {math.floor(nearestWildDistance)} studs away - get closer`)
	else
		HudController.setPrompt("No wild brainrot nearby")
	end
end

local function scanZork()
	zorkInBonkRange = false
	local rootPosition = getRootPosition()
	if not rootPosition then
		return
	end
	local zork = Workspace:FindFirstChild("ZORK the Snatcher")
	if zork and zork:IsA("Model") and zork.PrimaryPart then
		local pivot = zork:GetPivot().Position
		local distance = (Vector3.new(pivot.X, 0, pivot.Z) - Vector3.new(rootPosition.X, 0, rootPosition.Z)).Magnitude
		zorkInBonkRange = distance <= 14
	end
end

local function fireRemote(name: string, ...)
	local remote = Remotes.waitFor(name) :: RemoteEvent?
	if remote then
		remote:FireServer(...)
		return
	end
	-- A missing remote must never fail silently again: tell the player,
	-- throttled so a held key does not flood the toast stack.
	local now = os.clock()
	if now - lastConnectionToastAt >= 5 then
		lastConnectionToastAt = now
		HudController.showToast("Connection problem - can't reach the server. Rejoin if this persists.")
	end
end

local function onInteract(_action: string, inputState: any, _input: any)
	if inputState ~= Enum.UserInputState.Begin then
		return
	end
	if TitleController.isVisible() then
		return
	end
	if currentAction == "catch" then
		fireRemote("CatchBrainrot")
	elseif currentAction == "dock" then
		fireRemote("DockBrainrot")
	elseif currentAction == "steal" then
		fireRemote("StealBrainrot")
	end
end

local function onLock(_action: string, inputState: any, _input: any)
	if inputState == Enum.UserInputState.Begin and not TitleController.isVisible() then
		fireRemote("LockModule")
	end
end

local function onBonk(_action: string, inputState: any, _input: any)
	if inputState == Enum.UserInputState.Begin and not TitleController.isVisible() then
		fireRemote("BonkZork")
	end
end

local function onDrop(_action: string, inputState: any, _input: any)
	if inputState == Enum.UserInputState.Begin and not TitleController.isVisible() then
		fireRemote("DropCargo")
	end
end

function InputController.isZorkInBonkRange(): boolean
	return zorkInBonkRange
end

function InputController.init()
	-- Touch buttons on mobile, keys on desktop; one handler each.
	ContextActionService:BindAction("OrbitInteract", onInteract, true, Enum.KeyCode.E)
	ContextActionService:BindAction("OrbitLock", onLock, true, Enum.KeyCode.L)
	ContextActionService:BindAction("OrbitBonk", onBonk, true, Enum.KeyCode.F)
	ContextActionService:BindAction("OrbitDrop", onDrop, true, Enum.KeyCode.Q)
	task.spawn(function()
		while true do
			task.wait(0.25)
			if not TitleController.isVisible() then
				scanContext()
				scanZork()
			end
		end
	end)
end

return InputController
