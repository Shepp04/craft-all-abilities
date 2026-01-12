--!strict
-- Craftables (GameData type)

export type Recipe = {
	ingredients: {
		[ string ]: number,
	},
	craftingTime: number, -- in seconds
	minCraftingStationLevel: number?, -- optional minimum level of crafting station required
	isShaped: boolean, -- whether the recipe is shaped or shapeless
}

export type Stats = {
	cooldown: number?, -- in seconds
	[ string ]: number,
}

export type BehaviourConfig = {
	[ string ]: any,
}

export type StockInfo = {
	stockChance: number, -- chance (0 to 1) of item being in stock
	maxStock: number, -- maximum stock quantity
	purchasePrice: number, -- price to purchase the item
	purchaseCurrencyId: string, -- currency id used for purchase
}

export type DataEntry = {
	name: string,
	icon: string, -- image asset id or emoji
	rarity: number, -- e.g. 1 (common) to 5 (legendary)
	recipe: Recipe?, -- nil if not craftable
	stock: StockInfo?, -- nil if not sold by NPCs
	stats: Stats?, -- nil if no stats
	tags: { string }?, -- optional tags for categorisation
	behaviours: { [string]: BehaviourConfig }?,
	requirements: { [string]: any }?, -- optional requirements to unlock crafting
}

type DataTypeDict = {
	name: string,
	public_field_whitelist: { [string]: boolean },
	items: { [string]: DataEntry }
}

local DATA_TYPE_NAME = "Craftables"
local PUBLIC_FIELD_WHITELIST = {
	name = true,
	icon = true,
	rarity = true,
	recipe = true,
	stock = true,
	stats = true,
	tags = true,
	behaviours = true,
}
local DATA: { [string]: DataEntry } = {
	["default_craftable"] = {
		name = "Default Craftable",
		icon = "🛠️",
		rarity = 1,
		recipe = nil,
		stock = nil,
		stats = nil,
		tags = nil,
		behaviours = nil,
	},
}

local DataTypeDict: DataTypeDict = {
	name = DATA_TYPE_NAME,
	public_field_whitelist = PUBLIC_FIELD_WHITELIST,
	items = DATA,
}

return DataTypeDict