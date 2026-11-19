--!strict
-- HudController
-- The in-game HUD for BRAINROT ORBIT, restyled round 5 on the cartoon
-- UiKit: a cream cash card on the left, a lava countdown panel with a
-- progress bar up top, the mission strip, the event banner, the MY MODULE
-- roster, a bottom-right row of candy action buttons (LOCK / REBIRTH /
-- UPGRADES / INDEX), a bottom-center carry banner tinted by the carried
-- brainrot's rarity, cream toast cards with colored stripes, a zone banner
-- that announces each area, and a mute button for sound effects.
--
-- Layout rules: nothing sits in the TOP-LEFT corner (Roblox's own menu
-- buttons live there), no text ever overflows its box (fixed-size candy
-- titles fitted by UiKit, fitText/truncate for dynamic labels), and the
-- whole HUD scales with viewport height via UIScale (clamp(viewportY/760, 0.55, 1.4)).

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
local bannerFrame: Frame? = nil
local bannerLabel: TextLabel? = nil
local rosterFrame: Frame? = nil
local rosterHeader: TextLabel? = nil
local rosterRows: Frame? = nil
local rosterStrip: Frame? = nil
local lockButton: TextButton? = nil
local carryFrame: Frame? = nil
local carryLabel: TextLabel? = nil
local promptLabel: TextLabel? = nil
local toastContainer: Frame? = nil
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

	-- Cash card: left-middle, clear of the top-left Roblox menu buttons.
	-- Cream panel with a gold header strip: big credits, income rate,
	-- rebirth ring and pod count.
	local cashCard = UiKit.panel(gui, "CashCard", UDim2.new(0, 12, 0.5, -92), UDim2.new(0, 300, 0, 184), nil)
	UiKit.makeHeaderStrip(cashCard, UiKit.GOLD)
	UiKit.makeLabel(cashCard, "CreditsCaption", UDim2.new(0, 12, 0, 8), UDim2.new(0, 120, 0, 20), "CREDITS", 15, UiKit.COLORS.orange, true).TextXAlignment =
		Enum.TextXAlignment.Left
	creditsLabel = UiKit.makeLabel(cashCard, "Credits", UDim2.new(0, 12, 0, 28), UDim2.new(1, -24, 0, 42), "$0", 30, UiKit.GOLD, true)
	creditsLabel.TextXAlignment = Enum.TextXAlignment.Left
	rateLabel = UiKit.makeLabel(cashCard, "Rate", UDim2.new(0, 12, 0, 74), UDim2.new(1, -24, 0, 28), "$0/s  (x1)", 19, UiKit.COLORS.green, true)
	rateLabel.TextXAlignment = Enum.TextXAlignment.Left
	rebirthLabel = UiKit.makeLabel(cashCard, "Rebirths", UDim2.new(0, 12, 0, 106), UDim2.new(0, 140, 0, 28), "RING 0", 19, UiKit.COLORS.purple, true)
	rebirthLabel.TextXAlignment = Enum.TextXAlignment.Left
	podsLabel = UiKit.makeLabel(cashCard, "Pods", UDim2.new(0, 152, 0, 106), UDim2.new(1, -164, 0, 28), "PODS 0/4", 19, UiKit.TEXT, true)
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

	-- Storm countdown: top-center lava panel with a gold progress bar.
	-- The bar drains toward the next storm and refills during warning /
	-- active phases; the panel turns red as the storm closes in.
	stormPanel = UiKit.panel(gui, "StormPanel", UDim2.new(0.5, -280, 0, 8), UDim2.new(0, 560, 0, 76), UiKit.COLORS.lava)
	stormLabel = UiKit.makeLabel(stormPanel, "Storm", UDim2.new(0, 8, 0, 6), UDim2.new(1, -16, 0, 34), "NEXT SOLAR STORM IN 1:00", 18, UiKit.WHITE, true)
	local barBg = UiKit.makeFrame(stormPanel, "BarBg", UDim2.new(0, 16, 0, 48), UDim2.new(1, -32, 0, 14), Color3.fromRGB(60, 30, 20), 0)
	stormBarFill = UiKit.makeFrame(barBg, "BarFill", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0), UiKit.GOLD, 0)

	-- Mission strip: the next goal is always visible, 8 px below the
	-- countdown panel so the stack breathes.
	local missionStrip = UiKit.panel(gui, "MissionStrip", UDim2.new(0.5, -280, 0, 92), UDim2.new(0, 560, 0, 30), nil)
	UiKit.makeHeaderStrip(missionStrip, UiKit.ACCENT)
	missionLabel = UiKit.makeLabel(missionStrip, "Mission", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 1, 0), "MISSION 1/4: Catch a brainrot (E)", 15, UiKit.TEXT, true)

	-- Event banner: transient announcements (Golden Hour, Meteor, ZORK).
	bannerFrame = UiKit.panel(gui, "EventBanner", UDim2.new(0.5, -280, 0, 130), UDim2.new(0, 560, 0, 40), UiKit.GOLD)
	bannerFrame.Visible = false
	bannerLabel = UiKit.makeLabel(bannerFrame, "BannerText", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 1, 0), "", 17, UiKit.WHITE, true)

	-- Roster panel: MY MODULE (n/n) on the right side. Its header strip
	-- takes the player's module accent color once state arrives.
	rosterFrame = UiKit.panel(gui, "Roster", UDim2.new(1, -262, 0, 60), UDim2.new(0, 250, 0, 34), nil)
	rosterStrip = UiKit.makeHeaderStrip(rosterFrame, UiKit.ACCENT)
	rosterHeader = UiKit.makeLabel(rosterFrame, "Header", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 0, 30), "MY MODULE (0/4)", 16, UiKit.TEXT, true)
	rosterHeader.TextXAlignment = Enum.TextXAlignment.Left
	rosterRows = UiKit.makeFrame(rosterFrame, "Rows", UDim2.new(0, 0, 0, 30), UDim2.new(1, 0, 0, 0), UiKit.CREAM, 1)
	rosterRows.BackgroundTransparency = 1

	-- Action buttons: bottom-right candy row — LOCK / REBIRTH / UPGRADES /
	-- INDEX, each 150x64 with an icon, a title and a sub-line.
	local actions = {
		{ name = "LockButton", title = "🔒 LOCK", sub = "Shield (L)", color = UiKit.COLORS.red },
		{ name = "RebirthButton", title = "🔄 REBIRTH", sub = "+50% forever", color = UiKit.COLORS.purple },
		{ name = "UpgradesButton", title = "⚡ UPGRADES", sub = "4 tracks", color = UiKit.COLORS.blue },
		{ name = "IndexButton", title = "📖 INDEX", sub = "30 species", color = UiKit.COLORS.green },
	} :: { { name: string, title: string, sub: string, color: any } }
	for i, action in actions do
		local x = -642 + (i - 1) * 160
		local button = UiKit.button(
			gui,
			action.name,
			UDim2.new(1, x, 1, -76),
			UDim2.new(0, 150, 0, 64),
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
		elseif action.name == "RebirthButton" then
			button.MouseButton1Click:Connect(function()
				PanelsController.showRebirthConfirm()
			end)
		elseif action.name == "UpgradesButton" then
			button.MouseButton1Click:Connect(function()
				PanelsController.toggleUpgrades()
			end)
		elseif action.name == "IndexButton" then
			button.MouseButton1Click:Connect(function()
				PanelsController.toggleIndex()
			end)
		end
	end

	-- Carry banner: bottom-center, tinted by the carried brainrot's rarity.
	carryFrame = UiKit.panel(gui, "CarryBanner", UDim2.new(0.5, -320, 1, -132), UDim2.new(0, 640, 0, 56), nil)
	carryLabel = UiKit.makeLabel(carryFrame, "CarryText", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 1, 0), "CARGO EMPTY — catch a brainrot!", 16, UiKit.MUTED, true)

	-- Context prompt: what [E] does right now, above the carry banner.
	promptLabel = UiKit.makeLabel(gui, "Prompt", UDim2.new(0.5, -280, 1, -164), UDim2.new(0, 560, 0, 26), "", 16, UiKit.GOLD, true)
	promptLabel.Visible = false

	-- Help line: below the cash card, left-aligned with it. It used to sit
	-- bottom-center (y 1,-34), where it overlapped the bottom-right action
	-- buttons on narrow viewports: at 1024x768 the help band (x 232..792,
	-- y 734..758) crossed the buttons (x 382..1012, y 692..756). Here it
	-- never overlaps anything: the cash card ends 8 px above it, the
	-- toasts live on the right (x >= W-412, this ends at x 572), and the
	-- carry banner and the action row sit below it. Verified by coordinate
	-- math at 1024x768 and 1920x1080 (see the round 6 report).
	local helpLabel = UiKit.makeLabel(
		gui,
		"Help",
		UDim2.new(0, 12, 0.5, 100),
		UDim2.new(0, 560, 0, 24),
		"E catch / dock / steal    •    L lock module    •    F bonk ZORK    •    Q drop cargo",
		14,
		UiKit.WHITE,
		false
	)
	helpLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Toast stack: right side, below the roster (the roster can grow to
	-- 8 rows, ending near y=302 — the toasts start at y=320).
	toastContainer = UiKit.makeFrame(gui, "Toasts", UDim2.new(1, -412, 0, 320), UDim2.new(0, 400, 0, 280), UiKit.CREAM, 1)
	toastContainer.BackgroundTransparency = 1

	-- Zone banner: center screen, fades in/out when the player enters a
	-- new area. Hidden until the first zone change after the title.
	zoneFrame = UiKit.panel(gui, "ZoneBanner", UDim2.new(0.5, -250, 0.3, 0), UDim2.new(0, 500, 0, 64), UiKit.COLORS.cyan)
	zoneFrame.Visible = false
	zoneLabel = UiKit.makeLabel(zoneFrame, "ZoneText", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 1, 0), "", 24, UiKit.WHITE, true)

	-- Mute button: bottom-left, toggles sound effects (there is no music
	-- track in this build — no licensed asset id lives in the repo).
	muteButton = UiKit.button(gui, "MuteButton", UDim2.new(0, 12, 1, -76), UDim2.new(0, 64, 0, 64), UiKit.COLORS.blue, "♪", "SFX", 28, 12)
	muteButton.MouseButton1Click:Connect(function()
		local muted = BeamEffects.setMuted(not BeamEffects.isMuted())
		if muteButton then
			if muted then
				UiKit.setButtonColor(muteButton, Color3.fromRGB(120, 120, 130))
				UiKit.setButtonSubtitle(muteButton, "MUTED")
			else
				UiKit.setButtonColor(muteButton, UiKit.COLORS.blue)
				UiKit.setButtonSubtitle(muteButton, "SFX")
			end
		end
	end)

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
		local row = UiKit.makeFrame(rosterRows, `Row{i}`, UDim2.new(0, 0, 0, y), UDim2.new(1, 0, 0, rowHeight), UiKit.CREAM, 1)
		row.BackgroundTransparency = 1
		local rarityColor = BrainrotData.RARITY_COLORS[entry.rarity] or UiKit.TEXT
		local dot = UiKit.makeFrame(row, "Dot", UDim2.new(0, 8, 0, 8), UDim2.new(0, 10, 0, 10), rarityColor, 0)
		dot.Name = "Dot"
		-- The name (with its mutation tag) is capped at 16 chars and
		-- fitted down to 11 pt, so even "Dark Matter Donut [Cosmic]"
		-- stays on one line inside its 140 px row — never wrapping onto
		-- the row below.
		local name = entry.name
		if entry.mutation ~= "None" then
			name = `{name} [{entry.mutation}]`
		end
		name = UiKit.truncate(name, 16)
		local nameLabel = UiKit.makeLabel(row, "Name", UDim2.new(0, 24, 0, 0), UDim2.new(0, 140, 1, 0), name, 14, UiKit.TEXT, false)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		UiKit.fitText(nameLabel, 14, 11)
		local rateText = FormatUtil.formatRate(entry.rate)
		local rate = UiKit.makeLabel(row, "Rate", UDim2.new(1, -84, 0, 0), UDim2.new(0, 76, 1, 0), rateText, 14, UiKit.GOLD, true)
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
	local panelColor = UiKit.COLORS.lava
	if storm then
		if storm.phase == "warning" then
			text = `SOLAR STORM IN {math.ceil(storm.secondsLeft)}s — GET TO YOUR DOME!`
			fraction = math.clamp((storm.secondsLeft or 0) / 15, 0, 1)
			panelColor = Color3.fromRGB(255, 60, 40)
		elseif storm.phase == "active" then
			text = `SOLAR STORM! STAY IN YOUR DOME! ({math.ceil(storm.secondsLeft)}s)`
			fraction = math.clamp((storm.secondsLeft or 0) / 15, 0, 1)
			panelColor = Color3.fromRGB(255, 60, 40)
		else
			text = `NEXT SOLAR STORM IN {FormatUtil.formatCountdown(storm.nextStormIn or 60)}`
			fraction = math.clamp(1 - (storm.nextStormIn or 60) / 60, 0, 1)
		end
	end
	if goldenLeft > 0 then
		text = `{text}   •   GOLDEN HOUR 2x ({math.ceil(goldenLeft)}s)`
	end
	stormLabel.Text = text
	stormLabel.TextColor3 = UiKit.WHITE
	UiKit.fitText(stormLabel, 18, 12)
	UiKit.setPanelColor(stormPanel, panelColor)
	stormBarFill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
end

local function updateLockButton(state: { [string]: any })
	if not lockButton then
		return
	end
	local lockLeft = state.lockSecondsLeft or 0
	local cooldownLeft = state.lockCooldownLeft or 0
	if lockLeft > 0 then
		UiKit.setButtonTitle(lockButton, `🔒 LOCKED {math.ceil(lockLeft)}s`)
		UiKit.setButtonColor(lockButton, Color3.fromRGB(40, 170, 90))
	elseif cooldownLeft > 0 then
		UiKit.setButtonTitle(lockButton, `SHIELD {math.ceil(cooldownLeft)}s`)
		UiKit.setButtonColor(lockButton, Color3.fromRGB(170, 130, 40))
	else
		UiKit.setButtonTitle(lockButton, "🔒 LOCK")
		UiKit.setButtonColor(lockButton, UiKit.COLORS.red)
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
		carryLabel.Text = `CARGO (0/{capacity}) — catch a brainrot!`
		carryLabel.TextColor3 = UiKit.MUTED
	else
		local first = cargo[1]
		local rarityColor = BrainrotData.RARITY_COLORS[first.rarity] or UiKit.ACCENT
		UiKit.setPanelColor(carryFrame, UiKit.lighten(rarityColor, 0.35))
		local names: { string } = {}
		for _, entry in cargo do
			table.insert(names, entry.name)
		end
		carryLabel.Text = `CARRYING ({#cargo}/{capacity}): {UiKit.truncate(table.concat(names, ", "), 40)} — head home to dock!`
		carryLabel.TextColor3 = UiKit.TEXT
		UiKit.fitText(carryLabel, 16, 12)
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
		rebirthLabel.Text = `RING {state.rebirths or 0}`
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
				missionLabel.Text = `MISSION {mission.index}/{mission.total}: {mission.text} — REWARD {mission.reward} credits  [{math.floor(mission.progress)}/{mission.goal}]`
			end
			UiKit.fitText(missionLabel, 15, 11)
		end
	end
	updateStormPanel(state)
	updateLockButton(state)
	updateCarryBanner(state)
	rebuildRoster(state)
end

-- Shows the event banner for a few seconds (storm warnings refresh it
-- every second from the server, so they stay up as long as they last).
-- Big events also get a giant shout + screen flash via BeamEffects.
function HudController.showBanner(kind: string, text: string, seconds: number)
	if not bannerFrame or not bannerLabel then
		return
	end
	local color = BANNER_COLORS[kind] or UiKit.ACCENT
	UiKit.setPanelColor(bannerFrame, color)
	bannerLabel.Text = text
	bannerLabel.TextColor3 = UiKit.WHITE
	bannerFrame.Visible = true
	UiKit.fitText(bannerLabel, 17, 12)
	if kind == "storm-warning" then
		BeamEffects.shout("SOLAR STORM INCOMING!", color)
	elseif kind == "storm-active" then
		BeamEffects.shout("SOLAR STORM!", color)
	elseif kind == "zork" then
		BeamEffects.shout("ZORK IS HERE!", color)
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
-- break the toast count and stacking.
function HudController.showToast(text: string)
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
-- new area. Fades out after 2 seconds.
local function showZoneBanner(text: string, color: Color3)
	if not zoneFrame or not zoneLabel then
		return
	end
	UiKit.setPanelColor(zoneFrame, color)
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
