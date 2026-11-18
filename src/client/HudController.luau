--!strict
-- HudController
-- The in-game HUD for BRAINROT ORBIT: a centered top bar (credits, income
-- rate + multiplier, rebirth rings), the mission strip, the always-visible
-- storm countdown, the event banner, the MY MODULE roster panel, the
-- bottom-right action buttons (Lock / Rebirth / Upgrades / Index), the
-- cargo indicator, the context prompt and the toast stack.
--
-- Layout rules: nothing sits in the TOP-LEFT corner (Roblox's own menu
-- buttons live there), and no text ever overflows its box — dynamic labels
-- are truncated and fitted through UiKit.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type ScreenGui = any
type Instance = any
type TextLabel = any
type TextButton = any
type Frame = any
type RemoteEvent = any

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local requireModule = require :: any
local BrainrotData = requireModule(ReplicatedStorage:WaitForChild("BrainrotData"))
local ClientState = requireModule(script.Parent:WaitForChild("ClientState"))
local FormatUtil = requireModule(ReplicatedStorage:WaitForChild("FormatUtil"))
local PanelsController = requireModule(script.Parent:WaitForChild("PanelsController"))
local Remotes = requireModule(ReplicatedStorage:WaitForChild("Remotes"))
local UiKit = requireModule(script.Parent:WaitForChild("UiKit"))

local HudController = {}

local player = Players.LocalPlayer

local hudGui: ScreenGui? = nil
local creditsLabel: TextLabel? = nil
local rateLabel: TextLabel? = nil
local rebirthLabel: TextLabel? = nil
local missionLabel: TextLabel? = nil
local stormLabel: TextLabel? = nil
local bannerFrame: Frame? = nil
local bannerLabel: TextLabel? = nil
local rosterFrame: Frame? = nil
local rosterHeader: TextLabel? = nil
local rosterRows: Frame? = nil
local rosterStrip: Frame? = nil
local lockButton: TextButton? = nil
local cargoLabel: TextLabel? = nil
local promptLabel: TextLabel? = nil
local toastContainer: Frame? = nil
local bannerHideAt = 0

-- The eight module accent colors (mirrors the server's WorldBuilder
-- table): the MY MODULE panel's header strip takes the player's own
-- module color so the panel reads as theirs at a glance.
local MODULE_ACCENTS = {
	Color3.fromRGB(74, 163, 255),
	Color3.fromRGB(88, 214, 141),
	Color3.fromRGB(255, 130, 180),
	Color3.fromRGB(255, 160, 60),
	Color3.fromRGB(176, 108, 255),
	Color3.fromRGB(60, 220, 220),
	Color3.fromRGB(255, 215, 60),
	Color3.fromRGB(255, 100, 100),
} :: { any }

local BANNER_COLORS: { [string]: any } = {
	["storm-warning"] = Color3.fromRGB(255, 90, 70),
	["storm-active"] = Color3.fromRGB(255, 60, 40),
	["storm-over"] = Color3.fromRGB(90, 220, 130),
	["golden-hour"] = Color3.fromRGB(255, 200, 60),
	["golden-hour-over"] = Color3.fromRGB(170, 188, 212),
	["meteor"] = Color3.fromRGB(120, 200, 255),
	["zork"] = Color3.fromRGB(255, 90, 90),
	["zork-driven-off"] = Color3.fromRGB(90, 220, 130),
}

local function buildHud(playerGui: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "HudGui"
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Enabled = false

	-- Top bar: centered, clear of the top-left Roblox menu buttons.
	local topBar = UiKit.makeFrame(gui, "TopBar", UDim2.new(0.5, -280, 0, 8), UDim2.new(0, 560, 0, 40), UiKit.PANEL_BG, UiKit.PANEL_BG_TRANSPARENCY)
	UiKit.makeHeaderStrip(topBar, UiKit.GOLD)
	creditsLabel = UiKit.makeLabel(topBar, "Credits", UDim2.new(0, 8, 0, 0), UDim2.new(0, 180, 1, 0), "CREDITS  $0", 19, UiKit.GOLD, true)
	creditsLabel.TextXAlignment = Enum.TextXAlignment.Left
	rateLabel = UiKit.makeLabel(topBar, "Rate", UDim2.new(0, 188, 0, 0), UDim2.new(0, 200, 1, 0), "$0/s  (x1)", 19, UiKit.TEXT, true)
	rebirthLabel = UiKit.makeLabel(topBar, "Rebirths", UDim2.new(0, 388, 0, 0), UDim2.new(0, 164, 1, 0), "RING 0", 19, UiKit.ACCENT, true)
	rebirthLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- Mission strip: the next goal is always visible. It sits 8 px below
	-- the top bar now (was 4), so the stack breathes a little.
	local missionStrip = UiKit.makeFrame(gui, "MissionStrip", UDim2.new(0.5, -280, 0, 56), UDim2.new(0, 560, 0, 28), UiKit.PANEL_BG, 0.25)
	UiKit.makeHeaderStrip(missionStrip, UiKit.ACCENT)
	missionLabel = UiKit.makeLabel(missionStrip, "Mission", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 1, 0), "MISSION 1/4: Catch a brainrot (E)", 15, UiKit.TEXT, true)

	-- Storm countdown: always visible, turns red as the storm closes in.
	local stormStrip = UiKit.makeFrame(gui, "StormStrip", UDim2.new(0.5, -280, 0, 88), UDim2.new(0, 560, 0, 26), UiKit.PANEL_BG, 0.35)
	stormLabel = UiKit.makeLabel(stormStrip, "Storm", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 1, 0), "NEXT SOLAR STORM IN 1:00", 15, UiKit.MUTED, true)

	-- Event banner: transient announcements (Golden Hour, Meteor, ZORK).
	bannerFrame = UiKit.makeFrame(gui, "EventBanner", UDim2.new(0.5, -280, 0, 118), UDim2.new(0, 560, 0, 34), UiKit.PANEL_BG, 0.1)
	bannerFrame.Visible = false
	bannerLabel = UiKit.makeLabel(bannerFrame, "BannerText", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 1, 0), "", 17, UiKit.TEXT, true)

	-- Roster panel: MY MODULE (n/n) on the right side. Its header strip
	-- takes the player's module accent color once state arrives.
	rosterFrame = UiKit.makeFrame(gui, "Roster", UDim2.new(1, -262, 0, 60), UDim2.new(0, 250, 0, 34), UiKit.PANEL_BG, UiKit.PANEL_BG_TRANSPARENCY)
	rosterStrip = UiKit.makeHeaderStrip(rosterFrame, UiKit.ACCENT)
	rosterHeader = UiKit.makeLabel(rosterFrame, "Header", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 0, 30), "MY MODULE (0/4)", 16, UiKit.TEXT, true)
	rosterHeader.TextXAlignment = Enum.TextXAlignment.Left
	rosterRows = UiKit.makeFrame(rosterFrame, "Rows", UDim2.new(0, 0, 0, 30), UDim2.new(1, 0, 0, 0), UiKit.PANEL_BG, 1)
	rosterRows.BackgroundTransparency = 1

	-- Action buttons: bottom-right stack.
	local buttonNames = { "LockButton", "RebirthButton", "UpgradesButton", "IndexButton" }
	local buttonTexts = { "LOCK MODULE (L)", "REBIRTH", "UPGRADES", "INDEX" }
	for i, name in buttonNames do
		local y = -46 * (5 - i) - 8
		local button = UiKit.makeButton(gui, name, UDim2.new(1, -172, 1, y), UDim2.new(0, 160, 0, 38), buttonTexts[i], 16, UiKit.BUTTON_BG)
		if name == "LockButton" then
			lockButton = button
			button.MouseButton1Click:Connect(function()
				local remote = Remotes.waitFor("LockModule") :: RemoteEvent?
				if remote then
					remote:FireServer()
				end
			end)
		elseif name == "RebirthButton" then
			button.MouseButton1Click:Connect(function()
				PanelsController.showRebirthConfirm()
			end)
		elseif name == "UpgradesButton" then
			button.MouseButton1Click:Connect(function()
				PanelsController.toggleUpgrades()
			end)
		elseif name == "IndexButton" then
			button.MouseButton1Click:Connect(function()
				PanelsController.toggleIndex()
			end)
		end
	end

	-- Cargo indicator: bottom-left.
	local cargoFrame = UiKit.makeFrame(gui, "Cargo", UDim2.new(0, 12, 1, -76), UDim2.new(0, 260, 0, 64), UiKit.PANEL_BG, UiKit.PANEL_BG_TRANSPARENCY)
	cargoLabel = UiKit.makeLabel(cargoFrame, "CargoText", UDim2.new(0, 8, 0, 4), UDim2.new(1, -16, 1, -8), "CARGO (0/1)\nEmpty — catch a brainrot!", 15, UiKit.MUTED, true)
	cargoLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Context prompt: what [E] does right now, above the help line.
	promptLabel = UiKit.makeLabel(gui, "Prompt", UDim2.new(0.5, -280, 1, -64), UDim2.new(0, 560, 0, 26), "", 16, UiKit.GOLD, true)
	promptLabel.Visible = false

	-- Help line: bottom-center.
	UiKit.makeLabel(
		gui,
		"Help",
		UDim2.new(0.5, -280, 1, -34),
		UDim2.new(0, 560, 0, 24),
		"E catch / dock / steal    •    L lock module    •    F bonk ZORK    •    Q drop cargo",
		14,
		UiKit.MUTED,
		false
	)

	-- Toast stack: bottom-center, above the prompt.
	toastContainer = UiKit.makeFrame(gui, "Toasts", UDim2.new(0.5, -280, 1, -210), UDim2.new(0, 560, 0, 140), UiKit.PANEL_BG, 1)
	toastContainer.BackgroundTransparency = 1

	gui.Parent = playerGui
	return gui
end

local function rebuildRoster(state: { [string]: any })
	if not rosterRows or not rosterHeader or not rosterFrame then
		return
	end
	for _, child in rosterRows:GetChildren() do
		child:Destroy()
	end
	local roster = state.roster :: { any }
	local podsUsed = state.podsUsed or 0
	local podsMax = state.podsMax or 4
	rosterHeader.Text = `MY MODULE ({podsUsed}/{podsMax})`
	if rosterStrip then
		local moduleIndex = state.moduleIndex or 0
		if typeof(moduleIndex) == "number" and moduleIndex >= 1 and moduleIndex <= #MODULE_ACCENTS then
			rosterStrip.BackgroundColor3 = MODULE_ACCENTS[moduleIndex]
		else
			rosterStrip.BackgroundColor3 = UiKit.ACCENT
		end
	end
	local rowHeight = 26
	for i, entry in roster do
		local y = (i - 1) * rowHeight
		local row = UiKit.makeFrame(rosterRows, `Row{i}`, UDim2.new(0, 0, 0, y), UDim2.new(1, 0, 0, rowHeight), UiKit.PANEL_BG, 1)
		row.BackgroundTransparency = 1
		local rarityColor = BrainrotData.RARITY_COLORS[entry.rarity] or UiKit.TEXT
		local dot = UiKit.makeFrame(row, "Dot", UDim2.new(0, 8, 0, 8), UDim2.new(0, 10, 0, 10), rarityColor, 0)
		dot.Name = "Dot"
		local name = UiKit.truncate(entry.name, 17)
		if entry.mutation ~= "None" then
			name = `{name} [{entry.mutation}]`
			name = UiKit.truncate(name, 20)
		end
		local nameLabel = UiKit.makeLabel(row, "Name", UDim2.new(0, 24, 0, 0), UDim2.new(0, 140, 1, 0), name, 14, UiKit.TEXT, false)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		local rateText = FormatUtil.formatRate(entry.rate)
		local rate = UiKit.makeLabel(row, "Rate", UDim2.new(1, -84, 0, 0), UDim2.new(0, 76, 1, 0), rateText, 14, UiKit.GOLD, true)
		rate.TextXAlignment = Enum.TextXAlignment.Right
	end
	rosterRows.Size = UDim2.new(1, 0, 0, #roster * rowHeight)
	rosterFrame.Size = UDim2.new(0, 250, 0, 34 + #roster * rowHeight)
end

local function updateStormLabel(state: { [string]: any })
	if not stormLabel then
		return
	end
	local storm = state.storm :: { [string]: any }?
	local goldenLeft = state.goldenHourLeft or 0
	local text = ""
	local color = UiKit.MUTED
	if storm then
		if storm.phase == "warning" then
			text = `SOLAR STORM IN {math.ceil(storm.secondsLeft)}s — GET TO YOUR DOME!`
			color = Color3.fromRGB(255, 120, 90)
		elseif storm.phase == "active" then
			text = `SOLAR STORM! STAY IN YOUR DOME! ({math.ceil(storm.secondsLeft)}s)`
			color = Color3.fromRGB(255, 80, 60)
		else
			text = `NEXT SOLAR STORM IN {FormatUtil.formatCountdown(storm.nextStormIn or 60)}`
		end
	end
	if goldenLeft > 0 then
		text = `{text}   •   GOLDEN HOUR 2x ({math.ceil(goldenLeft)}s)`
	end
	stormLabel.Text = text
	stormLabel.TextColor3 = color
end

local function updateLockButton(state: { [string]: any })
	if not lockButton then
		return
	end
	local lockLeft = state.lockSecondsLeft or 0
	local cooldownLeft = state.lockCooldownLeft or 0
	if lockLeft > 0 then
		lockButton.Text = `LOCKED {math.ceil(lockLeft)}s`
		lockButton.BackgroundColor3 = Color3.fromRGB(40, 120, 80)
	elseif cooldownLeft > 0 then
		lockButton.Text = `SHIELD {math.ceil(cooldownLeft)}s`
		lockButton.BackgroundColor3 = Color3.fromRGB(90, 70, 30)
	else
		lockButton.Text = "LOCK MODULE (L)"
		lockButton.BackgroundColor3 = UiKit.BUTTON_BG
	end
end

local function updateCargo(state: { [string]: any })
	if not cargoLabel then
		return
	end
	local cargo = state.cargo :: { any }
	local capacity = state.cargoCapacity or 1
	if #cargo == 0 then
		cargoLabel.Text = `CARGO (0/{capacity})\nEmpty — catch a brainrot!`
		cargoLabel.TextColor3 = UiKit.MUTED
	else
		local names: { string } = {}
		for _, entry in cargo do
			table.insert(names, entry.name)
		end
		cargoLabel.Text = `CARGO ({#cargo}/{capacity})\n{UiKit.truncate(table.concat(names, ", "), 32)}`
		cargoLabel.TextColor3 = UiKit.TEXT
	end
end

-- Re-renders the whole HUD from one server state table.
function HudController.updateFromState(state: { [string]: any })
	if creditsLabel then
		creditsLabel.Text = `CREDITS  {FormatUtil.formatMoney(state.credits or 0)}`
	end
	if rateLabel then
		rateLabel.Text = `{FormatUtil.formatRate(state.rate or 0)}  ({FormatUtil.formatMultiplier(state.multiplier or 1)})`
	end
	if rebirthLabel then
		rebirthLabel.Text = `RING {state.rebirths or 0}`
	end
	if missionLabel then
		local mission = state.mission :: { [string]: any }?
		if mission then
			if mission.complete then
				missionLabel.Text = "ALL MISSIONS COMPLETE! You are a true Orbit legend."
			else
				missionLabel.Text = `MISSION {mission.index}/{mission.total}: {mission.text} — REWARD {mission.reward} credits  [{math.floor(mission.progress)}/{mission.goal}]`
			end
			UiKit.fitText(missionLabel, 15, 11)
		end
	end
	updateStormLabel(state)
	updateLockButton(state)
	updateCargo(state)
	rebuildRoster(state)
end

-- Shows the event banner for a few seconds (storm warnings refresh it
-- every second from the server, so they stay up as long as they last).
function HudController.showBanner(kind: string, text: string, seconds: number)
	if not bannerFrame or not bannerLabel then
		return
	end
	bannerLabel.Text = text
	bannerLabel.TextColor3 = BANNER_COLORS[kind] or UiKit.TEXT
	bannerFrame.Visible = true
	UiKit.fitText(bannerLabel, 17, 12)
	local hideAfter = seconds
	if kind == "storm-warning" or kind == "storm-active" then
		hideAfter = 1.5 -- refreshed every second by the server
	elseif hideAfter <= 0 then
		hideAfter = 5
	end
	local hideAt = os.clock() + hideAfter
	bannerHideAt = hideAt
	task.delay(hideAfter, function()
		if bannerHideAt == hideAt and bannerFrame then
			bannerFrame.Visible = false
		end
	end)
end

-- One-line feedback near the bottom of the screen, fading after 4 seconds.
function HudController.showToast(text: string)
	if not toastContainer then
		return
	end
	local children = toastContainer:GetChildren()
	if #children >= 3 then
		children[1]:Destroy()
	end
	local toast = UiKit.makeLabel(
		toastContainer,
		"Toast",
		UDim2.new(0, 0, 0, #toastContainer:GetChildren() * 30),
		UDim2.new(1, 0, 0, 28),
		UiKit.truncate(text, 64),
		15,
		UiKit.TEXT,
		true
	)
	toast.BackgroundTransparency = 0.25
	toast.BackgroundColor3 = UiKit.PANEL_BG
	task.spawn(function()
		task.wait(3.5)
		if toast.Parent then
			local tween = TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			toast:Destroy()
		end
	end)
end

-- The context prompt: what pressing [E] does right now.
function HudController.setPrompt(text: string?)
	if not promptLabel then
		return
	end
	if text and text ~= "" then
		promptLabel.Text = text
		promptLabel.Visible = true
	else
		promptLabel.Visible = false
	end
end

function HudController.show()
	if hudGui then
		hudGui.Enabled = true
	end
	local state = ClientState.getState()
	if state then
		HudController.updateFromState(state)
	end
end

function HudController.hide()
	if hudGui then
		hudGui.Enabled = false
	end
end

function HudController.init()
	local playerGui = player:WaitForChild("PlayerGui")
	hudGui = buildHud(playerGui)
	ClientState.getStateChangedSignal():Connect(function(state: any)
		HudController.updateFromState(state)
	end)
end

return HudController
