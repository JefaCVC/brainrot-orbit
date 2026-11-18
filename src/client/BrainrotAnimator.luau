--!strict
-- BrainrotAnimator
-- Procedural client-side animation for BRAINROT ORBIT: docked and pedestal
-- brainrots bob gently, crew NPCs sway or slowly turn at their posts. No
-- animation assets — every motion is a sine wave over the model's base
-- CFrame, and models further than ~220 studs from the camera are skipped
-- entirely (culled). Wild brainrots are NOT animated here: the server moves
-- them (with its own waddle), and a client offset would fight the server's
-- CFrame updates.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Model = any
type CFrame = any

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local requireModule = require :: any
local BrainrotData = requireModule(ReplicatedStorage:WaitForChild("BrainrotData"))

local BrainrotAnimator = {}

type AnimatedEntry = {
	model: Model,
	base: CFrame,
	phase: number,
	kind: string, -- "Bob" | "Sway" | "Turn"
}

local animated: { [Model]: AnimatedEntry } = {}
local lastScanAt = 0
local phaseCounter = 0

local function scanForAnimatedModels()
	local now = os.clock()
	if now - lastScanAt < 2 then
		return
	end
	lastScanAt = now
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Model") then
			local animate = descendant:GetAttribute("Animate")
			if (animate == "Bob" or animate == "Sway" or animate == "Turn") and animated[descendant] == nil then
				phaseCounter += 0.7
				animated[descendant] = {
					model = descendant,
					base = descendant:GetPivot(),
					phase = phaseCounter,
					kind = animate,
				}
			end
		end
	end
end

local function onRenderStepped()
	scanForAnimatedModels()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	local now = os.clock()
	local cullDistance = BrainrotData.CONFIG.animCullDistanceStuds
	local dead: { Model } = {}
	for model, entry in animated do
		if model.Parent == nil then
			table.insert(dead, model)
			continue
		end
		local basePosition = entry.base.Position
		local distance = (Vector3.new(basePosition.X, 0, basePosition.Z) - Vector3.new(cameraPosition.X, 0, cameraPosition.Z)).Magnitude
		if distance > cullDistance then
			continue
		end
		if entry.kind == "Bob" then
			local bob = math.sin(now * 2 + entry.phase) * 0.3
			model:PivotTo(entry.base * CFrame.new(0, bob, 0))
		elseif entry.kind == "Sway" then
			local sway = math.sin(now * 0.8 + entry.phase) * 0.12
			model:PivotTo(entry.base * CFrame.Angles(0, sway, 0))
		elseif entry.kind == "Turn" then
			-- A slow look-around: the NPC turns its head side to side
			-- (a yaw sweep) with a tiny breathing bob, so it reads as
			-- watching the station instead of standing frozen.
			local turn = math.sin(now * 0.5 + entry.phase) * 0.45
			local breathe = math.sin(now * 1.4 + entry.phase) * 0.06
			model:PivotTo(entry.base * CFrame.new(0, breathe, 0) * CFrame.Angles(0, turn, 0))
		end
	end
	for _, model in dead do
		animated[model] = nil
	end
end

function BrainrotAnimator.init()
	RunService.RenderStepped:Connect(onRenderStepped)
end

return BrainrotAnimator
