--!strict
-- Main
-- Client bootstrap for BRAINROT ORBIT. Wires the server's remotes to the
-- controllers (state, banners, toasts, tour commands), builds the title
-- screen first so the player lands on it, and starts the HUD, the panels,
-- the tutorial, the input bindings, the animator and the effects. The HUD
-- stays hidden until PLAY dismisses the title screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- require is aliased so the Luau analyzer treats module loads as untyped calls;
-- at runtime this is the plain Roblox require of a ModuleScript instance.
local requireModule = require :: any
local BeamEffects = requireModule(script.Parent:WaitForChild("BeamEffects"))
local BrainrotAnimator = requireModule(script.Parent:WaitForChild("BrainrotAnimator"))
local ClientState = requireModule(script.Parent:WaitForChild("ClientState"))
local HudController = requireModule(script.Parent:WaitForChild("HudController"))
local InputController = requireModule(script.Parent:WaitForChild("InputController"))
local PanelsController = requireModule(script.Parent:WaitForChild("PanelsController"))
local Remotes = requireModule(ReplicatedStorage:WaitForChild("Remotes"))
local TitleController = requireModule(script.Parent:WaitForChild("TitleController"))
local TutorialController = requireModule(script.Parent:WaitForChild("TutorialController"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Server -> client wiring. Each remote is waited for once here, which also
-- warms the Remotes cache for every controller that fires back.
local stateRemote = Remotes.waitFor("StateUpdate")
local stateRemoteMissing = stateRemote == nil
local didToastMissingState = false
if stateRemote then
	stateRemote.OnClientEvent:Connect(function(state: { [string]: any })
		ClientState.setState(state)
	end)
end

local bannerRemote = Remotes.waitFor("EventBanner")
if bannerRemote then
	bannerRemote.OnClientEvent:Connect(function(payload: { [string]: any })
		HudController.showBanner(payload.kind or "", payload.text or "", payload.seconds or 0)
	end)
end

local toastRemote = Remotes.waitFor("Toast")
if toastRemote then
	toastRemote.OnClientEvent:Connect(function(text: string)
		HudController.showToast(text)
	end)
end

local tourRemote = Remotes.waitFor("TourCommand")
if tourRemote then
	tourRemote.OnClientEvent:Connect(function(command: string)
		if command == "showTitle" then
			HudController.hide()
			TitleController.show()
		elseif command == "hideTitle" then
			TitleController.dismiss()
		elseif command == "openPanels" then
			PanelsController.openPanelsForTour()
		elseif command == "openIndex" then
			PanelsController.openIndexForTour()
		elseif command == "openQuests" then
			PanelsController.openQuestsForTour()
		elseif command == "hideTutorial" then
			TutorialController.hide()
		elseif command == "highlightCatch" then
			HudController.showToast("Press E to catch the Bloop Blorp!")
		end
	end)
end

-- What happens when the title screen is dismissed (PLAY or the tour):
-- the HUD appears and the server starts sending state updates.
local function onTitleDismissed()
	HudController.show()
	-- If the state remote never replicated, the player would otherwise sit
	-- in front of a dead HUD with no explanation. Toast once, here, where
	-- the HUD is visible (a toast at startup would fade behind the title).
	if stateRemoteMissing and not didToastMissingState then
		didToastMissingState = true
		HudController.showToast("Connection problem - remotes not found")
	end
	local readyRemote = Remotes.waitFor("PlayerReady")
	if readyRemote then
		readyRemote:FireServer()
	end
end

PanelsController.init()
HudController.init()
TitleController.init(playerGui, onTitleDismissed)
TutorialController.init()
InputController.init()
BrainrotAnimator.init()
BeamEffects.init()

print("[BRAINROT ORBIT] Client ready.")
