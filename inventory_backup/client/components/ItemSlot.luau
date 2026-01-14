--!strict
-- ItemSlot (Component)

-- // Services
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- // Utils
local GuiRefs = require(script.Parent.Parent.Utils.GuiRefs)

-- // Custom types

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

export type ItemSlotAPI = {
	_inited: boolean,
	_conns: { RBXScriptConnection },
	_opts: Opts,

	_frame: Frame,
	_itemId: string?,
	_quantity: number?,
	_showInHotbar: boolean,

	Init: (self: ItemSlotAPI) -> (),
	Destroy: (self: ItemSlotAPI) -> (),
	UpdateDisplay: (self: ItemSlotAPI, itemId: string?, quantity: number?, showInHotbar: boolean?) -> (),
	GetFrame: (self: ItemSlotAPI) -> Frame,
	SetVisible: (self: ItemSlotAPI, visible: boolean) -> (),
	SetPosition: (self: ItemSlotAPI, position: UDim2) -> (),
	SetRemoveButtonVisible: (self: ItemSlotAPI, visible: boolean) -> (),
}

export type Opts = {
	itemId: string?, -- nil for empty slot
	quantity: number?,
	slotIndex: number, -- position in parent container
	showInHotbar: boolean?, -- for visual indicator
	containerType: "inventory" | "hotbar",
	onClick: (itemId: string?) -> (), -- callback function
	onRemove: ((slotIndex: number) -> ())?, -- callback function (optional)
}

local ItemSlot = {}
ItemSlot.__index = ItemSlot

-- // Internal state
local _deps: Deps? = nil

-- ========== Constructor ========== --

function ItemSlot.new(deps: Deps, opts: Opts): ItemSlotAPI
	if not _deps then
		_deps = deps
	end

	local self = setmetatable({ _inited = false, _conns = {} } :: any, ItemSlot) :: ItemSlotAPI

	self._opts = opts
	self._frame = Instance.new("Frame")
	self._frame.Name = "ItemSlot_" .. tostring(opts.slotIndex)
	self._frame.BackgroundTransparency = 1

	self._itemId = opts.itemId
	self._quantity = opts.quantity or 0
	self._showInHotbar = opts.showInHotbar or false
	
	return self
end

-- ========== Public API ========== --

function ItemSlot:UpdateDisplay(itemId: string?, quantity: number?, showInHotbar: boolean?)
	self._itemId = itemId
	self._quantity = quantity or 0
	self._showInHotbar = if showInHotbar ~= nil then showInHotbar else false

	local itemInfo
	if self._itemId then
		itemInfo = _deps.GameData.Get("Items", self._itemId)
		if not itemInfo then
			warn("[ItemSlot] UpdateDisplay - itemId not found in GameData:", self._itemId)
		end
	end

	-- Update icon, name, quantity display
	if itemInfo then
		-- Set name and colours
		self._frame.Button.ItemName.Text = itemInfo.name or ""
		
		if itemInfo.textData then
			self._frame.Button.ItemName.TextColor3 = itemInfo.textData.nameColor or Color3.fromRGB(255, 255, 255)
			self._frame.Button.ItemName.Font = itemInfo.textData.nameFont or self._frame.Button.ItemName.Font
		end
		
		-- Handle icon (asset or emoji)
		if itemInfo.icon and string.sub(itemInfo.icon, 1, 12) == "rbxassetid://" then
			self._frame.Button.ItemIcon.ItemImageIcon.Image = itemInfo.icon
			self._frame.Button.ItemIcon.ItemImageIcon.Visible = true
			self._frame.Button.ItemIcon.ItemTextIcon.Text = ""
			self._frame.Button.ItemIcon.ItemTextIcon.Visible = false
		else
			self._frame.Button.ItemIcon.ItemImageIcon.Image = ""
			self._frame.Button.ItemIcon.ItemImageIcon.Visible = false
			self._frame.Button.ItemIcon.ItemTextIcon.Text = itemInfo.icon or "?"
			self._frame.Button.ItemIcon.ItemTextIcon.Visible = true
		end
		
		-- Show slot as filled
		self._frame.Button.BackgroundTransparency = 0.5
	else
		-- Empty slot
		self._frame.Button.ItemName.Text = ""
		self._frame.Button.ItemIcon.ItemImageIcon.Image = ""
		self._frame.Button.ItemIcon.ItemImageIcon.Visible = false
		self._frame.Button.ItemIcon.ItemTextIcon.Text = ""
		self._frame.Button.ItemIcon.ItemTextIcon.Visible = false
		self._frame.Button.BackgroundTransparency = 0.8
	end

	-- Update quantity
	self._frame.Button.Quantity.Text = if self._quantity and self._quantity > 1 then "x" .. tostring(self._quantity) else ""

	-- Update hotbar indicator (e.g. black-out)
	if self._opts.containerType == "inventory" then
		-- toggle black-out (dim if not shown in hotbar)
		self._frame.Button.ItemIcon.ItemImageIcon.UIGradient.Enabled = self._showInHotbar
		self._frame.Button.ItemIcon.ItemTextIcon.UIGradient.Enabled = self._showInHotbar
	elseif self._opts.containerType == "hotbar" then
		-- Show border when slot is filled
		self._frame.Button.UIStroke.Enabled = itemInfo ~= nil
	end
end

function ItemSlot:GetFrame(): Frame
	return self._frame
end

function ItemSlot:SetVisible(visible: boolean)
	self._frame.Visible = visible
end

function ItemSlot:SetPosition(position: UDim2)
	self._frame.Position = position
end

function ItemSlot:SetRemoveButtonVisible(visible: boolean)
	if self._frame:FindFirstChild("RemoveButton") then
		self._frame.RemoveButton.Visible = visible
	end
end

function ItemSlot:SetSelectedVisuals(selected: boolean)
	local uiStroke = self._frame.Button:FindFirstChildOfClass("UIStroke") :: UIStroke?
	if uiStroke then
		uiStroke.Thickness = if selected then 4 else 2 -- 255, 255, 100
		uiStroke.Color = if selected then Color3.fromRGB(255, 215, 0) else Color3.fromRGB(200, 200, 200)
		-- uiStroke.Enabled = selected
	end
end

-- ========== Internal ========== --

function ItemSlot:_handleClick()
	-- Handle click event
	if not self._opts.onClick then
		return
	end
	
	pcall(function()
		self._opts.onClick(self._itemId)
	end)
end

function ItemSlot:_handleRemove()
	-- Handle remove event
	if not self._opts.onRemove then
		return
	end
	
	pcall(function()
		self._opts.onRemove(self._opts.slotIndex)
	end)
end

-- ========== Life Cycle ========== --

function ItemSlot:Init()
	if self._inited then return end
	self._inited = true

	-- // Create Gui elements
	do
		local uiAspectRatio = Instance.new("UIAspectRatioConstraint")
		uiAspectRatio.AspectRatio = 1
		uiAspectRatio.Parent = self._frame

		local selectButton = Instance.new("TextButton")
		selectButton.Name = "Select"
		selectButton.Size = UDim2.new(1, 0, 1, 0)
		selectButton.BackgroundTransparency = 1
		selectButton.Text = ""
		selectButton.ZIndex = 2
		selectButton.Parent = self._frame

		local buttonFrame = Instance.new("Frame")
		buttonFrame.Name = "Button"
		buttonFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		buttonFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
		buttonFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		buttonFrame.BackgroundTransparency = 0.2
		buttonFrame.Size = UDim2.new(1, -5, 1, -5)
		buttonFrame.ZIndex = 1
		buttonFrame.Parent = self._frame

		local uiStroke = Instance.new("UIStroke")
		uiStroke.Color = Color3.fromRGB(200, 200, 200)
		uiStroke.Thickness = 2
		uiStroke.Enabled = false
		uiStroke.Parent = buttonFrame

		local uiCorner = Instance.new("UICorner")
		uiCorner.CornerRadius = UDim.new(0.15, 0)
		uiCorner.Parent = buttonFrame

		-- Make icon, name label, and quantity label
		local itemIcon = Instance.new("Frame")
		itemIcon.Name = "ItemIcon"
		itemIcon.Size = UDim2.new(0.8, 0, 0.8, 0)
		itemIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
		itemIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		itemIcon.BackgroundTransparency = 1
		itemIcon.ZIndex = 1
		itemIcon.Parent = buttonFrame

		local iconImageLabel = Instance.new("ImageLabel")
		iconImageLabel.Name = "ItemImageIcon"
		iconImageLabel.Size = UDim2.new(1, 0, 1, 0)
		iconImageLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
		iconImageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		iconImageLabel.BackgroundTransparency = 1
		iconImageLabel.ScaleType = Enum.ScaleType.Fit
		iconImageLabel.ZIndex = 1
		iconImageLabel.Parent = itemIcon

		local iconUIGradientImage = Instance.new("UIGradient") -- for dimming when not in hotbar
		iconUIGradientImage.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0))
		iconUIGradientImage.Enabled = false
		iconUIGradientImage.Parent = iconImageLabel

		local iconTextLabel = Instance.new("TextLabel")
		iconTextLabel.Name = "ItemTextIcon"
		iconTextLabel.Size = UDim2.new(1, 0, 1, 0)
		iconTextLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
		iconTextLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		iconTextLabel.BackgroundTransparency = 1
		iconTextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		iconTextLabel.TextScaled = true
		iconTextLabel.Font = Enum.Font.SourceSansBold
		iconTextLabel.Text = ""
		iconTextLabel.ZIndex = 1
		iconTextLabel.Parent = itemIcon

		local iconUIGradientText = Instance.new("UIGradient") -- for dimming when not in hotbar
		iconUIGradientText.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0))
		iconUIGradientText.Enabled = false
		iconUIGradientText.Parent = iconTextLabel

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "ItemName"
		nameLabel.Size = UDim2.new(1, -4, 0.2, 0)
		nameLabel.Position = UDim2.new(0, 2, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.SourceSansBold
		nameLabel.Text = ""
		nameLabel.ZIndex = 1
		nameLabel.Parent = buttonFrame

		local quantityLabel = Instance.new("TextLabel")
		quantityLabel.Name = "Quantity"
		quantityLabel.Size = UDim2.new(0.5, 0, 0.25, 0)
		quantityLabel.Position = UDim2.new(1, -2, 1, -2)
		quantityLabel.AnchorPoint = Vector2.new(1, 1)
		quantityLabel.BackgroundTransparency = 1
		quantityLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		quantityLabel.TextScaled = true
		quantityLabel.Font = Enum.Font.SourceSansBold
		quantityLabel.TextXAlignment = Enum.TextXAlignment.Right
		quantityLabel.Text = ""
		quantityLabel.ZIndex = 1
		quantityLabel.Parent = buttonFrame

		local slotLabel = Instance.new("TextLabel")
		slotLabel.Name = "SlotIndex"
		slotLabel.Size = UDim2.new(0.3, 0, 0.3, 0)
		slotLabel.Position = UDim2.new(0, 4, 1, -4)
		slotLabel.AnchorPoint = Vector2.new(0, 1)
		slotLabel.BackgroundTransparency = 1
		slotLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		slotLabel.TextScaled = true
		slotLabel.Font = Enum.Font.SourceSansBold
		slotLabel.Text = tostring(self._opts.slotIndex)
		slotLabel.TextXAlignment = Enum.TextXAlignment.Left
		slotLabel.TextYAlignment = Enum.TextYAlignment.Bottom
		slotLabel.ZIndex = 1
		slotLabel.Visible = self._opts.containerType == "hotbar" -- Only show for hotbar
		slotLabel.Parent = buttonFrame

		local remove = Instance.new("Frame")
		remove.Name = "RemoveButton"
		remove.Size = UDim2.new(0.25, 0, 0.25, 0)
		remove.Position = UDim2.new(1, 0, 0, 0)
		remove.AnchorPoint = Vector2.new(1, 0)
		remove.BackgroundTransparency = 1
		remove.ZIndex = 3
		remove.Parent = self._frame

		local removeButtonSelect = Instance.new("TextButton")
		removeButtonSelect.Name = "Select"
		removeButtonSelect.Size = UDim2.new(1, 0, 1, 0)
		removeButtonSelect.BackgroundTransparency = 1
		removeButtonSelect.Text = ""
		removeButtonSelect.ZIndex = 2
		removeButtonSelect.Parent = remove

		local removeButton = Instance.new("Frame")
		removeButton.Name = "Button"
		removeButton.Size = UDim2.new(1, -4, 1, -4)
		removeButton.Position = UDim2.new(0.5, 0, 0.5, 0)
		removeButton.AnchorPoint = Vector2.new(0.5, 0.5)
		removeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
		removeButton.ZIndex = 1
		removeButton.Parent = remove

		local removeButtonCorner = Instance.new("UICorner")
		removeButtonCorner.CornerRadius = UDim.new(1, 0)
		removeButtonCorner.Parent = removeButton

		local removeButtonText = Instance.new("TextLabel")
		removeButtonText.Name = "RemoveButtonText"
		removeButtonText.Size = UDim2.new(1, 0, 1, 0)
		removeButtonText.Position = UDim2.new(0.5, 0, 0.5, 0)
		removeButtonText.AnchorPoint = Vector2.new(0.5, 0.5)
		removeButtonText.BackgroundTransparency = 1
		removeButtonText.TextColor3 = Color3.fromRGB(255, 255, 255)
		removeButtonText.TextScaled = true
		removeButtonText.Font = Enum.Font.FredokaOne
		removeButtonText.Text = "X"
		removeButtonText.ZIndex = 1
		removeButtonText.Parent = removeButton
	end

	-- // Set tags for animation
	CollectionService:AddTag(self._frame, "ExpandingButton")
	CollectionService:AddTag(self._frame, "BouncingButton")
	CollectionService:AddTag(self._frame.Select, "ClickSFXButton")
	CollectionService:AddTag(self._frame.Select, "HoverSFXButton")

	CollectionService:AddTag(self._frame.RemoveButton, "ExpandingButton")
	CollectionService:AddTag(self._frame.RemoveButton.Select, "ClickSFXButton")
	CollectionService:AddTag(self._frame.RemoveButton.Select, "HoverSFXButton")

	-- // Toggle remove button visibility based on container type
	if self._opts.containerType == "hotbar" then
		self._frame.RemoveButton.Visible = true
	else
		self._frame.RemoveButton.Visible = false
	end

	-- // Set layout order based on slot index
	self._frame.LayoutOrder = self._opts.slotIndex
	
	-- // Set up click handlers
	table.insert(self._conns, self._frame.Select.MouseButton1Click:Connect(function()
		self:_handleClick()
	end))

	table.insert(self._conns, self._frame.RemoveButton.Select.MouseButton1Click:Connect(function()
		self:_handleRemove()
	end))

	-- // Initial update
	self:UpdateDisplay(self._itemId, self._quantity, self._showInHotbar)
end

function ItemSlot:Destroy()
	-- Cleanup connections
	for _, c in pairs(self._conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(self._conns)
	
	-- Destroy frame
	if self._frame then
		self._frame:Destroy()
		self._frame = nil :: any
	end
	
	self._inited = false
end

return ItemSlot :: ItemSlotAPI