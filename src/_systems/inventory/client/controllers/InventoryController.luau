--!strict
-- InventoryController (Controller) — client controller discovered by Controllers registry.

-- // Roblox Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- // Components
local InventoryComponent = require(script.Parent.Parent.Components:WaitForChild("Inventory"))
local HotbarComponent = require(script.Parent.Parent.Components:WaitForChild("Hotbar"))

-- // Utils
local GuiRefs = require(script.Parent.Parent.Utils:WaitForChild("GuiRefs"))

-- // Types (generated)
local ControllersTypes = require(ReplicatedStorage.Shared.Types.Controllers)

-- // Type aliases for deps inferred from real modules
type ControllerRegistry = ControllersTypes.Registry

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

export type InventoryControllerAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Controllers: ControllerRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: InventoryControllerAPI, deps: Deps) -> (),
	Start: (self: InventoryControllerAPI) -> (),
	Destroy: (self: InventoryControllerAPI) -> (),
}

local InventoryController = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Controllers = {} :: ControllerRegistry,
} :: InventoryControllerAPI

-- Private captured deps for intellisense-friendly access
local _deps: Deps?


-- ========== Public API ========== --

--[[
	ToggleInventory
	Opens or closes the inventory UI.
]]
function InventoryController:ToggleInventory()
	self._inventoryOpen = not self._inventoryOpen
	
	-- Update inventory visibility (will trigger _onInventoryVisibilityChanged)
	self._inventoryComponent:SetVisible(self._inventoryOpen)
end

-- ========== Internal ========== --

function InventoryController:_onInventoryVisibilityChanged()	
	-- Update hotbar remove button visibility
	self._hotbarComponent:SetInventoryOpen(self._inventoryOpen)
end

-- ========== Life Cycle ========== --

function InventoryController:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Get Gui references
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local inventoryGui = PlayerGui:WaitForChild("Inventory") :: ScreenGui
	local hotbarGui = PlayerGui:WaitForChild("Hotbar") :: ScreenGui

	-- // Get remotes
	self._setHotbarSlotRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "SetHotbarSlot") :: RemoteEvent

	-- // Create Hotbar component first
	self._hotbarComponent = HotbarComponent.new(_deps, {
		frame = GuiRefs.Get(hotbarGui, { "HotbarFrame" }),
		onActivate = function(slotNumber: number, stackId: string, itemId: string)
			-- Handle item activation (place, use, etc.)
			print("[InventoryController] Activating slot", slotNumber, "with stack", stackId, "item", itemId)
			-- TODO: Implement item activation logic
			-- For placeable items: trigger placement mode
			-- For abilities: cast ability
		end,
		onRemove = function(slotNumber: number)
			-- Remove stack from hotbar slot
			self._setHotbarSlotRemote:FireServer(slotNumber, nil)
		end,
	})

	-- // Create components
	self._inventoryComponent = InventoryComponent.new(_deps, {
		canvas = GuiRefs.Get(inventoryGui, { "Inventory" }),
		onStackClick = function(stackId: string, itemId: string)
			-- Get current inventory data
			local inventoryData = _deps.ReplicatedData:GetData("Inventory", true)
			if not inventoryData then
				warn("[InventoryController] onStackClick - no inventory data")
				return
			end
			
			-- Check if stack is already in hotbar
			local stackSlot = nil
			for slot, slotStackId in inventoryData.hotbar do
				if slotStackId == stackId then
					stackSlot = slot
					break
				end
			end
			
			if stackSlot then
				-- Stack is in hotbar, remove it (send nil)
				self._setHotbarSlotRemote:FireServer(stackSlot, nil)
			else
				-- Stack not in hotbar, find first available slot and add it
				local firstAvailableSlot = nil
				for slot = 1, inventoryData.hotbarSize do
					if not inventoryData.hotbar[slot] then
						firstAvailableSlot = slot
						break
					end
				end
				
				if firstAvailableSlot then
					self._setHotbarSlotRemote:FireServer(firstAvailableSlot, stackId)
				else
					warn("[InventoryController] No available hotbar slots")
					-- TODO: Show UI message to player
				end
			end
		end,
	})
	
	-- Track inventory open state
	self._inventoryOpen = false
end

function InventoryController:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- Connect inventory visibility change handler
	table.insert(self._conns, self._inventoryComponent:GetCanvas():GetPropertyChangedSignal("Visible"):Connect(function()
		self._inventoryOpen = self._inventoryComponent:GetCanvas().Visible
		self:_onInventoryVisibilityChanged()
	end))

	-- Initialise components
	self._hotbarComponent:Init()
	self._inventoryComponent:Init()
	
	-- Hotbar is always visible
	-- Inventory starts hidden
	self._inventoryComponent:SetVisible(false)
	
	-- TODO: Bind key to toggle inventory (e.g., "I" or "Tab")
	self:ToggleInventory()
end

function InventoryController:Destroy()
	-- Destroy components
	if self._inventoryComponent then
		self._inventoryComponent:Destroy()
	end
	if self._hotbarComponent then
		self._hotbarComponent:Destroy()
	end
	
	-- Cleanup connections
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return InventoryController :: InventoryControllerAPI
