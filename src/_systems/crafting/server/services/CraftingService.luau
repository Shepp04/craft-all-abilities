--!strict
-- CraftingService (Service) — lifecycle-first singleton discovered by Services registry.

-- // Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Classes
local CraftingStation = require(ServerScriptService.Server.Classes:WaitForChild("CraftingStation"))

-- // Types (custom)
type CraftingStationAPI = CraftingStation.CraftingStationAPI

-- Import from correct location
local InventoryService = require(ServerScriptService.Server.Services.InventoryService)
type InventoryProfile = InventoryService.InventoryProfile

-- Import Recipes type
export type RecipeEntry = {
	name: string,
	output: {
		itemId: string,
		quantity: number,
	},
	ingredients: {
		{ itemId: string, quantity: number? }
	},
	craftTime: number,
	requirements: {
		craftingStationId: string?,
		minStationLevel: number?,
	}?,
}

-- // Types (generated)
local ServicesTypes = require(ReplicatedStorage.Shared.Types.Services)

-- // Type aliases for deps inferred from real modules
type ServiceRegistry = ServicesTypes.Registry

type DataInterface  = ServicesTypes.DataInterface
type SharedPackages = typeof(require(ReplicatedStorage.Shared.Packages))
type GameData       = typeof(require(ReplicatedStorage.Shared.GameData))
type Monetisation   = typeof(require(ReplicatedStorage.Shared.Monetisation))
type Config         = typeof(require(ReplicatedStorage.Shared.Config))
type Tunables       = { [string]: any } -- external tunables, not synced by rojo

export type Deps = {
	DataInterface: DataInterface,
	SharedPackages: SharedPackages,
	GameData: GameData,
	Monetisation: Monetisation,
	Config: Config,
	Tunables: Tunables,
}

export type CraftingServiceAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Services: ServiceRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: CraftingServiceAPI, deps: Deps) -> (),
	Start: (self: CraftingServiceAPI) -> (),
	Destroy: (self: CraftingServiceAPI) -> (),
}

local CraftingService = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Services = {} :: ServiceRegistry,
}

-- Private captured deps for intellisense-friendly access
local _deps: Deps?
local _recipeCache: { [string]: RecipeEntry } = {}

-- ========== Helpers ========== --

local function ingredientCountsToString(ingredientCounts: { [string]: number }): string
	local parts: { string } = {}
	for itemId, count in ingredientCounts do
		table.insert(parts, itemId .. ":" .. tostring(count))
	end
	table.sort(parts)
	return table.concat(parts, "|")
end

local function doesRecipeMatch(recipe: RecipeEntry, provided: { [string]: number }): boolean
	-- Build recipe requirements map
	local required = {}
	for _, ingredient in recipe.ingredients do
		required[ingredient.itemId] = (required[ingredient.itemId] or 0) + (ingredient.quantity or 1)
	end

	-- Compare: must match exactly
	for itemId, count in required do
		if provided[itemId] ~= count then
			return false
		end
	end
	for itemId, count in provided do
		if required[itemId] ~= count then
			return false
		end
	end
	
	return true
end

local function matchRecipe(stackIds: { string }, inventoryProfile: InventoryProfile): RecipeEntry?
	-- Build ingredient count from stackIds
	local ingredientCounts: { [string]: number } = {}
	for _, stackId in stackIds do
		local stack = inventoryProfile.items[stackId]
		if not stack then return nil end -- Invalid stack

		ingredientCounts[stack.itemId] = (ingredientCounts[stack.itemId] or 0) + 1
	end

	-- Iterate all recipes, find exact match
	local ingredientCountIdx = ingredientCountsToString(ingredientCounts)
	if _recipeCache[ingredientCountIdx] then
		print("[CraftingService] Cache hit for recipe:", ingredientCountIdx)
		return _recipeCache[ingredientCountIdx]
	end

	-- Get all recipes from GameData
	local recipes = _deps.GameData.GetDataType("Recipes")
	if not recipes then
		warn("[CraftingService] No Recipes data type found")
		return nil
	end
	
	for _, recipe in recipes do
		if doesRecipeMatch(recipe, ingredientCounts) then
			_recipeCache[ingredientCountIdx] = recipe
			return recipe
		end
	end

	return nil
end

-- ========== Public API ========== --

function CraftingService:Craft(player: Player, station: CraftingStationAPI, stackIds: { string }): (boolean, string?)
	-- Validate everything first
	local recipe, err = self:_validateCraft(player, stackIds, station)
	if not recipe then
		return false, err
	end

	-- Consume ingredients
	local consumed = self:_consumeIngredients(player, stackIds)
	if not consumed then
		return false, "Failed to consume ingredients"
	end

	-- Start craft
	local started = station:StartCraft(player, recipe)
	if not started then
		-- CRITICAL: ingredients consumed but craft failed
		-- log error but do not refund ingredients (potential exploit)
		warn("[CraftingService] Failed to start craft at station", station, "for player", player)
		return false, "Station error"
	end

	return true, nil
end

-- ========== Internal ========== --

function CraftingService:_validateCraft(player: Player, stackIds: { string }, station: CraftingStationAPI): (RecipeEntry?, string?)
	-- Get player's inventory profile
	local inventoryProfile = self.Services.InventoryService:_getInventoryProfile(player)
	if not inventoryProfile then
		return nil, "No inventory"
	end

	-- Match recipe
	local recipe = matchRecipe(stackIds, inventoryProfile)
	if not recipe then
		return nil, "No matching recipe"
	end

	-- Check station requirements
	if recipe.requirements then
		if recipe.requirements.craftingStationId then
			if station._craftingStationId ~= recipe.requirements.craftingStationId then
				return nil, "Invalid crafting station"
			end
		end
		if recipe.requirements.minStationLevel then
			local stationLevel = station._level or 0
			if stationLevel < recipe.requirements.minStationLevel then
				return nil, "Crafting station level too low"
			end
		end
	end
	return recipe, nil
end

function CraftingService:_consumeIngredients(player: Player, stackIds: { string }): boolean
	-- Count how many times each stack is referenced
	local stackUsage: { [string]: number } = {}
	for _, stackId in stackIds do
		stackUsage[stackId] = (stackUsage[stackId] or 0) + 1
	end

	-- Validate and consume each stack
	for stackId, timesUsed in stackUsage do
		local stack = self.Services.InventoryService:GetStack(player, stackId)
		if not stack or stack.quantity < timesUsed then
			return false -- Not enough in stack
		end

		-- Remove the exact quantity needed
		local success = self.Services.InventoryService:RemoveFromStack(player, stackId, timesUsed)
		if not success then return false end
	end

	return true
end

-- ========== Life Cycle ========== --

function CraftingService:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Example: get/create remotes
end

function CraftingService:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Example: connect remotes, start loops, etc.
end

function CraftingService:Destroy()
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return CraftingService :: CraftingServiceAPI
