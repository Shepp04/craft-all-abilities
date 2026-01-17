--!strict
-- CraftingStations (GameData type)
-- Defines the available crafting stations in the game

export type DataEntry = {
	id: string?, -- Auto-filled from key
	name: string,
	description: string,
	icon: string,
	
	-- Unlock requirements
	unlockRequirements: {
		level: number?, -- Player level required
		currencyId: string?, -- Currency needed to unlock
		currencyCost: number?, -- Cost to unlock
		prerequisiteStationId: string?, -- Must have this station first
	}?,
	
	-- Station capabilities
	maxLevel: number, -- Maximum upgrade level
	upgradeCosts: { -- Cost per level (indexed by level)
		[number]: {
			currencyId: string,
			amount: number,
		}?
	}?,
	
	-- Crafting speed multiplier per level
	speedMultipliers: { [number]: number }?, -- e.g., [1] = 1.0, [2] = 1.2, [3] = 1.5
	
	-- Visual/gameplay
	modelPath: { string }?, -- Path to station model in ReplicatedStorage
	interactionRange: number?, -- ProximityPrompt MaxActivationDistance
}

type DataTypeDict = {
	name: string,
	public_field_whitelist: { [string]: boolean },
	items: { [string]: DataEntry }
}

local DATA_TYPE_NAME = "CraftingStations"
local PUBLIC_FIELD_WHITELIST = {
	id = true,
	name = true,
	description = true,
	icon = true,
	unlockRequirements = true,
	maxLevel = true,
	upgradeCosts = true,
	speedMultipliers = true,
	modelPath = true,
	interactionRange = true,
}

local DATA: { [string]: DataEntry } = {
	["basic_workbench"] = {
		name = "Basic Workbench",
		description = "A simple crafting station for basic recipes.",
		icon = "🔨",
		unlockRequirements = nil, -- Unlocked by default
		maxLevel = 3,
		upgradeCosts = {
			[2] = { currencyId = "coins", amount = 100 },
			[3] = { currencyId = "coins", amount = 250 },
		},
		speedMultipliers = {
			[1] = 1.0,
			[2] = 1.2,
			[3] = 1.5,
		},
		interactionRange = 10,
	},
}

-- Auto-fill id field from keys
for stationId, station in DATA do
	station.id = stationId
end

local DataTypeDict: DataTypeDict = {
	name = DATA_TYPE_NAME,
	public_field_whitelist = PUBLIC_FIELD_WHITELIST,
	items = DATA,
}

return DataTypeDict
