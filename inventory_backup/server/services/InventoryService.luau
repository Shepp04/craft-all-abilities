--!strict
-- InventoryService (Service) — lifecycle-first singleton discovered by Services registry.
--[[
	Manages player inventories including item storage and hotbar slots.
	Stores all items (ingredients + crafted) in profile.Data.Inventory.items.
	Hotbar slots reference items for quick access to non-ingredient items only.
	
	Usage:
		-- Add items to inventory
		InventoryService:AddItem(player, "wood", 10)
		
		-- Remove items from inventory
		InventoryService:RemoveItem(player, "wood", 5)
		
		-- Check quantity
		local count = InventoryService:GetItemCount(player, "wood")
		
		-- Equip to hotbar (non-ingredient items only)
		InventoryService:SetHotbarSlot(player, 1, "wooden_table")
		
		-- Get hotbar item
		local itemId = InventoryService:GetHotbarSlot(player, 1)
]]

-- // Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Types (custom)
export type InventoryItem = {
	itemId: string,
	quantity: number,
	-- instances used for non-stackable items
	instances: { [string]: any }?, -- instanceId -> instance data
}

export type InventoryProfile = {
	version: number,
	items: { [string]: InventoryItem }, -- itemId -> InventoryItem
	hotbar: { [number]: string? }, -- hotbar slot index -> itemId?
	hotbarSize: number,
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

export type InventoryServiceAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Services: ServiceRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: InventoryServiceAPI, deps: Deps) -> (),
	Start: (self: InventoryServiceAPI) -> (),
	Destroy: (self: InventoryServiceAPI) -> (),

	AddItem: (self: InventoryServiceAPI, player: Player, itemId: string, quantity: number) -> boolean,
	RemoveItem: (self: InventoryServiceAPI, player: Player, itemId: string, quantity: number) -> boolean,
	GetItemCount: (self: InventoryServiceAPI, player: Player, itemId: string) -> number,
	SetHotbarSlot: (self: InventoryServiceAPI, player: Player, slot: number, itemId: string?) -> boolean,
	GetHotbarSlot: (self: InventoryServiceAPI, player: Player, slot: number) -> string?,
	CanAddItem: (self: InventoryServiceAPI, player: Player, itemId: string, quantity: number) -> boolean,
}

local InventoryService = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Services = {} :: ServiceRegistry,
}

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- ========== Public API ========== --

--[[
	AddItem
	Adds items to a player's inventory with validation and stack limit checks.

	@param player: Player, The player to add items to
	@param itemId: string, The item ID from GameData.Items
	@param quantity: number, The amount to add (must be positive)

	@return success: boolean, True if items were added successfully
]]
function InventoryService:AddItem(player: Player, itemId: string, quantity: number): boolean
	if quantity <= 0 then
		warn("[InventoryService] AddItem - quantity must be positive:", quantity)
		return false
	end

	-- Validate item exists in GameData
	local itemInfo = _deps.GameData.Get("Items", itemId)
	if not itemInfo then
		warn("[InventoryService] AddItem - itemId does not exist in GameData:", itemId)
		return false
	end

	-- Get inventory profile
	local inventoryProfile = self:_getInventoryProfile(player)
	if not inventoryProfile then
		return false
	end

	-- Check stack limits
	local maxStack = itemInfo.maxStack or math.huge
	local currentItem = inventoryProfile.items[itemId]
	local currentQuantity = currentItem and currentItem.quantity or 0

	if currentQuantity + quantity > maxStack then
		warn("[InventoryService] AddItem - exceeding max stack for itemId:", itemId, "current:", currentQuantity, "adding:", quantity, "maxStack:", maxStack)
		return false
	end

	-- Add or update item
	if currentItem then
		currentItem.quantity += quantity
	else
		inventoryProfile.items[itemId] = {
			itemId = itemId,
			quantity = quantity,
		}
	end

	print("[InventoryService] Added", quantity, "x", itemId, "to", player.Name)
	return true
end

--[[
	RemoveItem
	Removes items from a player's inventory. Auto-clears from hotbar if quantity reaches 0.

	@param player: Player, The player to remove items from
	@param itemId: string, The item ID from GameData.Items
	@param quantity: number, The amount to remove (must be positive)

	@return success: boolean, True if items were removed successfully
]]
function InventoryService:RemoveItem(player: Player, itemId: string, quantity: number): boolean
	if quantity <= 0 then
		warn("[InventoryService] RemoveItem - quantity must be positive:", quantity)
		return false
	end

	-- Get inventory profile
	local inventoryProfile = self:_getInventoryProfile(player)
	if not inventoryProfile then
		return false
	end

	-- Check if player has the item
	local currentItem = inventoryProfile.items[itemId]
	if not currentItem then
		warn("[InventoryService] RemoveItem - player does not have itemId:", itemId)
		return false
	end

	-- Check if the player has enough
	if currentItem.quantity < quantity then
		warn("[InventoryService] RemoveItem - not enough quantity to remove for itemId:", itemId, "has:", currentItem.quantity, "trying to remove:", quantity)
		return false
	end

	-- Remove quantity
	currentItem.quantity -= quantity

	-- Remove item entry if quantity reaches 0
	if currentItem.quantity <= 0 then
		inventoryProfile.items[itemId] = nil

		-- Also clear from hotbar if present
		for slor, slotItemId in inventoryProfile.hotbar do
			if slotItemId == itemId then
				inventoryProfile.hotbar[slor] = nil
			end
		end
	end

	print("[InventoryService] Removed", quantity, "x", itemId, "from", player.Name)
	return true
end

--[[
	GetItemCount
	Returns the quantity of a specific item in the player's inventory.

	@param player: Player, The player to check
	@param itemId: string, The item ID from GameData.Items

	@return quantity: number, The item quantity (0 if not owned)
]]
function InventoryService:GetItemCount(player: Player, itemId: string): number
	-- Get inventory profile
	local inventoryProfile = self:_getInventoryProfile(player)
	if not inventoryProfile then
		return 0
	end

	local item = inventoryProfile.items[itemId]
	return item and item.quantity or 0
end

--[[
	SetHotbarSlot
	Equips an item to a hotbar slot. Only placeable items allowed. Pass nil to clear.

	@param player: Player, The player whose hotbar to modify
	@param slot: number, The hotbar slot number (1 to hotbarSize)
	@param itemId: string?, The item ID to equip (nil to clear slot)

	@return success: boolean, True if hotbar slot was set successfully
]]
function InventoryService:SetHotbarSlot(player: Player, slot: number, itemId: string?): boolean
	-- Get inventory profile
	local inventoryProfile = self:_getInventoryProfile(player)
	if not inventoryProfile then
		return false
	end

	-- Validate slot number
	if slot < 1 or slot > inventoryProfile.hotbarSize then
		warn("[InventoryService] SetHotbarSlot - invalid slot number:", slot)
		return false
	end

	-- If clearing the slot (itemId is nil)
	if not itemId then
		inventoryProfile.hotbar[slot] = nil
		print("[InventoryService] Cleared hotbar slot", slot, "for", player.Name)
		return true
	end

	-- Validate item exists in GameData
	local itemInfo = _deps.GameData.Get("Items", itemId)
	if not itemInfo then
		warn("[InventoryService] SetHotbarSlot - invalid itemId:", itemId)
		return false
	end

	-- Validate item is allowed in hotbar (e.g. not an ingredient)
	if not self:_isItemValidForHotbar(itemId) then
		warn("[InventoryService] SetHotbarSlot - itemId not valid for hotbar:", itemId)
		return false
	end

	-- Check the player owns it
	if self:GetItemCount(player, itemId) <= 0 then
		warn("[InventoryService] SetHotbarSlot - player does not own itemId:", itemId)
		return false
	end

	-- Set hotbar reference
	inventoryProfile.hotbar[slot] = itemId
	print("[InventoryService] Set hotbar slot", slot, "to", itemId, "for", player.Name)
	return true
end

--[[
	GetHotbarSlot
	Returns the item ID equipped in a specific hotbar slot.

	@param player: Player, The player whose hotbar to check
	@param slot: number, The hotbar slot number (1 to hotbarSize)

	@return itemId: string?, The item ID in the slot (nil if empty or invalid)
]]
function InventoryService:GetHotbarSlot(player: Player, slot: number): string?
	-- Get inventory profile
	local inventoryProfile = self:_getInventoryProfile(player)
	if not inventoryProfile then
		return nil
	end

	-- Validate slot number
	if slot < 1 or slot > inventoryProfile.hotbarSize then
		warn("[InventoryService] GetHotbarSlot - invalid slot number:", slot)
		return nil
	end

	return inventoryProfile.hotbar[slot]
end

--[[
	CanAddItem
	Checks if items can be added without exceeding stack limits. Non-mutating.

	@param player: Player, The player to check
	@param itemId: string, The item ID from GameData.Items
	@param quantity: number, The amount to check

	@return canAdd: boolean, True if items can be added within limits
]]
function InventoryService:CanAddItem(player: Player, itemId: string, quantity: number): boolean
	if quantity <= 0 then
		return false
	end

	-- Validate item exists in GameData
	local itemInfo = _deps.GameData.Get("Items", itemId)
	if not itemInfo then
		return false
	end

	-- Get inventory profile
	local inventoryProfile = self:_getInventoryProfile(player)
	if not inventoryProfile then
		return false
	end

	-- Check stack limits
	local maxStack = itemInfo.maxStack or math.huge
	local currentItem = inventoryProfile.items[itemId]
	local currentQuantity = currentItem and currentItem.quantity or 0

	return (currentQuantity + quantity) <= maxStack
end

-- ========== Internal ========== --

--[[
	_getInventoryProfile
	Retrieves the Inventory section from a player's profile.

	@param player: Player, The player whose profile to retrieve
	@param yield: boolean?, Whether to yield waiting for profile load

	@return profile: InventoryProfile?, The inventory profile section (nil if not found)
]]
function InventoryService:_getInventoryProfile(player: Player, yield: boolean?): InventoryProfile?
	-- Fetch player profile from DataInterface
	local profile = _deps.DataInterface:GetPlayerProfile(player, yield)
	if not profile or not profile.Data or not profile.Data.Inventory then
		warn("[InventoryService] _getInventoryProfile - no profile.Data.Inventory for player:", player.UserId)
		return nil
	end
	return profile.Data.Inventory :: InventoryProfile
end

--[[
	_isItemValidForHotbar
	Checks if an item is allowed in hotbar slots (excludes ingredients).

	@param itemId: string, The item ID from GameData.Items

	@return isValid: boolean, True if item can be equipped to hotbar
]]
function InventoryService:_isItemValidForHotbar(itemId: string): boolean
	-- Validate item exists in GameData
	local itemInfo = _deps.GameData.Get("Items", itemId)
	if not itemInfo then
		return false
	end

	-- Validate item is allowed in hotbar (e.g. not an ingredient)
	if itemInfo.type == "Ingredient" then
		return false
	end

	return true
end

-- ========== Life Cycle ========== --

function InventoryService:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Register reconcile section
	_deps.DataInterface:RegisterReconcileSection("Data", "Inventory", {
		version = 1 :: number,
		-- items indexed by itemId, instances of that itemId indexed by unique instanceId
		items = {
			["default_item"] = { quantity = 1 }
		} :: { [string]: InventoryItem }, -- itemId -> quantity
		hotbar = {
			-- NOTE: ingredients never referenced here
		} :: { [number]: string? }, -- hotbar slot index -> itemId?
		hotbarSize = 9 :: number,
	} :: InventoryProfile)

	-- // Create remotes
	self._setHotbarSlotRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "SetHotbarSlot") :: RemoteEvent
end

function InventoryService:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Connect remotes
	table.insert(self._conns, self._setHotbarSlotRemote.OnServerEvent:Connect(function(player: Player, slot: number, itemId: string?)
		local success = self:SetHotbarSlot(player, slot, itemId)
		if not success then
			warn("[InventoryService] Failed to set hotbar slot via remote for player:", player.Name, "slot:", slot, "itemId:", itemId)
		end
	end))
end

function InventoryService:Destroy()
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return InventoryService :: InventoryServiceAPI
