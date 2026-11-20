--!strict
-- BrainrotData
-- Shared game data for BRAINROT ORBIT: the 30 original brainrot species, the
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
	stat: string, -- "caught" | "docked" | "earned" | "locked"
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
} :: { [MutationName]: number }

-- The full roster: 30 original alien brainrots. Rates are credits per second.
-- Round 2 added ten species (Pixel Puff, Luna Lolly, Cosmo Cookie, Quantum
-- Quiche, Gravity Grape, Eclipse Eel, Asteroid Axolotl, Warp Whale, Galaxy
-- Gator, Dark Matter Donut); every rate slots between its neighbours so the
-- earn curve is unchanged in shape, just denser.
BrainrotData.SPECIES = {
	-- Common
	{ name = "Bloop Blorp", rarity = "Common", rate = 8, weight = 100, bodyColor = Color3.fromRGB(120, 200, 255), accentColor = Color3.fromRGB(40, 110, 200), bodyShape = "Ball", accessory = "Antenna", scale = 0.9 },
	{ name = "Pixel Puff", rarity = "Common", rate = 10, weight = 90, bodyColor = Color3.fromRGB(110, 230, 220), accentColor = Color3.fromRGB(30, 140, 130), bodyShape = "Block", accessory = "Antenna", scale = 0.85 },
	{ name = "Zorp Zorp", rarity = "Common", rate = 12, weight = 80, bodyColor = Color3.fromRGB(150, 255, 150), accentColor = Color3.fromRGB(40, 160, 60), bodyShape = "Ball", accessory = "Ears", scale = 0.9 },
	{ name = "Gloob Glorp", rarity = "Common", rate = 15, weight = 70, bodyColor = Color3.fromRGB(200, 160, 255), accentColor = Color3.fromRGB(120, 70, 200), bodyShape = "Ball", accessory = "Spots", scale = 1.0 },
	{ name = "Luna Lolly", rarity = "Common", rate = 18, weight = 65, bodyColor = Color3.fromRGB(255, 180, 210), accentColor = Color3.fromRGB(255, 245, 220), bodyShape = "Ball", accessory = "Ring", scale = 0.9 },
	{ name = "Comet Croissant", rarity = "Common", rate = 20, weight = 60, bodyColor = Color3.fromRGB(255, 200, 110), accentColor = Color3.fromRGB(200, 130, 40), bodyShape = "Block", accessory = "Tail", scale = 1.0 },
	{ name = "Cosmo Cookie", rarity = "Common", rate = 22, weight = 55, bodyColor = Color3.fromRGB(210, 170, 120), accentColor = Color3.fromRGB(120, 80, 200), bodyShape = "Cylinder", accessory = "Spots", scale = 0.95 },
	{ name = "Plasma Pingu", rarity = "Common", rate = 25, weight = 50, bodyColor = Color3.fromRGB(60, 70, 90), accentColor = Color3.fromRGB(240, 240, 250), bodyShape = "Cylinder", accessory = "Beak", scale = 1.0 },
	-- Uncommon
	{ name = "Nebula Noodle", rarity = "Uncommon", rate = 60, weight = 30, bodyColor = Color3.fromRGB(255, 150, 200), accentColor = Color3.fromRGB(255, 220, 240), bodyShape = "Cylinder", accessory = "Tail", scale = 1.0 },
	{ name = "Quantum Quiche", rarity = "Uncommon", rate = 75, weight = 27, bodyColor = Color3.fromRGB(170, 140, 255), accentColor = Color3.fromRGB(255, 230, 120), bodyShape = "Cylinder", accessory = "Ring", scale = 1.0 },
	{ name = "Astro Mochi", rarity = "Uncommon", rate = 90, weight = 24, bodyColor = Color3.fromRGB(255, 240, 220), accentColor = Color3.fromRGB(255, 170, 200), bodyShape = "Ball", accessory = "Ears", scale = 0.95 },
	{ name = "Void Vito", rarity = "Uncommon", rate = 130, weight = 18, bodyColor = Color3.fromRGB(70, 60, 120), accentColor = Color3.fromRGB(160, 130, 255), bodyShape = "Ball", accessory = "Ring", scale = 1.05 },
	{ name = "Gravity Grape", rarity = "Uncommon", rate = 150, weight = 16, bodyColor = Color3.fromRGB(140, 80, 200), accentColor = Color3.fromRGB(200, 255, 150), bodyShape = "Ball", accessory = "Tail", scale = 1.0 },
	{ name = "Meteor Mochi", rarity = "Uncommon", rate = 180, weight = 14, bodyColor = Color3.fromRGB(255, 120, 80), accentColor = Color3.fromRGB(255, 220, 120), bodyShape = "Ball", accessory = "Spots", scale = 1.0 },
	-- Rare
	{ name = "Galactic Gumbo", rarity = "Rare", rate = 400, weight = 8, bodyColor = Color3.fromRGB(90, 200, 140), accentColor = Color3.fromRGB(220, 255, 200), bodyShape = "Block", accessory = "Horns", scale = 1.1 },
	{ name = "Star S'more", rarity = "Rare", rate = 600, weight = 6, bodyColor = Color3.fromRGB(150, 100, 60), accentColor = Color3.fromRGB(255, 250, 230), bodyShape = "Block", accessory = "None", scale = 1.1 },
	{ name = "Eclipse Eel", rarity = "Rare", rate = 750, weight = 5, bodyColor = Color3.fromRGB(50, 70, 140), accentColor = Color3.fromRGB(255, 200, 90), bodyShape = "Cylinder", accessory = "Tail", scale = 1.1 },
	{ name = "Cosmo Corgi", rarity = "Rare", rate = 900, weight = 4, bodyColor = Color3.fromRGB(230, 160, 80), accentColor = Color3.fromRGB(255, 240, 220), bodyShape = "Block", accessory = "Ears", scale = 1.1 },
	{ name = "Lunar Llama", rarity = "Rare", rate = 1200, weight = 3, bodyColor = Color3.fromRGB(220, 220, 235), accentColor = Color3.fromRGB(150, 200, 255), bodyShape = "Cylinder", accessory = "Ears", scale = 1.2 },
	{ name = "Asteroid Axolotl", rarity = "Rare", rate = 1500, weight = 2.5, bodyColor = Color3.fromRGB(160, 160, 175), accentColor = Color3.fromRGB(255, 170, 200), bodyShape = "Ball", accessory = "Ears", scale = 1.15 },
	-- Epic
	{ name = "Solar Squirrel", rarity = "Epic", rate = 2000, weight = 2, bodyColor = Color3.fromRGB(255, 160, 40), accentColor = Color3.fromRGB(255, 230, 150), bodyShape = "Ball", accessory = "Tail", scale = 1.15 },
	{ name = "Orbit Ostrich", rarity = "Epic", rate = 3000, weight = 1.5, bodyColor = Color3.fromRGB(200, 220, 255), accentColor = Color3.fromRGB(255, 140, 180), bodyShape = "Cylinder", accessory = "Wings", scale = 1.3 },
	{ name = "Warp Whale", rarity = "Epic", rate = 3600, weight = 1.2, bodyColor = Color3.fromRGB(60, 110, 200), accentColor = Color3.fromRGB(140, 220, 255), bodyShape = "Cylinder", accessory = "Wings", scale = 1.35 },
	{ name = "Quasar Quokka", rarity = "Epic", rate = 4500, weight = 1, bodyColor = Color3.fromRGB(180, 140, 90), accentColor = Color3.fromRGB(255, 220, 170), bodyShape = "Ball", accessory = "Ears", scale = 1.2 },
	-- Legendary
	{ name = "Pulsar Panda", rarity = "Legendary", rate = 7000, weight = 0.5, bodyColor = Color3.fromRGB(240, 240, 245), accentColor = Color3.fromRGB(40, 40, 50), bodyShape = "Ball", accessory = "Ears", scale = 1.35 },
	{ name = "Galaxy Gator", rarity = "Legendary", rate = 8500, weight = 0.4, bodyColor = Color3.fromRGB(80, 190, 110), accentColor = Color3.fromRGB(255, 215, 90), bodyShape = "Block", accessory = "Horns", scale = 1.4 },
	{ name = "Nova Narwhal", rarity = "Legendary", rate = 10000, weight = 0.3, bodyColor = Color3.fromRGB(140, 200, 255), accentColor = Color3.fromRGB(255, 255, 255), bodyShape = "Cylinder", accessory = "Horns", scale = 1.4 },
	-- Secret
	{ name = "Supernova Sloth", rarity = "Secret", rate = 25000, weight = 0.1, bodyColor = Color3.fromRGB(255, 90, 120), accentColor = Color3.fromRGB(255, 220, 80), bodyShape = "Ball", accessory = "Ring", scale = 1.5 },
	{ name = "Dark Matter Donut", rarity = "Secret", rate = 35000, weight = 0.07, bodyColor = Color3.fromRGB(45, 40, 70), accentColor = Color3.fromRGB(255, 110, 200), bodyShape = "Ball", accessory = "Ring", scale = 1.5 },
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

-- The 4-mission chain. The HUD always shows the next goal. Mission 4 teaches
-- the lock verb, which is the player's only real defence against thieves.
-- Texts are kept short so the mission strip fits at a readable size.
BrainrotData.MISSIONS = {
	{ id = "catch1", text = "Catch a brainrot (E)", goal = 1, reward = 100, stat = "caught" },
	{ id = "dock3", text = "Dock 3 brainrots", goal = 3, reward = 500, stat = "docked" },
	{ id = "earn2000", text = "Earn 2,000 credits", goal = 2000, reward = 1500, stat = "earned" },
	{ id = "lock1", text = "Lock your module (L)", goal = 1, reward = 2500, stat = "locked" },
} :: { Mission }

export type Quest = {
	id: string,
	text: string,
	goal: number,
	reward: number, -- credits paid when the quest completes
	stat: string, -- "caught" | "docked" | "earned" | "locked" | "discovered" | "upgrades" | "rebirths" | "stolen" | "zapped"
}

-- The 14 station quests (round 7). Unlike the mission chain, every quest
-- tracks its own stat in parallel, so several can complete at once. All
-- stats come from the saved profile (or are derived from it), so progress
-- survives a rejoin. Rewards are paid once per quest, the first time its
-- goal is reached.
BrainrotData.QUESTS = {
	{ id = "q_catch1", text = "Catch your first brainrot", goal = 1, reward = 100, stat = "caught" },
	{ id = "q_catch10", text = "Catch 10 brainrots", goal = 10, reward = 800, stat = "caught" },
	{ id = "q_catch25", text = "Catch 25 brainrots", goal = 25, reward = 2500, stat = "caught" },
	{ id = "q_dock3", text = "Dock 3 brainrots in your pods", goal = 3, reward = 500, stat = "docked" },
	{ id = "q_dock8", text = "Dock 8 brainrots in your pods", goal = 8, reward = 2000, stat = "docked" },
	{ id = "q_earn2k", text = "Earn 2,000 credits", goal = 2000, reward = 1500, stat = "earned" },
	{ id = "q_earn50k", text = "Earn 50,000 credits", goal = 50000, reward = 6000, stat = "earned" },
	{ id = "q_lock1", text = "Lock your module once", goal = 1, reward = 2500, stat = "locked" },
	{ id = "q_lock3", text = "Lock your module 3 times", goal = 3, reward = 4000, stat = "locked" },
	{ id = "q_find5", text = "Find 5 Star Chart entries", goal = 5, reward = 1000, stat = "discovered" },
	{ id = "q_find15", text = "Find 15 Star Chart entries", goal = 15, reward = 5000, stat = "discovered" },
	{ id = "q_upg2", text = "Buy 2 upgrades", goal = 2, reward = 1200, stat = "upgrades" },
	{ id = "q_steal1", text = "Steal a brainrot from a rival", goal = 1, reward = 1500, stat = "stolen" },
	{ id = "q_zap1", text = "Zap ZORK away from the station", goal = 1, reward = 1500, stat = "zapped" },
} :: { Quest }

-- One-line flavor text per species (round 7): tap a tile in the Star Chart
-- to read its line. Plain human English, one joke each.
BrainrotData.FLAVOR = {
	["Bloop Blorp"] = "Blorps when happy. Blorps when sad. Mostly just blorps.",
	["Pixel Puff"] = "Nobody knows if it is a pet or a screensaver.",
	["Zorp Zorp"] = "Named itself twice because once was not enough.",
	["Gloob Glorp"] = "Smells like grape soda and poor decisions.",
	["Luna Lolly"] = "Made of moonlight and sugar. Do not lick it.",
	["Comet Croissant"] = "Flaky, fast, and gone before breakfast.",
	["Cosmo Cookie"] = "Baked in zero gravity. Still crumbles everywhere.",
	["Plasma Pingu"] = "A penguin that runs on static electricity.",
	["Nebula Noodle"] = "Slippery in five dimensions at once.",
	["Quantum Quiche"] = "It is both here and in the fridge until you look.",
	["Astro Mochi"] = "Soft, round, and impossible to stay mad at.",
	["Void Vito"] = "Speaks in whispers. The whispers echo.",
	["Gravity Grape"] = "Falls up on Tuesdays. Nobody has explained it.",
	["Meteor Mochi"] = "Arrived by crashing. Stayed for the snacks.",
	["Galactic Gumbo"] = "A stew that learned to walk. A slow walker.",
	["Star S'more"] = "Toasted by an actual star. Still gooey inside.",
	["Eclipse Eel"] = "Only comes out when the sun goes away.",
	["Cosmo Corgi"] = "Short legs, long orbit, zero fear.",
	["Lunar Llama"] = "Hums at the moon. The moon hums back.",
	["Asteroid Axolotl"] = "Smiles at everything, including the void.",
	["Solar Squirrel"] = "Stores sunshine in its cheeks for winter.",
	["Orbit Ostrich"] = "Too big to fly, too fast to catch.",
	["Warp Whale"] = "Sings songs that arrive before it does.",
	["Quasar Quokka"] = "The happiest thing in the known universe.",
	["Pulsar Panda"] = "Blinks in perfect rhythm. Great at parties.",
	["Galaxy Gator"] = "Has a whole spiral arm in its smile.",
	["Nova Narwhal"] = "Its horn points at whatever is about to explode.",
	["Supernova Sloth"] = "Moves slowly. Explodes quickly. Plan accordingly.",
	["Dark Matter Donut"] = "Invisible filling. You can taste the mystery.",
	["Big Bang Burrito"] = "One bite created a universe. Two bites, a food coma.",
} :: { [string]: string }

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
