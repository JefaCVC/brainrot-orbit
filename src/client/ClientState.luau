--!strict
-- ClientState
-- The client's single copy of the server's HUD state. Main.client.luau
-- writes it on every StateUpdate remote; the HUD, the panels and the input
-- controller read it (and listen to StateChanged) — nobody keeps a second
-- copy, so the screen can never disagree with itself.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type RBXScriptSignal = any

local ClientState = {}

local latestState: { [string]: any }? = nil
local changedEvent = Instance.new("BindableEvent")

function ClientState.setState(state: { [string]: any })
	latestState = state
	changedEvent:Fire(state)
end

function ClientState.getState(): { [string]: any }?
	return latestState
end

function ClientState.getStateChangedSignal(): RBXScriptSignal
	return changedEvent.Event
end

-- Convenience readers with safe defaults for the pre-first-update window.
function ClientState.getCredits(): number
	if latestState and typeof(latestState.credits) == "number" then
		return latestState.credits
	end
	return 0
end

function ClientState.getModuleIndex(): number
	if latestState and typeof(latestState.moduleIndex) == "number" then
		return latestState.moduleIndex
	end
	return 0
end

return ClientState
