--!strict
-- WorldBuilder
-- Builds the whole BRAINROT ORBIT station at runtime, from plain parts: a
-- BRIGHT observation deck (white-blue floors, warm lamps, big windows), eight
-- player modules with habitat pods and shield domes, a hydroponic garden, an
-- airlock, title pedestals, crew NPCs, a cleaning robot, and the space
-- backdrop (planet, satellites, stars) visible through the windows. Dark
-- space is only ever a backdrop — the play area is always bright.
--
-- Everything is anchored and deterministic: the same layout every server, so
-- the dossier screenshots and the TOUR.json steps always match the world.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Model = any
type BasePart = any
type Color3 = any
type Vector3 = any
type CFrame = any
type Instance = any
type TextLabel = any
type ParticleEmitter = any

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local requireModule = require :: any
local BrainrotFactory = requireModule(ServerScriptService:WaitForChild("BrainrotFactory"))
local BrainrotData = requireModule(game:GetService("ReplicatedStorage"):WaitForChild("BrainrotData"))

local WorldBuilder = {}

WorldBuilder.HUB_CENTER = Vector3.new(0, 0, 0)
WorldBuilder.AIRLOCK_POSITION = Vector3.new(88, 0, 0)
WorldBuilder.MODULES = {} :: { any }
WorldBuilder.STORM_EMITTERS = {} :: { ParticleEmitter }
WorldBuilder.CLEANING_ROBOT = nil :: Model?
WorldBuilder.ROBOT_WAYPOINTS = {} :: { Vector3 }

local MODULE_COUNT = 8
local MODULE_RADIUS = 95
local MODULE_ACCENTS = {
	Color3.fromRGB(74, 163, 255),
	Color3.fromRGB(88, 214, 141),
	Color3.fromRGB(255, 130, 180),
	Color3.fromRGB(255, 160, 60),
	Color3.fromRGB(176, 108, 255),
	Color3.fromRGB(60, 220, 220),
	Color3.fromRGB(255, 215, 60),
	Color3.fromRGB(255, 100, 100),
} :: { Color3 }

local rng = Random.new()

local function newFolder(name: string, parent: Instance): Instance
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function newPart(
	name: string,
	shape: string,
	size: Vector3,
	color: Color3,
	cframe: CFrame,
	parent: Instance,
	material: any?,
	transparency: number?
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType[shape]
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.CFrame = cframe
	part.Parent = parent
	return part
end

local function flatCylinder(name: string, radius: number, thickness: number, color: Color3, y: number, parent: Instance): BasePart
	-- A Roblox cylinder's axis runs along X, so a flat disc is rotated 90 degrees.
	local disc = newPart(name, "Cylinder", Vector3.new(thickness, radius * 2, radius * 2), color, CFrame.new(0, y, 0), parent)
	disc.CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90))
	return disc
end

local function addSign(parent: Instance, position: Vector3, title: string, subtitle: string, accent: Color3): TextLabel
	local pole = newPart("SignPole", "Cylinder", Vector3.new(5, 0.4, 0.4), Color3.fromRGB(120, 130, 150), CFrame.new(position + Vector3.new(0, 2.5, 0)), parent)
	pole.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local board = newPart(
		"SignBoard",
		"Block",
		Vector3.new(7, 2.2, 0.4),
		Color3.fromRGB(30, 40, 60),
		CFrame.new(position + Vector3.new(0, 5.6, 0)),
		parent,
		Enum.Material.SmoothPlastic
	)
	board.Name = "SignBoard"
	local tag = Instance.new("BillboardGui")
	tag.Name = "SignTag"
	tag.Size = UDim2.new(0, 220, 0, 70)
	tag.StudsOffset = Vector3.new(0, 5.6, 0)
	tag.AlwaysOnTop = false
	tag.Adornee = pole
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 32)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = title
	titleLabel.TextColor3 = accent
	titleLabel.TextSize = 20
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextWrapped = true
	titleLabel.Parent = tag
	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "Subtitle"
	subLabel.Position = UDim2.new(0, 0, 0, 32)
	subLabel.Size = UDim2.new(1, 0, 0, 26)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = subtitle
	subLabel.TextColor3 = Color3.fromRGB(220, 230, 245)
	subLabel.TextSize = 15
	subLabel.Font = Enum.Font.Gotham
	subLabel.TextWrapped = true
	subLabel.Parent = tag
	tag.Parent = parent
	return titleLabel
end

local function buildHub(folder: Instance)
	-- One big bright floor for the whole station, hub + outer deck.
	local floor = flatCylinder("StationFloor", 115, 2, Color3.fromRGB(225, 232, 245), -1, folder)
	floor.Material = Enum.Material.SmoothPlastic
	-- Bullseye deck pattern: concentric discs in station blue and white.
	flatCylinder("DeckRing1", 68, 0.25, Color3.fromRGB(200, 220, 245), 0.1, folder)
	flatCylinder("DeckRing2", 50, 0.25, Color3.fromRGB(235, 242, 252), 0.18, folder)
	flatCylinder("DeckRing3", 30, 0.25, Color3.fromRGB(190, 225, 255), 0.26, folder)
	local emblem = flatCylinder("CenterEmblem", 7, 0.3, Color3.fromRGB(255, 170, 60), 0.34, folder)
	emblem.Material = Enum.Material.Neon

	-- Window wall: 24 panels around the hub, alternating solid and glass.
	-- Four gaps (N/E/S/W) are the airlock doors to the outer deck.
	for i = 0, 23 do
		local angle = (i / 24) * math.pi * 2
		local isDoorGap = (i % 6) == 0
		if isDoorGap then
			-- Door frame: two posts and a lintel, open in the middle.
			local doorPos = Vector3.new(math.cos(angle) * 75, 0, math.sin(angle) * 75)
			local doorCf = CFrame.new(doorPos, Vector3.new(0, 0, 0))
			for _, side in { -1, 1 } do
				newPart(
					"DoorPost",
					"Block",
					Vector3.new(1.2, 10, 1.5),
					Color3.fromRGB(255, 170, 60),
					doorCf * CFrame.new(side * 5, 5, 0),
					folder,
					Enum.Material.Neon
				)
			end
			newPart("DoorLintel", "Block", Vector3.new(11.5, 1.2, 1.5), Color3.fromRGB(255, 170, 60), doorCf * CFrame.new(0, 9.4, 0), folder, Enum.Material.Neon)
		else
			local panelPos = Vector3.new(math.cos(angle) * 75, 5, math.sin(angle) * 75)
			local panelCf = CFrame.new(panelPos, Vector3.new(0, 5, 0))
			if i % 2 == 0 then
				newPart("WallPanel", "Block", Vector3.new(19.5, 10, 1.5), Color3.fromRGB(240, 244, 250), panelCf, folder)
			else
				local window = newPart(
					"WindowPanel",
					"Block",
					Vector3.new(19.5, 10, 0.6),
					Color3.fromRGB(150, 210, 255),
					panelCf,
					folder,
					Enum.Material.Glass,
					0.3
				)
				window.CanCollide = true
			end
		end
	end

	-- Warm lamp posts keep the deck bright even though space outside is dark.
	for i = 0, 7 do
		local angle = (i / 8) * math.pi * 2 + math.pi / 8
		local pos = Vector3.new(math.cos(angle) * 55, 0, math.sin(angle) * 55)
		local pole = newPart("LampPole", "Cylinder", Vector3.new(9, 0.5, 0.5), Color3.fromRGB(140, 150, 170), CFrame.new(pos + Vector3.new(0, 4.5, 0)), folder)
		pole.CFrame = CFrame.new(pos + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local head = newPart("LampHead", "Block", Vector3.new(2.4, 0.8, 2.4), Color3.fromRGB(255, 230, 170), CFrame.new(pos + Vector3.new(0, 9.2, 0)), folder, Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 225, 170)
		light.Range = 34
		light.Brightness = 1.6
		light.Parent = head
	end

	addSign(folder, Vector3.new(0, 0, 24), "OBSERVATION DECK", "Catch brainrots with your tractor beam [E]", Color3.fromRGB(120, 200, 255))
end

local function buildOuterDeck(folder: Instance)
	-- Safety posts + rails around the outer edge, with a neon tip each.
	local postCount = 32
	local posts: { Vector3 } = {}
	for i = 0, postCount - 1 do
		local angle = (i / postCount) * math.pi * 2
		local pos = Vector3.new(math.cos(angle) * 112, 0, math.sin(angle) * 112)
		table.insert(posts, pos)
		newPart("RailPost", "Block", Vector3.new(0.6, 3, 0.6), Color3.fromRGB(150, 160, 180), CFrame.new(pos + Vector3.new(0, 1.5, 0)), folder)
		newPart("RailTip", "Block", Vector3.new(0.8, 0.4, 0.8), Color3.fromRGB(255, 170, 60), CFrame.new(pos + Vector3.new(0, 3.2, 0)), folder, Enum.Material.Neon)
	end
	for i = 1, postCount do
		local a = posts[i]
		local b = posts[(i % postCount) + 1]
		local mid = (a + b) / 2 + Vector3.new(0, 2.6, 0)
		local length = (b - a).Magnitude
		newPart("RailBar", "Block", Vector3.new(length, 0.25, 0.25), Color3.fromRGB(170, 180, 200), CFrame.new(mid, b + Vector3.new(0, 2.6, 0)), folder)
	end

	-- Solar storm spark emitters (disabled until a storm starts).
	for i = 0, 3 do
		local angle = (i / 4) * math.pi * 2 + math.pi / 4
		local emitterPart = newPart(
			"StormEmitter",
			"Block",
			Vector3.new(1, 1, 1),
			Color3.fromRGB(255, 120, 40),
			CFrame.new(Vector3.new(math.cos(angle) * 90, 26, math.sin(angle) * 90)),
			folder,
			Enum.Material.Neon,
			1
		)
		emitterPart.CanCollide = false
		emitterPart.CanQuery = false
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		emitter.Rate = 70
		emitter.Lifetime = NumberRange.new(1, 2)
		emitter.Speed = NumberRange.new(25, 45)
		emitter.SpreadAngle = Vector2.new(160, 160)
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 220, 120))
		emitter.Size = NumberSequence.new(0.6)
		emitter.Transparency = NumberSequence.new(0.1)
		emitter.Parent = emitterPart
		table.insert(WorldBuilder.STORM_EMITTERS, emitter)
	end

	addSign(folder, Vector3.new(82, 0, 0), "OUTER DECK", "Exposed to space — storms hit here first!", Color3.fromRGB(255, 170, 90))
end

local function buildOneModule(folder: Instance, index: number): any
	local angle = math.rad(22.5 + (index - 1) * 45)
	local center = Vector3.new(math.cos(angle) * MODULE_RADIUS, 0, math.sin(angle) * MODULE_RADIUS)
	local accent = MODULE_ACCENTS[index]
	local moduleFolder = newFolder(`Module{index}`, folder)
	local faceHub = CFrame.new(center, Vector3.new(0, 0, 0))

	-- Module floor disc + accent ring.
	local moduleFloor = flatCylinder(`Module{index}Floor`, 16, 0.6, Color3.fromRGB(235, 240, 250), 0.1, moduleFolder)
	moduleFloor.CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local ring = flatCylinder(`Module{index}Ring`, 16.6, 0.3, accent, 0.05, moduleFolder)
	ring.CFrame = CFrame.new(center + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))

	-- Three walls (back + sides); the front stays open toward the hub.
	local wallOffsets = { Vector3.new(0, 3, -15.5), Vector3.new(-15.5, 3, 0), Vector3.new(15.5, 3, 0) }
	local wallSizes = { Vector3.new(32, 6, 1.2), Vector3.new(1.2, 6, 32), Vector3.new(1.2, 6, 32) }
	for i, offset in wallOffsets do
		local wallPos = faceHub:PointToWorldSpace(offset)
		newPart(`Module{index}Wall`, "Block", wallSizes[i], Color3.fromRGB(225, 232, 245), CFrame.new(wallPos, center), moduleFolder)
	end

	-- Shield dome: invisible until the module locks or a storm hits.
	local dome = newPart(`Module{index}Dome`, "Ball", Vector3.new(36, 22, 36), accent, CFrame.new(center + Vector3.new(0, 1, 0)), moduleFolder, Enum.Material.ForceField, 1)
	dome.CanCollide = false
	dome.CanQuery = false

	-- Eight habitat pods in a 2 x 4 grid.
	local podPositions: { Vector3 } = {}
	local podIndex = 0
	for _, row in { -4, 4 } do
		for _, col in { -6, -2, 2, 6 } do
			podIndex += 1
			local podPos = faceHub:PointToWorldSpace(Vector3.new(col, 0, row))
			table.insert(podPositions, podPos)
			local platform = newPart(
				`Pod{podIndex}Platform`,
				"Cylinder",
				Vector3.new(0.7, 4.6, 4.6),
				Color3.fromRGB(200, 212, 230),
				CFrame.new(podPos + Vector3.new(0, 0.35, 0)),
				moduleFolder
			)
			platform.CFrame = CFrame.new(podPos + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0, math.rad(90))
			local glow = newPart(
				`Pod{podIndex}Glow`,
				"Cylinder",
				Vector3.new(0.25, 5.0, 5.0),
				accent,
				CFrame.new(podPos + Vector3.new(0, 0.75, 0)),
				moduleFolder,
				Enum.Material.Neon
			)
			glow.CFrame = CFrame.new(podPos + Vector3.new(0, 0.75, 0)) * CFrame.Angles(0, 0, math.rad(90))
			glow.CanCollide = false
			local glass = newPart(`Pod{podIndex}Glass`, "Ball", Vector3.new(5.2, 4.6, 5.2), Color3.fromRGB(170, 220, 255), CFrame.new(podPos + Vector3.new(0, 2.6, 0)), moduleFolder, Enum.Material.Glass, 0.78)
			glass.CanCollide = false
		end
	end

	-- Owner sign at the module entrance.
	local signPos = faceHub:PointToWorldSpace(Vector3.new(0, 0, 17))
	local signLabel = addSign(moduleFolder, signPos, `MODULE {index}`, "Unclaimed — join to claim it!", accent)

	return {
		index = index,
		center = center,
		accent = accent,
		podPositions = podPositions,
		dome = dome,
		signLabel = signLabel,
		owner = nil :: any,
	}
end

local function buildModules(folder: Instance)
	for i = 1, MODULE_COUNT do
		table.insert(WorldBuilder.MODULES, buildOneModule(folder, i))
	end
end

local function buildGarden(folder: Instance)
	local gardenFolder = newFolder("HydroponicGarden", folder)
	local gardenCenter = Vector3.new(-42, 0, -38)
	local gardenFloor = flatCylinder("GardenFloor", 19, 0.5, Color3.fromRGB(190, 225, 190), 0.1, gardenFolder)
	gardenFloor.CFrame = CFrame.new(gardenCenter + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))

	-- Six planters, each with soil and three leafy plants.
	for i = 0, 5 do
		local angle = (i / 6) * math.pi * 2
		local planterPos = gardenCenter + Vector3.new(math.cos(angle) * 11, 0, math.sin(angle) * 11)
		newPart("Planter", "Block", Vector3.new(5, 1.6, 3), Color3.fromRGB(150, 110, 70), CFrame.new(planterPos + Vector3.new(0, 0.8, 0)), gardenFolder)
		newPart("Soil", "Block", Vector3.new(4.6, 0.4, 2.6), Color3.fromRGB(90, 60, 35), CFrame.new(planterPos + Vector3.new(0, 1.7, 0)), gardenFolder)
		for j = 0, 2 do
			local plantPos = planterPos + Vector3.new(-1.5 + j * 1.5, 0, 0)
			local stem = newPart("Stem", "Cylinder", Vector3.new(1.6, 0.25, 0.25), Color3.fromRGB(60, 140, 60), CFrame.new(plantPos + Vector3.new(0, 2.6, 0)), gardenFolder)
			stem.CFrame = CFrame.new(plantPos + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
			local leaves = newPart("Leaves", "Ball", Vector3.new(1.8, 1.8, 1.8), Color3.fromRGB(80, 200, 90), CFrame.new(plantPos + Vector3.new(0, 3.9, 0)), gardenFolder)
			leaves.Name = "Leaves"
			local fruit = newPart("Fruit", "Ball", Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(255, 120, 150), CFrame.new(plantPos + Vector3.new(0.6, 3.6, 0.5)), gardenFolder)
			fruit.Name = "Fruit"
		end
	end

	-- Grow-light posts + a water tank.
	for _, side in { -1, 1 } do
		local postPos = gardenCenter + Vector3.new(side * 7, 0, -8)
		local post = newPart("GrowPost", "Cylinder", Vector3.new(7, 0.4, 0.4), Color3.fromRGB(140, 150, 170), CFrame.new(postPos + Vector3.new(0, 3.5, 0)), gardenFolder)
		post.CFrame = CFrame.new(postPos + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local lamp = newPart("GrowLamp", "Block", Vector3.new(3, 0.6, 1.2), Color3.fromRGB(255, 240, 160), CFrame.new(postPos + Vector3.new(0, 7.2, 0)), gardenFolder, Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 240, 170)
		light.Range = 22
		light.Brightness = 1.2
		light.Parent = lamp
	end
	local tank = newPart("WaterTank", "Cylinder", Vector3.new(5, 3, 3), Color3.fromRGB(140, 200, 255), CFrame.new(gardenCenter + Vector3.new(0, 2.5, 12)), gardenFolder, Enum.Material.Glass, 0.3)
	tank.CFrame = CFrame.new(gardenCenter + Vector3.new(0, 2.5, 12)) * CFrame.Angles(0, 0, math.rad(90))

	addSign(gardenFolder, gardenCenter + Vector3.new(0, 0, 20), "HYDROPONIC GARDEN", "Fresh space-greens, grown on board", Color3.fromRGB(120, 230, 130))
end

local function buildAirlock(folder: Instance)
	local airlockFolder = newFolder("Airlock", folder)
	local center = WorldBuilder.AIRLOCK_POSITION
	local airlockFloor = flatCylinder("AirlockFloor", 9, 0.5, Color3.fromRGB(210, 215, 225), 0.1, airlockFolder)
	airlockFloor.CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	for _, offset in { Vector3.new(0, 3, -8.5), Vector3.new(0, 3, 8.5), Vector3.new(8.5, 3, 0) } do
		local size = Vector3.new(18, 6, 1.2)
		if offset.X ~= 0 then
			size = Vector3.new(1.2, 6, 18)
		end
		newPart("AirlockWall", "Block", size, Color3.fromRGB(225, 232, 245), CFrame.new(center + offset), airlockFolder)
	end
	-- The round outer door ZORK sneaks through.
	local door = newPart("AirlockDoor", "Cylinder", Vector3.new(0.8, 7, 7), Color3.fromRGB(255, 150, 60), CFrame.new(center + Vector3.new(9.2, 3.5, 0)), airlockFolder, Enum.Material.Neon)
	door.CFrame = CFrame.new(center + Vector3.new(9.2, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	addSign(airlockFolder, center + Vector3.new(-4, 0, 10), "AIRLOCK", "ZORK the Snatcher sneaks in here...", Color3.fromRGB(255, 150, 90))
end

local function buildTitlePedestals(folder: Instance)
	local pedestalFolder = newFolder("TitlePedestals", folder)
	local showcase = {
		{ "Bloop Blorp", "None" },
		{ "Plasma Pingu", "None" },
		{ "Cosmo Corgi", "Gold" },
		{ "Solar Squirrel", "None" },
		{ "Pulsar Panda", "Diamond" },
		{ "Big Bang Burrito", "Cosmic" },
	} :: { { string } }
	for i, entry in showcase do
		local x = -12.5 + (i - 1) * 5
		local pedestalPos = Vector3.new(x, 0, -14)
		local pedestal = newPart(`Pedestal{i}`, "Cylinder", Vector3.new(1.4, 3.6, 3.6), Color3.fromRGB(210, 220, 235), CFrame.new(pedestalPos + Vector3.new(0, 0.7, 0)), pedestalFolder)
		pedestal.CFrame = CFrame.new(pedestalPos + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local trim = newPart(`Pedestal{i}Trim`, "Cylinder", Vector3.new(0.3, 4.0, 4.0), Color3.fromRGB(255, 170, 60), CFrame.new(pedestalPos + Vector3.new(0, 1.5, 0)), pedestalFolder, Enum.Material.Neon)
		trim.CFrame = CFrame.new(pedestalPos + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local model = BrainrotFactory.buildBrainrotModel(entry[1], entry[2], `pedestal-{i}`)
		model:SetAttribute("Animate", "Bob")
		model:PivotTo(CFrame.new(pedestalPos + Vector3.new(0, 1.6 + BrainrotFactory.getRestHeight(entry[1]), 0)))
		model.Parent = pedestalFolder
	end
end

local function buildSpaceBackdrop(folder: Instance)
	local spaceFolder = newFolder("SpaceBackdrop", folder)
	-- The planet the station orbits, with a tilted ring.
	local planet = newPart("Planet", "Ball", Vector3.new(90, 90, 90), Color3.fromRGB(80, 180, 200), CFrame.new(350, 90, -450), spaceFolder)
	planet.CanCollide = false
	planet.CanQuery = false
	local planetRing = newPart("PlanetRing", "Cylinder", Vector3.new(1.5, 140, 140), Color3.fromRGB(180, 220, 240), CFrame.new(350, 90, -450), spaceFolder, Enum.Material.SmoothPlastic, 0.4)
	planetRing.CFrame = CFrame.new(350, 90, -450) * CFrame.Angles(math.rad(70), 0, math.rad(20))
	planetRing.CanCollide = false
	planetRing.CanQuery = false

	-- Two satellites drifting near the station.
	local satelliteSpots = { Vector3.new(-210, 130, -320), Vector3.new(260, 160, 260) }
	for i, spot in satelliteSpots do
		local satFolder = newFolder(`Satellite{i}`, spaceFolder)
		local body = newPart("SatBody", "Block", Vector3.new(4, 2.5, 2.5), Color3.fromRGB(200, 205, 215), CFrame.new(spot), satFolder)
		body:SetAttribute("IsSatellite", true)
		for _, side in { -1, 1 } do
			local wing = newPart("SatWing", "Block", Vector3.new(0.3, 3, 7), Color3.fromRGB(40, 80, 160), CFrame.new(spot + Vector3.new(side * 3.6, 0, 0)), satFolder)
			wing:SetAttribute("IsSatellite", true)
		end
		local beacon = newPart("SatBeacon", "Ball", Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(255, 80, 80), CFrame.new(spot + Vector3.new(0, 2.2, 0)), satFolder, Enum.Material.Neon)
		beacon:SetAttribute("IsSatellite", true)
		satFolder:SetAttribute("IsSatellite", true)
	end
end

local function buildCrewAndRobot(folder: Instance)
	local crewFolder = newFolder("Crew", folder)
	local crew = {
		{ "CMDR. NOVA", "Station Commander", Color3.fromRGB(60, 110, 200), Color3.fromRGB(230, 190, 160), Vector3.new(14, 0, 18) },
		{ "ENG. PIXEL", "Chief Engineer", Color3.fromRGB(200, 110, 60), Color3.fromRGB(160, 110, 80), Vector3.new(-16, 0, 14) },
		{ "DR. SPROUT", "Hydroponics Lead", Color3.fromRGB(70, 170, 80), Color3.fromRGB(240, 210, 180), Vector3.new(-42, 0, -28) },
	} :: { { any } }
	for _, entry in crew do
		local npc = BrainrotFactory.buildCrewNpc(entry[1], entry[2], entry[3], entry[4])
		npc:PivotTo(CFrame.new(entry[5] :: Vector3, Vector3.new(0, 0, 0)))
		npc.Parent = crewFolder
	end

	local robot = BrainrotFactory.buildCleaningRobot()
	robot:PivotTo(CFrame.new(20, 0, -20))
	robot.Parent = crewFolder
	WorldBuilder.CLEANING_ROBOT = robot
	WorldBuilder.ROBOT_WAYPOINTS = {
		Vector3.new(20, 0, -20),
		Vector3.new(-25, 0, -25),
		Vector3.new(-30, 0, 25),
		Vector3.new(25, 0, 30),
	}
end

-- Builds the entire station. Called once by Main.server.luau before any
-- player character loads, so nobody ever spawns into an empty void.
function WorldBuilder.buildWorld()
	local folder = Workspace:FindFirstChild("Station")
	if folder then
		folder:Destroy()
	end
	folder = newFolder("Station", Workspace)
	WorldBuilder.MODULES = {}
	WorldBuilder.STORM_EMITTERS = {}

	buildHub(folder)
	buildOuterDeck(folder)
	buildModules(folder)
	buildGarden(folder)
	buildAirlock(folder)
	buildTitlePedestals(folder)
	buildSpaceBackdrop(folder)
	buildCrewAndRobot(folder)
end

-- Random spawn point for a wild brainrot: mostly the bright hub, sometimes
-- the exposed outer deck. Never inside a player module.
function WorldBuilder.getRandomWildSpawnPoint(): Vector3
	for _ = 1, 12 do
		local point: Vector3
		if rng:NextNumber() < 0.7 then
			local angle = rng:NextNumber() * math.pi * 2
			local radius = 12 + rng:NextNumber() * 52
			point = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		else
			point = WorldBuilder.getRandomOuterDeckPoint()
		end
		local insideModule = false
		for _, module in WorldBuilder.MODULES do
			local delta = point - (module.center :: Vector3)
			if Vector3.new(delta.X, 0, delta.Z).Magnitude < 19 then
				insideModule = true
				break
			end
		end
		if not insideModule then
			return point
		end
	end
	return Vector3.new(30, 0, 30)
end

-- Random point on the exposed outer deck ring (radius 80-108).
function WorldBuilder.getRandomOuterDeckPoint(): Vector3
	local angle = rng:NextNumber() * math.pi * 2
	local radius = 80 + rng:NextNumber() * 28
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- Writes the owner's name onto a module's entrance sign.
function WorldBuilder.setModuleOwner(moduleIndex: number, ownerName: string?)
	local module = WorldBuilder.MODULES[moduleIndex]
	if not module then
		return
	end
	if ownerName and ownerName ~= "" then
		module.signLabel.Text = `MODULE {moduleIndex} - {ownerName}`
	else
		module.signLabel.Text = `MODULE {moduleIndex}`
	end
end

-- Shows or hides one module's shield dome.
function WorldBuilder.setDomeVisible(moduleIndex: number, visible: boolean)
	local module = WorldBuilder.MODULES[moduleIndex]
	if not module then
		return
	end
	local dome = module.dome :: BasePart
	dome.Transparency = if visible then 0.55 else 1
end

-- Shows or hides every module dome at once (solar storm).
function WorldBuilder.setAllDomesVisible(visible: boolean)
	for i = 1, #WorldBuilder.MODULES do
		WorldBuilder.setDomeVisible(i, visible)
	end
end

-- True when a world position sits inside any module's shield dome.
function WorldBuilder.isInsideAnyDome(position: Vector3): boolean
	local safeRadius = BrainrotData.CONFIG.domeSafeRadiusStuds
	for _, module in WorldBuilder.MODULES do
		local delta = position - (module.center :: Vector3)
		if Vector3.new(delta.X, 0, delta.Z).Magnitude <= safeRadius then
			return true
		end
	end
	return false
end

return WorldBuilder
