--!strict
-- Items (GameData type)

export type DataEntry = {
	name: string,
	description: string?,
	icon: string, -- emoji or asset id ("rbxassetid://123456789")
	type: "ingredient" | "crafted" | "tool",
	rarity: number, -- 1-5 scale
	tags: { string }?,

	-- inventory behaviour
	stackable: boolean,
	maxStack: number?,
	unique: boolean?, -- uses instances with properties e.g. durability or enchantments

	-- plot behaviour
	placeable: boolean,
	placementData: {
		modelPath: { string }, -- model path e.g. { "Shared", "Assets", "Items", "wooden_table" }
		gridSize: Vector2,
		rotatable: boolean,
		snapToGrid: boolean,
	}?,

	-- income behaviour
	incomeData: {
		rates: { [string]: number }, -- currencyId -> amount per interval
		interval: number?, -- seconds
		maxStored: { [string]: number }, -- currencyId -> max amount storable
		autoCollectable: boolean,
	}?,

	-- crafting behaviour
	canCraftWith: boolean, -- usable in crafting recipes
	craftable: boolean, -- craftable item
	recipeId: string?,

	-- purchase behaviour
	purchasable: boolean,
	priceData: {
		price: number,
		currencyId: string,
	}?,

	-- interaction behaviour
	interactive: boolean,
	interactionData: {
		cooldown: number, -- seconds
	}?,

	-- ability behaviour
	abilityId: string?,

	-- other
	deprecated: boolean?,
	hidden: boolean?, -- hide from UI but keep functional (for events/testing)
	createdAt: number?, -- timestamp
}

type DataTypeDict = {
	name: string,
	public_field_whitelist: { [string]: boolean },
	items: { [string]: DataEntry }
}

local DATA_TYPE_NAME = "Items"
local PUBLIC_FIELD_WHITELIST = {
	id = true, name = true, icon = true, rarity = true, stackable = true, maxStack = true,
}
local DATA: { [string]: DataEntry } = {
}

local DataTypeDict: DataTypeDict = {
	name = DATA_TYPE_NAME,
	public_field_whitelist = PUBLIC_FIELD_WHITELIST,
	items = DATA,
}

return DataTypeDict
