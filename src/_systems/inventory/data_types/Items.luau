--!strict
-- Items (GameData type)

export type DataEntry = {
	name: string,
	description: string?,
	icon: string, -- emoji or asset id ("rbxassetid://123456789")
	type: "ingredient" | "crafted" | "tool",
	rarity: number, -- 1-5 scale
	tags: { string }?,

	-- text behaviour
	textData: {
		nameColor: Color3,
		nameFont: Enum.Font?,
		descriptionColor: Color3?,
		descriptionFont: Enum.Font?,
	}?,

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
	name = true,
	description = true,
	icon = true,
	type = true,
	rarity = true,
	tags = true,
	textData = true,
	stackable = true,
	maxStack = true,
	unique = true,
	placeable = true,
	placementData = true,
	incomeData = true,
	canCraftWith = true,
	craftable = true,
	recipeId = true,
	purchasable = true,
	priceData = true,
	interactive = true,
	interactionData = true,
	abilityId = true,
	deprecated = true,
	hidden = true,
	createdAt = true,
}
local DATA: { [string]: DataEntry } = {
	["default_item"] = {
		name = "Default Item",
		description = "A default item used for testing purposes.",
		icon = "📦",
		type = "crafted",
		rarity = 1,
		stackable = true,
		maxStack = 99,
		placeable = false,
		incomeData = nil,
		canCraftWith = false,
		craftable = false,
		purchasable = false,
		interactive = false,
		deprecated = false,
		hidden = false,
		createdAt = 0,
	},

	["non_stackable_item"] = {
		name = "Non-Stackable Item",
		description = "An item that cannot be stacked in the inventory.",
		icon = "🗡️",
		type = "tool",
		rarity = 2,
		stackable = false,
		placeable = false,
		incomeData = nil,
		canCraftWith = false,
		craftable = false,
		purchasable = false,
		interactive = false,
		deprecated = false,
		hidden = false,
		createdAt = 0,
	},

	["water"] = {
		name = "Water",
		description = "A basic ingredient used in various recipes.",
		icon = "💦",
		type = "crafted",
		textData = {
			nameColor = Color3.fromRGB(100, 149, 237), -- cornflower blue
			nameFont = Enum.Font.FredokaOne,
		},
		rarity = 1,
		stackable = true,
		maxStack = 4,
		placeable = false,
		incomeData = nil,
		canCraftWith = true,
		craftable = false,
		purchasable = true,
		priceData = {
			price = 5,
			currencyId = "coins",
		},
		interactive = false,
		deprecated = false,
		hidden = false,
		createdAt = 0,
	},

	["flame"] = {
		name = "Flame",
		description = "A mystical ingredient that burns with an eternal fire.",
		icon = "🔥",
		type = "crafted",
		textData = {
			nameColor = Color3.fromRGB(255, 69, 0), -- orange red
			nameFont = Enum.Font.FredokaOne,
		},
		rarity = 3,
		stackable = true,
		maxStack = 10,
		placeable = false,
		incomeData = nil,
		canCraftWith = true,
		craftable = false,
		purchasable = true,
		priceData = {
			price = 20,
			currencyId = "gems",
		},
		interactive = false,
		deprecated = false,
		hidden = false,
		createdAt = 0,
	},

	["magic"] = {
		name = "Magic",
		description = "An ethereal substance used in powerful enchantments.",
		icon = "✨",
		type = "crafted",
		textData = {
			nameColor = Color3.fromRGB(186, 85, 211), -- medium orchid
			nameFont = Enum.Font.FredokaOne,
			descriptionColor = Color3.fromRGB(200, 162, 200),
			descriptionFont = Enum.Font.PatrickHand,
		},
		rarity = 4,
		stackable = true,
		maxStack = 5,
		placeable = false,
		incomeData = nil,
		canCraftWith = true,
		craftable = false,
		purchasable = true,
		priceData = {
			price = 50,
			currencyId = "gems",
		},
		interactive = false,
		deprecated = false,
		hidden = false,
		createdAt = 0,
	},
}

local DataTypeDict: DataTypeDict = {
	name = DATA_TYPE_NAME,
	public_field_whitelist = PUBLIC_FIELD_WHITELIST,
	items = DATA,
}

return DataTypeDict
