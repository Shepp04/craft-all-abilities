--!strict
-- Inventory (Component)

-- // Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- // Components
local ItemSlot = require(script.Parent.ItemSlot)

-- // Types
local ServicesTypes = require(ReplicatedStorage.Shared.Types.Services)
type InventoryProfile = ServicesTypes.InventoryProfile

-- // Type aliases for deps inferred from real modules
type ReplicatedData = typeof(require(ReplicatedStorage.Shared.Packages.ReplicatedData))
type SharedPackages = typeof(require(ReplicatedStorage.Shared.Packages))
type GameData       = typeof(require(ReplicatedStorage.Shared.GameData))
type Monetisation   = typeof(require(ReplicatedStorage.Shared.Monetisation))
type Config         = typeof(require(ReplicatedStorage.Shared.Config))
type Tunables       = { [string]: any } -- external tunables, not synced by rojo

export type Deps = {
	ReplicatedData: ReplicatedData,
	SharedPackages: SharedPackages,
	GameData: GameData,
	Monetisation: Monetisation,
	Config: Config,
	Tunables: Tunables,
}

type FilteredItem = {
	itemId: string,
	quantity: number,
	inHotbar: boolean,
}

export type InventoryAPI = {
	_inited: boolean,
	_conns: { RBXScriptConnection },
	_opts: Opts,
	_frame: Frame,
	_scrollingFrame: ScrollingFrame,
	_itemSlots: { ItemSlot.ItemSlotAPI },
	_inventoryData: InventoryProfile?,
	_hotbarSlots: { [number]: string? },
	_isVisible: boolean,
	_needsRefresh: boolean,
	_tooltip: Frame?,

	Init: (self: InventoryAPI) -> (),
	Destroy: (self: InventoryAPI) -> (),

	Refresh: (self: InventoryAPI) -> (), -- Rebuilds entire display from current data
	SetVisible: (self: InventoryAPI, visible: boolean) -> (), -- Show/hide the inventory UI
	UpdateSingleItem: (self: InventoryAPI, itemId: string) -> (), -- Update a single item slot by itemId
}

export type Opts = {
	frame: Frame,
	onItemClick: (itemId: string) -> (), -- callback to controller
}

local Inventory = {}
Inventory.__index = Inventory

-- // Internal state
local _deps: Deps? = nil

-- ========== Constructor ========== --

function Inventory.new(deps: Deps, opts: Opts): InventoryAPI
	if not _deps then
		_deps = deps
	end

	local self = setmetatable({ _inited = false, _conns = {} } :: any, Inventory) :: InventoryAPI
	
	self._opts = opts
	self._canvas = opts.canvas
	self._frame = self._canvas:FindFirstChild("Frame") :: Frame

	if not self._frame then
		error("[Inventory] Constructor - InventoryFrame not found in canvas")
	end

	self._scrollingFrame = nil :: any -- Set in Init
	self._itemSlots = {}
	self._inventoryData = nil
	self._hotbarSlots = {}
	self._isVisible = false
	self._needsRefresh = false
	self._tooltip = nil
	
	return self
end

-- ========== Public API ========== --

function Inventory:GetCanvas(): CanvasGroup
	return self._canvas
end

--[[
	Refresh
	Efficiently updates display from current ReplicatedData.
	Only rebuilds slots if items were added/removed.
	Optionally accepts data to avoid stale cache reads.
]]
function Inventory:Refresh(inventoryData: InventoryProfile?)
	if not self._inited then return end
	
	-- Use provided data or fetch latest
	if not inventoryData then
		inventoryData = self:_getInventoryData()
	end
	
	if not inventoryData then
		warn("[Inventory] Refresh - no inventory data available")
		return
	end
	
	-- Cache reference for internal use
	self._inventoryData = inventoryData
	
	-- Cache hotbar for quick lookups
	self._hotbarSlots = self._inventoryData.hotbar
	
	-- Get filtered items (placeable only)
	local filteredItems = self:_getFilteredItems()
	
	-- Check if we need full rebuild (item count changed)
	local needsRebuild = #filteredItems ~= #self._itemSlots
	
	if not needsRebuild then
		-- Check if the same items are present (order might differ)
		local currentItemIds = {}
		for _, itemData in filteredItems do
			currentItemIds[itemData.itemId] = true
		end
		
		for _, slot in self._itemSlots do
			if not currentItemIds[slot._itemId] then
				needsRebuild = true
				break
			end
		end
	end
	
	if needsRebuild then
		-- Full rebuild: destroy and recreate all slots
		for _, slot in self._itemSlots do
			slot:Destroy()
		end
		table.clear(self._itemSlots)
		
		-- Create new slots for each item
		for index, itemData in filteredItems do
			local slot = ItemSlot.new(_deps, {
				itemId = itemData.itemId,
				quantity = itemData.quantity,
				slotIndex = index,
				showInHotbar = itemData.inHotbar,
				containerType = "inventory",
				onClick = function(clickedItemId: string?)
					self:_handleItemClick(clickedItemId)
				end,
			})
			
			slot:Init()
			slot:GetFrame().Parent = self._scrollingFrame
			
			-- Set up hover tooltip
			self:_setupTooltip(slot:GetFrame(), itemData.itemId)
			
			table.insert(self._itemSlots, slot)
		end
	else
		-- Fast path: just update existing slots
		for _, itemData in filteredItems do
			-- Find the slot for this item
			for _, slot in self._itemSlots do
				if slot._itemId == itemData.itemId then
					slot:UpdateDisplay(itemData.itemId, itemData.quantity, itemData.inHotbar)
					break
				end
			end
		end
	end
	
	-- Show empty state if no items
	if #filteredItems == 0 then
		self:_showEmptyState()
	else
		self:_hideEmptyState()
	end
	
	self._needsRefresh = false
end

--[[
	SetVisible
	Shows or hides the inventory UI with smooth animation.
]]
function Inventory:SetVisible(visible: boolean)
	if self._isVisible == visible then return end
	
	self._isVisible = visible
	
	if visible then
		-- Refresh if needed before showing
		if self._needsRefresh then
			self:Refresh()
		end
		
		-- Show inventory canvas
		self._canvas.Visible = true
	else
		-- Hide inventory
		self._canvas.Visible = false
		
		-- Hide tooltip when closing
		self:_hideTooltip()
	end
end

--[[
	UpdateSingleItem
	Updates a specific item's display without full refresh.
]]
function Inventory:UpdateSingleItem(itemId: string)
	if not self._inited then return end
	
	-- Find the slot displaying this item
	for _, slot in self._itemSlots do
		if slot._itemId == itemId then
			-- Update inventory data
			self._inventoryData = self:_getInventoryData()
			if not self._inventoryData then return end
			
			local item = self._inventoryData.items[itemId]
			local inHotbar = self:_isItemInHotbar(itemId)
			
			if item then
				slot:UpdateDisplay(itemId, item.quantity, inHotbar)
			else
				-- Item no longer exists, refresh entire display
				self:Refresh()
			end
			return
		end
	end
	
	-- Item not found in current slots, do full refresh
	self:Refresh()
end

-- ========== Internal ========== --

--[[
	_getInventoryData
	Fetches current inventory data from ReplicatedData.
]]
function Inventory:_getInventoryData(): InventoryProfile?
	local player = Players.LocalPlayer
	local data = _deps.ReplicatedData:GetData("Inventory", true)
	return data
end

--[[
	_getFilteredItems
	Returns array of placeable items with their data.
]]
function Inventory:_getFilteredItems(): { FilteredItem }
	if not self._inventoryData then
		return {}
	end
	
	local filtered: { FilteredItem } = {}
	
	-- Iterate through all items in inventory
	for itemId, itemData in self._inventoryData.items do
		-- Fetch item definition from GameData
		local itemInfo = _deps.GameData.Get("Items", itemId)
		
		-- Filter
		if itemInfo and itemInfo.type ~= "ingredient" then
			-- Check if item is in hotbar
			local inHotbar = self:_isItemInHotbar(itemId)
			
			table.insert(filtered, {
				itemId = itemId,
				quantity = itemData.quantity,
				inHotbar = inHotbar,
			})
		end
	end
	
	-- Sort alphabetically by name
	table.sort(filtered, function(a, b)
		local aInfo = _deps.GameData.Get("Items", a.itemId)
		local bInfo = _deps.GameData.Get("Items", b.itemId)
		if aInfo and bInfo then
			return aInfo.name < bInfo.name
		end
		return false
	end)
	
	return filtered
end

--[[
	_isItemInHotbar
	Checks if an item is currently equipped in any hotbar slot.
]]
function Inventory:_isItemInHotbar(itemId: string): boolean
	for _, slotItemId in self._hotbarSlots do
		if slotItemId == itemId then
			return true
		end
	end
	return false
end

--[[
	_handleItemClick
	Callback when player clicks an item slot.
]]
function Inventory:_handleItemClick(itemId: string?)
	if not itemId then return end
	
	-- Delegate to controller
	pcall(function()
		self._opts.onItemClick(itemId)
	end)
end

--[[
	_connectDataChanges
	Listens to ReplicatedData changes and refreshes UI.
]]
function Inventory:_connectDataChanges()
	local player = Players.LocalPlayer

	local itemsConn = _deps.ReplicatedData.OnUpdate.Event:Connect(function(category: string, data: any)
		if category == "Inventory" then
			if self._isVisible then
				self:Refresh(data)
			else
				self._needsRefresh = true
			end
		end
	end)
	
	table.insert(self._conns, itemsConn)
end

--[[
	_setupTooltip
	Adds hover tooltip to an item slot.
]]
function Inventory:_setupTooltip(slotFrame: Frame, itemId: string)
	local button = slotFrame:FindFirstChild("Select") :: TextButton?
	if not button then return end
	
	local enterConn = button.MouseEnter:Connect(function()
		self:_showTooltip(itemId)
	end)
	
	local leaveConn = button.MouseLeave:Connect(function()
		self:_hideTooltip()
	end)
	
	table.insert(self._conns, enterConn)
	table.insert(self._conns, leaveConn)
end

--[[
	_showTooltip
	Displays tooltip with item information.
]]
function Inventory:_showTooltip(itemId: string)
	local itemInfo = _deps.GameData.Get("Items", itemId)
	if not itemInfo then return end
	
	-- Create tooltip if it doesn't exist
	if not self._tooltip then
		self._tooltip = Instance.new("Frame")
		self._tooltip.Name = "Tooltip"
		self._tooltip.Size = UDim2.new(0, 250, 0, 100)
		self._tooltip.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		self._tooltip.BorderSizePixel = 0
		self._tooltip.ZIndex = 100
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = self._tooltip
		
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 10)
		padding.PaddingBottom = UDim.new(0, 10)
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.Parent = self._tooltip
		
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "ItemName"
		nameLabel.Size = UDim2.new(1, 0, 0, 24)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextSize = 18
		nameLabel.Font = Enum.Font.SourceSansBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = self._tooltip
		
		local descLabel = Instance.new("TextLabel")
		descLabel.Name = "Description"
		descLabel.Size = UDim2.new(1, 0, 1, -30)
		descLabel.Position = UDim2.new(0, 0, 0, 30)
		descLabel.BackgroundTransparency = 1
		descLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		descLabel.TextSize = 14
		descLabel.Font = Enum.Font.SourceSans
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.TextWrapped = true
		descLabel.Parent = self._tooltip
		
		self._tooltip.Parent = self._frame.Parent
	end
	
	-- Update tooltip content
	local nameLabel = self._tooltip:FindFirstChild("ItemName") :: TextLabel
	local descLabel = self._tooltip:FindFirstChild("Description") :: TextLabel
	
	if nameLabel then
		nameLabel.Text = itemInfo.name

		-- Set colours
		if itemInfo.textData then
			nameLabel.TextColor3 = itemInfo.textData.nameColor or Color3.fromRGB(255, 255, 255)
			nameLabel.Font = itemInfo.textData.nameFont or Enum.Font.SourceSansBold
		end
	end
	
	if descLabel then
		descLabel.Text = itemInfo.description or "No description available."

		-- Set colours
		if itemInfo.textData then
			descLabel.TextColor3 = itemInfo.textData.descriptionColor or Color3.fromRGB(200, 200, 200)
			descLabel.Font = itemInfo.textData.descriptionFont or Enum.Font.SourceSans
		end
	end
	
	-- Position tooltip near mouse (simplified - always to the right)
	local mouse = Players.LocalPlayer:GetMouse()
	self._tooltip.Position = UDim2.new(0, mouse.X + 20, 0, mouse.Y - 50)
	self._tooltip.Visible = true
end

--[[
	_hideTooltip
	Hides the tooltip.
]]
function Inventory:_hideTooltip()
	if self._tooltip and self._tooltip.Visible then
		self._tooltip.Visible = false
	end
end

--[[
	_showEmptyState
	Displays message when inventory is empty.
]]
function Inventory:_showEmptyState()
	local existing = self._scrollingFrame:FindFirstChild("EmptyState")
	if existing then
		existing.Visible = true
		return
	end
	
	local emptyFrame = Instance.new("Frame")
	emptyFrame.Name = "EmptyState"
	emptyFrame.Size = UDim2.new(1, 0, 1, 0)
	emptyFrame.BackgroundTransparency = 1
	emptyFrame.Parent = self._scrollingFrame
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(150, 150, 150)
	label.TextSize = 20
	label.Font = Enum.Font.SourceSansItalic
	label.Text = "No items in inventory"
	label.Parent = emptyFrame
end

--[[
	_hideEmptyState
	Hides the empty state message.
]]
function Inventory:_hideEmptyState()
	local existing = self._scrollingFrame:FindFirstChild("EmptyState")
	if existing then
		existing.Visible = false
	end
end

-- ========== Life Cycle ========== --

function Inventory:Init()
	if self._inited then return end
	self._inited = true
	
	-- Find ScrollingFrame in the frame
	self._scrollingFrame = self._frame:FindFirstChildWhichIsA("ScrollingFrame", true)
	if not self._scrollingFrame then
		error("[Inventory] Init - ScrollingFrame not found in frame")
	end
	
	-- Ensure UIGridLayout exists for automatic slot positioning
	if not self._scrollingFrame:FindFirstChildOfClass("UIGridLayout") then
		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellSize = UDim2.new(0.2, -5, 0.4, 0)
		gridLayout.CellPadding = UDim2.new(0, 5, 0, 5)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = self._scrollingFrame
	end
	
	-- Connect to data changes
	self:_connectDataChanges()
	
	-- Initial refresh
	self:Refresh()
	
	-- Start hidden
	self._canvas.Visible = false
end

function Inventory:Destroy()
	-- Destroy all item slots
	for _, slot in self._itemSlots do
		pcall(function()
			slot:Destroy()
		end)
	end
	table.clear(self._itemSlots)
	
	-- Destroy tooltip
	if self._tooltip then
		self._tooltip:Destroy()
		self._tooltip = nil
	end
	
	-- Cleanup connections
	for _, c in pairs(self._conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(self._conns)
	
	-- Clear cached data
	self._inventoryData = nil
	table.clear(self._hotbarSlots)
	
	self._inited = false
end

return Inventory :: InventoryAPI