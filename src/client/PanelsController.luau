--!strict
-- PanelsController
-- The three pop-up panels of BRAINROT ORBIT: Upgrades (the four named,
-- levelled tracks with prices), the Brainrot Index (all 19 species in a
-- grid, undiscovered ones as ??? silhouettes) and the Rebirth confirmation
-- dialog. Panels open over the HUD, pause nothing, and close with their
-- X button, the same button that opened them, or the tour's openPanels
-- command (which opens Index + Upgrades together for the dossier shot).

-- Engine types used in annotations below (the values come from Roblox at runtime).
type ScreenGui = any
type Instance = any
type TextLabel = any
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
local rebirthDialog: Frame? = nil
local rebirthCostLabel: TextLabel? = nil

local TRACK_ORDER = { "Beam", "Cargo", "Shield", "Expansion" } :: { string }

local function closeButton(parent: Frame, onClose: () -> ())
	local button = UiKit.makeButton(parent, "Close", UDim2.new(1, -38, 0, 6), UDim2.new(0, 30, 0, 30), "X", 18, Color3.fromRGB(160, 60, 60))
	button.MouseButton1Click:Connect(onClose)
	return button
end

local function buildUpgradesPanel(gui: ScreenGui)
	local panel = UiKit.makeFrame(gui, "UpgradesPanel", UDim2.new(0.5, -260, 0.5, -190), UDim2.new(0, 520, 0, 380), UiKit.PANEL_BG, 0.05)
	panel.Visible = false
	UiKit.makeLabel(panel, "Title", UDim2.new(0, 12, 0, 6), UDim2.new(0, 300, 0, 32), "UPGRADES", 22, UiKit.TEXT, true)
	closeButton(panel, function()
		PanelsController.hideUpgrades()
	end)
	for i, track in TRACK_ORDER do
		local trackData = BrainrotData.UPGRADES[track]
		local y = 48 + (i - 1) * 80
		local row = UiKit.makeFrame(panel, `{track}Row`, UDim2.new(0, 12, 0, y), UDim2.new(1, -24, 0, 72), Color3.fromRGB(26, 38, 60), 0.1)
		UiKit.makeLabel(row, "Name", UDim2.new(0, 10, 0, 4), UDim2.new(0, 260, 0, 26), trackData.displayName, 18, UiKit.TEXT, true).TextXAlignment =
			Enum.TextXAlignment.Left
		local blurb = UiKit.makeLabel(row, "Blurb", UDim2.new(0, 10, 0, 30), UDim2.new(0, 260, 0, 36), trackData.blurb, 13, UiKit.MUTED, false)
		blurb.TextXAlignment = Enum.TextXAlignment.Left
		local levelLabel = UiKit.makeLabel(row, "Level", UDim2.new(0, 280, 0, 4), UDim2.new(0, 110, 0, 26), "Lv 0", 15, UiKit.ACCENT, true)
		levelLabel.Name = "Level"
		local buyButton = UiKit.makeButton(row, "Buy", UDim2.new(1, -120, 0, 14), UDim2.new(0, 108, 0, 44), "$500", 16, Color3.fromRGB(40, 130, 70))
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
			local levelLabel = row:FindFirstChild("Level") :: TextLabel?
			local buyButton = row:FindFirstChild("Buy") :: any
			if levelLabel then
				local levelName = trackData.levels[level + 1].name
				levelLabel.Text = `Lv {level} — {levelName}`
			end
			if buyButton then
				if level >= #trackData.levels - 1 then
					buyButton.Text = "MAX"
					buyButton.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
				else
					local nextLevel = trackData.levels[level + 2]
					buyButton.Text = `{FormatUtil.formatMoney(nextLevel.cost)}`
					buyButton.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
				end
			end
		end
	end
end

local function buildIndexPanel(gui: ScreenGui)
	local panel = UiKit.makeFrame(gui, "IndexPanel", UDim2.new(0.5, -260, 0.5, -190), UDim2.new(0, 520, 0, 380), UiKit.PANEL_BG, 0.05)
	panel.Visible = false
	UiKit.makeLabel(panel, "Title", UDim2.new(0, 12, 0, 6), UDim2.new(0, 300, 0, 32), "BRAINROT INDEX", 22, UiKit.TEXT, true)
	closeButton(panel, function()
		PanelsController.hideIndex()
	end)
	local grid = UiKit.makeFrame(panel, "Grid", UDim2.new(0, 12, 0, 46), UDim2.new(1, -24, 0, 322), UiKit.PANEL_BG, 1)
	grid.BackgroundTransparency = 1
	local columns = 5
	local cellWidth = 94
	local cellHeight = 76
	for i, species in BrainrotData.SPECIES do
		local col = (i - 1) % columns
		local rowIndex = math.floor((i - 1) / columns)
		local x = col * (cellWidth + 4)
		local y = rowIndex * (cellHeight + 4)
		local cell = UiKit.makeFrame(grid, `Cell{i}`, UDim2.new(0, x, 0, y), UDim2.new(0, cellWidth, 0, cellHeight), Color3.fromRGB(26, 38, 60), 0.1)
		local rarityColor = BrainrotData.RARITY_COLORS[species.rarity]
		UiKit.makeLabel(cell, "Name", UDim2.new(0, 4, 0, 4), UDim2.new(1, -8, 0, 30), species.name, 12, UiKit.TEXT, true)
		UiKit.makeLabel(cell, "Rate", UDim2.new(0, 4, 0, 34), UDim2.new(1, -8, 0, 18), FormatUtil.formatRate(species.rate), 12, UiKit.GOLD, true)
		UiKit.makeLabel(cell, "Rarity", UDim2.new(0, 4, 0, 52), UDim2.new(1, -8, 0, 18), string.upper(species.rarity), 11, rarityColor, true)
	end
	return panel
end

-- Re-renders the index grid: discovered species show their name and rate,
-- undiscovered ones are a ??? silhouette in dark grey.
local function refreshIndexPanel()
	local state = ClientState.getState()
	if not indexPanel or not state then
		return
	end
	local discovered = state.discovered :: { [string]: any }
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
			if discovered[species.name] == true then
				if nameLabel then
					nameLabel.Text = species.name
					nameLabel.TextColor3 = UiKit.TEXT
				end
				if rateLabel then
					rateLabel.Text = FormatUtil.formatRate(species.rate)
					rateLabel.TextColor3 = UiKit.GOLD
				end
				if rarityLabel then
					rarityLabel.Text = string.upper(species.rarity)
					rarityLabel.TextColor3 = BrainrotData.RARITY_COLORS[species.rarity]
				end
				(cell :: Frame).BackgroundColor3 = Color3.fromRGB(26, 38, 60)
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
				(cell :: Frame).BackgroundColor3 = Color3.fromRGB(20, 26, 36)
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
		title.Text = `BRAINROT INDEX  {discoveredCount}/19`
	end
end

local function buildRebirthDialog(gui: ScreenGui)
	local dialog = UiKit.makeFrame(gui, "RebirthDialog", UDim2.new(0.5, -200, 0.5, -110), UDim2.new(0, 400, 0, 220), UiKit.PANEL_BG, 0.02)
	dialog.Visible = false
	UiKit.makeLabel(dialog, "Title", UDim2.new(0, 12, 0, 8), UDim2.new(1, -24, 0, 32), "OPEN A NEW STATION RING?", 20, UiKit.TEXT, true)
	rebirthCostLabel = UiKit.makeLabel(dialog, "Cost", UDim2.new(0, 12, 0, 44), UDim2.new(1, -24, 0, 28), "Cost: $5,000", 17, UiKit.GOLD, true)
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
	local confirm = UiKit.makeButton(dialog, "Confirm", UDim2.new(0, 24, 0, 158), UDim2.new(0, 160, 0, 44), "REBIRTH!", 18, Color3.fromRGB(150, 80, 200))
	confirm.MouseButton1Click:Connect(function()
		local remote = Remotes.waitFor("Rebirth") :: RemoteEvent?
		if remote then
			remote:FireServer()
		end
		PanelsController.hideRebirthConfirm()
	end)
	local cancel = UiKit.makeButton(dialog, "Cancel", UDim2.new(1, -184, 0, 158), UDim2.new(0, 160, 0, 44), "NOT YET", 18, UiKit.BUTTON_BG)
	cancel.MouseButton1Click:Connect(function()
		PanelsController.hideRebirthConfirm()
	end)
	return dialog
end

function PanelsController.showUpgrades()
	refreshUpgradesPanel()
	if upgradesPanel then
		upgradesPanel.Visible = true
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

function PanelsController.showRebirthConfirm()
	local state = ClientState.getState()
	if rebirthCostLabel and state then
		rebirthCostLabel.Text = `Cost: {FormatUtil.formatMoney(state.rebirthCost or 5000)}  •  You have {FormatUtil.formatMoney(state.credits or 0)}`
	end
	if rebirthDialog then
		rebirthDialog.Visible = true
	end
end

function PanelsController.hideRebirthConfirm()
	if rebirthDialog then
		rebirthDialog.Visible = false
	end
end

-- Tour helper: opens the Index and Upgrades panels side by side for the
-- dossier's fourth screenshot.
function PanelsController.openPanelsForTour()
	if upgradesPanel then
		upgradesPanel.Position = UDim2.new(0, 12, 0.5, -190)
		upgradesPanel.Visible = true
	end
	if indexPanel then
		indexPanel.Position = UDim2.new(1, -532, 0.5, -190)
		indexPanel.Visible = true
	end
	refreshUpgradesPanel()
	refreshIndexPanel()
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
	rebirthDialog = buildRebirthDialog(gui)
	ClientState.getStateChangedSignal():Connect(function(_state: any)
		if upgradesPanel and upgradesPanel.Visible then
			refreshUpgradesPanel()
		end
		if indexPanel and indexPanel.Visible then
			refreshIndexPanel()
		end
	end)
end

return PanelsController
