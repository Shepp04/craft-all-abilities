--!strict
-- Plot (Server Class)

-- // Roblox Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

-- // Types
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
	owner: Player,
	slot: number,
}

export type PlotAPI = {
	_opts: Opts,
	_conns: { RBXScriptConnection },

	owner: Player,
	slot: number,
	_model: Model?,
	_objects: { [Instance]: any },

	Init: (self: PlotAPI) -> (),
	Destroy: (self: PlotAPI) -> (),

	GetPlayerSpawnCFrame: (self: PlotAPI) -> CFrame?,
	SetOwnerGui: (self: PlotAPI) -> (),
}

local Plot = {}
Plot.__index = Plot

-- // Internal state
local _deps: Deps?

-- // Constants
local SAMPLE_PLOT_MODEL: Model = workspace:WaitForChild("SamplePlot") :: Model
do
	-- Convert to model if it is a folder
	if SAMPLE_PLOT_MODEL:IsA("Folder") then
		local model = Instance.new("Model")
		for _, child in SAMPLE_PLOT_MODEL:GetChildren() do
			child.Parent = model
		end
		model.PrimaryPart = model:FindFirstChild("Base") :: BasePart
		model.Name = SAMPLE_PLOT_MODEL.Name
		SAMPLE_PLOT_MODEL = model :: Model
	end
	SAMPLE_PLOT_MODEL.Parent = nil -- remove from workspace
end
local PLOT_FOLDER: Folder = workspace:WaitForChild("Plots") :: Folder
local PLOT_CFRAMES = {
	[1] = CFrame.new(-72, 9, 0), -- leave a gap of 128 studs in z direction
	[2] = CFrame.new(-72, 9, 128),
	[3] = CFrame.new(-72, 9, 256),
} :: { [number]: CFrame }

-- ========== Helpers ========== --

local function getCFrameFromPlotSlot(slot: number): CFrame
	return PLOT_CFRAMES[slot] or error("Invalid plot slot: " .. tostring(slot))
end

-- ========== Constructor ========== --

function Plot.new(deps: Deps, opts: Opts?): PlotAPI
	_deps = deps

	local self = setmetatable({} :: any, Plot) :: PlotAPI
	self._opts = opts or {}
	self._conns = {}
	self._objects = {}

	self.owner = self._opts.owner
	if not self.owner then
		error("Plot must be constructed with an owner Player")
	end

	self.slot = self._opts.slot
	if not self.slot then
		error("Plot must be constructed with a slot number")
	end

	return self
end

-- ========== Public API ========== --

function Plot:GetPlayerSpawnCFrame(): CFrame?
	-- Return a CFrame within the plot for player spawning
	if self._model then
		local playerSpawn = self._model:FindFirstChild("PlayerSpawn") :: BasePart?
		if playerSpawn then
			return playerSpawn.CFrame
		end
	end
end

function Plot:SetOwnerGui()
	local gui = self._model and self._model:FindFirstChild("OwnerGui") :: BillboardGui?
	if not gui then
		warn("Plot model missing OwnerGui BillboardGui")
		return
	end
	
	local ownerNameLabel = gui:FindFirstChild("OwnerName") :: TextLabel?
	if ownerNameLabel then
		ownerNameLabel.Text = self.owner and self.owner.Name .. "'s Plot" or ""
	end

	local ownerIcon = gui:FindFirstChild("OwnerIcon") :: ImageLabel?
	if ownerIcon then
		local thumbType = Enum.ThumbnailType.HeadShot
		local thumbSize = Enum.ThumbnailSize.Size420x420

		local ok, content, isReady = pcall(function()
			return Players:GetUserThumbnailAsync(self.owner.UserId, thumbType, thumbSize)
		end)
		if ok and content then
			ownerIcon.Image = content
		else
			-- Fallback or loading image
			ownerIcon.Image = ""
		end
	end
end

-- ========== Internal ========== --

function Plot:_internalMethod()
	-- Example
end

-- ========== Life Cycle ========== --

function Plot:Init()
	-- // Create a blank model for the plot
	self._model = SAMPLE_PLOT_MODEL:Clone()
	self._model:PivotTo(getCFrameFromPlotSlot(self.slot))
	self._model.Parent = PLOT_FOLDER

	-- // Setup Owner GUI
	self:SetOwnerGui()
end

function Plot:Destroy()
	-- Destroy any created objects, disconnect connections, etc.
	for _, o in self._objects do
		if typeof(o) == "Instance" then
			o:Destroy()
		elseif type(o) == "table" and typeof(o.Destroy) == "function" then
			pcall(function() o:Destroy() end)
		end
	end
	table.clear(self._objects)

	-- Destroy the plot model
	if self._model then
		self._model:Destroy()
		self._model = nil
	end

	for _, c in self._conns do
		pcall(function() c:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
end

return Plot :: PlotAPI
