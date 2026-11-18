--!strict
-- BrainrotFactory
-- Builds every creature in BRAINROT ORBIT from plain parts: the 30 brainrot
-- species (body + eyes + one species accessory + a floating name tag), ZORK
-- the Snatcher, the station crew NPCs, the cleaning robot and the delivery
-- drone. No meshes, no asset ids, no animation assets — everything is
-- procedural, so the place file stays small and the game runs identically in
-- Studio and live.
--
-- A brainrot model is anchored and owned by the server. Its "Animate"
-- attribute tells the client animator how to move it: "Bob" (docked or on a
-- pedestal), "Rock" (wandering wild) or "None" (carried in a cargo bubble).

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Model = any
type BasePart = any
type Color3 = any
type Vector3 = any
type ModuleScript = any

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- require is aliased so the Luau analyzer treats module loads as untyped calls;
-- at runtime this is the plain Roblox require of a ModuleScript instance.
local requireModule = require :: any
local BrainrotData = requireModule(ReplicatedStorage:WaitForChild("BrainrotData"))
local FormatUtil = requireModule(ReplicatedStorage:WaitForChild("FormatUtil"))

local BrainrotFactory = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(20, 20, 25)

-- Round 3 made brainrots bigger so they read at a glance against the grey
-- metal: every species scales 1.4x, except the ones whose body would grow
-- past ~4.5 studs and no longer fit the 5.2-wide pod glass — those cap at
-- 1.25x. getRestHeight uses the same effective scale, so pods, pedestals
-- and wild spawns all keep placing the body center at the right height.
local GLOBAL_SCALE = 1.4
local CAP_SCALE = 1.25
local MAX_BODY_STUDS = 4.5

local function effectiveScale(species: any): number
	local base = species.scale :: number
	local baseSize = if species.bodyShape == "Cylinder" then 2.6 else 2.4
	if baseSize * base * GLOBAL_SCALE > MAX_BODY_STUDS then
		return base * CAP_SCALE
	end
	return base * GLOBAL_SCALE
end

local function makePart(name: string, shape: string, size: Vector3, color: Color3, position: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType[shape]
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.Position = position
	return part
end

local function addEyes(model: Model, body: BasePart, scale: number)
	-- Two white eyes with black pupils on the front (+Z) face of the body.
	local eyeOffset = 0.55 * scale
	local eyeSize = 0.55 * scale
	local front = body.Size.Z / 2
	for _, side in { -1, 1 } do
		local eye = makePart(
			"Eye",
			"Ball",
			Vector3.new(eyeSize, eyeSize, eyeSize * 0.6),
			WHITE,
			body.Position + Vector3.new(side * eyeOffset, 0.35 * scale, front + 0.1)
		)
		eye.Parent = model
		local pupil = makePart(
			"Pupil",
			"Ball",
			Vector3.new(eyeSize * 0.45, eyeSize * 0.45, eyeSize * 0.3),
			BLACK,
			body.Position + Vector3.new(side * eyeOffset, 0.35 * scale, front + 0.32 * scale)
		)
		pupil.Parent = model
	end
end

local function addAccessory(model: Model, body: BasePart, accessory: string, accent: Color3, scale: number)
	local top = body.Position + Vector3.new(0, body.Size.Y / 2, 0)
	if accessory == "Ears" then
		for _, side in { -1, 1 } do
			local ear = makePart(
				"Ear",
				"Ball",
				Vector3.new(0.5 * scale, 0.9 * scale, 0.4 * scale),
				accent,
				top + Vector3.new(side * 0.6 * scale, 0.35 * scale, 0)
			)
			ear.Parent = model
		end
	elseif accessory == "Horns" then
		for _, side in { -1, 1 } do
			local horn = makePart(
				"Horn",
				"Cylinder",
				Vector3.new(0.9 * scale, 0.35 * scale, 0.35 * scale),
				accent,
				top + Vector3.new(side * 0.55 * scale, 0.35 * scale, 0)
			)
			horn.CFrame = CFrame.new(horn.Position) * CFrame.Angles(0, 0, side * 0.6)
			horn.Parent = model
		end
	elseif accessory == "Wings" then
		for _, side in { -1, 1 } do
			local wing = makePart(
				"Wing",
				"Block",
				Vector3.new(0.25 * scale, 1.0 * scale, 1.2 * scale),
				accent,
				body.Position + Vector3.new(side * (body.Size.X / 2 + 0.15), 0.2 * scale, 0)
			)
			wing.CFrame = CFrame.new(wing.Position) * CFrame.Angles(0, 0, side * -0.5)
			wing.Parent = model
		end
	elseif accessory == "Tail" then
		local tail = makePart(
			"Tail",
			"Ball",
			Vector3.new(0.7 * scale, 0.7 * scale, 1.4 * scale),
			accent,
			body.Position + Vector3.new(0, -0.2 * scale, -(body.Size.Z / 2 + 0.5))
		)
		tail.Parent = model
	elseif accessory == "Antenna" then
		local stalk = makePart(
			"Antenna",
			"Cylinder",
			Vector3.new(0.9 * scale, 0.12 * scale, 0.12 * scale),
			accent,
			top + Vector3.new(0, 0.4 * scale, 0)
		)
		stalk.CFrame = CFrame.new(stalk.Position) * CFrame.Angles(0, 0, math.rad(90))
		stalk.Parent = model
		local tip = makePart("AntennaTip", "Ball", Vector3.new(0.4 * scale, 0.4 * scale, 0.4 * scale), accent, top + Vector3.new(0, 0.9 * scale, 0))
		tip.Material = Enum.Material.Neon
		tip.Parent = model
	elseif accessory == "Beak" then
		local beak = makePart(
			"Beak",
			"Block",
			Vector3.new(0.7 * scale, 0.35 * scale, 0.5 * scale),
			Color3.fromRGB(255, 170, 40),
			body.Position + Vector3.new(0, -0.15 * scale, body.Size.Z / 2 + 0.2)
		)
		beak.Parent = model
	elseif accessory == "Spots" then
		for i, offset in { Vector3.new(0.5, 0.5, 0.4), Vector3.new(-0.45, -0.3, 0.5), Vector3.new(0.1, 0.7, -0.3) } do
			local spot = makePart(
				`Spot{i}`,
				"Ball",
				Vector3.new(0.5 * scale, 0.5 * scale, 0.3 * scale),
				accent,
				body.Position + offset * scale
			)
			spot.Parent = model
		end
	elseif accessory == "Ring" then
		local ring = makePart(
			"Ring",
			"Cylinder",
			Vector3.new(0.18 * scale, 3.4 * scale, 3.4 * scale),
			accent,
			body.Position
		)
		ring.CFrame = CFrame.new(ring.Position) * CFrame.Angles(0, 0, math.rad(90))
		ring.Material = Enum.Material.Neon
		ring.CanCollide = false
		ring.Parent = model
	end
end

-- Name tag: 180 px wide with a two-line name area, so even the longest
-- mutated title ("Dark Matter Donut [COSMIC]", 27 chars) wraps instead of
-- clipping. The subtitle (rate + rarity) always fits on one line.
local function addNameTag(model: Model, body: BasePart, title: string, subtitle: string, subtitleColor: Color3)
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.new(0, 180, 0, 64)
	tag.StudsOffset = Vector3.new(0, 3.4, 0)
	-- Tags only render within 45 studs: at 140 every brainrot in the hub
	-- rendered its tag at once and they piled into an unreadable wall.
	tag.MaxDistance = 45
	tag.AlwaysOnTop = false
	tag.Adornee = body

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0, 40)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = title
	nameLabel.TextColor3 = WHITE
	nameLabel.TextSize = 15
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextWrapped = true
	nameLabel.Parent = tag

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "RateLabel"
	subLabel.Position = UDim2.new(0, 0, 0, 40)
	subLabel.Size = UDim2.new(1, 0, 0, 20)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = subtitle
	subLabel.TextColor3 = subtitleColor
	subLabel.TextSize = 14
	subLabel.Font = Enum.Font.GothamBold
	subLabel.TextWrapped = true
	subLabel.Parent = tag

	tag.Parent = model
end

-- How high a brainrot's model pivot floats above the surface it stands on
-- (body radius plus a small gap), so pods, pedestals and wild spawns all
-- place the model at the right height for its species' scale.
function BrainrotFactory.getRestHeight(speciesName: string): number
	local species = BrainrotData.getSpecies(speciesName)
	if not species then
		return 1.3
	end
	return 1.3 * effectiveScale(species)
end

-- Builds one brainrot of the given species and mutation at the origin; the
-- caller moves it with :PivotTo(). The model carries IsBrainrot, SpeciesName,
-- Mutation, BrainrotId and Animate attributes for the animator and the services.
function BrainrotFactory.buildBrainrotModel(speciesName: string, mutation: string, brainrotId: string): Model
	local species = BrainrotData.getSpecies(speciesName)
	assert(species ~= nil, `[BrainrotFactory] unknown species {speciesName}`)
	local data = species :: any
	local scale = effectiveScale(data)

	local bodyColor = data.bodyColor :: Color3
	local material = Enum.Material.SmoothPlastic
	if mutation == "Gold" then
		bodyColor = Color3.fromRGB(255, 210, 60)
	elseif mutation == "Diamond" then
		bodyColor = Color3.fromRGB(190, 235, 255)
		material = Enum.Material.Glass
	elseif mutation == "Irradiated" then
		bodyColor = Color3.fromRGB(140, 255, 100)
		material = Enum.Material.Neon
	elseif mutation == "Cosmic" then
		bodyColor = Color3.fromRGB(230, 110, 255)
		material = Enum.Material.Neon
	end

	local model = Instance.new("Model")
	model.Name = data.name

	local bodySize: Vector3
	if data.bodyShape == "Block" then
		bodySize = Vector3.new(2.4 * scale, 2.0 * scale, 2.2 * scale)
	elseif data.bodyShape == "Cylinder" then
		bodySize = Vector3.new(2.6 * scale, 2.0 * scale, 2.0 * scale)
	else
		bodySize = Vector3.new(2.4 * scale, 2.4 * scale, 2.4 * scale)
	end
	local body = makePart("Body", data.bodyShape, bodySize, bodyColor, Vector3.new(0, 1.6 * scale, 0))
	body.Material = material
	body.Parent = model
	model.PrimaryPart = body

	addEyes(model, body, scale)
	-- Every species gets a silhouette accessory. One species ships with
	-- "None" in the data; the factory gives it spots (marshmallow bits on
	-- a s'more) instead of leaving it bare. The data itself is untouched.
	local accessory = data.accessory :: string
	if accessory == "None" then
		accessory = "Spots"
	end
	addAccessory(model, body, accessory, data.accentColor, scale)

	-- Glow rings sit just above the floor the brainrot stands on. The
	-- model's pivot is the body center, so the ring's height in model
	-- space is 0.3 + 0.3 * scale — the old fixed 0.1 put the ring under
	-- the floor for every species. Diameters cap at 4.8 so the rings stay
	-- inside the pod's own 5.0 glow ring when docked. The mutation ring
	-- sits 0.12 above the rarity ring (it is the smaller disc), so the
	-- two never z-fight when both are present.
	local ringY = 0.3 + 0.3 * scale
	local function addGlowRing(name: string, diameter: number, color: Color3, yOffset: number)
		local ring = makePart(
			name,
			"Cylinder",
			Vector3.new(0.2, math.min(diameter, 4.8), math.min(diameter, 4.8)),
			color,
			Vector3.new(0, ringY + yOffset, 0)
		)
		ring.CFrame = CFrame.new(ring.Position) * CFrame.Angles(0, 0, math.rad(90))
		ring.Material = Enum.Material.Neon
		ring.CanCollide = false
		ring.Parent = model
	end

	-- A glowing ring under mutated brainrots so the mutation reads at a glance.
	if mutation ~= "None" then
		addGlowRing("MutationRing", 3.2 * scale, BrainrotData.MUTATION_COLORS[mutation], 0.12)
	end

	-- A rarity glow under Epic, Legendary and Secret brainrots, in the
	-- rarity color, so the valuable ones stand out across the deck.
	local rarityRingSize: { [string]: number } = { Epic = 3.4, Legendary = 3.8, Secret = 4.2 }
	local raritySize = rarityRingSize[data.rarity]
	if raritySize then
		addGlowRing("RarityRing", raritySize * scale, BrainrotData.RARITY_COLORS[data.rarity], 0)
	end

	local rate = BrainrotData.getRate(data.name, mutation)
	local title = data.name
	if mutation ~= "None" then
		title = `{data.name} [{string.upper(mutation)}]`
	end
	local subtitle = `{FormatUtil.formatRate(rate)} - {data.rarity}`
	addNameTag(model, body, title, subtitle, BrainrotData.RARITY_COLORS[data.rarity])

	model:SetAttribute("IsBrainrot", true)
	model:SetAttribute("SpeciesName", data.name)
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("BrainrotId", brainrotId)
	model:SetAttribute("Animate", "Rock")
	return model
end

-- Builds ZORK the Snatcher: a lanky green alien thief with huge eyes.
function BrainrotFactory.buildZorkModel(): Model
	local model = Instance.new("Model")
	model.Name = "ZORK the Snatcher"

	local torso = makePart("Torso", "Block", Vector3.new(2.0, 2.2, 1.2), Color3.fromRGB(90, 200, 90), Vector3.new(0, 2.4, 0))
	torso.Parent = model
	model.PrimaryPart = torso

	local head = makePart("Head", "Ball", Vector3.new(2.4, 2.0, 2.0), Color3.fromRGB(120, 230, 110), Vector3.new(0, 4.4, 0))
	head.Parent = model
	for _, side in { -1, 1 } do
		local eye = makePart("Eye", "Ball", Vector3.new(0.7, 0.9, 0.4), BLACK, head.Position + Vector3.new(side * 0.55, 0.15, 0.95))
		eye.Parent = model
		local arm = makePart("Arm", "Block", Vector3.new(0.5, 2.0, 0.5), Color3.fromRGB(90, 200, 90), torso.Position + Vector3.new(side * 1.35, -0.2, 0))
		arm.Parent = model
		local leg = makePart("Leg", "Block", Vector3.new(0.6, 1.4, 0.6), Color3.fromRGB(60, 140, 60), Vector3.new(side * 0.55, 0.7, 0))
		leg.Parent = model
		local antenna = makePart("Antenna", "Cylinder", Vector3.new(1.0, 0.12, 0.12), Color3.fromRGB(90, 200, 90), head.Position + Vector3.new(side * 0.5, 1.3, 0))
		antenna.CFrame = CFrame.new(antenna.Position) * CFrame.Angles(0, 0, side * 0.4)
		antenna.Parent = model
	end
	local sack = makePart("LootSack", "Ball", Vector3.new(1.4, 1.4, 1.4), Color3.fromRGB(150, 110, 60), torso.Position + Vector3.new(0, 0.4, -1.0))
	sack.Parent = model

	addNameTag(model, torso, "ZORK the Snatcher", "Bonk him 3x with [F]!", Color3.fromRGB(255, 90, 90))
	model:SetAttribute("IsZork", true)
	return model
end

-- Builds one station crew NPC: a simple blocky crewmate with a name tag.
-- NPCs are set dressing with a job title; they stand at their post and make
-- the station feel crewed. Client animator gives them a gentle idle sway.
function BrainrotFactory.buildCrewNpc(name: string, role: string, uniformColor: Color3, skinColor: Color3): Model
	local model = Instance.new("Model")
	model.Name = name

	local torso = makePart("Torso", "Block", Vector3.new(2.0, 2.0, 1.0), uniformColor, Vector3.new(0, 2.6, 0))
	torso.Parent = model
	model.PrimaryPart = torso

	local head = makePart("Head", "Ball", Vector3.new(1.5, 1.5, 1.5), skinColor, Vector3.new(0, 4.3, 0))
	head.Parent = model
	local helmet = makePart("Helmet", "Ball", Vector3.new(1.9, 1.9, 1.9), Color3.fromRGB(220, 230, 245), Vector3.new(0, 4.5, 0))
	helmet.Transparency = 0.45
	helmet.CanCollide = false
	helmet.Parent = model
	for _, side in { -1, 1 } do
		local arm = makePart("Arm", "Block", Vector3.new(0.55, 1.9, 0.55), uniformColor, torso.Position + Vector3.new(side * 1.35, 0, 0))
		arm.Parent = model
		local leg = makePart("Leg", "Block", Vector3.new(0.65, 1.6, 0.65), Color3.fromRGB(50, 55, 70), Vector3.new(side * 0.55, 0.8, 0))
		leg.Parent = model
	end

	addNameTag(model, torso, name, role, Color3.fromRGB(150, 220, 255))
	model:SetAttribute("IsCrewNpc", true)
	model:SetAttribute("Animate", "Sway")
	return model
end

-- Builds the cleaning robot that patrols the observation deck.
function BrainrotFactory.buildCleaningRobot(): Model
	local model = Instance.new("Model")
	model.Name = "MOP-BOT"

	local body = makePart("Body", "Cylinder", Vector3.new(1.2, 2.2, 2.2), Color3.fromRGB(200, 210, 225), Vector3.new(0, 0.8, 0))
	body.CFrame = CFrame.new(body.Position) * CFrame.Angles(0, 0, math.rad(90))
	body.Parent = model
	model.PrimaryPart = body

	local dome = makePart("Dome", "Ball", Vector3.new(1.4, 1.0, 1.4), Color3.fromRGB(120, 200, 255), Vector3.new(0, 1.7, 0))
	dome.Material = Enum.Material.Glass
	dome.Parent = model
	local brush = makePart("Brush", "Cylinder", Vector3.new(0.3, 2.6, 2.6), Color3.fromRGB(90, 200, 120), Vector3.new(0, 0.25, 0))
	brush.CFrame = CFrame.new(brush.Position) * CFrame.Angles(0, 0, math.rad(90))
	brush.Parent = model
	local light = makePart("Light", "Ball", Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(255, 220, 80), Vector3.new(0, 2.3, 0))
	light.Material = Enum.Material.Neon
	light.Parent = model

	addNameTag(model, body, "MOP-BOT", "Cleaning the deck...", Color3.fromRGB(150, 220, 150))
	model:SetAttribute("IsRobot", true)
	return model
end

-- Builds the delivery drone that hovers between the hub, the garden and the
-- airlock, ferrying supply crates. Server-patrolled like MOP-BOT; its
-- thrusters glow so it reads at a glance in the bright deck.
function BrainrotFactory.buildDeliveryDrone(): Model
	local model = Instance.new("Model")
	model.Name = "DELIVERY DRONE"

	local body = makePart("Body", "Block", Vector3.new(2.6, 1.0, 1.8), Color3.fromRGB(230, 120, 60), Vector3.new(0, 0, 0))
	body.Parent = model
	model.PrimaryPart = body

	local crate = makePart("Crate", "Block", Vector3.new(1.6, 1.2, 1.4), Color3.fromRGB(200, 170, 110), Vector3.new(0, -1.1, 0))
	crate.Parent = model
	local eye = makePart("Eye", "Ball", Vector3.new(0.7, 0.7, 0.4), Color3.fromRGB(120, 220, 255), Vector3.new(0, 0.1, 0.95))
	eye.Material = Enum.Material.Neon
	eye.Parent = model
	for _, side in { -1, 1 } do
		local rotor = makePart("Rotor", "Cylinder", Vector3.new(0.12, 1.6, 1.6), Color3.fromRGB(80, 90, 110), Vector3.new(side * 1.9, 0.6, 0))
		rotor.CFrame = CFrame.new(rotor.Position) * CFrame.Angles(0, 0, math.rad(90))
		rotor.CanCollide = false
		rotor.Parent = model
		local thruster = makePart("Thruster", "Ball", Vector3.new(0.5, 0.5, 0.5), Color3.fromRGB(120, 200, 255), Vector3.new(side * 1.2, -0.6, -0.8))
		thruster.Material = Enum.Material.Neon
		thruster.CanCollide = false
		thruster.Parent = model
	end
	local beacon = makePart("Beacon", "Ball", Vector3.new(0.35, 0.35, 0.35), Color3.fromRGB(255, 90, 90), Vector3.new(0, 0.7, 0))
	beacon.Material = Enum.Material.Neon
	beacon.Parent = model

	addNameTag(model, body, "DELIVERY DRONE", "Supplies for the modules!", Color3.fromRGB(255, 200, 140))
	model:SetAttribute("IsRobot", true)
	return model
end

return BrainrotFactory
