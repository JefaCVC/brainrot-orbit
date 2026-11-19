--!strict
-- PanelsController
-- The three pop-up panels of BRAINROT ORBIT, restyled round 5 on the
-- cartoon UiKit: Upgrades (the four named, levelled tracks with candy buy
-- buttons), the Brainrot Index (all 30 species in a scrollable grid,
-- undiscovered ones as ??? silhouettes) and the Rebirth confirmation
-- dialog. Panels open over the HUD, pause nothing, and close with their X
-- button, the same button that opened them, or the tour's openPanels
-- command (which opens Index + Upgrades together for the dossier shot).

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
local rebirthDialog: Frame? = nil
local rebirthCostLabel: TextLabel? = nil

local TRACK_ORDER = { "Beam", "Cargo", "Shield", "Expansion" } :: { string }
local TRACK_COLORS: { [string]: any } = {
	Beam = UiKit.COLORS.cyan,
	Cargo = UiKit.COLORS.green,
	Shield = UiKit.COLORS.blue,
	Expansion = UiKit.COLORS.purple,
}

local function closeButton(parent: Frame, onClose: () -> ())
	local button = UiKit.button(parent, "Close", UDim2.new(1, -40, 0, 6), UDim2.new(0, 32, 0, 32), UiKit.COLORS.red, "X", nil)
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
		UiKit.makeLabel(row, "Name", UDim2.new(0, 18, 0, 4), UDim2.new(0, 220, 0, 26), trackData.displayName, 18, UiKit.TEXT, true).TextXAlignment =
			Enum.TextXAlignment.Left
		local blurb = UiKit.makeLabel(row, "Blurb", UDim2.new(0, 18, 0, 30), UDim2.new(0, 220, 0, 36), trackData.blurb, 13, UiKit.MUTED, false)
		blurb.TextXAlignment = Enum.TextXAlignment.Left
		-- The level label is 150 px wide and fitted down to 11 pt, so even
		-- the longest level name ("Lv 2 — Triple Bubble") fits on one line.
		local levelLabel = UiKit.makeLabel(row, "Level", UDim2.new(0, 240, 0, 4), UDim2.new(0, 150, 0, 26), "Lv 0", 15, UiKit.ACCENT, true)
		levelLabel.Name = "Level"
		local buyButton = UiKit.button(row, "Buy", UDim2.new(1, -120, 0, 14), UDim2.new(0, 108, 0, 44), UiKit.COLORS.green, "$500", nil)
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
			local buyButton = row:FindFirstChild("Buy") :: TextButton?
			if levelLabel then
				local levelName = trackData.levels[level + 1].name
				levelLabel.Text = `Lv {level} — {levelName}`
				UiKit.fitText(levelLabel, 15, 11)
			end
			if buyButton then
				if level >= #trackData.levels - 1 then
					UiKit.setButtonTitle(buyButton, "MAX")
					UiKit.setButtonColor(buyButton, Color3.fromRGB(140, 140, 150))
				else
					local nextLevel = trackData.levels[level + 2]
					UiKit.setButtonTitle(buyButton, FormatUtil.formatMoney(nextLevel.cost))
					UiKit.setButtonColor(buyButton, UiKit.COLORS.green)
				end
			end
		end
	end
end

local function buildIndexPanel(gui: ScreenGui)
	local panel = UiKit.panel(gui, "IndexPanel", UDim2.new(0.5, -260, 0.5, -190), UDim2.new(0, 520, 0, 380), nil)
	panel.Visible = false
	UiKit.makeLabel(panel, "Title", UDim2.new(0, 12, 0, 6), UDim2.new(0, 300, 0, 32), "BRAINROT INDEX", 22, UiKit.TEXT, true).TextXAlignment =
		Enum.TextXAlignment.Left
	closeButton(panel, function()
		PanelsController.hideIndex()
	end)
	-- The grid scrolls: 30 species in 5 columns need 6 rows, which is
	-- taller than the panel. The canvas is sized from the roster so a
	-- future species never overflows the panel again.
	local grid = UiKit.makeScrollingFrame(panel, "Grid", UDim2.new(0, 12, 0, 46), UDim2.new(1, -24, 0, 322), UiKit.CREAM, 1)
	grid.BackgroundTransparency = 1
	local columns = 5
	local cellWidth = 94
	local cellHeight = 76
	local rows = math.ceil(#BrainrotData.SPECIES / columns)
	grid.CanvasSize = UDim2.new(0, 0, 0, rows * (cellHeight + 4))
	for i, species in BrainrotData.SPECIES do
		local col = (i - 1) % columns
		local rowIndex = math.floor((i - 1) / columns)
		local x = col * (cellWidth + 4)
		local y = rowIndex * (cellHeight + 4)
		local cell = UiKit.makeFrame(grid, `Cell{i}`, UDim2.new(0, x, 0, y), UDim2.new(0, cellWidth, 0, cellHeight), UiKit.CREAM_DARK, 0.1)
		local rarityColor = BrainrotData.RARITY_COLORS[species.rarity]
		UiKit.makeHeaderStrip(cell, rarityColor)
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
		title.Text = `BRAINROT INDEX  {discoveredCount}/{#BrainrotData.SPECIES}`
	end
end

local function buildRebirthDialog(gui: ScreenGui)
	local dialog = UiKit.panel(gui, "RebirthDialog", UDim2.new(0.5, -200, 0.5, -110), UDim2.new(0, 400, 0, 220), nil)
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
	local confirm = UiKit.button(dialog, "Confirm", UDim2.new(0, 24, 0, 158), UDim2.new(0, 160, 0, 44), UiKit.COLORS.purple, "REBIRTH!", nil)
	confirm.MouseButton1Click:Connect(function()
		local remote = Remotes.waitFor("Rebirth") :: RemoteEvent?
		if remote then
			remote:FireServer()
		end
		PanelsController.hideRebirthConfirm()
	end)
	local cancel = UiKit.button(dialog, "Cancel", UDim2.new(1, -184, 0, 158), UDim2.new(0, 160, 0, 44), Color3.fromRGB(140, 140, 150), "NOT YET", nil)
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

function PanelsController.showRebirthConfirm()
	local state = ClientState.getState()
	if rebirthCostLabel and state then
		rebirthCostLabel.Text = `Cost: {FormatUtil.formatMoney(state.rebirthCost or 5000)}  •  You have {FormatUtil.formatMoney(state.credits or 0)}`
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
