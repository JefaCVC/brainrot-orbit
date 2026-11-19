--!strict
-- WorldBuilder
-- Builds the whole BRAINROT ORBIT station at runtime, from plain parts: an
-- ENCLOSED industrial spaceship interior (grey metal floors, walls and
-- ceiling, orange ceiling pipes, hazard trim, colored console buttons, wall
-- screens and neon accent lights), eight player modules with tiered habitat
-- pods and shield domes, a hydroponic garden, an airlock, a showcase stage
-- with climbing rarity pedestals, five crew NPCs, a cleaning robot, a
-- delivery drone, control consoles with blinking lights, yellow supply
-- crates, dense colorful props, a docked shuttle, and the space backdrop
-- (planets, moon, satellites, stars, nebulae, a comet) visible through the
-- windows and the ceiling skylight. Round 5 pushes the color further: each
-- area has its own saturated accent, neon trim and point lights are
-- everywhere, and Bloom + ColorCorrection (Saturation +0.25) lift the
-- whole world. The station stays BRIGHT — dark space stays outside.
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

local Lighting = game:GetService("Lighting")
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
WorldBuilder.DELIVERY_DRONE = nil :: Model?
WorldBuilder.DRONE_WAYPOINTS = {} :: { Vector3 }
WorldBuilder.CONSOLE_LIGHTS = {} :: { BasePart }

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

-- Per-area station colors (round 5): each deck area gets its own saturated
-- accent, used in its gate lamps, signs and trim — like the reference
-- game's color-coded zones, so a player always knows where they stand.
local AREA_COLORS = {
	hub = Color3.fromRGB(60, 220, 220),
	garden = Color3.fromRGB(90, 220, 120),
	airlock = Color3.fromRGB(255, 150, 60),
	outer = Color3.fromRGB(255, 170, 60),
} :: { [string]: Color3 }

local rng = Random.new()

-- Warm interior light against cool dark space. This overrides the bright
-- flat values in default.project.json (Ambient 0.72+ with no sun is what
-- washed the round 2 hub out to pale blue-grey). Fog is pushed far out so
-- the starfield shell at radius 900-1200 never fades. ClockTime stays 0
-- (night): the project's Sky has no textures, so it renders the default
-- time-of-day sky — a daytime ClockTime would turn the space outside the
-- windows bright blue and hide every star. StormService snapshots these
-- values at storm start and restores them, so this stays compatible.
local function configureLighting()
	Lighting.Ambient = Color3.fromRGB(105, 105, 115)
	Lighting.OutdoorAmbient = Color3.fromRGB(25, 30, 55)
	Lighting.Brightness = 3
	Lighting.ClockTime = 0
	Lighting.FogColor = Color3.fromRGB(8, 10, 24)
	Lighting.FogStart = 2000
	Lighting.FogEnd = 10000
	-- Round 5: Bloom makes every Neon glow, ColorCorrection lifts the
	-- saturation of the whole world by +0.25, SunRays adds a soft halo.
	-- Old effects are removed first so a rebuild never stacks them.
	for _, name in { "OrbitBloom", "OrbitColorCorrection", "OrbitSunRays" } do
		local existing = Lighting:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "OrbitBloom"
	bloom.Intensity = 0.7
	bloom.Size = 28
	bloom.Threshold = 0.92
	bloom.Parent = Lighting
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "OrbitColorCorrection"
	correction.Saturation = 0.25
	correction.Contrast = 0.08
	correction.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Name = "OrbitSunRays"
	rays.Intensity = 0.06
	rays.Parent = Lighting
end

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

-- A flat ring on the floor (or ceiling) built from small boxes along a
-- circle — a real torus is not available, and this reads as one from any
-- play distance. Segments are non-collide floor/ceiling dressing.
local function flatRingSegments(
	folder: Instance,
	name: string,
	radius: number,
	y: number,
	count: number,
	height: number,
	depth: number,
	color: Color3,
	material: any?
)
	local chord = 2 * radius * math.sin(math.pi / count)
	for i = 0, count - 1 do
		local theta = ((i + 0.5) / count) * math.pi * 2
		local pos = Vector3.new(math.cos(theta) * radius, y, math.sin(theta) * radius)
		local segment = newPart(
			name,
			"Block",
			Vector3.new(chord + 0.15, height, depth),
			color,
			CFrame.new(pos) * CFrame.Angles(0, -(theta + math.pi / 2), 0),
			folder,
			material
		)
		segment.CanCollide = false
	end
end

-- Station sign: a pole, a dark board and a BillboardGui tag. The tag is
-- 280 px wide with a two-line subtitle area, so every title and subtitle
-- fits without clipping (the longest title, "HYDROPONIC GARDEN", is ~195 px
-- at 18 pt bold; the longest subtitle wraps cleanly into its 44 px area).
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
	tag.Size = UDim2.new(0, 280, 0, 84)
	tag.StudsOffset = Vector3.new(0, 5.6, 0)
	tag.AlwaysOnTop = false
	tag.Adornee = pole
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 30)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = title
	titleLabel.TextColor3 = accent
	titleLabel.TextSize = 18
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextWrapped = true
	titleLabel.Parent = tag
	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "Subtitle"
	subLabel.Position = UDim2.new(0, 0, 0, 32)
	subLabel.Size = UDim2.new(1, 0, 0, 44)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = subtitle
	subLabel.TextColor3 = Color3.fromRGB(220, 230, 245)
	subLabel.TextSize = 14
	subLabel.Font = Enum.Font.Gotham
	subLabel.TextWrapped = true
	subLabel.Parent = tag
	tag.Parent = parent
	return titleLabel
end

-- A zone-gate banner on both faces of a beam part: TextScaled LuckiestGuy
-- text in the area color, so the gate reads from either side. The text
-- can never overflow: TextScaled shrinks it to the 400x60 canvas.
local function addGateBanner(beam: BasePart, text: string, color: Color3)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local surface = Instance.new("SurfaceGui")
		surface.Name = "GateBanner"
		surface.Face = face
		surface.CanvasSize = Vector2.new(400, 60)
		surface.AlwaysOnTop = false
		surface.Adornee = beam
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextColor3 = color
		label.Font = Enum.Font.LuckiestGuy
		label.TextScaled = true
		label.TextStrokeColor3 = Color3.fromRGB(20, 16, 16)
		label.TextStrokeTransparency = 0.1
		label.Parent = surface
		surface.Parent = beam
	end
end

-- One control console: a grey metal base, a tilted neon screen, a light
-- strip that the blink loop toggles, and a button panel with colored
-- buttons and two levers — the classic spaceship bridge control, and the
-- main source of small bright color on the deck.
local function buildConsole(folder: Instance, position: Vector3, screenColor: Color3, lightColor: Color3)
	local facing = CFrame.new(position, Vector3.new(0, 0, 0))
	newPart("ConsoleBase", "Block", Vector3.new(4.5, 2.2, 2.2), Color3.fromRGB(140, 145, 155), facing * CFrame.new(0, 1.1, 0), folder)
	local screen = newPart(
		"ConsoleScreen",
		"Block",
		Vector3.new(3.8, 2.2, 0.3),
		screenColor,
		facing * CFrame.new(0, 3.2, 0.4) * CFrame.Angles(math.rad(-20), 0, 0),
		folder,
		Enum.Material.Neon
	)
	screen.CanCollide = false
	local light = newPart(
		"ConsoleLight",
		"Block",
		Vector3.new(3.8, 0.35, 0.35),
		lightColor,
		facing * CFrame.new(0, 2.35, 1.0),
		folder,
		Enum.Material.Neon
	)
	light.CanCollide = false
	table.insert(WorldBuilder.CONSOLE_LIGHTS, light)

	-- Button panel on the base top: a plate, eight colored buttons in two
	-- rows, and two levers with colored knobs.
	newPart("ButtonPlate", "Block", Vector3.new(3.8, 0.15, 1.4), Color3.fromRGB(70, 75, 85), facing * CFrame.new(0, 2.25, -0.4), folder)
	local buttonColors = {
		Color3.fromRGB(255, 80, 80),
		Color3.fromRGB(80, 140, 255),
		Color3.fromRGB(90, 220, 120),
		Color3.fromRGB(255, 215, 60),
		Color3.fromRGB(255, 120, 200),
	} :: { Color3 }
	for row = 0, 1 do
		for col = 0, 3 do
			local button = newPart(
				"ConsoleButton",
				"Cylinder",
				Vector3.new(0.12, 0.35, 0.35),
				buttonColors[((row * 4 + col) % 5) + 1],
				facing * CFrame.new(-1.35 + col * 0.9, 2.4, -0.8 + row * 0.7),
				folder,
				Enum.Material.Neon
			)
			button.CFrame = facing * CFrame.new(-1.35 + col * 0.9, 2.4, -0.8 + row * 0.7) * CFrame.Angles(0, 0, math.rad(90))
			button.CanCollide = false
		end
	end
	for _, side in { -1, 1 } do
		local lever = newPart(
			"ConsoleLever",
			"Cylinder",
			Vector3.new(0.9, 0.12, 0.12),
			Color3.fromRGB(180, 185, 195),
			facing * CFrame.new(side * 1.8, 2.65, 0.15),
			folder
		)
		lever.CFrame = facing * CFrame.new(side * 1.8, 2.65, 0.15) * CFrame.Angles(0, 0, math.rad(90))
		lever.CanCollide = false
		local knob = newPart(
			"LeverKnob",
			"Ball",
			Vector3.new(0.35, 0.35, 0.35),
			if side < 0 then Color3.fromRGB(255, 80, 80) else Color3.fromRGB(255, 215, 60),
			facing * CFrame.new(side * 1.8, 3.15, 0.15),
			folder,
			Enum.Material.Neon
		)
		knob.CanCollide = false
	end
end

local function buildHub(folder: Instance)
	-- One big dark grey metal floor for the whole station, hub + outer
	-- deck. The pale blue-white floor is gone: grey metal is the base and
	-- the color comes from the lanes, the emblem and the lights.
	local floor = flatCylinder("StationFloor", 115, 2, Color3.fromRGB(100, 105, 115), -1, folder)
	floor.Material = Enum.Material.SmoothPlastic
	-- Concentric deck discs in tonal greys, so the floor still reads as
	-- panelled metal instead of one flat slab.
	flatCylinder("DeckRing1", 68, 0.25, Color3.fromRGB(115, 120, 130), 0.1, folder)
	flatCylinder("DeckRing2", 50, 0.25, Color3.fromRGB(90, 95, 105), 0.18, folder)
	flatCylinder("DeckRing3", 30, 0.25, Color3.fromRGB(125, 130, 140), 0.26, folder)
	local emblem = flatCylinder("CenterEmblem", 7, 0.3, Color3.fromRGB(255, 170, 60), 0.34, folder)
	emblem.Material = Enum.Material.Neon

	-- Eight radial guide lanes, one per module in its accent color, from
	-- the center emblem out to the hub wall. They tell a new player which
	-- way their module is before they read any sign.
	for i = 1, MODULE_COUNT do
		local angle = math.rad(22.5 + (i - 1) * 45)
		local lane = newPart(
			`GuideLane{i}`,
			"Block",
			Vector3.new(65, 0.1, 1.2),
			MODULE_ACCENTS[i],
			CFrame.new(Vector3.new(math.cos(angle) * 40.5, 0.42, math.sin(angle) * 40.5)) * CFrame.Angles(0, -angle, 0),
			folder,
			Enum.Material.Neon
		)
		lane.CanCollide = false
	end

	-- Dark panel-seam rings and a glowing amber base strip at the wall
	-- foot, so the metal deck reads as bolted plates, not a plain disc.
	flatRingSegments(folder, "PanelSeam", 40, 0.36, 24, 0.15, 0.8, Color3.fromRGB(55, 60, 70))
	flatRingSegments(folder, "PanelSeam", 60, 0.28, 24, 0.15, 0.8, Color3.fromRGB(55, 60, 70))
	flatRingSegments(folder, "PanelSeam", 85, 0.1, 24, 0.15, 0.8, Color3.fromRGB(55, 60, 70))
	flatRingSegments(folder, "BaseStrip", 73.8, 0.25, 32, 0.4, 0.8, Color3.fromRGB(255, 170, 60), Enum.Material.Neon)

	-- Floor grating: two patches of long dark slats between the guide
	-- lanes, like the deck plates of a working spaceship corridor.
	local gratingSpots = {
		{ Vector3.new(17.7, 0.4, 17.7), math.rad(-45) },
		{ Vector3.new(-32, 0.4, 0), math.rad(180) },
	} :: { { any } }
	for _, spot in gratingSpots do
		local center = spot[1] :: Vector3
		local yaw = spot[2] :: number
		-- Perpendicular to the slat's long axis, so the slats sit side by
		-- side instead of end to end.
		local across = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
		for j = 0, 5 do
			local slat = newPart(
				"GratingSlat",
				"Block",
				Vector3.new(12, 0.15, 0.8),
				Color3.fromRGB(55, 60, 70),
				CFrame.new(center + across * ((j - 2.5) * 1.6)) * CFrame.Angles(0, yaw, 0),
				folder
			)
			slat.CanCollide = false
		end
	end

	-- Window wall: 24 panels around the hub, alternating solid grey metal
	-- and near-clear glass. Four gaps (N/E/S/W) are round doorways with
	-- yellow-black hazard trim to the outer deck.
	local stripColors = {
		Color3.fromRGB(60, 220, 220),
		Color3.fromRGB(255, 110, 200),
		Color3.fromRGB(255, 215, 60),
		Color3.fromRGB(255, 160, 60),
	} :: { Color3 }
	local screenPanels: { [number]: Color3 } = {
		[2] = Color3.fromRGB(255, 70, 70),
		[10] = Color3.fromRGB(80, 220, 255),
		[14] = Color3.fromRGB(90, 230, 130),
		[22] = Color3.fromRGB(255, 110, 200),
	}
	for i = 0, 23 do
		local angle = (i / 24) * math.pi * 2
		local isDoorGap = (i % 6) == 0
		if isDoorGap then
			-- Round doorway: a ring of 12 small boxes alternating yellow
			-- and black, framing the gap. Frame only — every segment is
			-- non-collide so the opening stays fully walkable.
			local doorPos = Vector3.new(math.cos(angle) * 75, 0, math.sin(angle) * 75)
			local doorCf = CFrame.new(doorPos, Vector3.new(0, 0, 0))
			for s = 0, 11 do
				local phi = (s / 12) * math.pi * 2
				local segment = newPart(
					"DoorRing",
					"Block",
					Vector3.new(2.6, 1.0, 1.2),
					if s % 2 == 0 then Color3.fromRGB(255, 200, 40) else Color3.fromRGB(30, 30, 35),
					doorCf * CFrame.new(math.cos(phi) * 5, 5 + math.sin(phi) * 5, 0) * CFrame.Angles(0, 0, phi + math.rad(90)),
					folder
				)
				segment.CanCollide = false
			end
			-- Yellow-black hazard tape across the threshold, just inside
			-- the doorway.
			for s = 0, 5 do
				local stripe = newPart(
					"ThresholdStripe",
					"Block",
					Vector3.new(1.8, 0.15, 1.2),
					if s % 2 == 0 then Color3.fromRGB(255, 200, 40) else Color3.fromRGB(30, 30, 35),
					doorCf * CFrame.new(-4.5 + s * 1.8, 0.3, -3),
					folder
				)
				stripe.CanCollide = false
			end
			-- Zone gate: two pillars with neon lamps in the area color,
			-- plus a banner beam above the ring naming where the doorway
			-- leads. The east gap (i == 0) leads to the airlock; the other
			-- three open onto the outer deck. The beam hangs at y=11 in
			-- front of the rim panel, clear of the ring's top (y=10).
			local gateColor = if i == 0 then AREA_COLORS.airlock else AREA_COLORS.outer
			local gateText = if i == 0 then "AIRLOCK" else "OUTER DECK"
			for _, side in { -1, 1 } do
				newPart("GatePillar", "Block", Vector3.new(1.2, 10, 1.2), Color3.fromRGB(140, 145, 155), doorCf * CFrame.new(side * 5.8, 5, 0), folder)
				local lamp = newPart(
					"GateLamp",
					"Ball",
					Vector3.new(1.4, 1.4, 1.4),
					gateColor,
					doorCf * CFrame.new(side * 5.8, 10.6, 0),
					folder,
					Enum.Material.Neon
				)
				lamp.CanCollide = false
				local lampLight = Instance.new("PointLight")
				lampLight.Color = gateColor
				lampLight.Range = 14
				lampLight.Brightness = 1.2
				lampLight.Parent = lamp
			end
			local beam = newPart(
				"GateBeam",
				"Block",
				Vector3.new(12, 1.8, 0.5),
				Color3.fromRGB(30, 35, 45),
				doorCf * CFrame.new(0, 11, -1.2),
				folder
			)
			beam.CanCollide = false
			local beamTrim = newPart(
				"GateBeamTrim",
				"Block",
				Vector3.new(12, 0.3, 0.6),
				gateColor,
				doorCf * CFrame.new(0, 10, -1.2),
				folder,
				Enum.Material.Neon
			)
			beamTrim.CanCollide = false
			addGateBanner(beam, gateText, gateColor)
		else
			local panelPos = Vector3.new(math.cos(angle) * 75, 5, math.sin(angle) * 75)
			local panelCf = CFrame.new(panelPos, Vector3.new(0, 5, 0))
			if i % 2 == 0 then
				newPart("WallPanel", "Block", Vector3.new(19.5, 10, 1.5), Color3.fromRGB(150, 155, 165), panelCf, folder)
				-- Neon accent strip along the top edge of every solid panel.
				local strip = newPart(
					"WallStrip",
					"Block",
					Vector3.new(19.5, 0.5, 0.4),
					stripColors[(math.floor(i / 2) % 4) + 1],
					panelCf * CFrame.new(0, 4.7, -0.85),
					folder,
					Enum.Material.Neon
				)
				strip.CanCollide = false
				-- Tilted glowing wall screen on four of the panels.
				local screenColor = screenPanels[i]
				if screenColor then
					local screen = newPart(
						"WallScreen",
						"Block",
						Vector3.new(6, 3.5, 0.3),
						screenColor,
						panelCf * CFrame.new(0, 0, -1.0) * CFrame.Angles(math.rad(15), 0, 0),
						folder,
						Enum.Material.Neon
					)
					screen.CanCollide = false
				end
				-- Paired vertical conduit pipes on two panels.
				if i == 4 or i == 16 then
					for _, side in { -1, 1 } do
						local pipe = newPart(
							"WallPipe",
							"Cylinder",
							Vector3.new(9, 0.5, 0.5),
							Color3.fromRGB(120, 125, 135),
							panelCf * CFrame.new(side * 3, 0, -1.0),
							folder
						)
						pipe.CFrame = panelCf * CFrame.new(side * 3, 0, -1.0) * CFrame.Angles(0, 0, math.rad(90))
					end
				end
				-- Vent slats on two panels.
				if i == 8 or i == 20 then
					for j = 0, 4 do
						newPart(
							"VentSlat",
							"Block",
							Vector3.new(4, 0.25, 0.2),
							Color3.fromRGB(40, 45, 55),
							panelCf * CFrame.new(0, -1.4 + j * 0.7, -0.85),
							folder
						)
					end
				end
			else
				local window = newPart(
					"WindowPanel",
					"Block",
					Vector3.new(19.5, 10, 0.6),
					Color3.fromRGB(200, 232, 255),
					panelCf,
					folder,
					Enum.Material.Glass,
					0.65
				)
				window.CanCollide = true
			end
		end
	end

	-- Curved conduit along the hub wall base, with red dashes: segmented
	-- cylinders following the wall circle. Non-collide, so it never blocks
	-- the doorways it crosses.
	for i = 0, 15 do
		local theta = ((i + 0.5) / 16) * math.pi * 2
		local yaw = -(theta + math.pi / 2)
		local pipe = newPart(
			"BasePipe",
			"Cylinder",
			Vector3.new(28.5, 0.8, 0.8),
			Color3.fromRGB(110, 115, 125),
			CFrame.new(Vector3.new(math.cos(theta) * 73, 1.2, math.sin(theta) * 73)) * CFrame.Angles(0, yaw, 0),
			folder
		)
		pipe.CanCollide = false
		local dash = newPart(
			"PipeDash",
			"Block",
			Vector3.new(1.2, 0.25, 0.5),
			Color3.fromRGB(255, 70, 70),
			CFrame.new(Vector3.new(math.cos(theta) * 73, 1.7, math.sin(theta) * 73)) * CFrame.Angles(0, yaw, 0),
			folder,
			Enum.Material.Neon
		)
		dash.CanCollide = false
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

	-- Six control consoles around the deck, each with a blinking light strip.
	local consoleColors = {
		{ Color3.fromRGB(90, 180, 255), Color3.fromRGB(255, 200, 60) },
		{ Color3.fromRGB(120, 230, 160), Color3.fromRGB(255, 120, 120) },
		{ Color3.fromRGB(200, 140, 255), Color3.fromRGB(120, 220, 255) },
		{ Color3.fromRGB(255, 180, 110), Color3.fromRGB(140, 255, 160) },
		{ Color3.fromRGB(90, 200, 255), Color3.fromRGB(255, 110, 200) },
		{ Color3.fromRGB(255, 190, 80), Color3.fromRGB(90, 220, 200) },
	} :: { { Color3 } }
	local consoleAngles = { 45, 135, 225, 315, 0, 180 } :: { number }
	for i, angleDeg in consoleAngles do
		local angle = math.rad(angleDeg)
		local pos = Vector3.new(math.cos(angle) * 40, 0, math.sin(angle) * 40)
		buildConsole(folder, pos, consoleColors[i][1], consoleColors[i][2])
	end

	addSign(folder, Vector3.new(0, 0, 24), "OBSERVATION DECK", "Catch brainrots with your tractor beam [E]", Color3.fromRGB(120, 200, 255))
end

-- The ceiling that turns the open disc into a station interior: a dark
-- metal disc at y=14 with a rim ring closing the gap above the 10-tall
-- walls, neon accent rings, radial beams, orange ceiling pipes, a glass
-- skylight with a neon ring, hanging light fixtures and red accent lights
-- on the rim. The drone (y=8) and the lamp heads (y=9.2) clear all of it.
local function buildCeiling(folder: Instance)
	local ceilingFolder = newFolder("Ceiling", folder)
	local darkMetal = Color3.fromRGB(60, 65, 75)

	-- The disc itself.
	flatCylinder("CeilingDisc", 76, 0.6, darkMetal, 14, ceilingFolder)

	-- Rim ring, y=10 to 14, aligned with the 24 wall panels. Door gaps
	-- get a dark panel plus an amber strip along its bottom edge.
	for i = 0, 23 do
		local angle = (i / 24) * math.pi * 2
		local isDoorGap = (i % 6) == 0
		local rimPos = Vector3.new(math.cos(angle) * 75, 12, math.sin(angle) * 75)
		local rimCf = CFrame.new(rimPos, Vector3.new(0, 12, 0))
		if isDoorGap then
			newPart("RimPanel", "Block", Vector3.new(11.5, 4, 1.5), darkMetal, rimCf, ceilingFolder)
			local strip = newPart(
				"RimStrip",
				"Block",
				Vector3.new(11.5, 0.6, 0.4),
				Color3.fromRGB(255, 170, 60),
				rimCf * CFrame.new(0, -1.6, -0.9),
				ceilingFolder,
				Enum.Material.Neon
			)
			strip.CanCollide = false
		else
			newPart("RimPanel", "Block", Vector3.new(19.5, 4, 1.5), darkMetal, rimCf, ceilingFolder)
		end
	end

	-- Concentric neon accent rings. Each ring is a neon disc with a dark
	-- disc over its center, leaving a glowing annulus. The rings step down
	-- toward the middle (innermost lowest) so no cover disc hides the ring
	-- inside it — from below the ceiling reads as dark metal with three
	-- smooth glowing rings.
	local ringColors = {
		Color3.fromRGB(60, 220, 220),
		Color3.fromRGB(255, 110, 200),
		Color3.fromRGB(255, 215, 60),
	} :: { Color3 }
	local ringRadii = { 30, 50, 70 } :: { number }
	for i, radius in ringRadii do
		local neonY = 13.5 + (i - 1) * 0.1
		local neon = flatCylinder("CeilingRing", radius, 0.15, ringColors[i], neonY, ceilingFolder)
		neon.Material = Enum.Material.Neon
		flatCylinder("CeilingRingCover", radius - 1, 0.15, darkMetal, neonY - 0.05, ceilingFolder)
	end

	-- Central skylight: a glass disc with a cyan neon ring, hung just
	-- below the innermost cover disc, with a warm light under it so it
	-- reads as light coming in from above. (A real hole through the disc
	-- is not possible with flat cylinders, so the skylight is a fixture
	-- on the ceiling's underside rather than an opening.)
	local skyNeon = flatCylinder("SkylightRing", 13, 0.15, Color3.fromRGB(60, 220, 220), 13.4, ceilingFolder)
	skyNeon.Material = Enum.Material.Neon
	local skylight = flatCylinder("Skylight", 12, 0.15, Color3.fromRGB(180, 220, 255), 13.35, ceilingFolder)
	skylight.Material = Enum.Material.Glass
	skylight.Transparency = 0.25
	local skyLight = Instance.new("PointLight")
	skyLight.Color = Color3.fromRGB(255, 240, 210)
	skyLight.Range = 45
	skyLight.Brightness = 1.5
	skyLight.Parent = skylight

	-- Twelve radial beams from the skylight edge out to the rim.
	for i = 0, 11 do
		local angle = (i / 12) * math.pi * 2
		newPart(
			"CeilingBeam",
			"Block",
			Vector3.new(64, 0.8, 1.2),
			Color3.fromRGB(110, 120, 140),
			CFrame.new(Vector3.new(math.cos(angle) * 44, 13.4, math.sin(angle) * 44)) * CFrame.Angles(0, -angle, 0),
			ceilingFolder
		)
	end

	-- Thick orange ceiling pipes, running across the hub. The middle pipe
	-- is split in two so it never crosses the skylight.
	local pipeColor = Color3.fromRGB(255, 140, 50)
	for _, z in { -25, 25 } do
		newPart("CeilingPipe", "Cylinder", Vector3.new(142, 2.4, 2.4), pipeColor, CFrame.new(0, 13.2, z), ceilingFolder)
	end
	for _, side in { -1, 1 } do
		newPart("CeilingPipe", "Cylinder", Vector3.new(61, 2.4, 2.4), pipeColor, CFrame.new(side * 44.5, 13.2, 0), ceilingFolder)
	end

	-- Six hanging light fixtures over the hub, alternating warm white and
	-- cyan, four of them carrying a real PointLight.
	local fixtureColors = {
		Color3.fromRGB(255, 240, 210),
		Color3.fromRGB(140, 220, 255),
	} :: { Color3 }
	for i = 0, 5 do
		local angle = math.rad(30 + i * 60)
		local pos = Vector3.new(math.cos(angle) * 40, 12.5, math.sin(angle) * 40)
		local fixture = newPart(
			"HangingLight",
			"Block",
			Vector3.new(3, 0.4, 1.5),
			fixtureColors[(i % 2) + 1],
			CFrame.new(pos) * CFrame.Angles(0, -(angle + math.pi / 2), 0),
			ceilingFolder,
			Enum.Material.Neon
		)
		fixture.CanCollide = false
		local rod = newPart(
			"LightRod",
			"Cylinder",
			Vector3.new(1.0, 0.25, 0.25),
			Color3.fromRGB(120, 125, 135),
			CFrame.new(Vector3.new(pos.X, 13.2, pos.Z)),
			ceilingFolder
		)
		rod.CFrame = CFrame.new(Vector3.new(pos.X, 13.2, pos.Z)) * CFrame.Angles(0, 0, math.rad(90))
		if i ~= 2 and i ~= 5 then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 225, 170)
			light.Range = 30
			light.Brightness = 1.2
			light.Parent = fixture
		end
	end

	-- Red circular accent lights in pairs on the rim wall.
	for i = 0, 3 do
		local angle = math.rad(45 + i * 90)
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		for _, side in { -1, 1 } do
			local center = radial * 74 + tangent * (side * 1.2) + Vector3.new(0, 12, 0)
			local housing = newPart(
				"RimLightHousing",
				"Cylinder",
				Vector3.new(0.3, 2.2, 2.2),
				Color3.fromRGB(40, 45, 55),
				CFrame.new(center + radial * 0.15) * CFrame.Angles(0, -angle, 0),
				ceilingFolder
			)
			housing.CanCollide = false
			local lens = newPart(
				"RimLight",
				"Cylinder",
				Vector3.new(0.4, 1.6, 1.6),
				Color3.fromRGB(255, 60, 60),
				CFrame.new(center) * CFrame.Angles(0, -angle, 0),
				ceilingFolder,
				Enum.Material.Neon
			)
			lens.CanCollide = false
		end
	end
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

	-- Yellow-black hazard tape across the walkway to the airlock.
	for i = 0, 7 do
		local stripe = newPart(
			"AirlockHazard",
			"Block",
			Vector3.new(1.2, 0.15, 1.5),
			if i % 2 == 0 then Color3.fromRGB(255, 200, 40) else Color3.fromRGB(30, 30, 35),
			CFrame.new(78, 0.1, -5.25 + i * 1.5),
			folder
		)
		stripe.CanCollide = false
	end

	-- Scattered cargo on the outer deck: four yellow crates and two
	-- barrels in accent colors. Spots are checked clear of the modules
	-- (19+ studs from any module center), the airlock and the rails.
	local crateSpots = {
		{ Vector3.new(60, 1, 60), 30 },
		{ Vector3.new(-70, 1, 55), 0 },
		{ Vector3.new(-60, 1, -70), 60 },
		{ Vector3.new(75, 1, -55), 15 },
	} :: { { any } }
	for _, spot in crateSpots do
		local pos = spot[1] :: Vector3
		local yaw = spot[2] :: number
		newPart("DeckCrate", "Block", Vector3.new(2.2, 2, 2.2), Color3.fromRGB(255, 200, 40), CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0), folder)
	end
	local barrelSpots = {
		{ Vector3.new(0, 1.25, 100), Color3.fromRGB(60, 220, 220) },
		{ Vector3.new(-100, 1.25, 0), Color3.fromRGB(255, 160, 60) },
	} :: { { any } }
	for _, spot in barrelSpots do
		local pos = spot[1] :: Vector3
		local color = spot[2] :: Color3
		local barrel = newPart("DeckBarrel", "Cylinder", Vector3.new(2.5, 1.8, 1.8), color, CFrame.new(pos), folder)
		barrel.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	end

	addSign(folder, Vector3.new(82, 0, 0), "OUTER DECK", "Storms hit here first!", Color3.fromRGB(255, 170, 90))
end

local function buildOneModule(folder: Instance, index: number): any
	local angle = math.rad(22.5 + (index - 1) * 45)
	local center = Vector3.new(math.cos(angle) * MODULE_RADIUS, 0, math.sin(angle) * MODULE_RADIUS)
	local accent = MODULE_ACCENTS[index]
	local moduleFolder = newFolder(`Module{index}`, folder)
	local faceHub = CFrame.new(center, Vector3.new(0, 0, 0))

	-- Module floor disc + accent ring.
	local moduleFloor = flatCylinder(`Module{index}Floor`, 16, 0.6, Color3.fromRGB(115, 120, 130), 0.1, moduleFolder)
	moduleFloor.CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local ring = flatCylinder(`Module{index}Ring`, 16.6, 0.3, accent, 0.05, moduleFolder)
	ring.CFrame = CFrame.new(center + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))

	-- Three grey metal walls (back + sides); the front stays open toward
	-- the hub. Each wall gets an accent neon trim strip along its top.
	local wallOffsets = { Vector3.new(0, 3, -15.5), Vector3.new(-15.5, 3, 0), Vector3.new(15.5, 3, 0) }
	local wallSizes = { Vector3.new(32, 6, 1.2), Vector3.new(1.2, 6, 32), Vector3.new(1.2, 6, 32) }
	local trimOffsets = { Vector3.new(0, 6.2, -15.5), Vector3.new(-15.5, 6.2, 0), Vector3.new(15.5, 6.2, 0) }
	local trimSizes = { Vector3.new(32, 0.4, 0.4), Vector3.new(0.4, 0.4, 32), Vector3.new(0.4, 0.4, 32) }
	for i, offset in wallOffsets do
		local wallPos = faceHub:PointToWorldSpace(offset)
		newPart(`Module{index}Wall`, "Block", wallSizes[i], Color3.fromRGB(170, 175, 185), CFrame.new(wallPos, center), moduleFolder)
		local trimPos = faceHub:PointToWorldSpace(trimOffsets[i])
		local trim = newPart(`Module{index}Trim`, "Block", trimSizes[i], accent, CFrame.new(trimPos, center), moduleFolder, Enum.Material.Neon)
		trim.CanCollide = false
	end

	-- Three lit windows on the back wall, warm yellow.
	for _, x in { -8, 0, 8 } do
		local windowPos = faceHub:PointToWorldSpace(Vector3.new(x, 3.5, -14.8))
		local window = newPart(
			`Module{index}Window`,
			"Block",
			Vector3.new(3, 2, 0.3),
			Color3.fromRGB(255, 220, 120),
			CFrame.new(windowPos, center),
			moduleFolder,
			Enum.Material.Neon
		)
		window.CanCollide = false
	end

	-- Roof detail: an antenna with a red beacon on the back wall, and a
	-- vent box beside it.
	local antennaPos = faceHub:PointToWorldSpace(Vector3.new(10, 7.5, -15.5))
	local antenna = newPart("ModuleAntenna", "Cylinder", Vector3.new(3, 0.25, 0.25), Color3.fromRGB(120, 125, 135), CFrame.new(antennaPos), moduleFolder)
	antenna.CFrame = CFrame.new(antennaPos) * CFrame.Angles(0, 0, math.rad(90))
	local beaconPos = faceHub:PointToWorldSpace(Vector3.new(10, 9.2, -15.5))
	local beacon = newPart("ModuleBeacon", "Ball", Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(255, 70, 70), CFrame.new(beaconPos), moduleFolder, Enum.Material.Neon)
	beacon.CanCollide = false
	local ventPos = faceHub:PointToWorldSpace(Vector3.new(-10, 4.5, -14.8))
	newPart("ModuleVent", "Block", Vector3.new(4, 2, 1), Color3.fromRGB(70, 75, 85), CFrame.new(ventPos, center), moduleFolder)

	-- Entrance frame: two accent neon posts at the front corners, each
	-- topped with a glowing lamp ball.
	for _, side in { -1, 1 } do
		local postPos = faceHub:PointToWorldSpace(Vector3.new(side * 15.5, 3, 15.5))
		local post = newPart(`Module{index}EntrancePost`, "Block", Vector3.new(0.8, 6, 0.8), accent, CFrame.new(postPos), moduleFolder, Enum.Material.Neon)
		post.CanCollide = false
		local lampPos = faceHub:PointToWorldSpace(Vector3.new(side * 15.5, 6.5, 15.5))
		local lamp = newPart(`Module{index}EntranceLamp`, "Ball", Vector3.new(1.2, 1.2, 1.2), accent, CFrame.new(lampPos), moduleFolder, Enum.Material.Neon)
		lamp.CanCollide = false
	end

	-- Shield dome: invisible until the module locks or a storm hits.
	local dome = newPart(`Module{index}Dome`, "Ball", Vector3.new(36, 22, 36), accent, CFrame.new(center + Vector3.new(0, 1, 0)), moduleFolder, Enum.Material.ForceField, 1)
	dome.CanCollide = false
	dome.CanQuery = false

	-- Eight habitat pods in a 2 x 4 grid, TIERED: the back row (local
	-- z = -4, farthest from the entrance) sits on a 1.5-stud riser so
	-- every docked brainrot is visible from the entrance. podPositions
	-- carries the raised Y, so GameService docks onto the riser with no
	-- code change (its dock math adds 0.7 + rest height on top).
	local podPositions: { Vector3 } = {}
	local podIndex = 0
	for _, row in { -4, 4 } do
		for _, col in { -6, -2, 2, 6 } do
			podIndex += 1
			local podPos = faceHub:PointToWorldSpace(Vector3.new(col, 0, row))
			local raise = if row == -4 then 1.5 else 0
			local podBase = podPos + Vector3.new(0, raise, 0)
			table.insert(podPositions, podBase)
			if raise > 0 then
				newPart(
					`Pod{podIndex}Riser`,
					"Block",
					Vector3.new(4.6, 1.5, 4.6),
					Color3.fromRGB(120, 125, 135),
					CFrame.new(podPos + Vector3.new(0, 0.75, 0)),
					moduleFolder
				)
				local tierEdgePos = faceHub:PointToWorldSpace(Vector3.new(col, 0.75, row + 2.4))
				local tierEdge = newPart(
					`Pod{podIndex}TierEdge`,
					"Block",
					Vector3.new(4.8, 0.3, 0.3),
					accent,
					CFrame.new(tierEdgePos, center),
					moduleFolder,
					Enum.Material.Neon
				)
				tierEdge.CanCollide = false
			end
			local platform = newPart(
				`Pod{podIndex}Platform`,
				"Cylinder",
				Vector3.new(0.7, 4.6, 4.6),
				Color3.fromRGB(140, 145, 155),
				CFrame.new(podBase + Vector3.new(0, 0.35, 0)),
				moduleFolder
			)
			platform.CFrame = CFrame.new(podBase + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0, math.rad(90))
			local glow = newPart(
				`Pod{podIndex}Glow`,
				"Cylinder",
				Vector3.new(0.25, 5.0, 5.0),
				accent,
				CFrame.new(podBase + Vector3.new(0, 0.75, 0)),
				moduleFolder,
				Enum.Material.Neon
			)
			glow.CFrame = CFrame.new(podBase + Vector3.new(0, 0.75, 0)) * CFrame.Angles(0, 0, math.rad(90))
			glow.CanCollide = false
			local glass = newPart(`Pod{podIndex}Glass`, "Ball", Vector3.new(5.2, 4.6, 5.2), Color3.fromRGB(170, 220, 255), CFrame.new(podBase + Vector3.new(0, 2.6, 0)), moduleFolder, Enum.Material.Glass, 0.78)
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
	-- Colorful space flowers between the planters: glowing Neon blooms
	-- in pink, cyan and gold, so the garden reads as the station's
	-- brightest patch of color.
	local flowerRng = Random.new(77)
	local flowerColors = {
		Color3.fromRGB(255, 120, 200),
		Color3.fromRGB(120, 220, 255),
		Color3.fromRGB(255, 215, 60),
		Color3.fromRGB(200, 140, 255),
	} :: { Color3 }
	for _ = 1, 12 do
		local angle = flowerRng:NextNumber() * math.pi * 2
		local radius = 4 + flowerRng:NextNumber() * 12
		local flowerPos = gardenCenter + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local stem = newPart("FlowerStem", "Cylinder", Vector3.new(1.2, 0.18, 0.18), Color3.fromRGB(60, 160, 70), CFrame.new(flowerPos + Vector3.new(0, 0.6, 0)), gardenFolder)
		stem.CFrame = CFrame.new(flowerPos + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local bloom = newPart(
			"FlowerBloom",
			"Ball",
			Vector3.new(0.9, 0.9, 0.9),
			flowerColors[flowerRng:NextInteger(1, #flowerColors)],
			CFrame.new(flowerPos + Vector3.new(0, 1.5, 0)),
			gardenFolder,
			Enum.Material.Neon
		)
		bloom.CanCollide = false
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
	-- The round outer door ZORK sneaks through, framed by a hazard ring
	-- and flanked by two neon lamp pillars — the airlock's own zone gate.
	local door = newPart("AirlockDoor", "Cylinder", Vector3.new(0.8, 7, 7), Color3.fromRGB(255, 150, 60), CFrame.new(center + Vector3.new(9.2, 3.5, 0)), airlockFolder, Enum.Material.Neon)
	door.CFrame = CFrame.new(center + Vector3.new(9.2, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	for s = 0, 11 do
		local phi = (s / 12) * math.pi * 2
		local segment = newPart(
			"AirlockDoorRing",
			"Block",
			Vector3.new(1.2, 2.2, 1.0),
			if s % 2 == 0 then Color3.fromRGB(255, 200, 40) else Color3.fromRGB(30, 30, 35),
			CFrame.new(center + Vector3.new(9.2, 3.5 + math.sin(phi) * 4.2, math.cos(phi) * 4.2)) * CFrame.Angles(phi, 0, 0),
			airlockFolder
		)
		segment.CanCollide = false
	end
	for _, side in { -1, 1 } do
		newPart("AirlockPillar", "Block", Vector3.new(1.2, 8, 1.2), Color3.fromRGB(140, 145, 155), CFrame.new(center + Vector3.new(8.5, 4, side * 6.5)), airlockFolder)
		local lamp = newPart(
			"AirlockLamp",
			"Ball",
			Vector3.new(1.4, 1.4, 1.4),
			AREA_COLORS.airlock,
			CFrame.new(center + Vector3.new(8.5, 8.6, side * 6.5)),
			airlockFolder,
			Enum.Material.Neon
		)
		lamp.CanCollide = false
		local lampLight = Instance.new("PointLight")
		lampLight.Color = AREA_COLORS.airlock
		lampLight.Range = 14
		lampLight.Brightness = 1.2
		lampLight.Parent = lamp
	end

	-- Supply crates stacked by the door — the delivery drone's cargo, and a
	-- reason for the airlock to exist besides ZORK's raids.
	local crateSpots = {
		{ Vector3.new(-6, 1, -6), 2 },
		{ Vector3.new(-6, 1, 6.5), 3 },
		{ Vector3.new(5, 1, 6.5), 2 },
	} :: { { any } }
	local crateColors = { Color3.fromRGB(255, 200, 40), Color3.fromRGB(245, 190, 35), Color3.fromRGB(255, 210, 70) } :: { Color3 }
	for i, spot in crateSpots do
		local base = spot[1] :: Vector3
		local stack = spot[2] :: number
		for level = 0, stack - 1 do
			newPart(
				"SupplyCrate",
				"Block",
				Vector3.new(2.2, 2, 2.2),
				crateColors[((i + level - 1) % #crateColors) + 1],
				CFrame.new(center + base + Vector3.new(0, level * 2, 0)),
				airlockFolder
			)
		end
	end

	-- One open crate with something glowing green inside — the delivery
	-- drone's most interesting cargo.
	local openCratePos = center + Vector3.new(5, 1, -6)
	newPart("OpenCrate", "Block", Vector3.new(2.2, 2, 2.2), Color3.fromRGB(255, 200, 40), CFrame.new(openCratePos), airlockFolder)
	local lid = newPart(
		"OpenCrateLid",
		"Block",
		Vector3.new(2.2, 0.3, 2.2),
		Color3.fromRGB(255, 200, 40),
		CFrame.new(openCratePos + Vector3.new(0, 1.6, -1.2)) * CFrame.Angles(math.rad(-50), 0, 0),
		airlockFolder
	)
	lid.CanCollide = false
	local glowBar = newPart(
		"OpenCrateGlow",
		"Block",
		Vector3.new(1.6, 0.3, 0.6),
		Color3.fromRGB(100, 255, 120),
		CFrame.new(openCratePos + Vector3.new(0, 0.9, 0)),
		airlockFolder,
		Enum.Material.Neon
	)
	glowBar.CanCollide = false

	addSign(airlockFolder, center + Vector3.new(-4, 0, 10), "AIRLOCK", "ZORK the Snatcher sneaks in here...", Color3.fromRGB(255, 150, 90))
end

-- The showcase stage behind the title screen: a low stage platform with a
-- gold neon edge, six pedestals that CLIMB by rarity (Common low, Secret
-- high), each with a neon ring + PointLight + vertical light beam in its
-- rarity color and a plaque naming the rarity; chasing marquee bulbs along
-- the stage's front edge (animated by TitleController); a 4-color confetti
-- emitter above the stage; and a big BRAINROT ORBIT title board behind it
-- all, high enough (y 5.5-12.5) that no pedestal label can cover it.
local function buildTitlePedestals(folder: Instance)
	local pedestalFolder = newFolder("TitlePedestals", folder)
	local showcase = {
		{ "Bloop Blorp", "None" },
		{ "Plasma Pingu", "None" },
		{ "Cosmo Corgi", "Gold" },
		{ "Warp Whale", "None" },
		{ "Pulsar Panda", "Diamond" },
		{ "Big Bang Burrito", "Cosmic" },
	} :: { { string } }
	local heights = { 1.2, 1.5, 1.9, 2.4, 2.9, 3.5 } :: { number }

	-- Stage platform + gold neon front edge.
	newPart("StagePlatform", "Block", Vector3.new(32, 1, 10), Color3.fromRGB(70, 75, 85), CFrame.new(0, 0.5, -14), pedestalFolder)
	local stageEdge = newPart("StageEdge", "Block", Vector3.new(32, 0.3, 0.3), Color3.fromRGB(255, 215, 60), CFrame.new(0, 1.05, -9), pedestalFolder, Enum.Material.Neon)
	stageEdge.CanCollide = false

	for i, entry in showcase do
		local x = -12.5 + (i - 1) * 5
		local height = heights[i]
		local pedestalPos = Vector3.new(x, 0, -14)
		local species = BrainrotData.getSpecies(entry[1])
		local rarityColor = Color3.fromRGB(200, 200, 210)
		local rarityName = "Common"
		if species then
			rarityColor = BrainrotData.RARITY_COLORS[species.rarity]
			rarityName = species.rarity
		end
		local pedestal = newPart(`Pedestal{i}`, "Cylinder", Vector3.new(height, 3.6, 3.6), Color3.fromRGB(210, 220, 235), CFrame.new(pedestalPos + Vector3.new(0, 1 + height / 2, 0)), pedestalFolder)
		pedestal.CFrame = CFrame.new(pedestalPos + Vector3.new(0, 1 + height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local trim = newPart(
			`Pedestal{i}Trim`,
			"Cylinder",
			Vector3.new(0.3, 4.0, 4.0),
			rarityColor,
			CFrame.new(pedestalPos + Vector3.new(0, 1 + height, 0)),
			pedestalFolder,
			Enum.Material.Neon
		)
		trim.CFrame = CFrame.new(pedestalPos + Vector3.new(0, 1 + height, 0)) * CFrame.Angles(0, 0, math.rad(90))
		trim.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = rarityColor
		light.Range = 10
		light.Brightness = 1.5
		light.Parent = trim
		-- Vertical light beam in the rarity color, rising from the pedestal.
		-- 8 studs tall: the tallest pedestal's beam tops out at y=12.5,
		-- clear of the ceiling at y=14.
		local beam = newPart(
			`Pedestal{i}Beam`,
			"Cylinder",
			Vector3.new(8, 0.5, 0.5),
			rarityColor,
			CFrame.new(pedestalPos + Vector3.new(0, 1 + height + 4, 0)),
			pedestalFolder,
			Enum.Material.Neon,
			0.55
		)
		beam.CFrame = CFrame.new(pedestalPos + Vector3.new(0, 1 + height + 4, 0)) * CFrame.Angles(0, 0, math.rad(90))
		beam.CanCollide = false
		beam.CanQuery = false
		-- Plaque naming the rarity, facing the spawn/camera (+Z).
		local plaque = newPart(
			`Pedestal{i}Plaque`,
			"Block",
			Vector3.new(3.4, 1.2, 0.3),
			Color3.fromRGB(30, 35, 45),
			CFrame.new(pedestalPos + Vector3.new(0, 1.6, 2.6)) * CFrame.Angles(0, math.pi, 0),
			pedestalFolder
		)
		plaque.CanCollide = false
		local plaqueGui = Instance.new("SurfaceGui")
		plaqueGui.Name = "PlaqueText"
		plaqueGui.Face = Enum.NormalId.Front
		plaqueGui.CanvasSize = Vector2.new(200, 60)
		plaqueGui.Adornee = plaque
		local plaqueLabel = Instance.new("TextLabel")
		plaqueLabel.Size = UDim2.new(1, 0, 1, 0)
		plaqueLabel.BackgroundTransparency = 1
		plaqueLabel.Text = string.upper(rarityName)
		plaqueLabel.TextColor3 = rarityColor
		plaqueLabel.Font = Enum.Font.LuckiestGuy
		plaqueLabel.TextScaled = true
		plaqueLabel.Parent = plaqueGui
		plaqueGui.Parent = plaque
		local model = BrainrotFactory.buildBrainrotModel(entry[1], entry[2], `pedestal-{i}`)
		model:SetAttribute("Animate", "Spin")
		model:PivotTo(CFrame.new(pedestalPos + Vector3.new(0, 1 + height + 0.2 + BrainrotFactory.getRestHeight(entry[1]), 0)))
		model.Parent = pedestalFolder
	end

	-- Marquee bulbs along the stage's front edge, cycling 4 colors. The
	-- client chases them (every third bulb lit, 8 steps/second).
	local bulbColors = {
		Color3.fromRGB(255, 215, 60),
		Color3.fromRGB(60, 220, 220),
		Color3.fromRGB(255, 120, 200),
		Color3.fromRGB(96, 214, 84),
	} :: { Color3 }
	for i = 0, 20 do
		local bulb = newPart(
			"MarqueeBulb",
			"Ball",
			Vector3.new(0.55, 0.55, 0.55),
			bulbColors[(i % 4) + 1],
			CFrame.new(-15 + i * 1.5, 1.3, -9.2),
			pedestalFolder,
			Enum.Material.Neon
		)
		bulb.CanCollide = false
		bulb:SetAttribute("BulbIndex", i + 1)
	end

	-- Confetti emitter above the stage: 4 colors, falling gently.
	local confettiAnchor = newPart("ConfettiAnchor", "Block", Vector3.new(1, 1, 1), Color3.fromRGB(255, 255, 255), CFrame.new(0, 12, -14), pedestalFolder, Enum.Material.SmoothPlastic, 1)
	confettiAnchor.CanCollide = false
	confettiAnchor.CanQuery = false
	local confetti = Instance.new("ParticleEmitter")
	confetti.Name = "StageConfetti"
	confetti.Enabled = true
	confetti.Rate = 30
	confetti.Lifetime = NumberRange.new(2, 4)
	confetti.Speed = NumberRange.new(2, 5)
	confetti.SpreadAngle = Vector2.new(90, 90)
	confetti.EmissionDirection = Enum.NormalId.Bottom
	confetti.Acceleration = Vector3.new(0, -6, 0)
	confetti.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 60)),
		ColorSequenceKeypoint.new(0.33, Color3.fromRGB(60, 220, 220)),
		ColorSequenceKeypoint.new(0.66, Color3.fromRGB(255, 120, 200)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(96, 214, 84)),
	})
	confetti.Size = NumberSequence.new(0.5)
	confetti.Transparency = NumberSequence.new(0.1, 1)
	confetti.Parent = confettiAnchor

	-- The big title board behind the stage, high above the pedestal
	-- labels: gold LuckiestGuy name + cyan tagline on a dark board with a
	-- neon gold frame. It hangs over the north walkway (bottom edge y=5.5
	-- clears every head).
	local board = newPart(
		"TitleBoard",
		"Block",
		Vector3.new(26, 7, 0.6),
		Color3.fromRGB(25, 30, 45),
		CFrame.new(0, 9, -26) * CFrame.Angles(0, math.pi, 0),
		pedestalFolder
	)
	board.CanCollide = false
	for _, offset in { Vector3.new(0, 3.65, 0), Vector3.new(0, -3.65, 0) } do
		local frameStrip = newPart(
			"TitleBoardFrame",
			"Block",
			Vector3.new(26.4, 0.3, 0.7),
			Color3.fromRGB(255, 215, 60),
			CFrame.new(Vector3.new(0, 9, -26) + offset),
			pedestalFolder,
			Enum.Material.Neon
		)
		frameStrip.CanCollide = false
	end
	for _, side in { -1, 1 } do
		newPart("TitleBoardPole", "Cylinder", Vector3.new(5.5, 0.4, 0.4), Color3.fromRGB(120, 130, 150), CFrame.new(side * 12, 2.75, -26), pedestalFolder).CFrame =
			CFrame.new(side * 12, 2.75, -26) * CFrame.Angles(0, 0, math.rad(90))
	end
	local boardLight = Instance.new("PointLight")
	boardLight.Color = Color3.fromRGB(255, 240, 210)
	boardLight.Range = 30
	boardLight.Brightness = 1.2
	boardLight.Parent = board
	local boardGui = Instance.new("SurfaceGui")
	boardGui.Name = "TitleBoardText"
	boardGui.Face = Enum.NormalId.Front
	boardGui.CanvasSize = Vector2.new(800, 220)
	boardGui.Adornee = board
	local boardName = Instance.new("TextLabel")
	boardName.Size = UDim2.new(1, 0, 0.65, 0)
	boardName.BackgroundTransparency = 1
	boardName.Text = "BRAINROT ORBIT"
	boardName.TextColor3 = Color3.fromRGB(255, 215, 60)
	boardName.Font = Enum.Font.LuckiestGuy
	boardName.TextScaled = true
	boardName.TextStrokeColor3 = Color3.fromRGB(20, 16, 16)
	boardName.TextStrokeTransparency = 0.1
	boardName.Parent = boardGui
	local boardTag = Instance.new("TextLabel")
	boardTag.Position = UDim2.new(0, 0, 0.65, 0)
	boardTag.Size = UDim2.new(1, 0, 0.35, 0)
	boardTag.BackgroundTransparency = 1
	boardTag.Text = "CATCH  •  DOCK  •  GET RICH"
	boardTag.TextColor3 = Color3.fromRGB(120, 220, 255)
	boardTag.Font = Enum.Font.FredokaOne
	boardTag.TextScaled = true
	boardTag.Parent = boardGui
	boardGui.Parent = board
end

local function buildSpaceBackdrop(folder: Instance)
	local spaceFolder = newFolder("SpaceBackdrop", folder)

	-- Stars: ~220 small neon balls on a shell at radius 900-1200, placed
	-- with a fixed seed so the sky is the same every server. Parts only —
	-- the Sky's StarCount is not relied on.
	local starRng = Random.new(12345)
	local starColors = {
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(255, 240, 200),
		Color3.fromRGB(200, 225, 255),
		Color3.fromRGB(255, 200, 230),
	} :: { Color3 }
	for _ = 1, 220 do
		local theta = starRng:NextNumber() * math.pi * 2
		local y = starRng:NextNumber() * 2 - 1
		local horizontal = math.sqrt(math.max(0, 1 - y * y))
		local radius = 900 + starRng:NextNumber() * 300
		local pos = Vector3.new(math.cos(theta) * horizontal * radius, y * radius, math.sin(theta) * horizontal * radius)
		local size = 0.6 + starRng:NextNumber() * 1.0
		local star = newPart(
			"Star",
			"Ball",
			Vector3.new(size, size, size),
			starColors[starRng:NextInteger(1, #starColors)],
			CFrame.new(pos),
			spaceFolder,
			Enum.Material.Neon
		)
		star.CanCollide = false
		star.CanQuery = false
	end

	-- Nebulae: fifteen huge faint neon clouds, far out, for color in the dark.
	local nebulaColors = {
		Color3.fromRGB(150, 80, 255),
		Color3.fromRGB(80, 220, 220),
		Color3.fromRGB(255, 120, 200),
	} :: { Color3 }
	for _ = 1, 15 do
		local theta = starRng:NextNumber() * math.pi * 2
		local y = starRng:NextNumber() * 500 - 100
		local radius = 950 + starRng:NextNumber() * 100
		local size = 120 + starRng:NextNumber() * 100
		local nebula = newPart(
			"Nebula",
			"Ball",
			Vector3.new(size, size, size),
			nebulaColors[starRng:NextInteger(1, #nebulaColors)],
			CFrame.new(math.cos(theta) * radius, y, math.sin(theta) * radius),
			spaceFolder,
			Enum.Material.Neon,
			0.88
		)
		nebula.CanCollide = false
		nebula.CanQuery = false
	end

	-- The planet the station orbits, smaller and farther than before so it
	-- reads as a world in the distance instead of a beach ball overhead,
	-- with a tilted ring and a glowing atmosphere shell.
	local planetCenter = Vector3.new(700, 180, -900)
	local planet = newPart("Planet", "Ball", Vector3.new(60, 60, 60), Color3.fromRGB(80, 180, 200), CFrame.new(planetCenter), spaceFolder)
	planet.CanCollide = false
	planet.CanQuery = false
	local planetRing = newPart("PlanetRing", "Cylinder", Vector3.new(1.5, 90, 90), Color3.fromRGB(180, 220, 240), CFrame.new(planetCenter), spaceFolder, Enum.Material.SmoothPlastic, 0.4)
	planetRing.CFrame = CFrame.new(planetCenter) * CFrame.Angles(math.rad(70), 0, math.rad(20))
	planetRing.CanCollide = false
	planetRing.CanQuery = false
	local atmosphere = newPart(
		"PlanetAtmosphere",
		"Ball",
		Vector3.new(66, 66, 66),
		Color3.fromRGB(170, 230, 255),
		CFrame.new(planetCenter),
		spaceFolder,
		Enum.Material.Neon,
		0.7
	)
	atmosphere.CanCollide = false
	atmosphere.CanQuery = false

	-- A small grey moon near the planet.
	local moon = newPart("Moon", "Ball", Vector3.new(16, 16, 16), Color3.fromRGB(180, 180, 190), CFrame.new(620, 230, -860), spaceFolder)
	moon.CanCollide = false
	moon.CanQuery = false

	-- A second, purple planet on the other side of the sky, with its own
	-- glowing atmosphere shell — the view out the south windows gets a
	-- landmark too.
	local planet2Center = Vector3.new(-800, 250, -600)
	local planet2 = newPart("Planet2", "Ball", Vector3.new(40, 40, 40), Color3.fromRGB(150, 90, 220), CFrame.new(planet2Center), spaceFolder)
	planet2.CanCollide = false
	planet2.CanQuery = false
	local atmosphere2 = newPart(
		"Planet2Atmosphere",
		"Ball",
		Vector3.new(45, 45, 45),
		Color3.fromRGB(220, 170, 255),
		CFrame.new(planet2Center),
		spaceFolder,
		Enum.Material.Neon,
		0.7
	)
	atmosphere2.CanCollide = false
	atmosphere2.CanQuery = false

	-- A comet: a bright head with a tail of fading balls, arcing across
	-- the northern sky.
	local cometHead = Vector3.new(-300, 400, -900)
	local cometDir = Vector3.new(0.5, -0.25, 0.3)
	local cometHeadPart = newPart("CometHead", "Ball", Vector3.new(6, 6, 6), Color3.fromRGB(255, 250, 220), CFrame.new(cometHead), spaceFolder, Enum.Material.Neon)
	cometHeadPart.CanCollide = false
	cometHeadPart.CanQuery = false
	for i = 1, 8 do
		local tailPart = newPart(
			"CometTail",
			"Ball",
			Vector3.new(6 - i * 0.6, 6 - i * 0.6, 6 - i * 0.6),
			Color3.fromRGB(170, 220, 255),
			CFrame.new(cometHead - cometDir * (i * 12)),
			spaceFolder,
			Enum.Material.Neon,
			0.15 + i * 0.09
		)
		tailPart.CanCollide = false
		tailPart.CanQuery = false
	end

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

	-- A docked shuttle, visible through the hub's big windows: the station
	-- is a place ships come to, not a sealed box.
	local shuttlePos = Vector3.new(150, 28, -90)
	local shuttleCf = CFrame.lookAt(shuttlePos, Vector3.new(0, 10, 0)) * CFrame.Angles(0, math.rad(90), 0)
	local shuttleBody = newPart("ShuttleBody", "Cylinder", Vector3.new(16, 5.5, 5.5), Color3.fromRGB(225, 230, 240), shuttleCf, spaceFolder)
	shuttleBody.CanCollide = false
	shuttleBody.CanQuery = false
	local nose = newPart("ShuttleNose", "Ball", Vector3.new(5, 5, 5), Color3.fromRGB(255, 170, 60), shuttleCf * CFrame.new(9.5, 0, 0), spaceFolder, Enum.Material.Neon)
	nose.CanCollide = false
	nose.CanQuery = false
	local cockpit = newPart("ShuttleCockpit", "Ball", Vector3.new(4, 3, 4), Color3.fromRGB(120, 200, 255), shuttleCf * CFrame.new(4, 2.5, 0), spaceFolder, Enum.Material.Glass, 0.2)
	cockpit.CanCollide = false
	cockpit.CanQuery = false
	for _, side in { -1, 1 } do
		local wing = newPart("ShuttleWing", "Block", Vector3.new(7, 0.5, 7), Color3.fromRGB(90, 140, 220), shuttleCf * CFrame.new(-1, -0.5, side * 5.5), spaceFolder)
		wing.CanCollide = false
		wing.CanQuery = false
		local engine = newPart("ShuttleEngine", "Cylinder", Vector3.new(1.5, 2, 2), Color3.fromRGB(255, 140, 60), shuttleCf * CFrame.new(-8.5, 0, side * 1.8), spaceFolder, Enum.Material.Neon)
		engine.CFrame = shuttleCf * CFrame.new(-8.5, 0, side * 1.8)
		engine.CanCollide = false
		engine.CanQuery = false
	end
	local shuttleBeacon = newPart("ShuttleBeacon", "Ball", Vector3.new(1, 1, 1), Color3.fromRGB(255, 90, 90), shuttleCf * CFrame.new(0, 3.5, 0), spaceFolder, Enum.Material.Neon)
	shuttleBeacon.CanCollide = false
	shuttleBeacon.CanQuery = false
end

local function buildCrewAndRobot(folder: Instance)
	local crewFolder = newFolder("Crew", folder)
	local crew = {
		{ "CMDR. NOVA", "Station Commander", Color3.fromRGB(60, 110, 200), Color3.fromRGB(230, 190, 160), Vector3.new(14, 0, 18), "Sway" },
		{ "ENG. PIXEL", "Chief Engineer", Color3.fromRGB(200, 110, 60), Color3.fromRGB(160, 110, 80), Vector3.new(-16, 0, 14), "Sway" },
		{ "DR. SPROUT", "Hydroponics Lead", Color3.fromRGB(70, 170, 80), Color3.fromRGB(240, 210, 180), Vector3.new(-42, 0, -28), "Sway" },
		{ "NAV. COMET", "Navigator", Color3.fromRGB(120, 90, 200), Color3.fromRGB(210, 170, 140), Vector3.new(30, 0, -10), "Turn" },
		{ "CHEF ZEST", "Galley Cook", Color3.fromRGB(220, 160, 60), Color3.fromRGB(180, 130, 100), Vector3.new(-30, 0, 34), "Turn" },
	} :: { { any } }
	for _, entry in crew do
		local npc = BrainrotFactory.buildCrewNpc(entry[1], entry[2], entry[3], entry[4])
		npc:SetAttribute("Animate", entry[6])
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

	-- The delivery drone hovers at 8 studs, ferrying supplies between the
	-- hub, the garden and the airlock crates.
	local drone = BrainrotFactory.buildDeliveryDrone()
	drone:PivotTo(CFrame.new(30, 8, -30))
	drone.Parent = crewFolder
	WorldBuilder.DELIVERY_DRONE = drone
	WorldBuilder.DRONE_WAYPOINTS = {
		Vector3.new(30, 8, -30),
		Vector3.new(-35, 8, -20),
		Vector3.new(-20, 8, 35),
		Vector3.new(60, 8, 10),
	}
end

-- Dense festive props, scattered with a fixed seed and placement rules:
-- clear of consoles, lamps, the garden, the stage, the signs, the spawn
-- pad, the modules and the airlock; at least 4 studs between props. Space
-- plants, glowing crystals, candy crates, barrels and wall banners — no
-- wide empty floor is left anywhere in the station.
local function buildProps(folder: Instance)
	local propsFolder = newFolder("Props", folder)
	local propRng = Random.new(11)
	local candyColors = {
		Color3.fromRGB(96, 214, 84),
		Color3.fromRGB(64, 168, 255),
		Color3.fromRGB(255, 88, 82),
		Color3.fromRGB(176, 104, 255),
		Color3.fromRGB(255, 156, 44),
		Color3.fromRGB(255, 206, 54),
		Color3.fromRGB(60, 220, 220),
		Color3.fromRGB(255, 120, 190),
	} :: { Color3 }
	local placed: { Vector3 } = {}

	local function clearOf(x: number, z: number, radius: number): boolean
		-- Fixed keep-out circles: center x/z + clearance radius.
		local keepOut = {
			{ 0, 0, 9 }, -- spawn pad
			{ 0, -14, 17 }, -- showcase stage
			{ -42, -38, 20 }, -- garden
			{ 0, 24, 4 }, -- deck sign
			{ 84, 10, 4 }, -- airlock sign
			{ -42, -18, 4 }, -- garden sign
		} :: { { number } }
		for _, circle in keepOut do
			local dx = x - circle[1]
			local dz = z - circle[2]
			if math.sqrt(dx * dx + dz * dz) < circle[3] + radius then
				return false
			end
		end
		-- Consoles (radius 40) and lamps (radius 55).
		for _, angleDeg in { 45, 135, 225, 315, 0, 180 } do
			local angle = math.rad(angleDeg)
			local dx = x - math.cos(angle) * 40
			local dz = z - math.sin(angle) * 40
			if math.sqrt(dx * dx + dz * dz) < 5 + radius then
				return false
			end
		end
		for i = 0, 7 do
			local angle = (i / 8) * math.pi * 2 + math.pi / 8
			local dx = x - math.cos(angle) * 55
			local dz = z - math.sin(angle) * 55
			if math.sqrt(dx * dx + dz * dz) < 3 + radius then
				return false
			end
		end
		-- Modules (outer deck props).
		for i = 1, MODULE_COUNT do
			local angle = math.rad(22.5 + (i - 1) * 45)
			local dx = x - math.cos(angle) * MODULE_RADIUS
			local dz = z - math.sin(angle) * MODULE_RADIUS
			if math.sqrt(dx * dx + dz * dz) < 19 + radius then
				return false
			end
		end
		-- The airlock (outer deck props).
		if math.sqrt((x - 88) * (x - 88) + z * z) < 12 + radius then
			return false
		end
		-- Other props: at least 4 studs apart.
		for _, other in placed do
			local dx = x - other.X
			local dz = z - other.Z
			if math.sqrt(dx * dx + dz * dz) < 4 + radius then
				return false
			end
		end
		return true
	end

	local function findSpot(minRadius: number, maxRadius: number, radius: number): Vector3?
		for _ = 1, 40 do
			local angle = propRng:NextNumber() * math.pi * 2
			local distance = minRadius + propRng:NextNumber() * (maxRadius - minRadius)
			local x = math.cos(angle) * distance
			local z = math.sin(angle) * distance
			if clearOf(x, z, radius) then
				local spot = Vector3.new(x, 0, z)
				table.insert(placed, spot)
				return spot
			end
		end
		return nil
	end

	local function buildSpacePlant(pos: Vector3, withLight: boolean)
		local pot = newPart("SpacePlantPot", "Cylinder", Vector3.new(1.2, 1.6, 1.6), Color3.fromRGB(200, 120, 80), CFrame.new(pos + Vector3.new(0, 0.6, 0)), propsFolder)
		pot.CFrame = CFrame.new(pos + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local stem = newPart("SpacePlantStem", "Cylinder", Vector3.new(1.6, 0.25, 0.25), Color3.fromRGB(60, 160, 70), CFrame.new(pos + Vector3.new(0, 1.9, 0)), propsFolder)
		stem.CFrame = CFrame.new(pos + Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local leafColor = candyColors[propRng:NextInteger(1, #candyColors)]
		local topLeaf: BasePart? = nil
		for _, offset in { Vector3.new(0, 2.9, 0), Vector3.new(0.7, 2.5, 0.3), Vector3.new(-0.7, 2.5, -0.3) } do
			local leaf = newPart("SpacePlantLeaf", "Ball", Vector3.new(1.1, 1.1, 1.1), leafColor, CFrame.new(pos + offset), propsFolder, Enum.Material.Neon)
			leaf.CanCollide = false
			if not topLeaf then
				topLeaf = leaf
			end
		end
		if withLight and topLeaf then
			local light = Instance.new("PointLight")
			light.Color = leafColor
			light.Range = 8
			light.Brightness = 1
			light.Parent = topLeaf
		end
	end

	local function buildCrystal(pos: Vector3, withLight: boolean)
		local crystalColor = candyColors[propRng:NextInteger(1, #candyColors)]
		local shards = propRng:NextInteger(2, 3)
		local tallest: BasePart? = nil
		local tallestHeight = 0
		for i = 1, shards do
			local height = 1.5 + propRng:NextNumber() * 2
			local shard = newPart(
				"Crystal",
				"Wedge",
				Vector3.new(1.0, height, 1.0),
				crystalColor,
				CFrame.new(pos + Vector3.new((i - 2) * 0.9, height / 2, (i % 2) * 0.6 - 0.3)) * CFrame.Angles(0, propRng:NextNumber() * math.pi * 2, 0),
				propsFolder,
				Enum.Material.Neon
			)
			shard.CanCollide = false
			if height > tallestHeight then
				tallestHeight = height
				tallest = shard
			end
		end
		if withLight and tallest then
			local light = Instance.new("PointLight")
			light.Color = crystalColor
			light.Range = 9
			light.Brightness = 1
			light.Parent = tallest
		end
	end

	local function buildCrate(pos: Vector3)
		local color = candyColors[propRng:NextInteger(1, #candyColors)]
		newPart("PropCrate", "Block", Vector3.new(2, 2, 2), color, CFrame.new(pos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, propRng:NextNumber() * math.pi * 2, 0), propsFolder)
	end

	local function buildBarrel(pos: Vector3)
		local color = candyColors[propRng:NextInteger(1, #candyColors)]
		local barrel = newPart("PropBarrel", "Cylinder", Vector3.new(2.2, 1.6, 1.6), color, CFrame.new(pos + Vector3.new(0, 1.1, 0)), propsFolder)
		barrel.CFrame = CFrame.new(pos + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	end

	-- Banners along the hub wall, between the door gaps.
	for i = 1, 8 do
		local angle = math.rad(22.5 + (i - 1) * 45)
		local base = Vector3.new(math.cos(angle) * 70, 0, math.sin(angle) * 70)
		local pole = newPart("BannerPole", "Cylinder", Vector3.new(6, 0.3, 0.3), Color3.fromRGB(140, 150, 170), CFrame.new(base + Vector3.new(0, 3, 0)), propsFolder)
		pole.CFrame = CFrame.new(base + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local flag = newPart(
			"BannerFlag",
			"Block",
			Vector3.new(2.5, 1.6, 0.2),
			candyColors[i],
			CFrame.new(base + Vector3.new(0, 5, 0), Vector3.new(0, 5, 0)),
			propsFolder,
			Enum.Material.Neon
		)
		flag.CanCollide = false
	end

	-- Hub scatter: plants, crystals, crates, barrels.
	for i = 1, 20 do
		local spot = findSpot(12, 66, 1.5)
		if spot then
			buildSpacePlant(spot, i % 4 == 0)
		end
	end
	for i = 1, 12 do
		local spot = findSpot(12, 66, 1.5)
		if spot then
			buildCrystal(spot, i % 3 == 0)
		end
	end
	for _ = 1, 10 do
		local spot = findSpot(12, 66, 1.5)
		if spot then
			buildCrate(spot)
		end
	end
	for _ = 1, 8 do
		local spot = findSpot(12, 66, 1.2)
		if spot then
			buildBarrel(spot)
		end
	end
	-- Outer deck scatter: crates, barrels and crystals on the exposed ring.
	for _ = 1, 6 do
		local spot = findSpot(80, 108, 1.5)
		if spot then
			buildCrate(spot)
		end
	end
	for _ = 1, 4 do
		local spot = findSpot(80, 108, 1.2)
		if spot then
			buildBarrel(spot)
		end
	end
	for _ = 1, 2 do
		local spot = findSpot(80, 108, 1.5)
		if spot then
			buildCrystal(spot, true)
		end
	end
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
	WorldBuilder.CONSOLE_LIGHTS = {}
	WorldBuilder.CLEANING_ROBOT = nil
	WorldBuilder.DELIVERY_DRONE = nil

	configureLighting()
	buildHub(folder)
	buildCeiling(folder)
	buildOuterDeck(folder)
	buildModules(folder)
	buildGarden(folder)
	buildAirlock(folder)
	buildTitlePedestals(folder)
	buildSpaceBackdrop(folder)
	buildCrewAndRobot(folder)
	buildProps(folder)
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

-- Writes the owner's name onto a module's entrance sign. The name is capped
-- at 10 characters so "MODULE 8 - <name>..." never exceeds the sign's
-- 280 px tag (24 chars at 18 pt bold is ~260 px).
function WorldBuilder.setModuleOwner(moduleIndex: number, ownerName: string?)
	local module = WorldBuilder.MODULES[moduleIndex]
	if not module then
		return
	end
	if ownerName and ownerName ~= "" then
		local shown = ownerName
		if #shown > 10 then
			shown = string.sub(shown, 1, 10) .. "..."
		end
		module.signLabel.Text = `MODULE {moduleIndex} - {shown}`
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
