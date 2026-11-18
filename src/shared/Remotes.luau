--!strict
-- Remotes
-- The whitelist of every RemoteEvent in BRAINROT ORBIT. The server creates
-- exactly these remotes (and no others) under ReplicatedStorage/OrbitRemotes
-- at startup; the client waits for them by name. Splitting client-to-server
-- and server-to-client names in one table keeps the API surface auditable: a
-- remote that is not listed here does not exist.
--
-- The folder is deliberately NOT named "Remotes": this ModuleScript itself
-- is named "Remotes" (Rojo syncs it under ReplicatedStorage), so a folder
-- with the same name made WaitForChild("Remotes") return the ModuleScript
-- and every client remote lookup timed out (round 3 bug fix — the client
-- was completely deaf and mute until the folder was renamed).
--
-- Client -> server remotes carry INTENT only (never an outcome): the server
-- re-derives every effect from its own state and validates every argument.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type RemoteEvent = any
type Instance = any

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

-- Requests the client may send to the server.
Remotes.CLIENT_TO_SERVER = {
	"CatchBrainrot", -- intent: catch the nearest wild brainrot in beam range
	"DockBrainrot", -- intent: dock the first carried brainrot in my nearest empty pod
	"LockModule", -- intent: raise my module's energy shield
	"StealBrainrot", -- intent: steal the nearest docked brainrot from a rival module
	"Rebirth", -- intent: open a new station ring (resets credits, +50% forever)
	"BuyUpgrade", -- intent: buy the next level of one upgrade track
	"BonkZork", -- intent: swing the Plasma Bat at ZORK the Snatcher
	"DropCargo", -- intent: drop everything in my cargo bubble
	"PlayerReady", -- the title screen was dismissed; start sending state updates
} :: { string }

-- Messages the server may send to the client.
Remotes.SERVER_TO_CLIENT = {
	"StateUpdate", -- full HUD state: credits, roster, cargo, missions, upgrades
	"EventBanner", -- storm warnings, Golden Hour, Meteor Shower, ZORK raids
	"Toast", -- one-line feedback ("Caught Bloop Blorp!", "Module locked!")
	"FxEvent", -- visual effects: tractor beam, bonk burst, storm flash
	"TourCommand", -- finalist-review tour: show title, open panels, highlight
} :: { string }

local remotesFolder: Instance? = nil

-- Creates the Remotes folder and every whitelisted RemoteEvent. Server only;
-- called once by Main.server.luau before any player can join.
function Remotes.createAll(): Instance
	local folder = Instance.new("Folder")
	folder.Name = "OrbitRemotes"
	for _, name in Remotes.CLIENT_TO_SERVER do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in Remotes.SERVER_TO_CLIENT do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	remotesFolder = folder
	return folder
end

-- Returns a RemoteEvent by name, waiting up to 10 seconds for replication.
-- Used by the client at startup; returns nil (with a warning) on timeout.
function Remotes.waitFor(name: string): RemoteEvent?
	local folder = remotesFolder
	if not folder then
		folder = ReplicatedStorage:WaitForChild("OrbitRemotes", 10)
		if not folder then
			warn(`[Remotes] OrbitRemotes folder did not replicate within 10s; cannot find {name}`)
			return nil
		end
		if not folder:IsA("Folder") then
			warn(`[Remotes] Expected OrbitRemotes to be a Folder, found {folder.ClassName}; cannot find {name}`)
			return nil
		end
		remotesFolder = folder
	end
	local remote = folder:WaitForChild(name, 10)
	if not remote then
		warn(`[Remotes] Remote {name} did not replicate within 10s`)
		return nil
	end
	return remote :: RemoteEvent
end

-- Returns a RemoteEvent created by createAll (server side, no waiting).
function Remotes.get(name: string): RemoteEvent?
	if not remotesFolder then
		return nil
	end
	return remotesFolder:FindFirstChild(name) :: RemoteEvent?
end

return Remotes
