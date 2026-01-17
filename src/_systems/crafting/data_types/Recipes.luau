--!strict
-- Recipes (GameData type)

export type DataEntry = {
	id: string?, -- Auto-filled from key on module load
	name: string,
	output: {
		itemId: string,
		quantity: number,
	},
	ingredients: {
		{ itemId: string, quantity: number }
	},
	craftTime: number,
	requirements: {
		craftingStationId: string?,
		minStationLevel: number?,
	}?,
}

type DataTypeDict = {
	name: string,
	public_field_whitelist: { [string]: boolean },
	items: { [string]: DataEntry }
}

local DATA_TYPE_NAME = "Recipes"
local PUBLIC_FIELD_WHITELIST = {
	id = true,
	name = true,
	output = true,
	ingredients = true,
	craftTime = true,
	requirements = true,
}

-- Example recipes
local DATA: { [string]: DataEntry } = {
	["wooden_plank"] = {
		name = "Wooden Plank",
		output = {
			itemId = "wood",
			quantity = 4,
		},
		ingredients = {
			{ itemId = "wood", quantity = 1 },
		},
		craftTime = 5,
		requirements = nil,
	},
	
	["stick"] = {
		name = "Stick",
		output = {
			itemId = "wood",
			quantity = 2,
		},
		ingredients = {
			{ itemId = "wood", quantity = 1 },
		},
		craftTime = 3,
		requirements = nil,
	},
}

-- Auto-fill id field from keys
for recipeId, recipe in DATA do
	recipe.id = recipeId
end

local DataTypeDict: DataTypeDict = {
	name = DATA_TYPE_NAME,
	public_field_whitelist = PUBLIC_FIELD_WHITELIST,
	items = DATA,
}

return DataTypeDict
