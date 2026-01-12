--!strict
-- PlotService (Service) — lifecycle-first singleton discovered by Services registry.

-- // Roblox Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Classes
local PlotClass = require(ServerScriptService.Server.Classes:WaitForChild("Plot"))

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

export type PlotServiceAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Services: ServiceRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: PlotServiceAPI, deps: Deps) -> (),
	Start: (self: PlotServiceAPI) -> (),
	Destroy: (self: PlotServiceAPI) -> (),
	
	-- Player lifecycle
	OnPlayerAdded: (self: PlotServiceAPI, player: Player) -> boolean,
	OnPlayerRemoving: (self: PlotServiceAPI, player: Player) -> boolean,
	
	-- Public API
	GetPlayerPlot: (self: PlotServiceAPI, player: Player) -> any?,
	GetOccupiedSlots: (self: PlotServiceAPI) -> { number },
}

local PlotService = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Services = {} :: ServiceRegistry,
}

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- Track active plots and slot availability
local _plots: { [Player]: any } = {} -- PlotAPI instances by player
local _occupiedSlots: { [number]: boolean } = {} -- which slots are taken
local MAX_PLOTS = 1 -- matches PLOT_CFRAMES in Plot.luau

-- ========== Helper Functions ========== --

local function findAvailablePlotSlot(): number?
	-- Find the first unoccupied slot
	for slot = 1, MAX_PLOTS do
		if not _occupiedSlots[slot] then
			return slot
		end
	end
	return nil -- All slots occupied
end

-- ========== Public API ========== --

function PlotService:GetPlayerPlot(player: Player): any?
	return _plots[player]
end

function PlotService:GetOccupiedSlots(): { number }
	local slots = {}
	for slot, _ in _occupiedSlots do
		table.insert(slots, slot)
	end
	return slots
end

-- ========== Player Life Cycle ========== --

function PlotService:OnPlayerAdded(player: Player): boolean
	-- Check if player already has a plot (shouldn't happen, but be defensive)
	if _plots[player] then
		warn("PlotService: Player", player.Name, "already has a plot assigned")
		return true
	end

	-- Wait for their profile to load
	local profile = _deps.DataInterface:GetPlayerProfile(player, true)
	if not profile then
		warn("PlotService: Player profile not found for", player.Name)
		return false
	end

	-- Find an available plot slot
	local assignedSlot = findAvailablePlotSlot()
	if not assignedSlot then
		warn("PlotService: No available plot slots for", player.Name)
		return false
	end

	-- Mark the slot as occupied (provisionally)
	_occupiedSlots[assignedSlot] = true

	-- Create a plot instance for the player
	local success, result = pcall(function()
		local plot = PlotClass.new(_deps, {
			owner = player,
			slot = assignedSlot,
		})
		plot:Init()
		return plot
	end)

	if not success then
		warn("PlotService: Failed to create plot for", player.Name, ":", result)
		_occupiedSlots[assignedSlot] = nil -- Free the slot
		return false
	end

	-- Store plot reference
	_plots[player] = result

	-- Teleport the player to their plot
	local cf = result:GetPlayerSpawnCFrame()
	if cf then
		self.Services.PlayerService:TeleportPlayers({ player }, cf, 0, true)
	end

	print("[PlotService] Successfully assigned plot slot", assignedSlot, "to", player.Name)
	return true -- Success
end

function PlotService:OnPlayerRemoving(player: Player): boolean
	local plot = _plots[player]
	if not plot then
		-- Player didn't have a plot (maybe failed to load)
		return true
	end

	-- Get the slot before destroying
	local slot = plot.slot

	-- Destroy the plot (cleans up model, connections, etc.)
	local success, err = pcall(function()
		plot:Destroy()
	end)

	if not success then
		warn("PlotService: Error destroying plot for", player.Name, ":", err)
		-- Continue cleanup anyway
	end

	-- Free the slot and remove plot reference
	if slot then
		_occupiedSlots[slot] = nil
		print("[PlotService] Freed plot slot", slot, "from", player.Name)
	end
	_plots[player] = nil

	return true
end

-- ========== Life Cycle ========== --

function PlotService:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Example: get/create remotes
end

function PlotService:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Connect player life cycle
	for _, plr in Players:GetPlayers() do
		local success = self:OnPlayerAdded(plr)
		if not success then
			-- Handle failure (e.g., kick player)
			plr:Kick("Failed to load your plot data. Please rejoin!")
		end
	end
	
	table.insert(self._conns, Players.PlayerAdded:Connect(function(plr: Player)
		local success = self:OnPlayerAdded(plr)
		if not success then
			-- Handle failure (e.g., kick player)
			plr:Kick("Failed to load your plot data. Please rejoin!")
		end
	end))
	
	table.insert(self._conns, Players.PlayerRemoving:Connect(function(plr: Player)
		self:OnPlayerRemoving(plr)
	end))
end

function PlotService:Destroy()
	-- Clean up all active plots
	for player, plot in _plots do
		pcall(function()
			plot:Destroy()
		end)
	end
	table.clear(_plots)
	table.clear(_occupiedSlots)

	-- Disconnect all connections
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return PlotService :: PlotServiceAPI