--!strict
-- Hotbar (Component)

-- // Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

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

export type HotbarAPI = {
	_inited: boolean,
	_conns: { RBXScriptConnection },
	_opts: Opts,
	_frame: Frame,
	_hotbarSlots: { ItemSlot.ItemSlotAPI },
	_equippedSlot: number?,
	_hotbarData: { [number]: string? }, -- slot -> stackId
	_inventoryOpen: boolean,

	Init: (self: HotbarAPI) -> (),
	Destroy: (self: HotbarAPI) -> (),
	
	Refresh: (self: HotbarAPI, inventoryData: InventoryProfile?) -> (),
	EquipSlot: (self: HotbarAPI, slotNumber: number) -> (),
	ActivateEquippedSlot: (self: HotbarAPI) -> (),
	SetInventoryOpen: (self: HotbarAPI, open: boolean) -> (),
	UpdateSlot: (self: HotbarAPI, slotNumber: number) -> (),
}

export type Opts = {
	frame: Frame,
	onActivate: (slotNumber: number, stackId: string, itemId: string) -> (), -- callback when item used
	onRemove: (slotNumber: number) -> (), -- callback when X button clicked
}

local Hotbar = {}
Hotbar.__index = Hotbar

-- // Internal state
local _deps: Deps? = nil

-- // Keyboard slot mappings (1-9 keys and 0 for slot 10 if needed)
local SLOT_KEYCODES = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

-- ========== Constructor ========== --

function Hotbar.new(deps: Deps, opts: Opts): HotbarAPI
	if not _deps then
		_deps = deps
	end

	local self = setmetatable({ _inited = false, _conns = {} } :: any, Hotbar) :: HotbarAPI
	
	self._opts = opts
	self._frame = opts.frame
	self._hotbarSlots = {}
	self._equippedSlot = nil
	self._hotbarData = {}
	self._inventoryOpen = false
	
	return self
end

-- ========== Public API ========== --

--[[
	Refresh
	Rebuilds all hotbar slots from current ReplicatedData.
	Optionally accepts data to avoid stale cache reads.
]]
function Hotbar:Refresh(inventoryData: InventoryProfile?)
	if not self._inited then
		return 
	end
	
	-- Use provided data or fetch latest
	if not inventoryData then
		inventoryData = self:_getInventoryData()
	end
	
	if not inventoryData then
		warn("[Hotbar] Refresh - no inventory data available")
		return
	end
	
	self._hotbarData = inventoryData.hotbar
	
	-- Update each slot
	for slotNumber = 1, #self._hotbarSlots do
		self:UpdateSlot(slotNumber)
	end
end

--[[
	EquipSlot
	Selects a hotbar slot and shows visual indicator.
]]
function Hotbar:EquipSlot(slotNumber: number)
	if slotNumber < 1 or slotNumber > #self._hotbarSlots then
		warn("[Hotbar] EquipSlot - invalid slot number:", slotNumber)
		return
	end
	
	-- If already equipped, activate it instead
	if self._equippedSlot == slotNumber then
		self:ActivateEquippedSlot()
		return
	end
	
	-- Clear previous equipped slot border
	if self._equippedSlot then
		local prevSlot = self._hotbarSlots[self._equippedSlot]
		if prevSlot then
			prevSlot:SetSelectedVisuals(false)
		end
	end
	
	-- Set new equipped slot
	self._equippedSlot = slotNumber
	
	-- Show border on new equipped slot
	local newSlot = self._hotbarSlots[slotNumber]
	if newSlot then
		newSlot:SetSelectedVisuals(true)
	end
end

--[[
	ActivateEquippedSlot
	Uses/activates the item in the currently equipped slot.
]]
function Hotbar:ActivateEquippedSlot()
	if not self._equippedSlot then
		warn("[Hotbar] ActivateEquippedSlot - no slot equipped")
		return
	end
	
	local stackId = self._hotbarData[self._equippedSlot]
	if not stackId then
		warn("[Hotbar] ActivateEquippedSlot - equipped slot is empty")
		return
	end
	
	-- Get inventory data to find itemId for this stack
	local inventoryData = self:_getInventoryData()
	if not inventoryData then return end
	
	local stack = inventoryData.items[stackId]
	if not stack then
		warn("[Hotbar] ActivateEquippedSlot - stack not found:", stackId)
		return
	end
	
	-- Fire callback to controller
	pcall(function()
		self._opts.onActivate(self._equippedSlot, stackId, stack.itemId)
	end)
end

--[[
	SetInventoryOpen
	Shows or hides remove buttons on all slots.
]]
function Hotbar:SetInventoryOpen(open: boolean)
	self._inventoryOpen = open
	
	-- Update visibility of remove buttons on all slots
	for _, slot in self._hotbarSlots do
		slot:SetRemoveButtonVisible(open)
	end
end

--[[
	UpdateSlot
	Updates a specific slot's display.
]]
function Hotbar:UpdateSlot(slotNumber: number)
	if slotNumber < 1 or slotNumber > #self._hotbarSlots then
		return
	end
	
	local slot = self._hotbarSlots[slotNumber]
	if not slot then return end
	
	local stackId = self._hotbarData[slotNumber]
	
	if stackId then
		-- Get inventory data to find this stack
		local inventoryData = self:_getInventoryData()
		if inventoryData and inventoryData.items[stackId] then
			local stack = inventoryData.items[stackId]
			slot:UpdateDisplay(stack.itemId, stack.quantity, true) -- true = in hotbar
		else
			-- Stack not found in inventory anymore, show empty
			slot:UpdateDisplay(nil, 0, false)
		end
	else
		-- Empty slot
		slot:UpdateDisplay(nil, 0, false)
	end
end

-- ========== Internal ========== --

--[[
	_getInventoryData
	Fetches current inventory data from ReplicatedData.
]]
function Hotbar:_getInventoryData(): InventoryProfile?
	local data = _deps.ReplicatedData:GetData("Inventory", true)
	return data
end

--[[
	_connectDataChanges
	Listens to ReplicatedData changes and refreshes hotbar.
]]
function Hotbar:_connectDataChanges()
	local conn = _deps.ReplicatedData.OnUpdate.Event:Connect(function(category: string, data: any)
		if category == "Inventory" then
			self:Refresh(data)
		end
	end)
	
	table.insert(self._conns, conn)
end

--[[
	_connectKeyboardInput
	Binds keyboard keys 1-9 to hotbar slots.
]]
function Hotbar:_connectKeyboardInput()
	local conn = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end -- Ignore if typing in textbox
		
		-- Check if it's a hotbar key
		local slotNumber = SLOT_KEYCODES[input.KeyCode]
		if slotNumber then
			self:EquipSlot(slotNumber)
		end
	end)
	
	table.insert(self._conns, conn)
end

--[[
	_handleSlotClick
	Callback when a slot is clicked.
]]
function Hotbar:_handleSlotClick(slotNumber: number)
	self:EquipSlot(slotNumber)
end

--[[
	_handleSlotRemove
	Callback when remove button is clicked.
]]
function Hotbar:_handleSlotRemove(slotNumber: number)
	pcall(function()
		self._opts.onRemove(slotNumber)
	end)
end

-- ========== Life Cycle ========== --

function Hotbar:Init()
	if self._inited then return end
	self._inited = true
	
	-- Get inventory data to know hotbar size
	local inventoryData = self:_getInventoryData()
	if not inventoryData then
		error("[Hotbar] Init - no inventory data")
	end
	
	local hotbarSize = inventoryData.hotbarSize or 9
	
	-- Create fixed number of ItemSlot components
	for slotNumber = 1, hotbarSize do
		local slot = ItemSlot.new(_deps, {
			itemId = nil,
			quantity = 0,
			slotIndex = slotNumber,
			showInHotbar = true,
			containerType = "hotbar",
			onClick = function(itemId: string?, slotIdx: number)
				self:_handleSlotClick(slotNumber)
			end,
			onRemove = function(slotIdx: number)
				self:_handleSlotRemove(slotNumber)
			end,
		})
		
		slot:Init()
		slot:GetFrame().Size = UDim2.new(1 / hotbarSize, -10, 1, 0) -- evenly distribute slots with padding
		slot:GetFrame().Parent = self._frame
		
		-- Initially hide remove button
		slot:SetRemoveButtonVisible(false)
		
		table.insert(self._hotbarSlots, slot)
	end
	
	-- Ensure UIListLayout exists for slot positioning
	if not self._frame:FindFirstChildOfClass("UIListLayout") then
		local listLayout = Instance.new("UIListLayout")
		listLayout.FillDirection = Enum.FillDirection.Horizontal
		listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		listLayout.Padding = UDim.new(0, 10)
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Parent = self._frame
	end
	
	-- Connect to data changes
	self:_connectDataChanges()
	
	-- Connect keyboard input
	self:_connectKeyboardInput()
	
	-- Initial refresh
	self:Refresh()
end

function Hotbar:Destroy()
	-- Destroy all slots
	for _, slot in self._hotbarSlots do
		pcall(function()
			slot:Destroy()
		end)
	end
	table.clear(self._hotbarSlots)
	
	-- Cleanup connections
	for _, c in pairs(self._conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(self._conns)
	
	-- Clear state
	self._equippedSlot = nil
	table.clear(self._hotbarData)
	
	self._inited = false
end

return Hotbar :: HotbarAPI
