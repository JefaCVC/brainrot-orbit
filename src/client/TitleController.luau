--!strict
-- TitleController
-- The 3D title screen: a two-line gradient logo, the tagline panel, three
-- colored step cards and a pulsing PLAY button — floating over the LIVE 3D
-- view of the showcase stage (six brainrots on climbing pedestals with
-- neon rings, light beams and chasing marquee bulbs, built by the server's
-- WorldBuilder). The camera sways gently while the title is up.
-- PLAY (or the tour's hideTitle) restores the normal camera, shows the HUD
-- and tells the server the player is ready for state updates.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type ScreenGui = any
type Instance = any
type TextLabel = any
type TextButton = any
type Color3 = any

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local requireModule = require :: any
local UiKit = requireModule(script.Parent:WaitForChild("UiKit"))

local TitleController = {}

local player = Players.LocalPlayer
local titleGui: ScreenGui? = nil
local titleScale: Instance? = nil
local playButton: TextButton? = nil
local onDismissed: (() -> ())? = nil
local marqueeBulbs: { Instance } = {}
local marqueeScanned = false

-- The title camera frames the showcase stage (z = -14) from the spawn pad.
local TITLE_CAMERA_POSITION = Vector3.new(0, 6.5, 10)
local TITLE_CAMERA_TARGET = Vector3.new(0, 3.5, -14)

-- One logo line: LuckiestGuy, a two-color gradient, -3 degrees of tilt and
-- a thick ink stroke.
local function logoLine(parent: Instance, name: string, y: number, text: string, fromColor: Color3, toColor: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.new(0.5, -420, 0, y)
	label.Size = UDim2.new(0, 840, 0, 64)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Rotation = -3
	label.Parent = parent
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, fromColor),
		ColorSequenceKeypoint.new(1, toColor),
	})
	gradient.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 6
	stroke.Color = UiKit.INK
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return label
end

local function pointTitleCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(TITLE_CAMERA_POSITION, TITLE_CAMERA_TARGET)
end

local function restoreGameCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	else
		player.CharacterAdded:Once(function(newCharacter: any)
			local newHumanoid = newCharacter:FindFirstChildOfClass("Humanoid")
			local currentCamera = Workspace.CurrentCamera
			if newHumanoid and currentCamera then
				currentCamera.CameraSubject = newHumanoid
			end
		end)
	end
end

local function buildTitleGui(playerGui: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "TitleGui"
	gui.DisplayOrder = 10
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	local scale = Instance.new("UIScale")
	scale.Name = "TitleScale"
	scale.Parent = gui
	titleScale = scale

	-- Vignette veils: dark at the top and bottom, fading to clear in the
	-- middle, so the text reads while the 3D stage stays visible.
	local topVeil = UiKit.makeFrame(gui, "TopVeil", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 210), Color3.fromRGB(8, 12, 24), 0)
	topVeil.BackgroundTransparency = 0
	local topGradient = Instance.new("UIGradient")
	topGradient.Rotation = 90
	topGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	topGradient.Parent = topVeil
	local bottomVeil = UiKit.makeFrame(gui, "BottomVeil", UDim2.new(0, 0, 1, -190), UDim2.new(1, 0, 0, 190), Color3.fromRGB(8, 12, 24), 0)
	bottomVeil.BackgroundTransparency = 0
	local bottomGradient = Instance.new("UIGradient")
	bottomGradient.Rotation = 270
	bottomGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	bottomGradient.Parent = bottomVeil

	-- Two-line gradient logo, tilted -3 degrees.
	logoLine(gui, "LogoLine1", 18, "BRAINROT", Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 150, 40))
	logoLine(gui, "LogoLine2", 82, "ORBIT", Color3.fromRGB(255, 150, 40), Color3.fromRGB(255, 80, 60))

	-- Tagline in a cream panel.
	local taglinePanel = UiKit.panel(gui, "Tagline", UDim2.new(0.5, -330, 0, 152), UDim2.new(0, 660, 0, 40), nil)
	UiKit.makeLabel(
		taglinePanel,
		"TaglineText",
		UDim2.new(0, 8, 0, 0),
		UDim2.new(1, -16, 1, 0),
		"Catch them. Dock them. Get rich before the storm hits.",
		20,
		UiKit.TEXT,
		true
	)

	-- The 3-step how-to: three colored cards in a row, low enough that the
	-- showcase stage shows above them.
	local steps = {
		{ "1", "CATCH", "Tractor-beam a wild\nbrainrot  [E]", UiKit.COLORS.blue },
		{ "2", "CARRY HOME", "Before the solar\nstorm hits", UiKit.COLORS.orange },
		{ "3", "GET RICH", "Credits every second\n+ rebirths", UiKit.COLORS.green },
	} :: { { any } }
	for i, step in steps do
		local x = -465 + (i - 1) * 320
		local card = UiKit.panel(gui, `StepCard{i}`, UDim2.new(0.5, x, 0.62, 0), UDim2.new(0, 310, 0, 96), step[4])
		UiKit.makeLabel(card, "StepNumber", UDim2.new(0, 10, 0, 6), UDim2.new(0, 40, 0, 40), step[1], 30, UiKit.WHITE, true)
		UiKit.makeLabel(card, "StepTitle", UDim2.new(0, 52, 0, 6), UDim2.new(1, -62, 0, 40), step[2], 20, UiKit.WHITE, true).TextXAlignment =
			Enum.TextXAlignment.Left
		UiKit.makeLabel(card, "StepText", UDim2.new(0, 10, 0, 48), UDim2.new(1, -20, 0, 44), step[3], 15, UiKit.WHITE, false).TextXAlignment =
			Enum.TextXAlignment.Left
	end

	-- Pulsing PLAY button (the pulse loop runs in init).
	playButton = UiKit.button(gui, "PlayButton", UDim2.new(0.5, -150, 1, -128), UDim2.new(0, 300, 0, 86), UiKit.COLORS.green, "▶  PLAY", "Catch them all!", 30, 15)
	playButton.MouseButton1Click:Connect(function()
		TitleController.dismiss()
	end)
	UiKit.makeLabel(
		gui,
		"Footer",
		UDim2.new(0.5, -420, 1, -36),
		UDim2.new(0, 840, 0, 28),
		"E catch / dock / steal    •    L lock module    •    F bonk ZORK    •    Q drop cargo",
		16,
		UiKit.WHITE,
		false
	)

	gui.Parent = playerGui
	return gui
end

-- Collects the stage's marquee bulbs once (the server builds them under
-- Station/TitlePedestals with the name "MarqueeBulb").
local function scanMarqueeBulbs()
	if marqueeScanned then
		return
	end
	local station = Workspace:FindFirstChild("Station")
	local stage = station and station:FindFirstChild("TitlePedestals")
	if not stage then
		return
	end
	marqueeScanned = true
	for _, child in stage:GetChildren() do
		if child.Name == "MarqueeBulb" then
			table.insert(marqueeBulbs, child)
		end
	end
	table.sort(marqueeBulbs, function(a: Instance, b: Instance)
		return (a:GetAttribute("BulbIndex") or 0) < (b:GetAttribute("BulbIndex") or 0)
	end)
end

-- Chasing marquee lights: every third bulb lit, stepping 8 times a second.
local function animateMarquee()
	local step = 0
	while true do
		task.wait(0.125)
		if not TitleController.isVisible() then
			continue
		end
		scanMarqueeBulbs()
		step += 1
		for i, bulb in marqueeBulbs do
			if (i + step) % 3 == 0 then
				bulb.Transparency = 0
				bulb.Material = Enum.Material.Neon
			else
				bulb.Transparency = 0.7
				bulb.Material = Enum.Material.SmoothPlastic
			end
		end
	end
end

-- Shows the title screen over the live 3D stage view.
function TitleController.show()
	if titleGui then
		titleGui.Enabled = true
	end
	pointTitleCamera()
end

-- Hides the title screen, restores the game camera and runs the dismiss
-- callback (Main wires it to show the HUD + fire PlayerReady). Safe to
-- call repeatedly: the tour can show and dismiss the title many times.
function TitleController.dismiss()
	if titleGui then
		titleGui.Enabled = false
	end
	restoreGameCamera()
	local callback = onDismissed
	if callback then
		callback()
	end
end

function TitleController.isVisible(): boolean
	return titleGui ~= nil and titleGui.Enabled
end

function TitleController.init(playerGui: Instance, dismissCallback: () -> ())
	onDismissed = dismissCallback
	titleGui = buildTitleGui(playerGui)
	TitleController.show()
	-- Gentle camera sway + pulsing PLAY + responsive scale, all while the
	-- title is up.
	RunService.RenderStepped:Connect(function()
		if not TitleController.isVisible() then
			return
		end
		local camera = Workspace.CurrentCamera
		local now = os.clock()
		if camera then
			local swayX = math.sin(now * 0.3) * 2
			local swayY = math.sin(now * 0.23) * 0.8
			camera.CFrame = CFrame.lookAt(TITLE_CAMERA_POSITION + Vector3.new(swayX, swayY, 0), TITLE_CAMERA_TARGET)
			if titleScale then
				titleScale.Scale = UiKit.responsiveScale(camera.ViewportSize.Y)
			end
		end
		if playButton then
			local pulse = playButton:FindFirstChildOfClass("UIScale")
			if pulse then
				pulse.Scale = 1 + math.sin(now * 4) * 0.04
			end
		end
	end)
	task.spawn(animateMarquee)
end

return TitleController
