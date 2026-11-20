--!strict
-- PanelsController
-- The pop-up panels of BRAINROT ORBIT, restyled round 5 on the cartoon
-- UiKit and rebuilt round 7 from the top-10 audit: Upgrades (the four
-- named, levelled tracks with LV n/m and candy buy buttons), the Star
-- Chart (all 30 species in a rarity-sorted scrollable grid, undiscovered
-- ones as ??? silhouettes, ON BASE tags, a mutation legend and one-line
-- flavor text per alien), Quests (the 14 station quests with progress and
-- rewards), and the Rebirth confirmation dialog. Panels open over the HUD,
-- pause nothing, and close with their X button, the same button that
-- opened them, or the tour's commands (openPanels opens Star Chart +
-- Upgrades together for the dossier shot).

-- Engine types used in annotations below (the values come from Roblox at runtime).
type ScreenGui = any
type Instance = any
type TextLabel = any
type TextButton = any
type Frame = any
type RemoteEvent = any

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local requireModule = require :: any
local BrainrotData = requireModule(ReplicatedStorage:WaitForChild("BrainrotData"))
local ClientState = requireModule(script.Parent:WaitForChild("ClientState"))
local FormatUtil = requireModule(ReplicatedStorage:WaitForChild("FormatUtil"))
local Remotes = requireModule(ReplicatedStorage:WaitForChild("Remotes"))
local UiKit = requireModule(script.Parent:WaitForChild("UiKit"))

local PanelsController = {}

local player = Players.LocalPlayer

local upgradesPanel: Frame? = nil
local indexPanel: Frame? = nil
local questsPanel: Frame? = nil
local rebirthDialog: Frame? = nil
local rebirthCostLabel: TextLabel? = nil
local flavorLabel: TextLabel? = nil

local TRACK_ORDER = { "Beam", "Cargo", "Shield", "Expansion" } :: { string }
local TRACK_COLORS: { [string]: any } = {
	Beam = UiKit.COLORS.cyan,
	Cargo = UiKit.COLORS.green,
	Shield = UiKit.COLORS.blue,
	Expansion = UiKit.COLORS.purple,
}

local function closeButton(parent: Frame, onClose: () -> ())
	local button = UiKit.button(parent, "Close", UDim2.new(1, -40, 0, 6), UDim2.new(0, 32, 0, 32), UiKit.BUTTON_COLORS.red, "X", nil)
	button.MouseButton1Click:Connect(onClose)
	return button
end

local function buildUpgradesPanel(gui: ScreenGui)
	local panel = UiKit.panel(gui, "UpgradesPanel", UDim2.new(0.5, -260, 0.5, -190), UDim2.new(0, 520, 0, 380), nil)
	panel.Visible = false
	UiKit.makeLabel(panel, "Title", UDim2.new(0, 12, 0, 6), UDim2.new(0, 300, 0, 32), "UPGRADES", 22, UiKit.TEXT, true).TextXAlignment =
		Enum.TextXAlignment.Left
	closeButton(panel, function()
		PanelsController.hideUpgrades()
	end)
	for i, track in TRACK_ORDER do
		local trackData = BrainrotData.UPGRADES[track]
		local y = 48 + (i - 1) * 80
		local row = UiKit.makeFrame(panel, `{track}Row`, UDim2.new(0, 12, 0, y), UDim2.new(1, -24, 0, 72), UiKit.CREAM_DARK, 0.1)
		local stripe = UiKit.makeFrame(row, "Stripe", UDim2.new(0, 0, 0, 6), UDim2.new(0, 10, 1, -12), TRACK_COLORS[track], 0)
		stripe.Name = "Stripe"
		UiKit.makeLabel(row, "Name", UDim2.new(0, 18, 0, 4), UDim2.new(0, 200, 0, 26), trackData.displayName, 18, UiKit.TEXT, true).TextXAlignment =
			Enum.TextXAlignment.Left
		local blurb = UiKit.makeLabel(row, "Blurb", UDim2.new(0, 18, 0, 30), UDim2.new(0, 200, 0, 36), trackData.blurb, 14, UiKit.MUTED, false)
		blurb.TextXAlignment = Enum.TextXAlignment.Left
		-- The level label is 170 px wide and fitted down to 13 pt, so
		-- even the longest level ("LV 2/2 - Triple Bubble") fits on one
		-- line. The dark blue passes 4.9:1 on cream.
		local levelLabel = UiKit.makeLabel(row, "Level", UDim2.new(0, 222, 0, 4), UDim2.new(0, 170, 0, 26), "LV 0/2", 15, UiKit.BLUE_DARK, true)
		levelLabel.Name = "Level"
		local buyButton = UiKit.button(row, "Buy", UDim2.new(1, -120, 0, 14), UDim2.new(0, 108, 0, 44), UiKit.BUTTON_COLORS.green, "$500", nil)
		buyButton.Name = "Buy"
		buyButton.MouseButton1Click:Connect(function()
			local remote = Remotes.waitFor("BuyUpgrade") :: RemoteEvent?
			if remote then
				remote:FireServer(track)
			end
		end)
	end
	return panel
end

local function refreshUpgradesPanel()
	local state = ClientState.getState()
	if not upgradesPanel or not state then
		return
	end
	local upgrades = state.upgrades :: { [string]: any }
	for _, track in TRACK_ORDER do
		local trackData = BrainrotData.UPGRADES[track]
		local row = upgradesPanel:FindFirstChild(`{track}Row`)
		if row then
			local level = upgrades[track] or 0
			local maxLevel = #trackData.levels - 1
			local levelLabel = row:FindFirstChild("Level") :: TextLabel?
			local buyButton = row:FindFirstChild("Buy") :: TextButton?
			if levelLabel then
				local levelName = trackData.levels[level + 1].name
				levelLabel.Text = `LV {level}/{maxLevel} - {levelName}`
				UiKit.fitText(levelLabel, 15, 13)
			end
			if buyButton then
				if level >= maxLevel then
					UiKit.setButtonTitle(buyButton, "MAX")
					UiKit.setButtonColor(buyButton, UiKit.BUTTON_COLORS.gray)
				else
					local nextLevel = trackData.levels[level + 2]
					UiKit.setButtonTitle(buyButton, FormatUtil.formatMoney(nextLevel.cost))
					UiKit.setButtonColor(buyButton, UiKit.BUTTON_COLORS.green)
				end
			end
		end
	end
end

local function buildIndexPanel(gui: ScreenGui)
	local panel = UiKit.panel(gui, "IndexPanel", UDim2.new(0.5, -280, 0.5, -230), UDim2.new(0, 560, 0, 460), nil)
	panel.Visible = false
	UiKit.makeLabel(panel, "Title", UDim2.new(0, 12, 0, 6), UDim2.new(0, 300, 0, 32), "STAR CHART", 22, UiKit.TEXT, true).TextXAlignment =
		Enum.TextXAlignment.Left
	closeButton(panel, function()
		PanelsController.hideIndex()
	end)
	-- The grid scrolls: 30 species in 5 columns need 6 rows, which is
	-- taller than the panel. The canvas is sized from the roster so a
	-- future species never overflows the panel again. Cells are 100x92:
	-- a wrapped 14 pt name (two lines), rate, rarity and an ON BASE tag.
	local grid = UiKit.makeScrollingFrame(panel, "Grid", UDim2.new(0, 12, 0, 46), UDim2.new(1, -24, 0, 296), UiKit.CREAM, 1)
	grid.BackgroundTransparency = 1
	local columns = 5
	local cellWidth = 100
	local cellHeight = 92
	local gap = 8
	local rows = math.ceil(#BrainrotData.SPECIES / columns)
	grid.CanvasSize = UDim2.new(0, 0, 0, rows * (cellHeight + gap))
	for i, species in BrainrotData.SPECIES do
		local col = (i - 1) % columns
		local rowIndex = math.floor((i - 1) / columns)
		local x = col * (cellWidth + gap)
		local y = rowIndex * (cellHeight + gap)
		local cell = UiKit.makeFrame(grid, `Cell{i}`, UDim2.new(0, x, 0, y), UDim2.new(0, cellWidth, 0, cellHeight), UiKit.CREAM_DARK, 0.1)
		local rarityColor = BrainrotData.RARITY_COLORS[species.rarity]
		UiKit.makeHeaderStrip(cell, rarityColor)
		UiKit.makeLabel(cell, "Name", UDim2.new(0, 4, 0, 4), UDim2.new(1, -8, 0, 34), species.name, 14, UiKit.TEXT, true)
		UiKit.makeLabel(cell, "Rate", UDim2.new(0, 4, 0, 40), UDim2.new(1, -8, 0, 18), FormatUtil.formatRate(species.rate), 14, UiKit.GOLD_DARK, true)
		UiKit.makeLabel(cell, "Rarity", UDim2.new(0, 4, 0, 58), UDim2.new(1, -8, 0, 16), string.upper(species.rarity), 13, UiKit.darken(rarityColor, 0.45), true)
		local onBase = UiKit.makeLabel(cell, "OnBase", UDim2.new(0, 4, 0, 74), UDim2.new(1, -8, 0, 16), "ON BASE", 13, UiKit.GREEN_DARK, true)
		onBase.Visible = false
		-- Tap a tile to read its flavor line (discovered species only).
		local tap = Instance.new("TextButton")
		tap.Name = "Tap"
		tap.Size = UDim2.new(1, 0, 1, 0)
		tap.BackgroundTransparency = 1
		tap.Text = ""
		tap.ZIndex = cell.ZIndex + 3
		tap.Parent = cell
		tap.MouseButton1Click:Connect(function()
			local state = ClientState.getState()
			local discovered = state and state.discovered :: { [string]: any }?
			if not flavorLabel then
				return
			end
			if discovered and discovered[species.name] == true then
				local line = BrainrotData.FLAVOR[species.name] or ""
				flavorLabel.Text = `{species.name}: {line}`
			else
				flavorLabel.Text = "??? - catch one to find out what it is!"
			end
		end)
	end
	-- Mutation legend with multipliers, then the flavor line.
	UiKit.makeLabel(
		panel,
		"Legend",
		UDim2.new(0, 12, 0, 348),
		UDim2.new(1, -24, 0, 28),
		"GOLD x2  -  DIAMOND x3  -  IRRADIATED x4  -  COSMIC x10",
		14,
		UiKit.TEXT,
		true
	)
	flavorLabel = UiKit.makeLabel(
		panel,
		"Flavor",
		UDim2.new(0, 12, 0, 380),
		UDim2.new(1, -24, 0, 64),
		"Tap a tile to read its story.",
		14,
		UiKit.MUTED,
		false
	)
	return panel
end

-- Re-renders the Star Chart grid: discovered species show their name,
-- rate and rarity plus an ON BASE tag when docked; undiscovered ones are
-- a ??? silhouette in dark grey.
local function refreshIndexPanel()
	local state = ClientState.getState()
	if not indexPanel or not state then
		return
	end
	local discovered = state.discovered :: { [string]: any }
	local dockedNames: { [string]: boolean } = {}
	for _, entry in state.roster :: { any } do
		dockedNames[entry.name] = true
	end
	local grid = indexPanel:FindFirstChild("Grid")
	if not grid then
		return
	end
	for i, species in BrainrotData.SPECIES do
		local cell = grid:FindFirstChild(`Cell{i}`)
		if cell then
			local nameLabel = cell:FindFirstChild("Name") :: TextLabel?
			local rateLabel = cell:FindFirstChild("Rate") :: TextLabel?
			local rarityLabel = cell:FindFirstChild("Rarity") :: TextLabel?
			local onBase = cell:FindFirstChild("OnBase") :: TextLabel?
			if discovered[species.name] == true then
				if nameLabel then
					nameLabel.Text = species.name
					nameLabel.TextColor3 = UiKit.TEXT
				end
				if rateLabel then
					rateLabel.Text = FormatUtil.formatRate(species.rate)
					rateLabel.TextColor3 = UiKit.GOLD_DARK
				end
				if rarityLabel then
					rarityLabel.Text = string.upper(species.rarity)
					rarityLabel.TextColor3 = UiKit.darken(BrainrotData.RARITY_COLORS[species.rarity], 0.45)
				end
				if onBase then
					onBase.Visible = dockedNames[species.name] == true
				end
				(cell :: Frame).BackgroundColor3 = UiKit.CREAM_DARK
			else
				if nameLabel then
					nameLabel.Text = "???"
					nameLabel.TextColor3 = UiKit.MUTED
				end
				if rateLabel then
					rateLabel.Text = "???"
					rateLabel.TextColor3 = UiKit.MUTED
				end
				if rarityLabel then
					rarityLabel.Text = "???"
					rarityLabel.TextColor3 = UiKit.MUTED
				end
				if onBase then
					onBase.Visible = false
				end
				(cell :: Frame).BackgroundColor3 = Color3.fromRGB(210, 200, 185)
			end
		end
	end
	local discoveredCount = 0
	for _, species in BrainrotData.SPECIES do
		if discovered[species.name] == true then
			discoveredCount += 1
		end
	end
	local title = indexPanel:FindFirstChild("Title") :: TextLabel?
	if title then
		title.Text = `STAR CHART  {discoveredCount}/{#BrainrotData.SPECIES}`
	end
end

local function buildQuestsPanel(gui: ScreenGui)
	local panel = UiKit.panel(gui, "QuestsPanel", UDim2.new(0, 12, 0.5, -190), UDim2.new(0, 380, 0, 380), nil)
	panel.Visible = false
	UiKit.makeLabel(panel, "Title", UDim2.new(0, 12, 0, 6), UDim2.new(0, 300, 0, 32), "QUESTS", 22, UiKit.TEXT, true).TextXAlignment =
		Enum.TextXAlignment.Left
	closeButton(panel, function()
		PanelsController.hideQuests()
	end)
	-- Scrolling list: 14 quests, one row each (56 px + 4 px gap).
	local list = UiKit.makeScrollingFrame(panel, "List", UDim2.new(0, 12, 0, 46), UDim2.new(1, -24, 0, 322), UiKit.CREAM, 1)
	list.BackgroundTransparency = 1
	list.CanvasSize = UDim2.new(0, 0, 0, #BrainrotData.QUESTS * 60)
	for i, quest in BrainrotData.QUESTS do
		local y = (i - 1) * 60
		local row = UiKit.makeFrame(list, `Quest{i}`, UDim2.new(0, 0, 0, y), UDim2.new(1, -6, 0, 56), UiKit.CREAM_DARK, 0.1)
		local textLabel = UiKit.makeLabel(row, "Text", UDim2.new(0, 10, 0, 4), UDim2.new(0, 240, 0, 28), quest.text, 14, UiKit.TEXT, true)
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		UiKit.fitText(textLabel, 14, 13)
		local progressLabel = UiKit.makeLabel(row, "Progress", UDim2.new(1, -84, 0, 4), UDim2.new(0, 74, 0, 26), "0/1", 15, UiKit.BLUE_DARK, true)
		progressLabel.TextXAlignment = Enum.TextXAlignment.Right
		local rewardLabel = UiKit.makeLabel(row, "Reward", UDim2.new(0, 10, 0, 32), UDim2.new(0, 240, 0, 20), `REWARD ${quest.reward}`, 14, UiKit.GOLD_DARK, true)
		rewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	end
	return panel
end

local function refreshQuestsPanel()
	local state = ClientState.getState()
	if not questsPanel or not state then
		return
	end
	local quests = state.quests :: { any }?
	local list = questsPanel:FindFirstChild("List")
	if not list or not quests then
		return
	end
	local doneCount = 0
	for i, questState in quests do
		local row = list:FindFirstChild(`Quest{i}`)
		if row then
			local progressLabel = row:FindFirstChild("Progress") :: TextLabel?
			local rewardLabel = row:FindFirstChild("Reward") :: TextLabel?
			if questState.done then
				doneCount += 1
				if progressLabel then
					progressLabel.Text = "DONE"
					progressLabel.TextColor3 = UiKit.GREEN_DARK
				end
				if rewardLabel then
					rewardLabel.Text = "REWARD CLAIMED"
					rewardLabel.TextColor3 = UiKit.GREEN_DARK
				end
				(row :: Frame).BackgroundColor3 = Color3.fromRGB(205, 245, 205)
			else
				if progressLabel then
					progressLabel.Text = `{math.floor(questState.progress)}/{questState.goal}`
					progressLabel.TextColor3 = UiKit.BLUE_DARK
				end
				if rewardLabel then
					rewardLabel.Text = `REWARD ${FormatUtil.formatMoney(questState.reward)}`
					rewardLabel.TextColor3 = UiKit.GOLD_DARK
				end
				(row :: Frame).BackgroundColor3 = UiKit.CREAM_DARK
			end
		end
	end
	local title = questsPanel:FindFirstChild("Title") :: TextLabel?
	if title then
		title.Text = `QUESTS  {doneCount}/{#BrainrotData.QUESTS}`
	end
end

local function buildRebirthDialog(gui: ScreenGui)
	local dialog = UiKit.panel(gui, "RebirthDialog", UDim2.new(0.5, -200, 0.5, -110), UDim2.new(0, 400, 0, 220), nil)
	dialog.Visible = false
	UiKit.makeLabel(dialog, "Title", UDim2.new(0, 12, 0, 8), UDim2.new(1, -24, 0, 32), "OPEN A NEW STATION RING?", 20, UiKit.TEXT, true)
	rebirthCostLabel = UiKit.makeLabel(dialog, "Cost", UDim2.new(0, 12, 0, 44), UDim2.new(1, -24, 0, 28), "Cost: $5,000", 17, UiKit.GOLD_DARK, true)
	UiKit.makeLabel(
		dialog,
		"Explain",
		UDim2.new(0, 16, 0, 76),
		UDim2.new(1, -32, 0, 70),
		"Credits reset to 0 and your docked brainrots return to the wild. Forever: +50% credits and +1 habitat pod.",
		15,
		UiKit.MUTED,
		false
	)
	local confirm = UiKit.button(dialog, "Confirm", UDim2.new(0, 24, 0, 158), UDim2.new(0, 160, 0, 44), UiKit.BUTTON_COLORS.purple, "REBIRTH!", nil)
	confirm.MouseButton1Click:Connect(function()
		local remote = Remotes.waitFor("Rebirth") :: RemoteEvent?
		if remote then
			remote:FireServer()
		end
		PanelsController.hideRebirthConfirm()
	end)
	local cancel = UiKit.button(dialog, "Cancel", UDim2.new(1, -184, 0, 158), UDim2.new(0, 160, 0, 44), UiKit.BUTTON_COLORS.gray, "NOT YET", nil)
	cancel.MouseButton1Click:Connect(function()
		PanelsController.hideRebirthConfirm()
	end)
	return dialog
end

function PanelsController.showUpgrades()
	refreshUpgradesPanel()
	if upgradesPanel then
		upgradesPanel.Visible = true
		UiKit.pop(upgradesPanel)
	end
end

function PanelsController.hideUpgrades()
	if upgradesPanel then
		upgradesPanel.Visible = false
	end
end

function PanelsController.toggleUpgrades()
	if upgradesPanel and upgradesPanel.Visible then
		PanelsController.hideUpgrades()
	else
		PanelsController.showUpgrades()
	end
end

function PanelsController.showIndex()
	refreshIndexPanel()
	if indexPanel then
		indexPanel.Visible = true
		UiKit.pop(indexPanel)
	end
end

function PanelsController.hideIndex()
	if indexPanel then
		indexPanel.Visible = false
	end
end

function PanelsController.toggleIndex()
	if indexPanel and indexPanel.Visible then
		PanelsController.hideIndex()
	else
		PanelsController.showIndex()
	end
end

function PanelsController.showQuests()
	refreshQuestsPanel()
	if questsPanel then
		questsPanel.Visible = true
		UiKit.pop(questsPanel)
	end
end

function PanelsController.hideQuests()
	if questsPanel then
		questsPanel.Visible = false
	end
end

function PanelsController.toggleQuests()
	if questsPanel and questsPanel.Visible then
		PanelsController.hideQuests()
	else
		PanelsController.showQuests()
	end
end

function PanelsController.showRebirthConfirm()
	local state = ClientState.getState()
	if rebirthCostLabel and state then
		rebirthCostLabel.Text = `Cost: {FormatUtil.formatMoney(state.rebirthCost or 5000)}  -  You have {FormatUtil.formatMoney(state.credits or 0)}`
	end
	if rebirthDialog then
		rebirthDialog.Visible = true
		UiKit.pop(rebirthDialog)
	end
end

function PanelsController.hideRebirthConfirm()
	if rebirthDialog then
		rebirthDialog.Visible = false
	end
end

-- Tour helper: opens the Star Chart and Upgrades panels side by side for
-- the dossier's fourth screenshot (shot at 1280x720).
function PanelsController.openPanelsForTour()
	if upgradesPanel then
		upgradesPanel.Position = UDim2.new(0, 12, 0.5, -190)
		upgradesPanel.Visible = true
	end
	if indexPanel then
		indexPanel.Position = UDim2.new(1, -572, 0.5, -230)
		indexPanel.Visible = true
	end
	refreshUpgradesPanel()
	refreshIndexPanel()
end

-- Tour helpers: one panel at a time, centered (Star Chart) or left
-- (Quests), for the dedicated panel screenshots.
function PanelsController.openIndexForTour()
	if indexPanel then
		indexPanel.Position = UDim2.new(0.5, -280, 0.5, -230)
		indexPanel.Visible = true
	end
	refreshIndexPanel()
end

function PanelsController.openQuestsForTour()
	if questsPanel then
		questsPanel.Position = UDim2.new(0, 12, 0.5, -190)
		questsPanel.Visible = true
	end
	refreshQuestsPanel()
end

function PanelsController.init()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "PanelsGui"
	gui.DisplayOrder = 8
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	upgradesPanel = buildUpgradesPanel(gui)
	indexPanel = buildIndexPanel(gui)
	questsPanel = buildQuestsPanel(gui)
	rebirthDialog = buildRebirthDialog(gui)
	ClientState.getStateChangedSignal():Connect(function(_state: any)
		if upgradesPanel and upgradesPanel.Visible then
			refreshUpgradesPanel()
		end
		if indexPanel and indexPanel.Visible then
			refreshIndexPanel()
		end
		if questsPanel and questsPanel.Visible then
			refreshQuestsPanel()
		end
	end)
end

return PanelsController
