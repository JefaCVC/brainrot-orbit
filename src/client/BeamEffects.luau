--!strict
-- BeamEffects
-- Client-side visual effects for BRAINROT ORBIT, driven by the server's
-- FxEvent remote: the tractor beam (a cyan energy cylinder that snaps from
-- the player to the caught brainrot and fades), the catch burst, the dock
-- pop with floating +credits text, the steal flash, the rebirth confetti,
-- the storm screen flash, and the BONK! burst when the Plasma Bat lands on
-- ZORK. All effects are procedural (parts, ParticleEmitters, tweens) — no
-- asset ids. Cosmetic only — the server already decided the outcome before
-- the effect plays.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Vector3 = any
type RemoteEvent = any
type ScreenGui = any
type Frame = any

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local requireModule = require :: any
local FormatUtil = requireModule(ReplicatedStorage:WaitForChild("FormatUtil"))
local Remotes = requireModule(ReplicatedStorage:WaitForChild("Remotes"))

local BeamEffects = {}

local player = Players.LocalPlayer
local flashFrame: Frame? = nil

-- A glowing cylinder from `from` to `to` that pulses thick, then fades out
-- over 0.6 seconds.
local function showBeam(from: Vector3, to: Vector3)
	local direction = to - from
	local length = direction.Magnitude
	if length < 0.5 then
		return
	end
	local beam = Instance.new("Part")
	beam.Name = "TractorBeam"
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(length, 1.4, 1.4)
	beam.Color = Color3.fromRGB(120, 220, 255)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.1
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
				-- Pulse: thick on steps 1-2, then slim while fading.
				local thickness = if step <= 2 then 1.4 else 0.7
				beam.Size = Vector3.new(length, thickness, thickness)
				beam.Transparency = 0.1 + (step / 6) * 0.9
			end
		end
		beam:Destroy()
	end)
end

-- A one-shot particle burst at a position: an invisible anchor with a
-- ParticleEmitter that fires `count` particles in the given colour.
local function showParticles(position: Vector3, color: any, count: number, speed: number)
	local anchor = Instance.new("Part")
	anchor.Name = "BurstAnchor"
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = position
	anchor.Parent = Workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new(0.5)
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Parent = anchor
	emitter:Emit(count)
	task.delay(1.5, function()
		anchor:Destroy()
	end)
end

-- An expanding neon ring on the ground that grows and fades — the "pop"
-- under a catch, a dock or a steal.
local function showRing(position: Vector3, color: any)
	local ring = Instance.new("Part")
	ring.Name = "BurstRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.1
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CFrame = CFrame.new(Vector3.new(position.X, 0.4, position.Z)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace
	task.spawn(function()
		for step = 1, 6 do
			task.wait(0.08)
			if ring.Parent then
				local radius = 1 + step * 0.9
				ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
				ring.Transparency = 0.1 + (step / 6) * 0.9
			end
		end
		ring:Destroy()
	end)
end

-- A floating label that rises and fades (BONK!, +$X/s, STOLEN!, NEW RING!).
local function showFloatingText(position: Vector3, text: string, color: any, textSize: number)
	local anchor = Instance.new("Part")
	anchor.Name = "FloatAnchor"
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = position + Vector3.new(0, 2, 0)
	anchor.Parent = Workspace
	local tag = Instance.new("BillboardGui")
	tag.Name = "FloatTag"
	tag.Size = UDim2.new(0, 200, 0, 60)
	tag.AlwaysOnTop = true
	tag.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextSize = textSize
	label.Font = Enum.Font.GothamBold
	label.TextWrapped = true
	label.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	label.TextStrokeTransparency = 0.2
	label.Parent = tag
	tag.Parent = anchor
	task.spawn(function()
		for step = 1, 10 do
			task.wait(0.09)
			if anchor.Parent then
				anchor.Position += Vector3.new(0, 0.3, 0)
				label.TextTransparency = step / 10
			end
		end
		anchor:Destroy()
	end)
end

-- A floating BONK! label over ZORK that rises and fades.
local function showBonk(position: Vector3, count: number)
	showFloatingText(position + Vector3.new(0, 4, 0), `BONK! ({count}/3)`, Color3.fromRGB(255, 210, 60), 28)
end

-- Catch pop: a burst in the brainrot's rarity colour + an expanding ring.
local function showBurst(position: Vector3, color: any)
	showParticles(position, color, 24, 12)
	showRing(position, color)
end

-- Dock pop: a green burst, a ring, and the new income as floating text.
local function showDock(position: Vector3, rate: number)
	showParticles(position, Color3.fromRGB(90, 220, 130), 20, 10)
	showRing(position, Color3.fromRGB(90, 220, 130))
	showFloatingText(position, `+{FormatUtil.formatRate(rate)}`, Color3.fromRGB(255, 200, 60), 26)
end

-- Steal flash: a red burst where the brainrot was taken.
local function showSteal(position: Vector3)
	showParticles(position, Color3.fromRGB(255, 90, 90), 24, 12)
	showRing(position, Color3.fromRGB(255, 90, 90))
	showFloatingText(position, "STOLEN!", Color3.fromRGB(255, 90, 90), 26)
end

-- Rebirth confetti: three coloured bursts + a NEW RING! label.
local function showConfetti(position: Vector3)
	local colors = { Color3.fromRGB(255, 200, 60), Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 110, 200) }
	for _, color in colors do
		showParticles(position + Vector3.new(0, 2, 0), color, 30, 16)
	end
	showFloatingText(position, "NEW RING!", Color3.fromRGB(255, 200, 60), 30)
end

-- A full-screen orange flash when the solar storm hits.
local function showStormFlash()
	if not flashFrame then
		return
	end
	flashFrame.BackgroundTransparency = 0.55
	local tween = TweenService:Create(flashFrame, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
	tween:Play()
end

local function onFxEvent(payload: { [string]: any })
	local kind = payload.kind
	if kind == "beam" and payload.from and payload.to then
		showBeam(payload.from, payload.to)
	elseif kind == "bonk" and payload.position then
		showBonk(payload.position, payload.count or 1)
	elseif kind == "burst" and payload.position then
		showBurst(payload.position, payload.color or Color3.fromRGB(120, 220, 255))
	elseif kind == "dock" and payload.position then
		showDock(payload.position, payload.rate or 0)
	elseif kind == "steal" and payload.position then
		showSteal(payload.position)
	elseif kind == "confetti" and payload.position then
		showConfetti(payload.position)
	elseif kind == "stormFlash" then
		showStormFlash()
	end
end

function BeamEffects.init()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "FxGui"
	gui.DisplayOrder = 20
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	local frame = Instance.new("Frame")
	frame.Name = "StormFlash"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(255, 140, 50)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	flashFrame = frame

	local remote = Remotes.waitFor("FxEvent") :: RemoteEvent?
	if remote then
		remote.OnClientEvent:Connect(onFxEvent)
	end
end

return BeamEffects
