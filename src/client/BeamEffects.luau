--!strict
-- BeamEffects
-- Client-side visual effects for BRAINROT ORBIT, driven by the server's
-- FxEvent remote: the tractor beam (a cyan energy cylinder that snaps from
-- the player to the caught brainrot and fades) and the BONK! burst when the
-- Plasma Bat lands on ZORK. Cosmetic only — the server already decided the
-- outcome before the effect plays.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Vector3 = any
type RemoteEvent = any

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local requireModule = require :: any
local Remotes = requireModule(ReplicatedStorage:WaitForChild("Remotes"))

local BeamEffects = {}

-- A glowing cylinder from `from` to `to` that fades out over 0.6 seconds.
local function showBeam(from: Vector3, to: Vector3)
	local direction = to - from
	local length = direction.Magnitude
	if length < 0.5 then
		return
	end
	local beam = Instance.new("Part")
	beam.Name = "TractorBeam"
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(length, 0.7, 0.7)
	beam.Color = Color3.fromRGB(120, 220, 255)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.25
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	-- The cylinder's long axis is X; lookAt aims -Z, so rotate 90 deg about Y.
	beam.CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0)
	beam.Parent = Workspace
	task.spawn(function()
		for step = 1, 6 do
			task.wait(0.1)
			if beam.Parent then
				beam.Transparency = 0.25 + (step / 6) * 0.75
			end
		end
		beam:Destroy()
	end)
end

-- A floating BONK! label over ZORK that rises and fades.
local function showBonk(position: Vector3, count: number)
	local anchor = Instance.new("Part")
	anchor.Name = "BonkAnchor"
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = position + Vector3.new(0, 6, 0)
	anchor.Parent = Workspace
	local tag = Instance.new("BillboardGui")
	tag.Name = "BonkTag"
	tag.Size = UDim2.new(0, 140, 0, 60)
	tag.AlwaysOnTop = true
	tag.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = `BONK! ({count}/3)`
	label.TextColor3 = Color3.fromRGB(255, 210, 60)
	label.TextSize = 28
	label.Font = Enum.Font.GothamBold
	label.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	label.TextStrokeTransparency = 0.2
	label.Parent = tag
	tag.Parent = anchor
	task.spawn(function()
		for step = 1, 8 do
			task.wait(0.1)
			if anchor.Parent then
				anchor.Position += Vector3.new(0, 0.35, 0)
				label.TextTransparency = step / 8
			end
		end
		anchor:Destroy()
	end)
end

local function onFxEvent(payload: { [string]: any })
	local kind = payload.kind
	if kind == "beam" and payload.from and payload.to then
		showBeam(payload.from, payload.to)
	elseif kind == "bonk" and payload.position then
		showBonk(payload.position, payload.count or 1)
	end
end

function BeamEffects.init()
	local remote = Remotes.waitFor("FxEvent") :: RemoteEvent?
	if remote then
		remote.OnClientEvent:Connect(onFxEvent)
	end
end

return BeamEffects
