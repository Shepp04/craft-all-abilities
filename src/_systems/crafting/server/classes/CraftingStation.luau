--!strict
-- CraftingStation (Server Class)

-- // Roblox Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Types
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

export type ActiveCraftData = {
	userId: number,
	recipeId: string,
	startTime: number,
	endTime: number,
}

type ActiveCraft = {
	player: Player,
	recipe: RecipeEntry,
	startTime: number,
	endTime: number,
}

local ServicesTypes = require(ReplicatedStorage.Shared.Types.Services)

-- // Type aliases for deps
type ServiceRegistry = ServicesTypes.Registry

type ReplicatedData = typeof(require(ReplicatedStorage.Shared.Packages.ReplicatedData))
type SharedPackages = typeof(require(ReplicatedStorage.Shared.Packages))
type GameData       = typeof(require(ReplicatedStorage.Shared.GameData))
type Monetisation   = typeof(require(ReplicatedStorage.Shared.Monetisation))
type Config         = typeof(require(ReplicatedStorage.Shared.Config))
type Tunables       = { [string]: any } -- external tunables, not synced by rojo

export type Deps = {
	ReplicatedData: ReplicatedData,
	Services: ServiceRegistry,
	SharedPackages: SharedPackages,
	GameData: GameData,
	Monetisation: Monetisation,
	Config: Config,
	Tunables: Tunables,
}

export type Opts = {
	-- args used when constructing the class
	craftingStationId: string,
	model: Model,
	onStateChanged: (() -> ())?, -- Callback when state changes (for auto-saving)
}

export type CraftingStationAPI = {
	_opts: Opts,
	_conns: { RBXScriptConnection },
	_onStateChanged: (() -> ())?,

	_activeCraft: ActiveCraft?,
	_craftingStationId: string,
	_level: number,
	model: Model,
	_trigger: BasePart?,

	Init: (self: CraftingStationAPI) -> (),
	Destroy: (self: CraftingStationAPI) -> (),
	
	StartCraft: (self: CraftingStationAPI, player: Player, recipe: RecipeEntry) -> boolean,
	GetCraftProgress: (self: CraftingStationAPI) -> number?,
	CanCollect: (self: CraftingStationAPI, player: Player) -> boolean,
	CollectCraft: (self: CraftingStationAPI, player: Player) -> boolean,
	CancelCraft: (self: CraftingStationAPI, player: Player) -> boolean,
	RestoreActiveCraft: (self: CraftingStationAPI, craftData: ActiveCraftData) -> boolean,
	GetActiveCraftData: (self: CraftingStationAPI) -> ActiveCraftData?,
}

local CraftingStation = {}
CraftingStation.__index = CraftingStation

-- // Internal state
local _deps: Deps?

-- ========== Constructor ========== --

function CraftingStation.new(deps: Deps, opts: Opts?): CraftingStationAPI
	_deps = deps

	local self = setmetatable({} :: any, CraftingStation) :: CraftingStationAPI
	self._opts = opts or {}
	self._conns = {}
	self._onStateChanged = opts and opts.onStateChanged or nil

	self._activeCraft = nil
	self._craftingStationId = self._opts.craftingStationId
	self._level = 1 -- Default level, can be upgraded later

	self.model = self._opts.model
	self._trigger = self.model and self.model:FindFirstChild("Trigger") :: BasePart?
	if not self._trigger then
		error("CraftingStation model is missing a 'Trigger' part")
	end

	return self
end

-- ========== Public API ========== --

function CraftingStation:StartCraft(player: Player, recipe: RecipeEntry): boolean
	if self._activeCraft then
		-- Already crafting
		warn("[CraftingStation] Attempted to start craft while one is already active")
		return false
	end

	local currentTime = os.time()
	self._activeCraft = {
		player = player,
		recipe = recipe,
		startTime = currentTime,
		endTime = currentTime + recipe.craftTime,
	}
	
	print("[CraftingStation] Started craft:", recipe.name or recipe.id, "for", player.Name)
	
	-- Notify state change for auto-save
	if self._onStateChanged then
		self._onStateChanged()
	end
	
	return true
end

function CraftingStation:GetCraftProgress(): number? -- returns 0-1 or nil
	if not self._activeCraft then
		return nil
	end
	
	local currentTime = os.time()
	local elapsed = currentTime - self._activeCraft.startTime
	local duration = self._activeCraft.endTime - self._activeCraft.startTime
	
	if duration <= 0 then
		return 1 -- Instant craft
	end
	
	local progress = math.clamp(elapsed / duration, 0, 1)
	return progress
end

function CraftingStation:CanCollect(player: Player): boolean
	-- Check that there is an active craft
	if not self._activeCraft then
		return false
	end

	-- Check that the craft is complete
	if self:GetCraftProgress() ~= 1 then
		return false
	end

	-- Check that this player owns the craft
	if self._activeCraft.player.UserId ~= player.UserId then
		warn("Player " .. player.Name .. " attempted to collect a craft they do not own.")
		return false
	end

	return true
end

function CraftingStation:CollectCraft(player: Player): boolean
	if not self:CanCollect(player) then
		return false
	end

	local recipe = self._activeCraft.recipe

	-- Add output to inventory
	local success = _deps.Services.InventoryService:AddItem(player, recipe.output.itemId, recipe.output.quantity)
	if success then
		-- Clear craft state
		self:_clearCraftState()
		
		-- Notify state change for auto-save
		if self._onStateChanged then
			self._onStateChanged()
		end
		
		return true
	else
		-- Inventory may be full - let the player try again later
		return false
	end
end

function CraftingStation:CancelCraft(player: Player): boolean
	if not self._activeCraft then
		return false
	end

	if self._activeCraft.player.UserId ~= player.UserId then
		warn("Player " .. player.Name .. " attempted to cancel a craft they do not own.")
		return false
	end

	-- Clear craft state
	self:_clearCraftState()
	
	-- Notify state change for auto-save
	if self._onStateChanged then
		self._onStateChanged()
	end
	
	return true
end

function CraftingStation:RestoreActiveCraft(craftData: ActiveCraftData): boolean
	if self._activeCraft then
		warn("[CraftingStation] Cannot restore craft - station already has active craft")
		return false
	end
	
	-- Find player by UserId
	local player = Players:GetPlayerByUserId(craftData.userId)
	if not player then
		warn("[CraftingStation] Cannot restore craft - user not in game:", craftData.userId)
		-- Player offline - craft continues, they can collect when they return
		-- For now, we'll skip restoration if player is offline
		-- TODO: Decide if offline crafts should continue
		return false
	end
	
	-- Get recipe from GameData
	local recipe = _deps.GameData.Get("Recipes", craftData.recipeId)
	if not recipe then
		warn("[CraftingStation] Cannot restore craft - recipe not found:", craftData.recipeId)
		return false
	end
	
	self._activeCraft = {
		player = player,
		recipe = recipe,
		startTime = craftData.startTime,
		endTime = craftData.endTime,
	}
	
	print("[CraftingStation] Restored craft:", recipe.name or recipe.id, "for", player.Name)
	return true
end

function CraftingStation:GetActiveCraftData(): ActiveCraftData?
	if not self._activeCraft then
		return nil
	end
	
	return {
		userId = self._activeCraft.player.UserId,
		recipeId = self._activeCraft.recipe.id,
		startTime = self._activeCraft.startTime,
		endTime = self._activeCraft.endTime,
	}
end

-- ========== Internal ========== --

function CraftingStation:_clearCraftState()
	self._activeCraft = nil
end

-- ========== Life Cycle ========== --

function CraftingStation:Init()
	-- // Create a proximity prompt
	local prompt = self._trigger:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Craft"
		prompt.ObjectText = "Crafting Station"
		prompt.HoldDuration = 0.5
		prompt.RequiresLineOfSight = false
		prompt.Parent = self._trigger
	end

	table.insert(self._conns, prompt.Triggered:Connect(function(player: Player)
		-- Open crafting UI for player
		_deps.Services.MenuService:OpenMenuForPlayer(player, "Crafting")
	end))
end

function CraftingStation:Destroy()
	for _, c in self._conns do
		pcall(function() c:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
end

return CraftingStation :: CraftingStationAPI
