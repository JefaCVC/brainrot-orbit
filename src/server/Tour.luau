--!strict
-- Tour
-- Finalist-review helpers for TOUR.json: one function per dossier screenshot,
-- each taking a single player name (or "first" for the first player in the
-- server) and bringing the game to that screen. The reviewer runs these from
-- Studio's command bar; the client half of each step arrives over the
-- TourCommand remote (show the title screen, open the panels, ...).
-- Module path for TOUR.json: ServerScriptService.Tour

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Vector3 = any

local ServerScriptService = game:GetService("ServerScriptService")

local requireModule = require :: any
local GameService = requireModule(ServerScriptService:WaitForChild("GameService"))
local StormService = requireModule(ServerScriptService:WaitForChild("StormService"))
local WorldBuilder = requireModule(ServerScriptService:WaitForChild("WorldBuilder"))

local Tour = {}

-- Screenshot 1: the 3D title screen — logo, tagline, 3-step how-to, PLAY.
-- The player is placed in front of the brainrot pedestals and the title
-- screen opens over the live 3D view.
function Tour.showTitle(playerName: string): string
	local runtime = GameService.getRuntimeForPlayerName(playerName)
	if not runtime then
		return "no player found"
	end
	GameService.teleportPlayerTo(runtime.player, Vector3.new(0, 0, 4))
	GameService.sendTourCommand(runtime.player, "showTitle")
	return `title screen shown to {runtime.player.Name}`
end

-- Screenshot 2: the tractor-beam catch — a wild Bloop Blorp waiting ten
-- studs in front of the player on the observation deck.
function Tour.showCatch(playerName: string): string
	local runtime = GameService.getRuntimeForPlayerName(playerName)
	if not runtime then
		return "no player found"
	end
	GameService.teleportPlayerTo(runtime.player, Vector3.new(25, 0, 25))
	GameService.sendTourCommand(runtime.player, "hideTitle")
	GameService.spawnWildInFront(runtime.player)
	return `wild Bloop Blorp placed in front of {runtime.player.Name} — press E to catch`
end

-- Screenshot 3: the solar storm — the storm goes active at once (domes
-- up, orange sky, spark emitters on), the player standing on the open deck.
function Tour.showStorm(playerName: string): string
	local runtime = GameService.getRuntimeForPlayerName(playerName)
	if not runtime then
		return "no player found"
	end
	GameService.teleportPlayerTo(runtime.player, Vector3.new(0, 0, 24))
	GameService.sendTourCommand(runtime.player, "hideTitle")
	StormService.forceStormActive()
	return "solar storm active — domes up, sky orange, 15s to capture"
end

-- Screenshot 4: a full module — the player's pods are filled with a
-- showcase roster (Gold, Diamond, Cosmic included), 50,000 credits, and the
-- Index + Upgrades panels open over the game.
function Tour.showModule(playerName: string): string
	local runtime = GameService.getRuntimeForPlayerName(playerName)
	if not runtime then
		return "no player found"
	end
	if runtime.moduleIndex == 0 then
		return "player has no module yet"
	end
	GameService.grantDemoModule(runtime)
	local module = WorldBuilder.MODULES[runtime.moduleIndex]
	GameService.teleportPlayerTo(runtime.player, module.center + Vector3.new(0, 0, 10))
	GameService.sendTourCommand(runtime.player, "hideTitle")
	GameService.sendTourCommand(runtime.player, "openPanels")
	return `showcase module granted to {runtime.player.Name} — Index + Upgrades open`
end

return Tour
