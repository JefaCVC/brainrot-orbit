--!strict
-- TutorialController
-- First-60-seconds onboarding for BRAINROT ORBIT: a small left-side panel
-- walks a new player through catch -> dock -> lock, with a 3D beacon (a
-- Highlight + a floating arrow) pointing at the exact thing to do next:
-- the nearest wild brainrot, then the nearest empty pod in their module,
-- then their module itself. Steps advance from live server state, so the
-- tutorial can never get stuck or contradict the game.
--
-- Rules: it only ever appears for fresh players (no mission completed yet),
-- never while the title screen is up, and it is always dismissible with
-- the X button. Session-only — no DataStore schema change.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Player = any
type Model = any
type Vector3 = any
type Instance = any
type TextLabel = any
type Frame = any
type Highlight = any

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local requireModule = require :: any
local ClientState = requireModule(script.Parent:WaitForChild("ClientState"))
local TitleController = requireModule(script.Parent:WaitForChild("TitleController"))
local UiKit = requireModule(script.Parent:WaitForChild("UiKit"))

local TutorialController = {}

local player = Players.LocalPlayer

local tutorialFrame: Frame? = nil
local stepLabel: TextLabel? = nil
local highlight: Highlight? = nil
local arrowAnchor: Instance? = nil
local arrowGui: Instance? = nil

local currentStep = 0 -- 0 = hidden, 1 = catch, 2 = dock, 3 = lock, 4 = done
local dismissed = false
local everLocked = false
local doneShownAt = 0

local STEP_TEXTS = {
	"1/3  Catch a wild brainrot — press [E]",
	"2/3  Dock it in a pod in your module — [E]",
	"3/3  Lock your module to stay safe — [L]",
	"You're set! Earn credits, upgrade, rebirth.",
} :: { string }

local function getRootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	return root.Position
end

-- Nearest wild brainrot to the player (step 1 beacon target).
local function findNearestWild(rootPosition: Vector3): (Model?, Vector3?)
	local wildFolder = Workspace:FindFirstChild("WildBrainrots")
	if not wildFolder then
		return nil, nil
	end
	local best: Model? = nil
	local bestPosition: Vector3? = nil
	local bestDistance = math.huge
	for _, model in wildFolder:GetChildren() do
		if model:IsA("Model") and model.PrimaryPart then
			local pivot = model:GetPivot().Position
			local distance = (Vector3.new(pivot.X, 0, pivot.Z) - Vector3.new(rootPosition.X, 0, rootPosition.Z)).Magnitude
			if distance < bestDistance then
				best = model
				bestPosition = pivot
				bestDistance = distance
			end
		end
	end
	return best, bestPosition
end

-- Nearest empty pod platform in the player's own module (step 2 beacon).
local function findNearestEmptyPod(state: { [string]: any }, rootPosition: Vector3): (Instance?, Vector3?)
	local moduleIndex = state.moduleIndex or 0
	if moduleIndex == 0 then
		return nil, nil
	end
	local station = Workspace:FindFirstChild("Station")
	local moduleFolder = station and station:FindFirstChild(`Module{moduleIndex}`)
	if not moduleFolder then
		return nil, nil
	end
	local occupied: { [number]: boolean } = {}
	for _, entry in state.roster :: { any } do
		occupied[entry.pod] = true
	end
	local best: Instance? = nil
	local bestPosition: Vector3? = nil
	local bestDistance = math.huge
	for _, child in moduleFolder:GetChildren() do
		local podNumber = string.match(child.Name, "^Pod(%d+)Platform$")
		if podNumber and child:IsA("BasePart") then
			local podIndex = tonumber(podNumber) or 0
			if podIndex >= 1 and podIndex <= (state.podsMax or 4) and not occupied[podIndex] then
				local distance = (Vector3.new(child.Position.X, 0, child.Position.Z) - Vector3.new(rootPosition.X, 0, rootPosition.Z)).Magnitude
				if distance < bestDistance then
					best = child
					bestPosition = child.Position
					bestDistance = distance
				end
			end
		end
	end
	return best, bestPosition
end

-- The player's own module floor (step 3 beacon).
local function findModuleFloor(state: { [string]: any }): (Instance?, Vector3?)
	local moduleIndex = state.moduleIndex or 0
	if moduleIndex == 0 then
		return nil, nil
	end
	local station = Workspace:FindFirstChild("Station")
	local moduleFolder = station and station:FindFirstChild(`Module{moduleIndex}`)
	local floor = moduleFolder and moduleFolder:FindFirstChild(`Module{moduleIndex}Floor`)
	if floor and floor:IsA("BasePart") then
		return floor, floor.Position
	end
	return nil, nil
end

-- Points the beacon at the current step's target (or hides it).
local function updateBeacon()
	if not highlight or not arrowAnchor or not arrowGui then
		return
	end
	local state = ClientState.getState()
	local rootPosition = getRootPosition()
	if currentStep < 1 or currentStep > 3 or not state or not rootPosition or TitleController.isVisible() then
		highlight.Adornee = nil
		arrowGui.Enabled = false
		return
	end
	local target: any = nil
	local targetPosition: Vector3? = nil
	if currentStep == 1 then
		target, targetPosition = findNearestWild(rootPosition)
	elseif currentStep == 2 then
		target, targetPosition = findNearestEmptyPod(state, rootPosition)
	elseif currentStep == 3 then
		target, targetPosition = findModuleFloor(state)
	end
	if target and targetPosition then
		highlight.Adornee = target
		arrowAnchor.Position = targetPosition + Vector3.new(0, 6, 0)
		arrowGui.Enabled = true
	else
		highlight.Adornee = nil
		arrowGui.Enabled = false
	end
end

-- Decides the current step purely from server state, so the tutorial can
-- never disagree with the game: docked -> lock, carrying -> dock, else
-- catch. Locking once completes the tutorial for the session.
local function computeStep(state: { [string]: any }): number
	if dismissed then
		return 0
	end
	if (state.missionsCompleted or 0) >= 4 then
		return 0
	end
	local lockLeft = state.lockSecondsLeft or 0
	if lockLeft > 0 then
		everLocked = true
	end
	local podsUsed = state.podsUsed or 0
	local cargo = state.cargo :: { any }
	if podsUsed > 0 then
		if everLocked then
			return 4
		end
		return 3
	elseif #cargo > 0 then
		return 2
	else
		return 1
	end
end

local function refreshFromState(state: { [string]: any }?)
	if not tutorialFrame or not stepLabel then
		return
	end
	if not state then
		tutorialFrame.Visible = false
		currentStep = 0
		updateBeacon()
		return
	end
	-- Returning players who already have a docked roster never see the
	-- tutorial. A player who finished mission 1 but has nothing docked
	-- still needs the steps, so they are not skipped here.
	if (state.missionsCompleted or 0) >= 1 and currentStep == 0 and not everLocked then
		if (state.podsUsed or 0) > 0 then
			dismissed = true
		end
	end
	local step = computeStep(state)
	if step == 4 and currentStep ~= 4 then
		doneShownAt = os.clock()
	end
	currentStep = step
	if step == 0 then
		tutorialFrame.Visible = false
		updateBeacon()
		return
	end
	if step == 4 and os.clock() - doneShownAt > 5 then
		tutorialFrame.Visible = false
		dismissed = true
		currentStep = 0
		updateBeacon()
		return
	end
	stepLabel.Text = STEP_TEXTS[step]
	UiKit.fitText(stepLabel, 15, 12)
	tutorialFrame.Visible = not TitleController.isVisible()
	updateBeacon()
end

function TutorialController.hide()
	dismissed = true
	currentStep = 0
	if tutorialFrame then
		tutorialFrame.Visible = false
	end
	updateBeacon()
end

function TutorialController.init()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "TutorialGui"
	gui.DisplayOrder = 6
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	-- Left side, clear of the top bar, the roster and the cargo panel.
	local frame = UiKit.makeFrame(gui, "Tutorial", UDim2.new(0, 12, 0, 120), UDim2.new(0, 320, 0, 76), UiKit.PANEL_BG, UiKit.PANEL_BG_TRANSPARENCY)
	frame.Visible = false
	tutorialFrame = frame
	UiKit.makeLabel(frame, "Title", UDim2.new(0, 10, 0, 4), UDim2.new(0, 120, 0, 22), "TUTORIAL", 14, UiKit.ACCENT, true).TextXAlignment =
		Enum.TextXAlignment.Left
	local dismiss = UiKit.makeButton(frame, "Dismiss", UDim2.new(1, -32, 0, 4), UDim2.new(0, 26, 0, 26), "X", 15, Color3.fromRGB(160, 60, 60))
	dismiss.MouseButton1Click:Connect(function()
		TutorialController.hide()
	end)
	local label = UiKit.makeLabel(frame, "Step", UDim2.new(0, 10, 0, 28), UDim2.new(1, -20, 0, 42), "", 15, UiKit.TEXT, false)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	stepLabel = label

	-- The beacon: a Highlight on the target + a floating gold arrow.
	local beacon = Instance.new("Highlight")
	beacon.Name = "TutorialBeacon"
	beacon.FillColor = Color3.fromRGB(90, 180, 255)
	beacon.FillTransparency = 0.6
	beacon.OutlineColor = Color3.fromRGB(255, 255, 255)
	beacon.OutlineTransparency = 0
	beacon.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	beacon.Adornee = nil
	beacon.Parent = Workspace
	highlight = beacon

	local anchor = Instance.new("Part")
	anchor.Name = "TutorialArrowAnchor"
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = Vector3.new(0, 50, 0)
	anchor.Parent = Workspace
	arrowAnchor = anchor
	local tag = Instance.new("BillboardGui")
	tag.Name = "TutorialArrow"
	tag.Size = UDim2.new(0, 60, 0, 60)
	tag.AlwaysOnTop = true
	tag.Enabled = false
	tag.Adornee = anchor
	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.new(1, 0, 1, 0)
	arrow.BackgroundTransparency = 1
	arrow.Text = "▼"
	arrow.TextColor3 = Color3.fromRGB(255, 200, 60)
	arrow.TextSize = 40
	arrow.Font = Enum.Font.GothamBold
	arrow.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	arrow.TextStrokeTransparency = 0.2
	arrow.Parent = tag
	tag.Parent = anchor
	arrowGui = tag

	ClientState.getStateChangedSignal():Connect(function(state: any)
		refreshFromState(state)
	end)
	-- Re-target the beacon twice a second: wild brainrots wander, and the
	-- player moves. Also hides the panel while the title screen is up.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if tutorialFrame then
				if TitleController.isVisible() then
					tutorialFrame.Visible = false
				elseif currentStep > 0 and not dismissed then
					if currentStep == 4 and os.clock() - doneShownAt > 5 then
						TutorialController.hide()
					else
						tutorialFrame.Visible = true
					end
				end
			end
			updateBeacon()
		end
	end)
end

return TutorialController
