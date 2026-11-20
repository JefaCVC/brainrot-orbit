--!strict
-- BeamEffects
-- Client-side visual effects for BRAINROT ORBIT, driven by the server's
-- FxEvent remote: the tractor beam (a cyan energy cylinder that snaps from
-- the player to the caught brainrot and fades), the catch burst, the dock
-- pop with floating +credits text, the steal flash, the rebirth confetti,
-- the storm screen flash, and the ZAPPED! burst when the Zapper lands on
-- ZORK. Round 5 adds: built-in Roblox sounds with varied pitch, giant
-- "shout" texts + screen flashes for big events, floating +$X cash popups
-- over the player's own module sign every second, and a home beam from the
-- player to their module while carrying. All effects are procedural
-- (parts, ParticleEmitters, tweens, built-in rbxasset:// sounds) — no
-- asset ids. Cosmetic only — the server already decided the outcome before
-- the effect plays.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Vector3 = any
type RemoteEvent = any
type ScreenGui = any
type Frame = any
type TextLabel = any
type Instance = any
type Color3 = any

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local requireModule = require :: any
local ClientState = requireModule(script.Parent:WaitForChild("ClientState"))
local FormatUtil = requireModule(ReplicatedStorage:WaitForChild("FormatUtil"))
local Remotes = requireModule(ReplicatedStorage:WaitForChild("Remotes"))
local TitleController = requireModule(script.Parent:WaitForChild("TitleController"))

local BeamEffects = {}

local player = Players.LocalPlayer
local flashFrame: Frame? = nil
local shoutLabel: TextLabel? = nil
local muted = false

-- Built-in Roblox sounds (rbxasset:// library paths, not uploaded assets).
local SOUNDS: { [string]: string } = {
	ping = "rbxasset://sounds/electronicpingshort.wav",
	swoosh = "rbxasset://sounds/action_jump.mp3",
	oof = "rbxasset://sounds/uuhhh.mp3",
	bonk = "rbxasset://sounds/collide.wav",
}
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local function playSound(name: string, pitch: number?, volume: number?)
	if muted then
		return
	end
	local soundId = SOUNDS[name]
	if not soundId then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.PlaybackSpeed = pitch or 1
	sound.Volume = volume or 0.6
	SoundService:PlayLocalSound(sound)
	task.delay(3, function()
		sound:Destroy()
	end)
end

function BeamEffects.setMuted(value: boolean): boolean
	muted = value
	return muted
end

function BeamEffects.isMuted(): boolean
	return muted
end

-- A full-screen color flash (the storm flash frame, recolored per event).
local function flashScreen(color: Color3, strength: number)
	if not flashFrame then
		return
	end
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = 1 - strength
	local tween = TweenService:Create(flashFrame, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
	tween:Play()
end

-- Giant LuckiestGuy shout text that pops in the upper-middle of the screen
-- with a colored screen flash — for storms, rebirths and ZORK raids.
function BeamEffects.shout(text: string, color: Color3)
	if not shoutLabel then
		return
	end
	shoutLabel.Text = text
	shoutLabel.TextColor3 = color
	shoutLabel.TextTransparency = 0
	local stroke = shoutLabel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	local scale = shoutLabel:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.6
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	flashScreen(color, 0.25)
	task.spawn(function()
		task.wait(1.4)
		if shoutLabel then
			local fade = TweenService:Create(shoutLabel, TweenInfo.new(0.4), { TextTransparency = 1 })
			fade:Play()
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			end
		end
	end)
end

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
	emitter.Texture = SPARKLE_TEXTURE
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

-- A floating label that rises and fades (ZAPPED!, +$X/s, STOLEN!, NEW RING!).
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
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextWrapped = true
	label.TextStrokeColor3 = Color3.fromRGB(20, 20, 24)
	label.TextStrokeTransparency = 0.1
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

-- A floating ZAPPED! label over ZORK that rises and fades.
local function showBonk(position: Vector3, count: number)
	showFloatingText(position + Vector3.new(0, 4, 0), `ZAPPED! ({count}/3)`, Color3.fromRGB(255, 210, 60), 28)
	playSound("bonk", 1 + count * 0.15, 0.7)
end

-- Catch pop: a burst in the brainrot's rarity colour + an expanding ring.
local function showBurst(position: Vector3, color: any)
	showParticles(position, color, 50, 12)
	showRing(position, color)
	playSound("ping", 1.2, 0.6)
end

-- Dock pop: a green burst, a ring, and the new income as floating text.
local function showDock(position: Vector3, rate: number)
	showParticles(position, Color3.fromRGB(90, 220, 130), 50, 10)
	showRing(position, Color3.fromRGB(90, 220, 130))
	showFloatingText(position, `+{FormatUtil.formatRate(rate)}`, Color3.fromRGB(255, 200, 60), 26)
	playSound("ping", 1.5, 0.6)
end

-- Steal flash: a red burst where the brainrot was taken.
local function showSteal(position: Vector3)
	showParticles(position, Color3.fromRGB(255, 90, 90), 50, 12)
	showRing(position, Color3.fromRGB(255, 90, 90))
	showFloatingText(position, "STOLEN!", Color3.fromRGB(255, 90, 90), 26)
	playSound("oof", 1, 0.7)
end

-- Rebirth confetti: three coloured bursts + a NEW RING! label + a shout.
local function showConfetti(position: Vector3)
	local colors = { Color3.fromRGB(255, 200, 60), Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 110, 200) }
	for _, color in colors do
		showParticles(position + Vector3.new(0, 2, 0), color, 30, 16)
	end
	showFloatingText(position, "NEW RING!", Color3.fromRGB(255, 200, 60), 30)
	BeamEffects.shout("NEW RING!", Color3.fromRGB(176, 104, 255))
	playSound("ping", 1.8, 0.7)
end

-- A full-screen orange flash when the solar storm hits.
local function showStormFlash()
	flashScreen(Color3.fromRGB(255, 140, 50), 0.45)
	playSound("swoosh", 0.7, 0.7)
end

local function onFxEvent(payload: { [string]: any })
	local kind = payload.kind
	if kind == "beam" and payload.from and payload.to then
		showBeam(payload.from, payload.to)
		playSound("swoosh", 1, 0.6)
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

-- The home beam: a green-to-yellow sparkle Beam from the player to their
-- own module while they carry cargo. Attachments live on the character's
-- root part and the module floor, so the beam follows both ends.
local homeBeam: Instance? = nil
local homeAttachment0: Instance? = nil
local homeAttachment1: Instance? = nil

local function getMyModuleFloor(): Instance?
	local state = ClientState.getState()
	local moduleIndex = state and state.moduleIndex or 0
	if moduleIndex == 0 then
		return nil
	end
	local station = Workspace:FindFirstChild("Station")
	local moduleFolder = station and station:FindFirstChild(`Module{moduleIndex}`)
	local floor = moduleFolder and moduleFolder:FindFirstChild(`Module{moduleIndex}Floor`)
	if floor and floor:IsA("BasePart") then
		return floor
	end
	return nil
end

local function destroyHomeBeam()
	if homeBeam then
		homeBeam:Destroy()
		homeBeam = nil
	end
	if homeAttachment0 then
		homeAttachment0:Destroy()
		homeAttachment0 = nil
	end
	if homeAttachment1 then
		homeAttachment1:Destroy()
		homeAttachment1 = nil
	end
end

local function updateHomeBeam()
	local state = ClientState.getState()
	local cargo = state and state.cargo :: { any }?
	local carrying = cargo ~= nil and #cargo > 0
	if not carrying or TitleController.isVisible() then
		destroyHomeBeam()
		return
	end
	if homeBeam and homeAttachment0 and homeAttachment0.Parent and homeAttachment1 and homeAttachment1.Parent then
		return -- already live and attached
	end
	destroyHomeBeam()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local floor = getMyModuleFloor()
	if not root or not floor then
		return
	end
	local attach0 = Instance.new("Attachment")
	attach0.Name = "HomeBeamAttach"
	attach0.Parent = root
	local attach1 = Instance.new("Attachment")
	attach1.Name = "HomeBeamAttach"
	attach1.Position = Vector3.new(0, 2, 0)
	attach1.Parent = floor
	local beam = Instance.new("Beam")
	beam.Name = "HomeBeam"
	beam.Attachment0 = attach0
	beam.Attachment1 = attach1
	beam.Color = ColorSequence.new(Color3.fromRGB(90, 220, 130), Color3.fromRGB(255, 220, 60))
	beam.Texture = SPARKLE_TEXTURE
	beam.TextureSpeed = 2
	beam.FaceCamera = true
	beam.Width0 = 1.5
	beam.Width1 = 1.5
	beam.LightEmission = 1
	beam.Parent = root
	homeBeam = beam
	homeAttachment0 = attach0
	homeAttachment1 = attach1
end

-- Floating +$X cash popups over the player's own module sign, once a
-- second, while the HUD is up and the module earns.
local function cashPopupLoop()
	while true do
		task.wait(1)
		if TitleController.isVisible() then
			continue
		end
		local state = ClientState.getState()
		if not state then
			continue
		end
		local rate = state.rate or 0
		if rate <= 0 then
			continue
		end
		local moduleIndex = state.moduleIndex or 0
		if moduleIndex == 0 then
			continue
		end
		local station = Workspace:FindFirstChild("Station")
		local moduleFolder = station and station:FindFirstChild(`Module{moduleIndex}`)
		local signBoard = moduleFolder and moduleFolder:FindFirstChild("SignBoard")
		if signBoard and signBoard:IsA("BasePart") then
			showFloatingText(signBoard.Position + Vector3.new(0, 3, 0), `+{FormatUtil.formatMoney(rate)}`, Color3.fromRGB(120, 255, 140), 22)
		end
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

	-- The shout label: giant LuckiestGuy text, upper-middle of the screen.
	local shout = Instance.new("TextLabel")
	shout.Name = "Shout"
	shout.Position = UDim2.new(0.5, -400, 0.22, 0)
	shout.Size = UDim2.new(0, 800, 0, 90)
	shout.BackgroundTransparency = 1
	shout.Text = ""
	shout.TextColor3 = Color3.fromRGB(255, 255, 255)
	shout.Font = Enum.Font.LuckiestGuy
	shout.TextScaled = true
	shout.TextTransparency = 1
	shout.Parent = gui
	local shoutStroke = Instance.new("UIStroke")
	shoutStroke.Thickness = 3
	shoutStroke.Color = Color3.fromRGB(20, 20, 24)
	shoutStroke.Transparency = 1
	shoutStroke.Parent = shout
	local shoutScale = Instance.new("UIScale")
	shoutScale.Parent = shout
	shoutLabel = shout

	local remote = Remotes.waitFor("FxEvent") :: RemoteEvent?
	if remote then
		remote.OnClientEvent:Connect(onFxEvent)
	end
	ClientState.getStateChangedSignal():Connect(function(_state: any)
		updateHomeBeam()
	end)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		updateHomeBeam()
	end)
	task.spawn(cashPopupLoop)
end

return BeamEffects
