--!strict
-- TitleController
-- The 3D title screen: a big BRAINROT ORBIT logo, the tagline, the 3-step
-- how-to and a PLAY button — floating over the LIVE 3D view of the six
-- brainrots posed on their pedestals (the camera is scripted to frame
-- them). The overlay is mostly transparent so the world shows through;
-- this is dossier image 1, so it has to sell the game at a glance.
-- PLAY (or the tour's hideTitle) restores the normal camera, shows the HUD
-- and tells the server the player is ready for state updates.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type ScreenGui = any
type Instance = any

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local requireModule = require :: any
local UiKit = requireModule(script.Parent:WaitForChild("UiKit"))

local TitleController = {}

local player = Players.LocalPlayer
local titleGui: ScreenGui? = nil
local onDismissed: (() -> ())? = nil

-- The title camera frames the six pedestals (z = -14) from the spawn pad.
local TITLE_CAMERA_POSITION = Vector3.new(0, 6.5, 10)
local TITLE_CAMERA_TARGET = Vector3.new(0, 3.5, -14)

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

	-- A soft dark veil at the top and bottom so the text reads, while the
	-- 3D pedestals stay visible in the middle of the screen.
	local topVeil = UiKit.makeFrame(gui, "TopVeil", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 190), Color3.fromRGB(8, 12, 24), 0.25)
	topVeil.Name = "TopVeil"
	local bottomVeil = UiKit.makeFrame(gui, "BottomVeil", UDim2.new(0, 0, 1, -170), UDim2.new(1, 0, 0, 170), Color3.fromRGB(8, 12, 24), 0.25)
	bottomVeil.Name = "BottomVeil"

	local logo = UiKit.makeLabel(gui, "Logo", UDim2.new(0.5, -420, 0, 18), UDim2.new(0, 840, 0, 72), "BRAINROT ORBIT", 64, UiKit.TEXT, true)
	logo.TextStrokeColor3 = Color3.fromRGB(10, 20, 40)
	logo.TextStrokeTransparency = 0.1
	UiKit.makeLabel(
		gui,
		"Tagline",
		UDim2.new(0.5, -420, 0, 92),
		UDim2.new(0, 840, 0, 34),
		"Catch them. Dock them. Get rich before the storm hits.",
		22,
		UiKit.GOLD,
		true
	)

	-- The 3-step how-to: one panel, three columns, each step one line.
	local howTo = UiKit.makeFrame(gui, "HowTo", UDim2.new(0.5, -330, 0.5, -40), UDim2.new(0, 660, 0, 132), UiKit.PANEL_BG, UiKit.PANEL_BG_TRANSPARENCY)
	local steps = {
		{ "1", "CATCH", "Tractor-beam a wild\nbrainrot  [E]" },
		{ "2", "CARRY HOME", "Before the solar\nstorm hits" },
		{ "3", "GET RICH", "Credits every second\n+ rebirths" },
	} :: { { string } }
	for i, step in steps do
		local x = (i - 1) * 220 + 10
		UiKit.makeLabel(howTo, `StepNumber{i}`, UDim2.new(0, x, 0, 8), UDim2.new(0, 200, 0, 36), step[1], 30, UiKit.ACCENT, true)
		UiKit.makeLabel(howTo, `StepTitle{i}`, UDim2.new(0, x, 0, 44), UDim2.new(0, 200, 0, 28), step[2], 19, UiKit.TEXT, true)
		UiKit.makeLabel(howTo, `StepText{i}`, UDim2.new(0, x, 0, 74), UDim2.new(0, 200, 0, 50), step[3], 15, UiKit.MUTED, false)
	end

	local playButton = UiKit.makeButton(gui, "PlayButton", UDim2.new(0.5, -120, 1, -128), UDim2.new(0, 240, 0, 62), "PLAY", 30, Color3.fromRGB(40, 170, 80))
	playButton.MouseButton1Click:Connect(function()
		TitleController.dismiss()
	end)
	UiKit.makeLabel(
		gui,
		"Footer",
		UDim2.new(0.5, -420, 1, -56),
		UDim2.new(0, 840, 0, 28),
		"E catch / dock / steal    •    L lock module    •    F bonk ZORK    •    Q drop cargo",
		16,
		UiKit.MUTED,
		false
	)

	gui.Parent = playerGui
	return gui
end

-- Shows the title screen over the live 3D pedestal view.
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
end

return TitleController
