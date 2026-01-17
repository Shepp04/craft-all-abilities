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
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Types (custom)
export type ItemStack = {
	itemId: string,
	quantity: number,
}

export type InventoryProfile = {
	version: number,
	items: { [string]: ItemStack }, -- stackId -> ItemStack
	hotbar: { [number]: string? }, -- hotbar slot index -> stackId?
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
	RemoveItemFromStack: (self: InventoryServiceAPI, player: Player, stackId: string, quantity: number) -> boolean,
	GetItemCount: (self: InventoryServiceAPI, player: Player, itemId: string) -> number,
	GetStack: (self: InventoryServiceAPI, player: Player, stackId: string) -> ItemStack?,
	SetHotbarSlot: (self: InventoryServiceAPI, player: Player, slot: number, stackId: string?) -> boolean,
	GetHotbarSlot: (self: InventoryServiceAPI, player: Player, slot: number) -> string?,
	CanAddItem: (self: InventoryServiceAPI, player: Player, itemId: string, quantity: number) -> boolean,
	GetStacksForItem: (self: InventoryServiceAPI, player: Player, itemId: string) -> { [string]: ItemStack },
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
	Automatically creates new stacks when existing stacks are full.

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

	local maxStack = itemInfo.maxStack or math.huge
	local remaining = quantity

	-- Find all existing stacks for this item
	local existingStacks = {}
	for stackId, stack in inventoryProfile.items do
		if stack.itemId == itemId then
			table.insert(existingStacks, { stackId = stackId, stack = stack })
		end
	end

	-- Try to fill incomplete stacks first
	for _, stackData in existingStacks do
		if remaining <= 0 then break end
		
		local stack = stackData.stack
		local available = maxStack - stack.quantity
		
		if available > 0 then
			local toAdd = math.min(available, remaining)
			stack.quantity += toAdd
			remaining -= toAdd
			-- print("[InventoryService] Added", toAdd, "to existing stack", stackData.stackId)
		end
	end

	-- Create new stacks for remaining items
	while remaining > 0 do
		local toAdd = math.min(maxStack, remaining)
		local newStackId = self:_generateStackId()
		
		inventoryProfile.items[newStackId] = {
			itemId = itemId,
			quantity = toAdd,
		}
		
		remaining -= toAdd
		-- print("[InventoryService] Created new stack", newStackId, "with", toAdd, "x", itemId)
	end

	-- print("[InventoryService] Added", quantity, "x", itemId, "to", player.Name)
	return true
end

--[[
	RemoveItem
	Removes items from a player's inventory. Prioritizes non-hotbar stacks first.
	Auto-clears from hotbar if stack is depleted.

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

	-- Check if player has enough total quantity
	local totalCount = self:GetItemCount(player, itemId)
	if totalCount < quantity then
		warn("[InventoryService] RemoveItem - not enough quantity for itemId:", itemId, "has:", totalCount, "trying to remove:", quantity)
		return false
	end

	-- Get all stacks for this item, separated by hotbar/non-hotbar
	local hotbarStackIds = {}
	for _, stackId in inventoryProfile.hotbar do
		if stackId then
			hotbarStackIds[stackId] = true
		end
	end

	local nonHotbarStacks = {}
	local hotbarStacks = {}
	
	for stackId, stack in inventoryProfile.items do
		if stack.itemId == itemId then
			if hotbarStackIds[stackId] then
				table.insert(hotbarStacks, { stackId = stackId, stack = stack })
			else
				table.insert(nonHotbarStacks, { stackId = stackId, stack = stack })
			end
		end
	end

	local remaining = quantity

	-- Remove from non-hotbar stacks first
	for _, stackData in nonHotbarStacks do
		if remaining <= 0 then break end
		
		local stack = stackData.stack
		local toRemove = math.min(stack.quantity, remaining)
		
		stack.quantity -= toRemove
		remaining -= toRemove
		
		-- Delete empty stacks
		if stack.quantity <= 0 then
			inventoryProfile.items[stackData.stackId] = nil
			--print("[InventoryService] Deleted empty stack", stackData.stackId)
		end
	end

	-- If still need to remove more, take from hotbar stacks
	for _, stackData in hotbarStacks do
		if remaining <= 0 then break end
		
		local stack = stackData.stack
		local toRemove = math.min(stack.quantity, remaining)
		
		stack.quantity -= toRemove
		remaining -= toRemove
		
		-- Delete empty stacks and clear from hotbar
		if stack.quantity <= 0 then
			inventoryProfile.items[stackData.stackId] = nil
			
			-- Clear from hotbar
			for slot, slotStackId in inventoryProfile.hotbar do
				if slotStackId == stackData.stackId then
					inventoryProfile.hotbar[slot] = nil
				end
			end
			
			-- print("[InventoryService] Deleted empty hotbar stack", stackData.stackId)
		end
	end

	-- print("[InventoryService] Removed", quantity, "x", itemId, "from", player.Name)
	return true
end

--[[
	RemoveItemFromStack
	Removes a specific quantity from a given stackId.

	@param player: Player, The player whose inventory to modify
	@param stackId: string, The stack ID to remove items from
	@param quantity: number, The amount to remove (must be positive)

	@return success: boolean, True if items were removed successfully
]]
function InventoryService:RemoveItemFromStack(player: Player, stackId: string, quantity: number): boolean
	-- Get inventory profile
	local inventoryProfile = self:_getInventoryProfile(player)
	if not inventoryProfile then
		return false
	end

	local stack = inventoryProfile.items[stackId]
	if not stack then
		warn("[InventoryService] RemoveItemFromStack - invalid stackId:", stackId)
		return false
	end

	if quantity <= 0 then
		warn("[InventoryService] RemoveItemFromStack - quantity must be positive:", quantity)
		return false
	end

	if stack.quantity < quantity then
		warn("[InventoryService] RemoveItemFromStack - not enough quantity in stack:", stackId, "has:", stack.quantity, "trying to remove:", quantity)
		return false
	end

	stack.quantity -= quantity

	-- Delete empty stacks and clear from hotbar
	if stack.quantity <= 0 then
		inventoryProfile.items[stackId] = nil
		
		-- Clear from hotbar
		for slot, slotStackId in inventoryProfile.hotbar do
			if slotStackId == stackId then
				inventoryProfile.hotbar[slot] = nil
			end
		end
		
		-- print("[InventoryService] Deleted empty stack", stackId)
	end

	-- print("[InventoryService] Removed", quantity, "from stack", stackId, "for", player.Name)
	return true
end

--[[
	GetItemCount
	Returns the total quantity of a specific item across all stacks.

	@param player: Player, The player to check
	@param itemId: string, The item ID from GameData.Items

	@return quantity: number, The total item quantity (0 if not owned)
]]
function InventoryService:GetItemCount(player: Player, itemId: string): number
	-- Get inventory profile
	local inventoryProfile = self:_getInventoryProfile(player)
	if not inventoryProfile then
		return 0
	end

	local total = 0
	for _, stack in inventoryProfile.items do
		if stack.itemId == itemId then
			total += stack.quantity
		end
	end

	return total
end

--[[
	GetStack
	Returns a specific item stack by its stackId.

	@param player: Player, The player whose inventory to check
	@param stackId: string, The stack ID to retrieve

	@return stack: ItemStack?, The item stack (nil if not found)
]]
function InventoryService:GetStack(player: Player, stackId: string): ItemStack?
	-- Get inventory profile
	local inventoryProfile = self:_getInventoryProfile(player)
	if not inventoryProfile then
		return nil
	end

	return inventoryProfile.items[stackId]
end

--[[
	SetHotbarSlot
	Equips a stack to a hotbar slot. Only placeable items allowed. Pass nil to clear.

	@param player: Player, The player whose hotbar to modify
	@param slot: number, The hotbar slot number (1 to hotbarSize)
	@param stackId: string?, The stack ID to equip (nil to clear slot)

	@return success: boolean, True if hotbar slot was set successfully
]]
function InventoryService:SetHotbarSlot(player: Player, slot: number, stackId: string?): boolean
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

	-- If clearing the slot (stackId is nil)
	if not stackId then
		inventoryProfile.hotbar[slot] = nil
		-- print("[InventoryService] Cleared hotbar slot", slot, "for", player.Name)
		return true
	end

	-- Validate stack exists
	local stack = inventoryProfile.items[stackId]
	if not stack then
		warn("[InventoryService] SetHotbarSlot - invalid stackId:", stackId)
		return false
	end

	-- Validate item is allowed in hotbar
	if not self:_isItemValidForHotbar(stack.itemId) then
		warn("[InventoryService] SetHotbarSlot - item not valid for hotbar:", stack.itemId)
		return false
	end

	-- Set hotbar reference
	inventoryProfile.hotbar[slot] = stackId
	-- print("[InventoryService] Set hotbar slot", slot, "to", stackId, "for", player.Name)
	return true
end

--[[
	GetHotbarSlot
	Returns the stack ID equipped in a specific hotbar slot.

	@param player: Player, The player whose hotbar to check
	@param slot: number, The hotbar slot number (1 to hotbarSize)

	@return stackId: string?, The stack ID in the slot (nil if empty or invalid)
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
	Checks if items can be added. Always true now since we create multiple stacks.

	@param player: Player, The player to check
	@param itemId: string, The item ID from GameData.Items
	@param quantity: number, The amount to check

	@return canAdd: boolean, True if items can be added
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

	-- With multiple stacks, we can always add items
	return true
end

--[[
	GetStacksForItem
	Returns all stacks for a specific item.

	@param player: Player, The player whose inventory to check
	@param itemId: string, The item ID from GameData.Items

	@return stacks: { [string]: ItemStack }, Dictionary of stackId -> ItemStack
]]
function InventoryService:GetStacksForItem(player: Player, itemId: string): { [string]: ItemStack }
	local inventoryProfile = self:_getInventoryProfile(player)
	if not inventoryProfile then
		return {}
	end

	local stacks = {}
	for stackId, stack in inventoryProfile.items do
		if stack.itemId == itemId then
			stacks[stackId] = stack
		end
	end

	return stacks
end

-- ========== Internal ========== --

--[[
	_generateStackId
	Generates a unique stack ID using UUID.

	@return stackId: string, A unique stack identifier
]]
function InventoryService:_generateStackId(): string
	return HttpService:GenerateGUID(false)
end

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
	if itemInfo.type == "ingredient" then
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
		items = {
			["default_stack_starter"] = { itemId = "default_item", quantity = 1 }
		} :: { [string]: ItemStack }, -- stackId -> ItemStack
		hotbar = {
			-- NOTE: ingredients never referenced here
		} :: { [number]: string? }, -- hotbar slot index -> stackId?
		hotbarSize = 9 :: number,
	} :: InventoryProfile)

	-- // Create remotes
	self._setHotbarSlotRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "SetHotbarSlot") :: RemoteEvent
end

function InventoryService:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Connect remotes
	table.insert(self._conns, self._setHotbarSlotRemote.OnServerEvent:Connect(function(player: Player, slot: number, stackId: string?)
		local success = self:SetHotbarSlot(player, slot, stackId)
		if not success then
			warn("[InventoryService] Failed to set hotbar slot via remote for player:", player.Name, "slot:", slot, "stackId:", stackId)
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
