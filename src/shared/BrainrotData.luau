--!strict
-- BrainrotData
-- Shared game data for BRAINROT ORBIT: the 19 original brainrot species, the
-- rarity ladder, mutations, upgrade tracks, the mission chain and every tuned
-- constant. Server and client both require this module; it holds no mutable
-- state and no secrets, so it is safe to replicate.

-- Engine types used in annotations below (the values come from Roblox at runtime).
type Color3 = any

export type RarityName = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Secret"
export type MutationName = "None" | "Gold" | "Diamond" | "Irradiated" | "Cosmic"

export type Species = {
	name: string,
	rarity: RarityName,
	rate: number, -- base credits earned per second when docked in a habitat pod
	weight: number, -- wild spawn weight (higher = more common in the wild)
	bodyColor: Color3,
	accentColor: Color3,
	bodyShape: string, -- "Ball" | "Block" | "Cylinder"
	accessory: string, -- "None" | "Ears" | "Horns" | "Wings" | "Tail" | "Antenna" | "Beak" | "Spots" | "Ring"
	scale: number, -- body size multiplier, 0.8 (tiny) to 1.6 (secret-sized)
}

export type UpgradeLevel = {
	name: string,
	cost: number, -- credits to buy this level (0 for the starting level)
	beamRange: number?, -- Tractor Beam track
	carryCapacity: number?, -- Cargo Bubble track
	lockSeconds: number?, -- Shield Extender track
	extraPods: number?, -- Module Expansion track
}

export type UpgradeTrack = {
	displayName: string,
	blurb: string,
	levels: { UpgradeLevel },
}

export type Mission = {
	id: string,
	text: string,
	goal: number,
	reward: number, -- credits paid when the mission completes
	stat: string, -- "caught" | "docked" | "earned"
}

local BrainrotData = {}

-- Rarity ladder: display colour per tier, used by name tags, the index and the roster.
BrainrotData.RARITY_COLORS = {
	Common = Color3.fromRGB(184, 192, 204),
	Uncommon = Color3.fromRGB(88, 214, 141),
	Rare = Color3.fromRGB(74, 163, 255),
	Epic = Color3.fromRGB(176, 108, 255),
	Legendary = Color3.fromRGB(255, 176, 32),
	Secret = Color3.fromRGB(255, 77, 109),
} :: { [RarityName]: Color3 }

-- Mutation income multipliers. Irradiated only ever comes from a solar storm.
BrainrotData.MUTATION_MULTIPLIERS = {
	None = 1,
	Gold = 2,
	Diamond = 3,
	Irradiated = 4,
	Cosmic = 10,
} :: { [MutationName]: number }

BrainrotData.MUTATION_COLORS = {
	None = Color3.fromRGB(255, 255, 255),
	Gold = Color3.fromRGB(255, 215, 0),
	Diamond = Color3.fromRGB(120, 220, 255),
	Irradiated = Color3.fromRGB(120, 255, 90),
	Cosmic = Color3.fromRGB(255, 110, 255),
} :: { [MutationName]: Color3 }

-- The full roster: 19 original alien brainrots. Rates are credits per second.
BrainrotData.SPECIES = {
	-- Common
	{ name = "Bloop Blorp", rarity = "Common", rate = 8, weight = 100, bodyColor = Color3.fromRGB(120, 200, 255), accentColor = Color3.fromRGB(40, 110, 200), bodyShape = "Ball", accessory = "Antenna", scale = 0.9 },
	{ name = "Zorp Zorp", rarity = "Common", rate = 12, weight = 80, bodyColor = Color3.fromRGB(150, 255, 150), accentColor = Color3.fromRGB(40, 160, 60), bodyShape = "Ball", accessory = "Ears", scale = 0.9 },
	{ name = "Gloob Glorp", rarity = "Common", rate = 15, weight = 70, bodyColor = Color3.fromRGB(200, 160, 255), accentColor = Color3.fromRGB(120, 70, 200), bodyShape = "Ball", accessory = "Spots", scale = 1.0 },
	{ name = "Comet Croissant", rarity = "Common", rate = 20, weight = 60, bodyColor = Color3.fromRGB(255, 200, 110), accentColor = Color3.fromRGB(200, 130, 40), bodyShape = "Block", accessory = "Tail", scale = 1.0 },
	{ name = "Plasma Pingu", rarity = "Common", rate = 25, weight = 50, bodyColor = Color3.fromRGB(60, 70, 90), accentColor = Color3.fromRGB(240, 240, 250), bodyShape = "Cylinder", accessory = "Beak", scale = 1.0 },
	-- Uncommon
	{ name = "Nebula Noodle", rarity = "Uncommon", rate = 60, weight = 30, bodyColor = Color3.fromRGB(255, 150, 200), accentColor = Color3.fromRGB(255, 220, 240), bodyShape = "Cylinder", accessory = "Tail", scale = 1.0 },
	{ name = "Astro Mochi", rarity = "Uncommon", rate = 90, weight = 24, bodyColor = Color3.fromRGB(255, 240, 220), accentColor = Color3.fromRGB(255, 170, 200), bodyShape = "Ball", accessory = "Ears", scale = 0.95 },
	{ name = "Void Vito", rarity = "Uncommon", rate = 130, weight = 18, bodyColor = Color3.fromRGB(70, 60, 120), accentColor = Color3.fromRGB(160, 130, 255), bodyShape = "Ball", accessory = "Ring", scale = 1.05 },
	{ name = "Meteor Mochi", rarity = "Uncommon", rate = 180, weight = 14, bodyColor = Color3.fromRGB(255, 120, 80), accentColor = Color3.fromRGB(255, 220, 120), bodyShape = "Ball", accessory = "Spots", scale = 1.0 },
	-- Rare
	{ name = "Galactic Gumbo", rarity = "Rare", rate = 400, weight = 8, bodyColor = Color3.fromRGB(90, 200, 140), accentColor = Color3.fromRGB(220, 255, 200), bodyShape = "Block", accessory = "Horns", scale = 1.1 },
	{ name = "Star S'more", rarity = "Rare", rate = 600, weight = 6, bodyColor = Color3.fromRGB(150, 100, 60), accentColor = Color3.fromRGB(255, 250, 230), bodyShape = "Block", accessory = "None", scale = 1.1 },
	{ name = "Cosmo Corgi", rarity = "Rare", rate = 900, weight = 4, bodyColor = Color3.fromRGB(230, 160, 80), accentColor = Color3.fromRGB(255, 240, 220), bodyShape = "Block", accessory = "Ears", scale = 1.1 },
	{ name = "Lunar Llama", rarity = "Rare", rate = 1200, weight = 3, bodyColor = Color3.fromRGB(220, 220, 235), accentColor = Color3.fromRGB(150, 200, 255), bodyShape = "Cylinder", accessory = "Ears", scale = 1.2 },
	-- Epic
	{ name = "Solar Squirrel", rarity = "Epic", rate = 2000, weight = 2, bodyColor = Color3.fromRGB(255, 160, 40), accentColor = Color3.fromRGB(255, 230, 150), bodyShape = "Ball", accessory = "Tail", scale = 1.15 },
	{ name = "Orbit Ostrich", rarity = "Epic", rate = 3000, weight = 1.5, bodyColor = Color3.fromRGB(200, 220, 255), accentColor = Color3.fromRGB(255, 140, 180), bodyShape = "Cylinder", accessory = "Wings", scale = 1.3 },
	{ name = "Quasar Quokka", rarity = "Epic", rate = 4500, weight = 1, bodyColor = Color3.fromRGB(180, 140, 90), accentColor = Color3.fromRGB(255, 220, 170), bodyShape = "Ball", accessory = "Ears", scale = 1.2 },
	-- Legendary
	{ name = "Pulsar Panda", rarity = "Legendary", rate = 7000, weight = 0.5, bodyColor = Color3.fromRGB(240, 240, 245), accentColor = Color3.fromRGB(40, 40, 50), bodyShape = "Ball", accessory = "Ears", scale = 1.35 },
	{ name = "Nova Narwhal", rarity = "Legendary", rate = 10000, weight = 0.3, bodyColor = Color3.fromRGB(140, 200, 255), accentColor = Color3.fromRGB(255, 255, 255), bodyShape = "Cylinder", accessory = "Horns", scale = 1.4 },
	-- Secret
	{ name = "Supernova Sloth", rarity = "Secret", rate = 25000, weight = 0.1, bodyColor = Color3.fromRGB(255, 90, 120), accentColor = Color3.fromRGB(255, 220, 80), bodyShape = "Ball", accessory = "Ring", scale = 1.5 },
	{ name = "Big Bang Burrito", rarity = "Secret", rate = 50000, weight = 0.05, bodyColor = Color3.fromRGB(220, 180, 100), accentColor = Color3.fromRGB(120, 200, 90), bodyShape = "Cylinder", accessory = "Spots", scale = 1.6 },
} :: { Species }

local speciesByName: { [string]: Species } = {}
for _, species in BrainrotData.SPECIES do
	speciesByName[species.name] = species
end

function BrainrotData.getSpecies(name: string): Species?
	return speciesByName[name]
end

function BrainrotData.getRate(speciesName: string, mutation: MutationName): number
	local species = speciesByName[speciesName]
	if not species then
		return 0
	end
	local multiplier = BrainrotData.MUTATION_MULTIPLIERS[mutation] or 1
	return species.rate * multiplier
end

function BrainrotData.isValidMutation(mutation: string): boolean
	return BrainrotData.MUTATION_MULTIPLIERS[mutation :: MutationName] ~= nil
end

-- Four named, levelled upgrade tracks. Level 0 is the starting level (free).
BrainrotData.UPGRADES = {
	Beam = {
		displayName = "Tractor Beam",
		blurb = "Longer pull range for catching wild brainrots.",
		levels = {
			{ name = "Mk I", cost = 0, beamRange = 24 },
			{ name = "Mk II", cost = 500, beamRange = 32 },
			{ name = "Mk III", cost = 2500, beamRange = 42 },
		},
	},
	Cargo = {
		displayName = "Cargo Bubble",
		blurb = "Carry more brainrots home in one trip.",
		levels = {
			{ name = "Standard", cost = 0, carryCapacity = 1 },
			{ name = "Double Bubble", cost = 800, carryCapacity = 2 },
			{ name = "Triple Bubble", cost = 3000, carryCapacity = 3 },
		},
	},
	Shield = {
		displayName = "Shield Extender",
		blurb = "Your module lock lasts longer.",
		levels = {
			{ name = "Standard", cost = 0, lockSeconds = 30 },
			{ name = "Extended", cost = 600, lockSeconds = 40 },
			{ name = "Max Dome", cost = 2000, lockSeconds = 50 },
		},
	},
	Expansion = {
		displayName = "Module Expansion",
		blurb = "More habitat pods in your module.",
		levels = {
			{ name = "Standard", cost = 0, extraPods = 0 },
			{ name = "+1 Pod", cost = 1200, extraPods = 1 },
			{ name = "+2 Pods", cost = 5000, extraPods = 2 },
		},
	},
} :: { [string]: UpgradeTrack }

-- The 3-mission chain. The HUD always shows the next goal.
BrainrotData.MISSIONS = {
	{ id = "catch1", text = "Catch a brainrot (E)", goal = 1, reward = 100, stat = "caught" },
	{ id = "dock3", text = "Dock 3 brainrots in your pods", goal = 3, reward = 500, stat = "docked" },
	{ id = "earn2000", text = "Earn 2,000 credits total", goal = 2000, reward = 1500, stat = "earned" },
} :: { Mission }

-- Tuned constants for the whole game.
BrainrotData.CONFIG = {
	maxPlayers = 8,
	basePods = 4,
	maxPods = 8,
	wildTargetCount = 12,
	wildWanderSpeed = 4,
	stormPeriodSeconds = 60, -- time between solar storms
	stormWarningSeconds = 15, -- "GET TO YOUR DOME!" warning before the storm hits
	stormDurationSeconds = 15,
	stormKnockbackSpeed = 55,
	stormIrradiateChance = 0.25, -- exposed wild brainrot mutates Irradiated
	zorkPeriodSeconds = 70, -- ZORK the Snatcher raids about this often
	zorkBonksToDriveOff = 3,
	zorkBonkBonusCredits = 250,
	goldenHourMinGapSeconds = 150,
	goldenHourMaxGapSeconds = 240,
	goldenHourDurationSeconds = 60,
	goldenHourMultiplier = 2,
	meteorShowerMinGapSeconds = 180,
	meteorShowerMaxGapSeconds = 300,
	meteorShowerBonusCount = 6,
	rebirthBaseCost = 5000, -- cost = base * 2 ^ rebirths
	rebirthMultiplierPerRing = 0.5, -- +50% credits forever per rebirth
	lockCooldownSeconds = 60,
	catchCooldownSeconds = 0.5,
	stealCooldownSeconds = 5,
	bonkCooldownSeconds = 0.5,
	dockRangeStuds = 12,
	stealRangeStuds = 12,
	bonkRangeStuds = 14,
	domeSafeRadiusStuds = 17,
	autosaveSeconds = 60,
	animCullDistanceStuds = 220,
}

return BrainrotData
