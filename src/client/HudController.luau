--!strict
-- HudController
-- The in-game HUD for BRAINROT ORBIT, restyled round 5 on the cartoon
-- UiKit and rebuilt round 7 from the top-10 audit: a feature-count strip
-- across the top, a big storm countdown panel with a progress bar, the
-- mission strip, the event banner, a Golden Hour panel, the MY MODULE
-- roster, a left-side station feed, a bottom row of six candy action
-- buttons (LOCK / ZAP / REBIRTH / UPGRADES / QUESTS / STAR CHART), a
-- bottom-center carry banner tinted by the carried brainrot's rarity,
-- cream toast cards with colored stripes, a zone banner that announces
-- each area, and a mute button for sound effects.
--
-- Layout rules: nothing sits in the TOP-LEFT corner (Roblox's own menu
-- buttons live there), no text ever overflows its box (fixed-size candy
-- titles fitted by UiKit, fitText/truncate for dynamic labels, nothing
-- below 13 pt), and the whole HUD scales with viewport height via UIScale
-- (clamp(viewportY/760, 0.55, 1.4)). Top stack and bottom row were checked
-- by coordinate math at 1024x768 and 1280x720 (see the round 7 report).

-- Engine types used in annotations below (the values come from Roblox at runtime).
type ScreenGui = any
type Instance = any
type TextLabel = any
type TextButton = any
type Frame = any
type RemoteEvent = any
type Vector3 = any
type Color3 = any

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local requireModule = require :: any
local BeamEffects = requireModule(script.Parent:WaitForChild("BeamEffects"))
local BrainrotData = requireModule(ReplicatedStorage:WaitForChild("BrainrotData"))
local ClientState = requireModule(script.Parent:WaitForChild("ClientState"))
local FormatUtil = requireModule(ReplicatedStorage:WaitForChild("FormatUtil"))
local PanelsController = requireModule(script.Parent:WaitForChild("PanelsController"))
local Remotes = requireModule(ReplicatedStorage:WaitForChild("Remotes"))
local TitleController = requireModule(script.Parent:WaitForChild("TitleController"))
local UiKit = requireModule(script.Parent:WaitForChild("UiKit"))

local HudController = {}

local player = Players.LocalPlayer

local hudGui: ScreenGui? = nil
local hudScale: Instance? = nil
local creditsLabel: TextLabel? = nil
local rateLabel: TextLabel? = nil
local rebirthLabel: TextLabel? = nil
local podsLabel: TextLabel? = nil
local missionLabel: TextLabel? = nil
local stormPanel: Frame? = nil
local stormLabel: TextLabel? = nil
local stormBarFill: Frame? = nil
local goldenPanel: Frame? = nil
local goldenLabel: TextLabel? = nil
local bannerFrame: Frame? = nil
local bannerLabel: TextLabel? = nil
local rosterFrame: Frame? = nil
local rosterHeader: TextLabel? = nil
local rosterRows: Frame? = nil
local rosterStrip: Frame? = nil
local lockButton: TextButton? = nil
local zapButton: TextButton? = nil
local rebirthButton: TextButton? = nil
local upgradesButton: TextButton? = nil
local questsButton: TextButton? = nil
local indexButton: TextButton? = nil
local carryFrame: Frame? = nil
local carryLabel: TextLabel? = nil
local promptLabel: TextLabel? = nil
local toastContainer: Frame? = nil
local feedRows: { TextLabel } = {}
local feedLines: { string } = {}
local zoneFrame: Frame? = nil
local zoneLabel: TextLabel? = nil
local muteButton: TextButton? = nil
local bannerHideAt = 0
local zoneHideAt = 0
local currentZone = ""

-- The eight module accent colors (mirrors the server's WorldBuilder
-- table): the MY MODULE panel's header strip takes the player's own
-- module color so the panel reads as theirs at a glance, and the zone
-- banner uses it inside a module.
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

-- Module centers (radius 95, angles 22.5 + 45k) for the zone banner.
local function getModuleCenter(index: number): Vector3
	local angle = math.rad(22.5 + (index - 1) * 45)
	return Vector3.new(math.cos(angle) * 95, 0, math.sin(angle) * 95)
end

-- Relative luminance, for picking banner text color: dark text on light
-- banners (gold, pale green), white text on dark ones (red).
local function bgLuminance(color: Color3): number
	local function channel(c: number): number
		if c <= 0.03928 then
			return c / 12.92
		end
		return ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
end

local function buildHud(playerGui: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "HudGui"
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local scale = Instance.new("UIScale")
	scale.Name = "HudScale"
	scale.Parent = gui
	hudScale = scale

	-- Feature strip: the game's whole feature list in one line, top
	-- center, dark navy with white text (13.2:1). Real numbers only.
	local featureStrip = UiKit.panel(gui, "FeatureStrip", UDim2.new(0.5, -280, 0, 8), UDim2.new(0, 560, 0, 28), Color3.fromRGB(36, 48, 70))
	UiKit.makeLabel(
		featureStrip,
		"Features",
		UDim2.new(0, 8, 0, 0),
		UDim2.new(1, -16, 1, 0),
		"30 BRAINROTS - 6 RARITIES - 4 MUTATIONS - STEAL - LOCK - REBIRTH",
		14,
		UiKit.WHITE,
		true
	)

	-- Cash card: left-middle, clear of the top-left Roblox menu buttons.
	-- Cream panel with a gold header strip: big credits, income rate,
	-- rebirth ring + multiplier, and pod count. Colored text uses the
	-- dark variants (4.8-6.0:1 on cream).
	local cashCard = UiKit.panel(gui, "CashCard", UDim2.new(0, 12, 0.5, -92), UDim2.new(0, 300, 0, 184), nil)
	UiKit.makeHeaderStrip(cashCard, UiKit.GOLD)
	UiKit.makeLabel(cashCard, "CreditsCaption", UDim2.new(0, 12, 0, 8), UDim2.new(0, 120, 0, 20), "CREDITS", 15, UiKit.ORANGE_DARK, true).TextXAlignment =
		Enum.TextXAlignment.Left
	creditsLabel = UiKit.makeLabel(cashCard, "Credits", UDim2.new(0, 12, 0, 28), UDim2.new(1, -24, 0, 42), "$0", 30, UiKit.GOLD_DARK, true)
	creditsLabel.TextXAlignment = Enum.TextXAlignment.Left
	rateLabel = UiKit.makeLabel(cashCard, "Rate", UDim2.new(0, 12, 0, 74), UDim2.new(1, -24, 0, 28), "$0/s  (x1)", 19, UiKit.GREEN_DARK, true)
	rateLabel.TextXAlignment = Enum.TextXAlignment.Left
	rebirthLabel = UiKit.makeLabel(cashCard, "Rebirths", UDim2.new(0, 12, 0, 106), UDim2.new(0, 168, 0, 28), "RING 0 - x1", 19, UiKit.PURPLE_DARK, true)
	rebirthLabel.TextXAlignment = Enum.TextXAlignment.Left
	podsLabel = UiKit.makeLabel(cashCard, "Pods", UDim2.new(0, 184, 0, 106), UDim2.new(1, -196, 0, 28), "PODS 0/4", 19, UiKit.TEXT, true)
	podsLabel.TextXAlignment = Enum.TextXAlignment.Left
	UiKit.makeLabel(
		cashCard,
		"Hint",
		UDim2.new(0, 12, 0, 140),
		UDim2.new(1, -24, 0, 32),
		"Dock brainrots to earn every second!",
		14,
		UiKit.MUTED,
		false
	).TextXAlignment = Enum.TextXAlignment.Left

	-- Storm countdown: top-center panel with a gold progress bar, BIG
	-- (round 7: the hazard event is the top banner, with a live
	-- countdown in every phase). Calm color is a dark lava red so the
	-- white 20 pt text passes 4.2:1; warning/active go storm red.
	stormPanel = UiKit.panel(gui, "StormPanel", UDim2.new(0.5, -280, 0, 44), UDim2.new(0, 560, 0, 84), Color3.fromRGB(220, 70, 30))
	stormLabel = UiKit.makeLabel(stormPanel, "Storm", UDim2.new(0, 8, 0, 6), UDim2.new(1, -16, 0, 40), "NEXT SOLAR STORM IN 1:00", 20, UiKit.WHITE, true)
	local barBg = UiKit.makeFrame(stormPanel, "BarBg", UDim2.new(0, 16, 0, 56), UDim2.new(1, -32, 0, 14), Color3.fromRGB(60, 30, 20), 0)
	stormBarFill = UiKit.makeFrame(barBg, "BarFill", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0), UiKit.GOLD, 0)

	-- Mission strip: the next goal is always visible, 8 px below the
	-- countdown panel so the stack breathes.
	local missionStrip = UiKit.panel(gui, "MissionStrip", UDim2.new(0.5, -280, 0, 136), UDim2.new(0, 560, 0, 32), nil)
	UiKit.makeHeaderStrip(missionStrip, UiKit.ACCENT)
	missionLabel = UiKit.makeLabel(missionStrip, "Mission", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 1, 0), "MISSION 1/4: Catch a brainrot (E)  [0/1]  +$100", 15, UiKit.TEXT, true)

	-- Event banner: transient announcements (storms, ZORK, meteors).
	bannerFrame = UiKit.panel(gui, "EventBanner", UDim2.new(0.5, -280, 0, 176), UDim2.new(0, 560, 0, 40), UiKit.GOLD)
	bannerFrame.Visible = false
	bannerLabel = UiKit.makeLabel(bannerFrame, "BannerText", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 1, 0), "", 17, UiKit.WHITE, true)

	-- Golden Hour panel: gold with dark text (11:1), visible only while
	-- the bonus window runs, with its own live countdown.
	goldenPanel = UiKit.panel(gui, "GoldenPanel", UDim2.new(0.5, -280, 0, 224), UDim2.new(0, 560, 0, 36), UiKit.GOLD)
	goldenPanel.Visible = false
	goldenLabel = UiKit.makeLabel(goldenPanel, "GoldenText", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 1, 0), "", 16, UiKit.TEXT, true)

	-- Roster panel: MY MODULE (n/n) on the right side, below the top
	-- stack so it never overlaps the storm panel. Its header strip
	-- takes the player's module accent color once state arrives.
	rosterFrame = UiKit.panel(gui, "Roster", UDim2.new(1, -262, 0, 140), UDim2.new(0, 250, 0, 34), nil)
	rosterStrip = UiKit.makeHeaderStrip(rosterFrame, UiKit.ACCENT)
	rosterHeader = UiKit.makeLabel(rosterFrame, "Header", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 0, 30), "MY MODULE (0/4)", 16, UiKit.TEXT, true)
	rosterHeader.TextXAlignment = Enum.TextXAlignment.Left
	rosterRows = UiKit.makeFrame(rosterFrame, "Rows", UDim2.new(0, 0, 0, 30), UDim2.new(1, 0, 0, 0), UiKit.CREAM, 1)
	rosterRows.BackgroundTransparency = 1

	-- Action buttons: bottom-right candy row, six buttons, 140x64 with
	-- an 8 px gap (total 880 px). Each shows live state in its sub-line:
	-- lock state, ZORK presence, rebirth cost + next multiplier, upgrades
	-- bought, quests done, Star Chart found count.
	local actions = {
		{ name = "LockButton", title = "LOCK", sub = "Airlock (L)", color = UiKit.BUTTON_COLORS.red },
		{ name = "ZapButton", title = "ZAP", sub = "Zap ZORK (F)", color = UiKit.BUTTON_COLORS.orange },
		{ name = "RebirthButton", title = "REBIRTH", sub = "$5K - x1.5 next", color = UiKit.BUTTON_COLORS.purple },
		{ name = "UpgradesButton", title = "UPGRADES", sub = "0/8 bought", color = UiKit.BUTTON_COLORS.blue },
		{ name = "QuestsButton", title = "QUESTS", sub = "0/14 done", color = UiKit.BUTTON_COLORS.cyan },
		{ name = "IndexButton", title = "STAR CHART", sub = "0/30 found", color = UiKit.BUTTON_COLORS.green },
	} :: { { name: string, title: string, sub: string, color: any } }
	for i, action in actions do
		local x = -892 + (i - 1) * 148
		local button = UiKit.button(
			gui,
			action.name,
			UDim2.new(1, x, 1, -76),
			UDim2.new(0, 140, 0, 64),
			action.color,
			action.title,
			action.sub,
			20,
			13
		)
		if action.name == "LockButton" then
			lockButton = button
			button.MouseButton1Click:Connect(function()
				local remote = Remotes.waitFor("LockModule") :: RemoteEvent?
				if remote then
					remote:FireServer()
				end
			end)
		elseif action.name == "ZapButton" then
			zapButton = button
			button.MouseButton1Click:Connect(function()
				local remote = Remotes.waitFor("BonkZork") :: RemoteEvent?
				if remote then
					remote:FireServer()
				end
			end)
		elseif action.name == "RebirthButton" then
			rebirthButton = button
			button.MouseButton1Click:Connect(function()
				PanelsController.showRebirthConfirm()
			end)
		elseif action.name == "UpgradesButton" then
			upgradesButton = button
			button.MouseButton1Click:Connect(function()
				PanelsController.toggleUpgrades()
			end)
		elseif action.name == "QuestsButton" then
			questsButton = button
			button.MouseButton1Click:Connect(function()
				PanelsController.toggleQuests()
			end)
		elseif action.name == "IndexButton" then
			indexButton = button
			button.MouseButton1Click:Connect(function()
				PanelsController.toggleIndex()
			end)
		end
	end

	-- Carry banner: bottom-center, tinted by the carried brainrot's rarity.
	carryFrame = UiKit.panel(gui, "CarryBanner", UDim2.new(0.5, -320, 1, -132), UDim2.new(0, 640, 0, 56), nil)
	carryLabel = UiKit.makeLabel(carryFrame, "CarryText", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 1, 0), "CARGO (0/1) - catch a brainrot!", 16, UiKit.MUTED, true)

	-- Context prompt: what [E] does right now, above the carry banner.
	-- Bright gold on the 3D world (no panel behind it), thin dark stroke.
	promptLabel = UiKit.makeLabel(gui, "Prompt", UDim2.new(0.5, -280, 1, -164), UDim2.new(0, 560, 0, 26), "", 16, UiKit.GOLD, true)
	promptLabel.Visible = false

	-- Help line: below the cash card, left-aligned with it. It used to sit
	-- bottom-center (y 1,-34), where it overlapped the bottom-right action
	-- buttons on narrow viewports. Here it never overlaps anything: the
	-- cash card ends 8 px above it, the feed starts 4 px below it, and the
	-- carry banner and the action row sit below it.
	local helpLabel = UiKit.makeLabel(
		gui,
		"Help",
		UDim2.new(0, 12, 0.5, 100),
		UDim2.new(0, 560, 0, 24),
		"E catch / dock / steal  -  L lock  -  F zap ZORK  -  Q drop cargo",
		14,
		UiKit.WHITE,
		false
	)
	helpLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Station feed: the last 3 events on the left, under the help line.
	-- Every toast lands here too, so the game reads as alive in a still
	-- image ("QUEST DONE ...", "Module locked for 30s!", "ZAPPED ...").
	local feedPanel = UiKit.panel(gui, "Feed", UDim2.new(0, 12, 0.5, 128), UDim2.new(0, 360, 0, 96), nil)
	UiKit.makeLabel(feedPanel, "FeedTitle", UDim2.new(0, 10, 0, 2), UDim2.new(0, 160, 0, 20), "STATION FEED", 14, UiKit.ORANGE_DARK, true).TextXAlignment =
		Enum.TextXAlignment.Left
	for i = 1, 3 do
		local row = UiKit.makeLabel(feedPanel, `FeedRow{i}`, UDim2.new(0, 10, 0, 22 + (i - 1) * 24), UDim2.new(1, -20, 0, 24), "", 14, UiKit.TEXT, false)
		row.TextXAlignment = Enum.TextXAlignment.Left
		feedRows[i] = row
	end

	-- Toast stack: right side, below the roster (the roster can grow to
	-- 8 rows, ending near y=382 — the toasts start at y=400).
	toastContainer = UiKit.makeFrame(gui, "Toasts", UDim2.new(1, -412, 0, 400), UDim2.new(0, 400, 0, 280), UiKit.CREAM, 1)
	toastContainer.BackgroundTransparency = 1

	-- Zone banner: center screen, fades in/out when the player enters a
	-- new area. Hidden until the first zone change after the title.
	zoneFrame = UiKit.panel(gui, "ZoneBanner", UDim2.new(0.5, -250, 0.3, 0), UDim2.new(0, 500, 0, 64), UiKit.COLORS.cyan)
	zoneFrame.Visible = false
	zoneLabel = UiKit.makeLabel(zoneFrame, "ZoneText", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 1, 0), "", 24, UiKit.WHITE, true)

	-- Mute button: bottom-left, toggles sound effects (there is no music
	-- track in this build — no licensed asset id lives in the repo).
	muteButton = UiKit.button(gui, "MuteButton", UDim2.new(0, 12, 1, -76), UDim2.new(0, 64, 0, 64), UiKit.BUTTON_COLORS.blue, "♪", "SFX", 28, 13)
	muteButton.MouseButton1Click:Connect(function()
		local muted = BeamEffects.setMuted(not BeamEffects.isMuted())
		if muteButton then
			if muted then
				UiKit.setButtonColor(muteButton, UiKit.BUTTON_COLORS.gray)
				UiKit.setButtonSubtitle(muteButton, "MUTED")
			else
				UiKit.setButtonColor(muteButton, UiKit.BUTTON_COLORS.blue)
				UiKit.setButtonSubtitle(muteButton, "SFX")
			end
		end
	end)

	gui.Parent = playerGui
	return gui
end

-- Adds one line to the station feed (newest last, max 3 kept).
local function addFeedLine(text: string)
	local line: string = UiKit.truncate(text, 42)
	table.insert(feedLines, line)
	while #feedLines > 3 do
		table.remove(feedLines, 1)
	end
	for i = 1, 3 do
		local row = feedRows[i]
		if row then
			row.Text = feedLines[i] or ""
		end
	end
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
		local row = UiKit.makeFrame(rosterRows, `Row{i}`, UDim2.new(0, 0, 0, y), UDim2.new(1, 0, 0, rowHeight), UiKit.CREAM, 1)
		row.BackgroundTransparency = 1
		local rarityColor = BrainrotData.RARITY_COLORS[entry.rarity] or UiKit.TEXT
		local dot = UiKit.makeFrame(row, "Dot", UDim2.new(0, 8, 0, 8), UDim2.new(0, 10, 0, 10), rarityColor, 0)
		dot.Name = "Dot"
		-- The name (with its mutation tag) is capped at 16 chars and
		-- fitted down to 13 pt, so even "Dark Matter Donut [Cosmic]"
		-- stays on one line inside its 140 px row — never wrapping onto
		-- the row below.
		local name = entry.name
		if entry.mutation ~= "None" then
			name = `{name} [{entry.mutation}]`
		end
		name = UiKit.truncate(name, 16)
		local nameLabel = UiKit.makeLabel(row, "Name", UDim2.new(0, 24, 0, 0), UDim2.new(0, 140, 1, 0), name, 14, UiKit.TEXT, false)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		UiKit.fitText(nameLabel, 14, 13)
		local rateText = FormatUtil.formatRate(entry.rate)
		local rate = UiKit.makeLabel(row, "Rate", UDim2.new(1, -84, 0, 0), UDim2.new(0, 76, 1, 0), rateText, 14, UiKit.GOLD_DARK, true)
		rate.TextXAlignment = Enum.TextXAlignment.Right
	end
	rosterRows.Size = UDim2.new(1, 0, 0, #roster * rowHeight)
	rosterFrame.Size = UDim2.new(0, 250, 0, 34 + #roster * rowHeight)
end

local function updateStormPanel(state: { [string]: any })
	if not stormLabel or not stormBarFill or not stormPanel then
		return
	end
	local storm = state.storm :: { [string]: any }?
	local goldenLeft = state.goldenHourLeft or 0
	local text = ""
	local fraction = 1
	local panelColor = Color3.fromRGB(220, 70, 30)
	if storm then
		if storm.phase == "warning" then
			text = `SOLAR STORM IN {FormatUtil.formatCountdown(storm.secondsLeft or 0)} - GET TO YOUR DOME!`
			fraction = math.clamp((storm.secondsLeft or 0) / 15, 0, 1)
			panelColor = Color3.fromRGB(255, 60, 40)
		elseif storm.phase == "active" then
			if state.stormSheltered then
				text = "SOLAR STORM! SHELTERED IN THE DOME - x2 INCOME"
			else
				text = "SOLAR STORM! SHELTER IN THE DOME!"
			end
			fraction = math.clamp((storm.secondsLeft or 0) / 15, 0, 1)
			panelColor = Color3.fromRGB(255, 60, 40)
		else
			text = `NEXT SOLAR STORM IN {FormatUtil.formatCountdown(storm.nextStormIn or 60)}`
			fraction = math.clamp(1 - (storm.nextStormIn or 60) / 60, 0, 1)
		end
	end
	stormLabel.Text = text
	stormLabel.TextColor3 = UiKit.WHITE
	UiKit.fitText(stormLabel, 20, 13)
	UiKit.setPanelColor(stormPanel, panelColor)
	stormBarFill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
	-- Golden Hour gets its own gold panel (dark text, 11:1) instead of
	-- being crammed onto the storm line.
	if goldenPanel and goldenLabel then
		if goldenLeft > 0 then
			goldenLabel.Text = `GOLDEN HOUR! STATION PAYS x2 - {FormatUtil.formatCountdown(goldenLeft)} LEFT`
			goldenPanel.Visible = true
		else
			goldenPanel.Visible = false
		end
	end
end

local function updateLockButton(state: { [string]: any })
	if not lockButton then
		return
	end
	local lockLeft = state.lockSecondsLeft or 0
	local cooldownLeft = state.lockCooldownLeft or 0
	if lockLeft > 0 then
		UiKit.setButtonTitle(lockButton, `LOCKED {math.ceil(lockLeft)}s`)
		UiKit.setButtonSubtitle(lockButton, "Airlock shut")
		UiKit.setButtonColor(lockButton, Color3.fromRGB(40, 170, 90))
	elseif cooldownLeft > 0 then
		UiKit.setButtonTitle(lockButton, `SHIELD {math.ceil(cooldownLeft)}s`)
		UiKit.setButtonSubtitle(lockButton, "Recharging")
		UiKit.setButtonColor(lockButton, Color3.fromRGB(150, 110, 30))
	else
		UiKit.setButtonTitle(lockButton, "LOCK")
		UiKit.setButtonSubtitle(lockButton, "Airlock (L)")
		UiKit.setButtonColor(lockButton, UiKit.BUTTON_COLORS.red)
	end
end

local function updateZapButton(state: { [string]: any })
	if not zapButton then
		return
	end
	if state.zorkActive then
		UiKit.setButtonTitle(zapButton, "ZAP!")
		UiKit.setButtonSubtitle(zapButton, "ZORK is here!")
		UiKit.setButtonColor(zapButton, UiKit.BUTTON_COLORS.orange)
	else
		UiKit.setButtonTitle(zapButton, "ZAP")
		UiKit.setButtonSubtitle(zapButton, "Zap ZORK (F)")
		UiKit.setButtonColor(zapButton, UiKit.BUTTON_COLORS.gray)
	end
end

local function updateBarButtons(state: { [string]: any })
	if rebirthButton then
		local rebirths = state.rebirths or 0
		local nextMultiplier = 1 + (rebirths + 1) * 0.5
		UiKit.setButtonSubtitle(
			rebirthButton,
			`{FormatUtil.formatMoney(state.rebirthCost or 5000)} - {FormatUtil.formatMultiplier(nextMultiplier)} next`
		)
	end
	if upgradesButton then
		local bought = 0
		local upgrades = state.upgrades :: { [string]: any }?
		if upgrades then
			for _, level in upgrades do
				if typeof(level) == "number" then
					bought += level
				end
			end
		end
		UiKit.setButtonSubtitle(upgradesButton, `{bought}/8 bought`)
	end
	if questsButton then
		UiKit.setButtonSubtitle(questsButton, `{state.questsDoneCount or 0}/{state.questsTotal or 14} done`)
	end
	if indexButton then
		local found = 0
		local discovered = state.discovered :: { [string]: any }?
		if discovered then
			for _ in discovered do
				found += 1
			end
		end
		UiKit.setButtonSubtitle(indexButton, `{found}/30 found`)
	end
end

local function updateCarryBanner(state: { [string]: any })
	if not carryFrame or not carryLabel then
		return
	end
	local cargo = state.cargo :: { any }
	local capacity = state.cargoCapacity or 1
	if #cargo == 0 then
		UiKit.setPanelColor(carryFrame, UiKit.CREAM)
		carryLabel.Text = `CARGO (0/{capacity}) - catch a brainrot!`
		carryLabel.TextColor3 = UiKit.MUTED
	else
		local first = cargo[1]
		local rarityColor = BrainrotData.RARITY_COLORS[first.rarity] or UiKit.ACCENT
		UiKit.setPanelColor(carryFrame, UiKit.lighten(rarityColor, 0.35))
		local label = first.name
		if first.mutation ~= "None" then
			label = `[{first.mutation}] {label}`
		end
		label = UiKit.truncate(label, 24)
		local extra = ""
		if #cargo > 1 then
			extra = ` +{#cargo - 1} more`
		end
		carryLabel.Text = `CARRYING: {label} ({FormatUtil.formatRate(first.rate or 0)}){extra} - RETURN TO STATION!`
		carryLabel.TextColor3 = UiKit.TEXT
		UiKit.fitText(carryLabel, 16, 13)
	end
end

-- Re-renders the whole HUD from one server state table.
function HudController.updateFromState(state: { [string]: any })
	if creditsLabel then
		creditsLabel.Text = FormatUtil.formatMoney(state.credits or 0)
		UiKit.fitText(creditsLabel, 30, 18)
	end
	if rateLabel then
		rateLabel.Text = `{FormatUtil.formatRate(state.rate or 0)}  ({FormatUtil.formatMultiplier(state.multiplier or 1)})`
	end
	if rebirthLabel then
		rebirthLabel.Text = `RING {state.rebirths or 0} - {FormatUtil.formatMultiplier(state.multiplier or 1)}`
	end
	if podsLabel then
		podsLabel.Text = `PODS {state.podsUsed or 0}/{state.podsMax or 4}`
	end
	if missionLabel then
		local mission = state.mission :: { [string]: any }?
		if mission then
			if mission.complete then
				missionLabel.Text = "ALL MISSIONS COMPLETE! You are a true Orbit legend."
			else
				missionLabel.Text =
					`MISSION {mission.index}/{mission.total}: {mission.text}  [{math.floor(mission.progress)}/{mission.goal}]  +${mission.reward}`
			end
			UiKit.fitText(missionLabel, 15, 13)
		end
	end
	updateStormPanel(state)
	updateLockButton(state)
	updateZapButton(state)
	updateBarButtons(state)
	updateCarryBanner(state)
	rebuildRoster(state)
end

-- Shows the event banner for a few seconds (storm warnings refresh it
-- every second from the server, so they stay up as long as they last).
-- Big events also get a giant shout + screen flash via BeamEffects.
-- The banner text is dark on light banners, white on dark ones.
function HudController.showBanner(kind: string, text: string, seconds: number)
	if not bannerFrame or not bannerLabel then
		return
	end
	local color = BANNER_COLORS[kind] or UiKit.ACCENT
	UiKit.setPanelColor(bannerFrame, color)
	bannerLabel.Text = text
	if bgLuminance(color) > 0.45 then
		bannerLabel.TextColor3 = UiKit.TEXT
	else
		bannerLabel.TextColor3 = UiKit.WHITE
	end
	bannerFrame.Visible = true
	UiKit.fitText(bannerLabel, 17, 13)
	if kind == "storm-warning" then
		BeamEffects.shout("SOLAR STORM INCOMING!", color)
	elseif kind == "storm-active" then
		BeamEffects.shout("SOLAR STORM!", color)
	elseif kind == "zork" then
		BeamEffects.shout("ZORK IS HERE!", color)
	elseif kind == "zork-driven-off" then
		addFeedLine(text)
	end
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

-- One-line feedback on the right side: a cream card with a colored stripe,
-- max 5, fading after 5 seconds. The card is built manually (no shadow):
-- UiKit.panel's shadow would land in this container as an extra child and
-- break the toast count and stacking. Every toast also lands in the
-- station feed on the left, where it stays visible.
function HudController.showToast(text: string)
	addFeedLine(text)
	if not toastContainer then
		return
	end
	local children = toastContainer:GetChildren()
	if #children >= 5 then
		children[1]:Destroy()
	end
	local y = #toastContainer:GetChildren() * 56
	local toast = UiKit.makeFrame(toastContainer, "Toast", UDim2.new(0, 0, 0, y), UDim2.new(1, 0, 0, 52), UiKit.CREAM, 0)
	UiKit.shade(toast, UiKit.CREAM, 0.18, 0.12)
	UiKit.outline(toast, 3)
	local stripe = UiKit.makeFrame(toast, "Stripe", UDim2.new(0, 0, 0, 6), UDim2.new(0, 14, 1, -12), UiKit.GOLD, 0)
	stripe.Name = "Stripe"
	local label = UiKit.makeLabel(toast, "ToastText", UDim2.new(0, 22, 0, 0), UDim2.new(1, -30, 1, 0), UiKit.truncate(text, 64), 15, UiKit.TEXT, true)
	label.TextXAlignment = Enum.TextXAlignment.Left
	UiKit.pop(toast)
	task.spawn(function()
		task.wait(4.5)
		if toast.Parent then
			local tween = TweenService:Create(toast, TweenInfo.new(0.5), { BackgroundTransparency = 1 })
			local labelTween = TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 })
			local stripeTween = TweenService:Create(stripe, TweenInfo.new(0.5), { BackgroundTransparency = 1 })
			tween:Play()
			labelTween:Play()
			stripeTween:Play()
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

-- The zone banner: a big colored announcement when the player enters a
-- new area. Fades out after 2 seconds. The background is darkened 40%
-- so the white 24 pt text passes 3:1 on every zone color.
local function showZoneBanner(text: string, color: Color3)
	if not zoneFrame or not zoneLabel then
		return
	end
	UiKit.setPanelColor(zoneFrame, UiKit.darken(color, 0.4))
	zoneLabel.Text = text
	zoneFrame.Visible = true
	UiKit.pop(zoneFrame)
	local hideAt = os.clock() + 2
	zoneHideAt = hideAt
	task.delay(2, function()
		if zoneHideAt == hideAt and zoneFrame then
			zoneFrame.Visible = false
		end
	end)
end

-- Figures out which named area the player is standing in.
local function computeZone(rootPosition: Vector3): (string, Color3)
	local flat = Vector3.new(rootPosition.X, 0, rootPosition.Z)
	for i = 1, 8 do
		local center = getModuleCenter(i)
		if (flat - center).Magnitude < 17 then
			return `MODULE {i}`, MODULE_ACCENTS[i]
		end
	end
	if (flat - Vector3.new(-42, 0, -38)).Magnitude < 19 then
		return "HYDROPONIC GARDEN", UiKit.COLORS.green
	end
	if (flat - Vector3.new(88, 0, 0)).Magnitude < 12 then
		return "AIRLOCK", UiKit.COLORS.orange
	end
	if flat.Magnitude < 75 then
		return "OBSERVATION DECK", UiKit.COLORS.cyan
	end
	return "OUTER DECK", UiKit.COLORS.gold
end

local function pollZone()
	while true do
		task.wait(0.5)
		if TitleController.isVisible() or not hudGui or not hudGui.Enabled then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			continue
		end
		local zone, color = computeZone(root.Position)
		if zone ~= currentZone then
			currentZone = zone
			showZoneBanner(zone, color)
		end
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
	-- Responsive scale: the whole HUD scales with viewport height.
	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if camera and hudScale then
			hudScale.Scale = UiKit.responsiveScale(camera.ViewportSize.Y)
		end
	end)
	task.spawn(pollZone)
end

return HudController
